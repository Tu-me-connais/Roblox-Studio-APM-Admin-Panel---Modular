--[[
	Dispatcher : distribue des actions ciblées aux CLIENTS des joueurs (Fly, Noclip...) sous l'autorité du serveur. Les autres commandes (Freeze, Kick...)
	s'exécutent déjà sur le serveur et passent par ctx.Perform ; ici ne vit que ce qui doit s'exécuter chez la cible.

	Chemin d'une action : commande (Sentinel, panneau, commande personnalisée, module futur) -> Dispatcher.Apply ->
	  admin reconnu (APM.AccessPanel) + droit sur l'action (matrice des modules : ctx.Ranks.CanUse) + fréquence limitée ->
	  cibles résolues : soi-même, ou grade STRICTEMENT inférieur (ctx.Ranks.CanTarget : « all » ne contourne jamais une protection) ->
	  une instruction par client (identifiant unique, numéro d'ordre, expiration, paramètres bornés ; jamais de code) ->
	  attente BORNÉE des accusés -> vérification côté serveur quand une preuve existe (Hooks.Verify) -> bilan chiffré -> journal.
	Une réussite n'est annoncée que pour un client qui a répondu ; un accusé n'est PAS une preuve absolue (le client est une machine étrangère) :
	le bilan distingue donc confirmés, vérifiés par le serveur, en attente de réapparition, non confirmés, protégés et échecs.

	Le client ne peut RIEN demander : ActionReport ne transporte que des réponses (Ack), « prêt » (Ready) et « effet terminé » (Ended), toutes
	validées (identifiant émis POUR ce joueur, usage unique, délai, listes fermées). Un joueur ne peut donc pas se donner Fly en forgeant une requête.

	Etat : en mémoire serveur seulement, jamais enregistré ; un joueur qui revient n'a plus aucun effet. Aucune boucle permanente :
	tout est piloté par des événements (acquittements, réapparitions, départs).

	Pour les tests : Dispatcher.Create(ctx, services) accepte de faux joueurs, un faux transport, une fausse horloge et de faux soutiens.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HooksModule = require(script.Hooks)

local Dispatcher = {}

local MAX_BATCH = 40
local ACK_WINDOW = 3
local VERIFY_DELAY = 0.35
local READY_COOLDOWN = 5

local function sharedCatalog()
	local shared = ReplicatedStorage:FindFirstChild("APM_Shared") or ReplicatedStorage:WaitForChild("APM_Shared", 10)
	return require(shared:WaitForChild("ActionCatalog", 10))
end

function Dispatcher.Create(ctx, services)
	services = services or {}
	local Ranks, Guard = ctx.Ranks, ctx.Guard
	local function Msg(key, ...)
		return ctx.Msg(key, ...)
	end
	local Catalog = services.Catalog or sharedCatalog()
	local http = services.HttpService or game:GetService("HttpService")
	local clock = services.Clock or os.clock
	local serverNow = services.ServerNow or function() return workspace:GetServerTimeNow() end
	local spawn = services.Spawn or task.spawn
	local delay = services.Delay or task.delay
	local wait = services.Wait or task.wait
	local ackWindow = services.AckWindow or ACK_WINDOW
	local verifyDelay = services.VerifyDelay or VERIFY_DELAY
	local readyCooldown = services.ReadyCooldown or READY_COOLDOWN
	local function isPlayer(value)
		if services.IsPlayer then return services.IsPlayer(value) end
		return typeof(value) == "Instance" and value:IsA("Player") and value.Parent == Players
	end
	local function getPlayers()
		return services.GetPlayers and services.GetPlayers() or Players:GetPlayers()
	end
	local send = services.Send or function(player, packet)
		ctx.Remotes.ActionDispatch:FireClient(player, packet)
	end
	local hooks = services.Hooks or HooksModule.Create(ctx, services)

	local api = {}
	local desired = {} -- [userId] = { [action] = { Params, Seq, By, ByName, Since, Source } } : ce que le serveur veut chez ce joueur
	local seqs = {} -- [userId] = { [action] = dernier numéro d'ordre émis }
	local pending = {} -- [id] = instruction envoyée et attendant sa réponse
	local readyAt = {} -- [userId] = horloge du dernier « Ready » accepté
	local unknownAcks = {} -- [userId] = { Count, Start }
	local watchers = {} -- [Player] = connexion CharacterAdded

	----------------------------------------------------------------------------------------------------------
	-- Helpers

	local function enabledFor(action)
		if not Catalog.Get(action) then return false end
		local tools = type(ctx.Settings) == "table" and ctx.Settings.ClientTools
		if type(tools) ~= "table" then return true end
		for _, entry in tools do
			local name = type(entry) == "string" and entry or (type(entry) == "table" and entry.Name)
			if name == action then return true end
		end
		return false
	end

	local function abuse(player, fr, en)
		if ctx.Sentinel and ctx.Sentinel.RecordAbuse then pcall(ctx.Sentinel.RecordAbuse, player, { fr = fr, en = en }) end
	end

	local function callHook(action, name, ...)
		local hook = hooks[action]
		local fn = hook and hook[name]
		if type(fn) ~= "function" then return nil end
		local ok, result = pcall(fn, ...)
		if not ok then
			warn(("[APM] Dispatcher %s.%s : %s"):format(action, name, tostring(result)))
			return nil
		end
		return result
	end

	local function prune()
		local now = clock()
		for id, record in pending do
			if record.Until < now then pending[id] = nil end
		end
	end

	local function nextSeq(userId, action)
		local per = seqs[userId]
		if not per then
			per = {}
			seqs[userId] = per
		end
		per[action] = (per[action] or 0) + 1
		return per[action]
	end

	-- Envoie UNE instruction à UN client. Renvoie son enregistrement d'attente, ou nil si l'envoi a échoué.
	-- prepare(record) s'exécute AVANT l'envoi : l'état voulu est donc déjà inscrit quand la réponse arrive, même instantanée.
	local function issue(target, action, op, params, batch, prepare)
		prune()
		local id = http:GenerateGUID(false)
		local record = { Id = id, UserId = target.UserId, Action = action, Op = op, Seq = nextSeq(target.UserId, action),
			Until = clock() + Catalog.TTL + 5, Batch = batch, Target = target }
		pending[id] = record
		if prepare then prepare(record) end
		local packet = { V = Catalog.Version, Id = id, Seq = record.Seq, Op = op, Effect = action, Params = params, Expires = serverNow() + Catalog.TTL }
		if batch then batch.Waiting += 1 end
		local ok = pcall(send, target, packet)
		if not ok then
			pending[id] = nil
			if batch then batch.Waiting -= 1 end
			return nil
		end
		return record
	end

	-- Le serveur ne veut plus cet effet chez ce joueur (ordre refusé par son client, arrêt, départ...)
	local function forgetDesired(userId, action, player, expectedSeq)
		local per = desired[userId]
		local entry = per and per[action]
		if not entry or (expectedSeq ~= nil and entry.Seq ~= expectedSeq) then return false end
		per[action] = nil
		if next(per) == nil then desired[userId] = nil end
		if player then callHook(action, "Clear", player) end
		return true
	end

	local function syncToolState(player, action, state)
		if type(ctx.ClientToolStates) == "table" then
			local states = ctx.ClientToolStates[player]
			if state and not states then
				states = {}
				ctx.ClientToolStates[player] = states
			end
			if states then states[action] = state or nil end
		end
	end

	-- Réponse d'un client à une instruction
	local function settle(record, status, detail)
		record.Status, record.Detail = status, detail
		local batch = record.Batch
		if batch then
			batch.Waiting -= 1
			if batch.Waiting <= 0 and batch.Thread then
				local thread = batch.Thread
				batch.Thread = nil
				spawn(thread)
			end
		end
		if record.Op == "Start" then
			if status == "Applied" then
				-- soutien serveur, seulement si l'effet est toujours voulu (un arrêt plus récent l'aurait retiré)
				local per = desired[record.UserId]
				local entry = per and per[record.Action]
				if entry and entry.Seq == record.Seq and isPlayer(record.Target) then
					entry.Confirmed = true
					if detail ~= "Armed" then callHook(record.Action, "Apply", record.Target, entry.Params) end
				end
			else
				forgetDesired(record.UserId, record.Action, record.Target, record.Seq)
				syncToolState(record.Target, record.Action, false)
			end
		end
	end

	-- Attend les réponses d'un lot, au plus ackWindow secondes (pas de boucle : le thread est réveillé par la dernière réponse ou par le délai)
	local function awaitAcks(batch)
		if batch.Waiting <= 0 then return end
		batch.Thread = coroutine.running()
		local timer = delay(ackWindow, function()
			local thread = batch.Thread
			if thread then
				batch.Thread = nil
				spawn(thread)
			end
		end)
		coroutine.yield()
		if typeof(timer) == "thread" then pcall(task.cancel, timer) end
	end

	----------------------------------------------------------------------------------------------------------
	-- Etat voulu

	function api.Handles(action)
		return enabledFor(action)
	end

	function api.GetState(player, action)
		local per = isPlayer(player) and desired[player.UserId]
		return per ~= nil and per ~= false and per[action] ~= nil
	end

	-- Actions voulues chez ce joueur : { [action] = true }
	function api.Active(player)
		local result = {}
		local per = isPlayer(player) and desired[player.UserId]
		if per then
			for action in per do result[action] = true end
		end
		return result
	end

	-- Description publique des actions que CET admin peut distribuer (panneau, aide)
	function api.Describe(admin)
		local list = {}
		for _, name in Catalog.Names() do
			if enabledFor(name) and (admin == nil or Ranks.CanUse(admin, name)) then
				table.insert(list, { Name = name, Kind = Catalog.Kind(name), Label = "Tool." .. name .. ".Label" })
			end
		end
		return list
	end

	-- Le panneau de l'admin (outil Fly / Noclip de sa propre fenêtre) annonce un changement sur SON personnage : le serveur le consigne
	function api.NoteClientState(player, action, state)
		if not isPlayer(player) or not enabledFor(action) or type(state) ~= "boolean" then return end
		local userId = player.UserId
		if state then
			local per = desired[userId]
			if not per then
				per = {}
				desired[userId] = per
			end
			local params = Catalog.CleanParams(action, nil, false)
			per[action] = { Params = params, Seq = 0, By = userId, ByName = player.Name, Since = os.time(), Source = "Panel", Confirmed = true }
			callHook(action, "Apply", player, params)
		elseif desired[userId] and desired[userId][action] then
			forgetDesired(userId, action, player)
		else
			callHook(action, "Clear", player)
		end
	end

	----------------------------------------------------------------------------------------------------------
	-- Bilan

	local function newTally(action, state)
		return { Action = action, State = state == true, Requested = 0, Affected = 0, Verified = 0, Pending = 0, Protected = 0, Failed = 0,
			Unconfirmed = 0, Idle = 0, Results = {}, Order = {}, Ok = false }
	end

	local function mark(tally, userId, name, status, detail)
		tally.Results[userId] = { Name = name, Status = status, Detail = detail }
		table.insert(tally.Order, userId)
	end

	--[[
		Applique (state = true) ou retire (state = false) une action sur une liste de joueurs. Renvoie le bilan :
		  Ok, Code (si refus global : NotAdmin | NoAccess | Unknown | InvalidValue | InvalidTarget | RateLimited),
		  Requested, Affected (accusé par le client), Verified (dont constatés par le serveur), Pending (acceptés, en attente de réapparition),
		  Protected, Failed, Unconfirmed (aucune réponse à temps, ou serveur en désaccord), Idle (arrêt demandé mais rien à arrêter),
		  Results[userId] = { Name, Status, Detail }.
		Un joueur n'est jamais compté « affecté » sans réponse de son client. Peut attendre jusqu'à ackWindow secondes.
	]]
	function api.Apply(admin, action, targets, state, options)
		options = options or {}
		local tally = newTally(action, state)
		if not enabledFor(action) then tally.Code = "Unknown" return tally end
		if not isPlayer(admin) or not Ranks.IsAdmin(admin) then tally.Code = "NotAdmin" return tally end
		if not Ranks.CanUse(admin, action) then
			tally.Code = "NoAccess"
			if ctx.Log then ctx.Log(admin.Name, action, nil, Msg("Log.NoAccess"), "Access", "warning") end
			return tally
		end
		if type(state) ~= "boolean" then tally.Code = "InvalidValue" return tally end
		if type(targets) ~= "table" or #targets == 0 then tally.Code = "InvalidTarget" return tally end
		local params = Catalog.CleanParams(action, options.Params, false)
		if not params then tally.Code = "InvalidValue" return tally end
		if not Guard.Allow(admin, "Dispatch", options.RateMax or 12, 10) then tally.Code = "RateLimited" return tally end

		local batch = { Waiting = 0 }
		local sent, seen = {}, {}
		for _, target in targets do
			local userId = (type(target) == "table" or typeof(target) == "Instance") and target.UserId or nil
			if userId and not seen[userId] then
				seen[userId] = true
				if tally.Requested >= MAX_BATCH then
					tally.Failed += 1
					mark(tally, userId, target.Name, "Failed", "Limit")
				else
					tally.Requested += 1
					if not isPlayer(target) then
						tally.Failed += 1
						mark(tally, userId, target.Name, "Failed", "Gone")
					elseif target ~= admin and not Ranks.CanTarget(admin, target) then
						tally.Protected += 1
						mark(tally, userId, target.Name, "Protected")
					else
						local record = issue(target, action, state and "Start" or "Stop", state and params or nil, batch, function(prepared)
							if state then
								local per = desired[userId]
								if not per then
									per = {}
									desired[userId] = per
								end
								per[action] = { Params = params, Seq = prepared.Seq, By = admin.UserId, ByName = admin.Name, Since = os.time(), Source = "Dispatch" }
								syncToolState(target, action, true)
								if ctx.Sentinel and ctx.Sentinel.Exempt then pcall(ctx.Sentinel.Exempt, target, 5, "APM " .. action) end
							else
								-- un arrêt est une décision du serveur : elle ne dépend pas de la réponse du client
								if not forgetDesired(userId, action, target) then callHook(action, "Clear", target) end
								syncToolState(target, action, false)
							end
						end)
						if not record then
							if state then forgetDesired(userId, action, target) end -- envoi impossible : rien n'est voulu
							tally.Failed += 1
							mark(tally, userId, target.Name, "Failed", "Send")
						else
							table.insert(sent, record)
						end
					end
				end
			end
		end
		if tally.Requested == 0 then tally.Code = "InvalidTarget" return tally end

		awaitAcks(batch)

		local needVerify = false
		if state and type(hooks[action]) == "table" and type(hooks[action].Verify) == "function" then
			for _, record in sent do
				if record.Status == "Applied" and record.Detail == nil then needVerify = true break end
			end
		end
		if needVerify then wait(verifyDelay) end -- le temps que l'état du client soit répliqué jusqu'au serveur

		for _, record in sent do
			local name = record.Target.Name
			local status, detail = record.Status, record.Detail
			if status == nil then
				tally.Unconfirmed += 1
				mark(tally, record.UserId, name, "Unconfirmed", "NoAnswer")
			elseif status == "Applied" and detail == "Armed" then
				tally.Pending += 1
				mark(tally, record.UserId, name, "Pending", "Armed")
			elseif status == "Applied" then
				local proof = isPlayer(record.Target) and callHook(action, "Verify", record.Target) or nil
				if proof == false then
					tally.Unconfirmed += 1
					mark(tally, record.UserId, name, "Unconfirmed", "Mismatch")
				else
					tally.Affected += 1
					if proof == true then tally.Verified += 1 end
					mark(tally, record.UserId, name, "Affected", proof == true and "Verified" or nil)
				end
			elseif status == "Stopped" then
				if detail == "Idle" then
					tally.Idle += 1
					mark(tally, record.UserId, name, "Idle")
				else
					tally.Affected += 1
					mark(tally, record.UserId, name, "Affected")
				end
			else
				tally.Failed += 1
				mark(tally, record.UserId, name, "Failed", detail or status)
			end
		end
		tally.Ok = tally.Affected + tally.Pending > 0 or (not state and tally.Idle > 0 and tally.Failed + tally.Unconfirmed + tally.Protected == 0)

		if ctx.Statistics and ctx.Statistics.RecordAction then pcall(ctx.Statistics.RecordAction, action, "Moderation", admin.Name, tally.Ok) end
		if ctx.Log then
			local first = tally.Results[tally.Order[1]]
			local label = tally.Requested == 1 and first and first.Name or ("(" .. tally.Requested .. ")")
			local level = (tally.Failed + tally.Unconfirmed + tally.Protected > 0) and "warning" or "info"
			ctx.Log(admin.Name, action, label, api.TallyMessage(tally), "Moderation", level)
		end
		return tally
	end

	-- Message chiffré d'un bilan : « Fly activé — 8 affecté(s), 2 protégé(s), 0 échec(s) » (+ non confirmés, en attente, déjà inactifs s'il y en a)
	function api.TallyMessage(tally)
		local suffix = tally.State and "On" or "Off"
		local failed = tally.Failed
		if tally.Unconfirmed > 0 or tally.Pending > 0 or tally.Idle > 0 then
			return Msg("Dispatch.Tally." .. suffix .. "Full", tally.Action, tally.Affected, tally.Protected, failed, tally.Unconfirmed, tally.Pending, tally.Idle)
		end
		return Msg("Dispatch.Tally." .. suffix, tally.Action, tally.Affected, tally.Protected, failed)
	end

	--[[
		Bilan -> (Ok, Code, Text, Details) pour Sentinel et le panneau. Code : Done | Partial | Failed | Protected | Denied | RateLimited | Invalid | Unavailable.
		Une cible : phrase simple. Plusieurs : le bilan chiffré, avec le détail des échecs.
	]]
	function api.Summarize(tally)
		if tally.Code then
			if tally.Code == "NotAdmin" or tally.Code == "NoAccess" then return false, "Denied", Msg("Srv.NoModuleAccess") end
			if tally.Code == "RateLimited" then return false, "RateLimited", Msg("Assistant.RateLimited") end
			if tally.Code == "InvalidTarget" then return false, "NotFound", Msg("Srv.SelectValidPlayer") end
			if tally.Code == "InvalidValue" then return false, "Invalid", Msg("Assistant.Invalid") end
			return false, "Unavailable", Msg("Assistant.Unavailable")
		end
		local action = tally.Action
		if tally.Requested == 1 then
			local userId = tally.Order[1]
			local item = tally.Results[userId]
			local name = item.Name
			if item.Status == "Affected" then
				return true, "Done", Msg(tally.State and "Dispatch.One.On" or "Dispatch.One.Off", action, name)
			elseif item.Status == "Pending" then
				return true, "Done", Msg("Dispatch.Armed", action, name)
			elseif item.Status == "Idle" then
				return false, "Failed", Msg("Dispatch.AlreadyOff", action, name)
			elseif item.Status == "Protected" then
				return false, "Protected", Msg("Srv.ProtectedRank", name)
			elseif item.Status == "Unconfirmed" then
				return false, "Failed", Msg(item.Detail == "Mismatch" and "Dispatch.Mismatch" or "Dispatch.Unconfirmed", action, name)
			end
			return false, "Failed", Msg("Dispatch.Rejected", action, name, tostring(item.Detail or "?"))
		end
		local details = {}
		for _, userId in tally.Order do
			local item = tally.Results[userId]
			if #details >= 3 then break end
			if item.Status == "Unconfirmed" then
				table.insert(details, Msg(item.Detail == "Mismatch" and "Dispatch.Mismatch" or "Dispatch.Unconfirmed", action, item.Name))
			elseif item.Status == "Failed" then
				table.insert(details, Msg("Dispatch.Rejected", action, item.Name, tostring(item.Detail or "?")))
			end
		end
		local text = api.TallyMessage(tally)
		local clean = tally.Affected + tally.Pending > 0 or tally.Ok
		local complete = tally.Protected + tally.Failed + tally.Unconfirmed == 0 and (tally.Idle == 0 or not tally.State)
		if not clean then
			return false, tally.Protected == tally.Requested and "Protected" or "Failed", text, details
		end
		return true, complete and "Done" or "Partial", text, details
	end

	--[[
		Contrat de ctx.Perform pour une action distribuée : (réussi, état, message). Permet au panneau (remote Action), aux commandes
		personnalisées et aux modules futurs d'appeler ctx.Perform(admin, "Fly", joueur, true) comme pour n'importe quelle commande.
		value : true / false ; nil = bascule selon l'état connu. target : nil = soi-même.
	]]
	function api.Perform(admin, action, target, value, emit, extra)
		emit = type(emit) == "function" and emit or function() end
		if not isPlayer(admin) then return false, "NotAdmin" end
		if target == nil then target = admin end
		if not isPlayer(target) then
			local message = Msg("Srv.SelectValidPlayer")
			emit(message, false)
			return false, "InvalidTarget", message
		end
		local state = value
		if state == nil then state = not api.GetState(target, action) end
		local tally = api.Apply(admin, action, { target }, state)
		local ok, code, message = api.Summarize(tally)
		local status = ok and "Done" or (code == "Denied" and "NoAccess" or code == "Protected" and "Protected" or code == "Invalid" and "InvalidValue"
			or code == "NotFound" and "InvalidTarget" or "Failed")
		if tally.Code == "NotAdmin" then status = "NotAdmin" end
		if message ~= nil then emit(message, ok) end
		return ok, status, message
	end

	----------------------------------------------------------------------------------------------------------
	-- Messages du client (ActionReport) : des réponses seulement, jamais une demande

	local function sendDesired(player)
		local per = desired[player.UserId]
		if not per then return end
		for action, entry in per do
			if entry.Source ~= "Panel" then -- un état lancé depuis le panneau de l'admin existe déjà sur son client
				local record = issue(player, action, "Start", entry.Params, nil)
				if record then entry.Seq = record.Seq end
			end
		end
	end

	function api.HandleReport(player, kind, a, b, c)
		if not isPlayer(player) then return end
		if type(kind) ~= "string" then
			abuse(player, "Type de message invalide", "Invalid message type")
			return
		end
		if not Guard.Allow(player, "ActionReport", 40, 10) then
			abuse(player, "Fréquence : actions distribuées", "Rate limit: distributed actions")
			return
		end
		if kind == "Ack" then
			if not Catalog.IsGuid(a) or type(b) ~= "string" or not Catalog.Statuses[b] or (c ~= nil and (type(c) ~= "string" or not Catalog.Details[c])) then
				abuse(player, "Accusé invalide", "Invalid acknowledgement")
				return
			end
			local record = pending[a]
			if not record then
				-- tardif ou inconnu : bénin une fois, suspect en rafale
				local bucket = unknownAcks[player.UserId]
				local now = clock()
				if not bucket or now - bucket.Start > 30 then
					bucket = { Count = 0, Start = now }
					unknownAcks[player.UserId] = bucket
				end
				bucket.Count += 1
				if bucket.Count > 8 then abuse(player, "Accusés inconnus", "Unknown acknowledgements") end
				return
			end
			if record.UserId ~= player.UserId then
				abuse(player, "Accusé forgé (identifiant d'un autre joueur)", "Forged acknowledgement (another player's id)")
				return
			end
			if record.Status ~= nil then return end -- déjà répondu : usage unique
			if clock() > record.Until then pending[a] = nil return end
			settle(record, b, c)
		elseif kind == "Ready" then
			if a ~= Catalog.Version then return end
			local now = clock()
			if readyAt[player.UserId] and now - readyAt[player.UserId] < readyCooldown then return end
			readyAt[player.UserId] = now
			sendDesired(player)
		elseif kind == "Ended" then
			if type(a) ~= "string" or not Catalog.Get(a) or type(b) ~= "string" or not Catalog.EndReasons[b] then
				abuse(player, "Fin d'effet invalide", "Invalid effect end")
				return
			end
			if forgetDesired(player.UserId, a, player) then
				syncToolState(player, a, false)
				if b == "Error" and ctx.Log then ctx.Log(player.Name, a, player.Name, Msg("Dispatch.EndedError", a), "Moderation", "warning") end
			end
		else
			abuse(player, "Type de message inconnu", "Unknown message type")
		end
	end

	----------------------------------------------------------------------------------------------------------
	-- Cycle de vie des joueurs

	function api.OnCharacter(player, character)
		local per = desired[player.UserId]
		if not per then return end
		for action in per do callHook(action, "OnCharacter", player, character) end
	end

	function api.Watch(player)
		if watchers[player] then return end
		watchers[player] = player.CharacterAdded:Connect(function(character)
			if not desired[player.UserId] then return end
			spawn(function()
				local root = character:WaitForChild("HumanoidRootPart", 10)
				if root and player.Character == character and isPlayer(player) then api.OnCharacter(player, character) end
			end)
		end)
	end

	-- Un joueur part : rien ne lui reste (ni état, ni instruction en attente), les lots qui l'attendaient sont libérés
	function api.Forget(player)
		if player == nil then return end
		local userId = player.UserId
		if watchers[player] then
			watchers[player]:Disconnect()
			watchers[player] = nil
		end
		local per = desired[userId]
		if per then
			for action in per do callHook(action, "Clear", player) end
		end
		desired[userId], seqs[userId], readyAt[userId], unknownAcks[userId] = nil, nil, nil, nil
		for id, record in pending do
			if record.UserId == userId then
				pending[id] = nil
				if record.Status == nil then
					record.Status, record.Detail = "Failed", "Error"
					local batch = record.Batch
					if batch then
						batch.Waiting -= 1
						if batch.Waiting <= 0 and batch.Thread then
							local thread = batch.Thread
							batch.Thread = nil
							spawn(thread)
						end
					end
				end
			end
		end
	end

	function api.Snapshot()
		local players, pendingCount = 0, 0
		for _ in desired do players += 1 end
		for _ in pending do pendingCount += 1 end
		return { PlayersWithEffects = players, Pending = pendingCount }
	end

	----------------------------------------------------------------------------------------------------------
	-- Panneau classique : remote DispatchAction (session privée des admins uniquement)

	-- mode "List" | "State" (action = joueur) | "Apply" (action, joueur ou "all", état)
	function api.HandlePanel(player, mode, action, target, state)
		if not isPlayer(player) or not Ranks.IsAdmin(player) or not Guard.Allow(player, "DispatchAction", 20, 10) then return false end
		if mode == "List" then
			return true, api.Describe(player)
		elseif mode == "State" then
			if not isPlayer(action) then return false end
			local active = api.Active(action)
			local visible = {}
			for name in active do
				if Ranks.CanUse(player, name) then visible[name] = true end
			end
			return true, visible
		elseif mode == "Apply" then
			if type(action) ~= "string" or type(state) ~= "boolean" then return false end
			local targets = {}
			if target == "all" then
				for _, other in getPlayers() do
					if #targets >= MAX_BATCH then break end
					if isPlayer(other) then table.insert(targets, other) end
				end
			elseif isPlayer(target) then
				targets = { target }
			else
				return false
			end
			local tally = api.Apply(player, action, targets, state)
			local ok, _, message, details = api.Summarize(tally)
			if ctx.Notify then ctx.Notify(player, message, ok) end
			for _, detail in details or {} do
				if ctx.Notify then ctx.Notify(player, detail, false) end
			end
			return ok, tally.Requested == 1 and isPlayer(target) and { [action] = state and ok or nil } or nil
		end
		return false
	end

	function api.Destroy()
		for player, connection in watchers do
			connection:Disconnect()
			watchers[player] = nil
		end
	end

	return api
end

----------------------------------------------------------------------------------------------------------
-- Branchement dans l'APM

function Dispatcher.Init(ctx)
	if ctx.Dispatcher and ctx.Dispatcher.Apply then return ctx.Dispatcher end
	local modules = type(ctx.Settings) == "table" and ctx.Settings.Modules
	if type(modules) == "table" and modules.Dispatcher == false then return nil end
	local api = Dispatcher.Create(ctx)
	ctx.Dispatcher = api
	local R = ctx.Remotes
	R.ActionReport.OnServerEvent:Connect(function(player, kind, a, b, c)
		api.HandleReport(player, kind, a, b, c)
	end)
	R.DispatchAction.OnServerInvoke = function(player, mode, action, target, state)
		return api.HandlePanel(player, mode, action, target, state)
	end
	Players.PlayerAdded:Connect(api.Watch)
	Players.PlayerRemoving:Connect(api.Forget)
	for _, player in Players:GetPlayers() do api.Watch(player) end
	return api
end

return Dispatcher
