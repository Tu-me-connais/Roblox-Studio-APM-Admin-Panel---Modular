--[[
	Funny.Scenes : moteur serveur des effets (autorité, réservation des personnages, démarrage, arrêt et restauration).
	Les clients publics se contentent d'afficher les décors (marqueurs dans Workspace.APM_FunnyScenes).
	Chaque scène est revérifiée en continu (droits, grade de la cible, personnage, durée) et arrêtée dès qu'une condition tombe.
	Journal : une scène locale est inscrite par cible ; une scène « tout le serveur » ou interserveurs n'ajoute qu'une ligne
	de résumé par serveur, pour ne pas chasser les vraies actions de modération du journal partagé.
]]
local Catalog = require(script.Parent.Catalog)
local CATALOG, BY_ID = Catalog.List, Catalog.ById

local Scenes = {}

local MAX_SKIN_LOOKUPS = 2 -- recherches d'avatar simultanées (API Roblox) par serveur, tous admins confondus

local function msg(fr, en, ...)
	if select("#", ...) > 0 then return { p = { fr = fr, en = en }, a = { ... }, n = select("#", ...) } end
	return { fr = fr, en = en }
end

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

function Scenes.Create(ctx, services)
	services = services or {}
	local players = services.Players or game:GetService("Players")
	local run = services.RunService or game:GetService("RunService")
	local world = services.Workspace or workspace
	local clock = services.Clock or os.clock
	local serverClock = services.ServerClock or function() return workspace:GetServerTimeNow() end
	local random = services.Random or Random.new()
	local spawn = services.Spawn or task.spawn
	local transforms = services.Transforms or require(script.Parent.Transforms).Create(ctx, services)
	local isPlayer = services.IsPlayer or function(p) return typeof(p) == "Instance" and p:IsA("Player") end
	local config = type(ctx.Settings.Funny) == "table" and ctx.Settings.Funny or {}
	local function limit(name, default, min, max)
		local n = config[name]
		return finite(n) and math.clamp(math.floor(n), min, max) or default
	end
	local maximum = limit("MaxDuration", 60, 5, 60)
	local maxActive = limit("MaxActiveScenes", 16, 1, 32)
	local maxGroup = limit("MaxGroupTargets", 8, 1, 12)
	local active, byTarget, connections = {}, {}, {}
	local skinLookups = 0
	local nextId = 0
	local destroyed = false
	local lastTick = -math.huge
	local sceneFolder = Instance.new("Folder")
	sceneFolder.Name = "APM_FunnyScenes"
	sceneFolder:SetAttribute("APMFunnyService", true)
	assert(not world:FindFirstChild(sceneFolder.Name), "[APM] Funny scene folder collision")
	sceneFolder.Parent = world
	local api = {}
	local remoteActors = {}

	function api.Can(p, permission)
		if remoteActors[p] then return ctx.Ranks.BroadcastPermission(p.UserId, permission, p.Cap) end
		return isPlayer(p) and p.Parent == players and ctx.Ranks.IsAdmin(p) and ctx.Ranks.HasPermission(p, "APM.AccessPanel") and ctx.Ranks.HasPermission(p, permission)
	end
	local function enabled()
		return not destroyed and config.Enabled ~= false and not (ctx.Settings.Modules and ctx.Settings.Modules.Funny == false)
	end
	local function effectOn(id)
		return BY_ID[id] ~= nil and (not ctx.Ranks.IsFeatureEnabled or ctx.Ranks.IsFeatureEnabled(Catalog.EffectFeature(id)))
	end
	-- « Au hasard » : parmi les décors visuels encore actifs (les effets sans permission dédiée)
	local function randomVisual()
		local pool = {}
		for _, entry in CATALOG do
			if entry.Permission == nil and effectOn(entry.Id) then table.insert(pool, entry.Id) end
		end
		return #pool > 0 and pool[random:NextInteger(1, #pool)] or nil
	end
	local function has(p, permission)
		return api.Can(p, permission)
	end
	local function canTarget(a, p)
		if not isPlayer(p) or p.Parent ~= players then return false end
		if remoteActors[a] then return ctx.Ranks.CanBroadcastTarget(a.UserId, p, a.Cap) end
		return p == a or ctx.Ranks.CanTarget(a, p)
	end
	local function character(p)
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if char and char.Parent and hum and hum.Health > 0 and root and root:IsA("BasePart") then return char, hum, root end
	end
	local function count()
		local n = 0
		for _ in active do n += 1 end
		return n
	end
	local function permitted(record)
		local permission = BY_ID[record.Scenario].Permission
		return enabled() and effectOn(record.Scenario) and has(record.Actor, "Funny.View") and has(record.Actor, "Funny.Use") and (not permission or has(record.Actor, permission))
			and (record.Scope ~= "Group" or has(record.Actor, "Funny.Group"))
			and (record.Reach == "Local" or has(record.Actor, "Funny.Server"))
			and (record.Reach ~= "CrossServer" or has(record.Actor, "Funny.CrossServer"))
			and (not record.NetworkValid or record.NetworkValid()) and (not record.NetworkEnds or serverClock() < record.NetworkEnds) and canTarget(record.Actor, record.Target)
	end
	local function same(record)
		-- Avatar resets may replace the root while the asynchronous API is still running.
		if record.Applying and (record.Scenario == "Skin" or record.Scenario == "BodyParts") then return transforms.IsSame(record) end
		local char, hum, root = character(record.Target)
		return char == record.Character and hum == record.Humanoid and root == record.Root
	end
	local function mayStop(a, r)
		if r.Actor.UserId == a.UserId then return true end
		local live = players:GetPlayerByUserId(r.Actor.UserId)
		if live then return has(a, "Funny.StopAll") and canTarget(a, live) end
		return has(a, "Funny.StopAll") and ctx.Ranks.CanTargetUserId and ctx.Ranks.CanTargetUserId(a, r.Actor.UserId) == true
	end
	local function release(record)
		if record.Model then record.Model:Destroy() end
		for _, desc in { record.BeforeDescription, record.NewDescription } do
			if desc then desc:Destroy() end
		end
		active[record.Id] = nil
		if remoteActors[record.Actor] then
			local held = false
			for _, r in active do
				if r.Actor == record.Actor then
					held = true
					break
				end
			end
			if not held then remoteActors[record.Actor] = nil end
		end
		if byTarget[record.Target] == record then byTarget[record.Target] = nil end
		if destroyed and count() == 0 then sceneFolder:Destroy() end
	end
	local function restore(record)
		if record.Cleaning or record.Applying then return end
		record.Cleaning = true
		spawn(function()
			local ok, err = pcall(transforms.Restore, record)
			if not ok then
				record.State = "RestoreFailed"
				record.Error = { fr = "Restauration du personnage impossible ; arrêter pour réessayer ou réapparaître.", en = "Character restoration failed; stop to retry or respawn." }
				record.Cleaning = false
				warn("[APM] Funny restore: " .. tostring(err))
				return
			end
			if ctx.Log and record.Reach == "Local" then ctx.Log(record.Actor.Name, "FunnyStop", record.Target.Name, ctx.Msg("Log.SceneStopped", BY_ID[record.Scenario].Label, "Funny.StopReason." .. tostring(record.StopReason)), "Funny", "info") end
			release(record)
		end)
	end
	local function stopTransaction(record, reason)
		local group = record.Transaction or { record }
		for _, item in group do
			if active[item.Id] == item then
				item.Cancelled = true
				item.StopReason = reason
				item.State = "Stopping"
				if item.Model then item.Model:SetAttribute("State", "Stopping") end
			end
		end
		for _, item in group do
			if active[item.Id] == item then restore(item) end
		end
	end

	function api.Reconcile()
		if api.Network then api.Network.Reconcile() end
		if next(active) == nil then return end -- aucune scène : rien à vérifier (appelé 10 fois par seconde)
		local list = {}
		for _, r in active do table.insert(list, r) end
		for _, record in list do
			if active[record.Id] == record then
				if record.State == "RestoreFailed" then
					if not same(record) then release(record) end
				elseif not record.Cancelled then
					if not permitted(record) then
						stopTransaction(record, "AccessRevoked")
					elseif not same(record) then
						stopTransaction(record, "CharacterChanged")
					elseif clock() >= record.EndAt then
						stopTransaction(record, "Expired")
					end
				end
			end
		end
	end

	local function marker(record)
		local model = Instance.new("Model")
		model.Name = "Scene_" .. record.Id
		record.Model = model
		for name, value in { APMFunny = true, Scenario = record.Scenario, TargetUserId = record.Target.UserId, Intensity = record.Intensity, Seed = random:NextInteger(1, 1000000),
			StartServer = record.StartServer, Duration = record.Duration, RenderVisual = BY_ID[record.Scenario].Permission == nil, State = "Running" } do
			model:SetAttribute(name, value)
		end
		model.Parent = sceneFolder
	end

	function api.Start(actor, request, metadata)
		metadata = metadata or {}
		if not has(actor, "Funny.View") or not has(actor, "Funny.Use") or not enabled() then return false, msg("Accès Funny refusé ou module désactivé.", "Funny denied or disabled.") end
		local clean = Catalog.ValidateRequest(request, maximum)
		if not clean then return false, msg("Paramètres de scène invalides.", "Invalid scene parameters.") end
		local scenario = clean.Scenario
		if scenario == "Random" then scenario = randomVisual() end
		if not scenario or not effectOn(scenario) then return false, msg("Effet désactivé dans les Paramètres.", "Effect disabled in Settings.") end
		local permission = BY_ID[scenario].Permission
		if permission and not has(actor, permission) then return false, msg("Permission de transformation ou de physique requise.", "Transformation or physics permission required.") end
		if clean.Scope == "Group" and not has(actor, "Funny.Group") then return false, msg("Permission de groupe requise.", "Group permission required.") end
		clean.Scenario = scenario
		api.Reconcile()
		if clean.Scope == "Server" then
			if not has(actor, "Funny.Server") then return false, msg("Permission serveur requise.", "Server permission required.") end
			local candidates = {}
			for _, p in players:GetPlayers() do
				if canTarget(actor, p) and character(p) and not byTarget[p] then table.insert(candidates, p) end
			end
			table.sort(candidates, function(a, b) return a.UserId < b.UserId end)
			local total, ids, failed = 0, {}, 0
			for _, p in candidates do
				if byTarget[p] or count() >= maxActive then continue end
				local one = table.clone(clean)
				one.Scope = "Player"
				one.TargetUserId = p.UserId
				local meta = table.clone(metadata)
				meta.Reach = metadata.Reach == "CrossServer" and "CrossServer" or "Server"
				local success, _, result = api.Start(actor, one, meta)
				if success then
					total += result.Count
					for _, id in result.Ids do table.insert(ids, id) end
				else
					failed += 1
				end
			end
			if total == 0 then return false, msg("Aucune cible éligible disponible ou limite atteinte.", "No eligible available target or scene limit reached.") end
			if ctx.Log then ctx.Log(actor.Name, "FunnyStart", "*", ctx.Msg("Log.SceneGroup", BY_ID[scenario].Label, total, clean.Duration, "Funny.Reach." .. (metadata.Reach or "Server")), "Funny", "info") end
			return true, msg("Situation lancée sur %s joueur(s) ; limites et grades appliqués.", "Scene started for %s player(s); limits and ranks enforced.", total),
				{ Scenario = scenario, Count = total, Ids = ids, Failed = failed, Reach = metadata.Reach or "Server" }
		end
		api.Reconcile()
		local targets = {}
		if clean.Scope == "Self" then
			targets = { actor }
		elseif clean.Scope == "Player" then
			local p = players:GetPlayerByUserId(clean.TargetUserId)
			if p then targets = { p } end
		else
			for _, p in players:GetPlayers() do
				if canTarget(actor, p) and character(p) and not byTarget[p] then table.insert(targets, p) end
			end
			for i = #targets, 2, -1 do
				local j = random:NextInteger(1, i)
				targets[i], targets[j] = targets[j], targets[i]
			end
			while #targets > maxGroup do table.remove(targets) end
		end
		if #targets == 0 then return false, msg("Aucune cible disponible.", "No available target.") end
		local partner
		if scenario == "BodyParts" then
			if clean.PartnerMode == "Player" then
				partner = players:GetPlayerByUserId(clean.PartnerUserId)
			else
				local candidates = {}
				for _, p in players:GetPlayers() do
					if p ~= targets[1] and character(p) and (clean.Operation == "Copy" or (canTarget(actor, p) and not byTarget[p])) then table.insert(candidates, p) end
				end
				if #candidates > 0 then partner = candidates[random:NextInteger(1, #candidates)] end
			end
			if not partner or partner == targets[1] or not character(partner) then return false, msg("Aucun partenaire distinct disponible.", "No distinct available partner.") end
			if clean.Operation == "Swap" then
				if not canTarget(actor, partner) then return false, msg("Le partenaire est protégé par son grade.", "The partner's rank is protected.") end
				table.insert(targets, partner)
			end
		end
		if count() + #targets > maxActive then return false, msg("Limite de scènes atteinte.", "Scene limit reached.") end
		local prepared = {}
		for _, target in targets do
			if not canTarget(actor, target) then return false, msg("Cible protégée par son grade.", "Target protected by rank.") end
			local char, hum, root = character(target)
			if not char or byTarget[target] then return false, msg("Personnage indisponible ou déjà réservé par une scène.", "Character unavailable or already reserved.") end
			nextId += 1
			table.insert(prepared, { Id = tostring(nextId), Actor = actor, Target = target, Scenario = scenario, Character = char, Humanoid = hum, Root = root, Scope = clean.Scope,
				Reach = metadata.Reach or "Local", NetworkId = metadata.NetworkId, Origin = metadata.Origin, NetworkEnds = metadata.Ends, NetworkValid = metadata.Valid,
				Intensity = clean.Intensity, Duration = clean.Duration, StartAt = clock(), StartServer = serverClock(), EndAt = clock() + clean.Duration,
				EndsAt = serverClock() + clean.Duration, State = "Preparing", Applying = true })
		end
		if scenario == "Skin" then
			if skinLookups >= MAX_SKIN_LOOKUPS then return false, msg("Recherche d'avatar déjà en cours ; réessaie dans un instant.", "Avatar lookup already in progress; try again shortly.") end
			skinLookups += 1
		end
		-- Reserve all affected characters before any avatar/network API can yield.
		for _, record in prepared do
			record.Transaction = prepared
			active[record.Id] = record
			byTarget[record.Target] = record
		end
		local skin
		local ok, err = pcall(function()
			if permission then
				for _, record in prepared do transforms.Capture(record) end
			end
			if scenario == "Skin" then
				local id, name
				skin, id, name = transforms.ResolveSkin(clean.Account)
				for _, r in prepared do
					r.NewDescription = skin:Clone()
					r.SourceAccount = name
					r.SourceUserId = id
				end
			elseif scenario == "BodyParts" then
				local donor = clean.Operation == "Swap" and prepared[2].BeforeDescription or transforms.ReadDescription(partner.Character:FindFirstChildOfClass("Humanoid"))
				prepared[1].NewDescription = transforms.CopyPart(prepared[1].BeforeDescription:Clone(), donor, clean.BodyPart)
				prepared[1].PartnerUserId = partner.UserId
				prepared[1].BodyPart = clean.BodyPart
				prepared[1].Operation = clean.Operation
				if clean.Operation == "Swap" then
					prepared[2].NewDescription = transforms.CopyPart(prepared[2].BeforeDescription:Clone(), prepared[1].BeforeDescription, clean.BodyPart)
					prepared[2].PartnerUserId = prepared[1].Target.UserId
					prepared[2].BodyPart = clean.BodyPart
					prepared[2].Operation = clean.Operation
				else
					donor:Destroy()
				end
			end
			for _, record in prepared do
				assert(not record.Cancelled and permitted(record) and same(record), "Authorization or character changed")
				if permission then
					transforms.Apply(record, clean)
				else
					(services.BuildVisual or marker)(record)
				end
				assert(not record.Cancelled and permitted(record) and same(record), "Authorization or character changed")
			end
		end)
		if scenario == "Skin" then skinLookups -= 1 end
		if skin then skin:Destroy() end
		for _, record in prepared do record.Applying = false end
		if not ok then
			stopTransaction(prepared[1], "ConstructionFailed")
			warn("[APM] Funny preparation: " .. tostring(err))
			return false, msg("Création annulée : personnage, avatar ou autorisation indisponible. Restauration demandée.", "Creation cancelled: character, avatar or authorization unavailable. Restoration requested.")
		end
		local now, serverNow = clock(), serverClock()
		for _, record in prepared do
			record.State = "Running"
			record.StartAt = now
			record.StartServer = serverNow
			record.EndsAt = math.min(serverNow + clean.Duration, record.NetworkEnds or math.huge)
			record.EndAt = now + math.max(0, record.EndsAt - serverNow)
			if record.Model then record.Model:SetAttribute("StartServer", serverNow) end
			if ctx.Log and record.Reach == "Local" then ctx.Log(actor.Name, "FunnyStart", record.Target.Name, ctx.Msg("Log.SceneLocal", BY_ID[scenario].Label, clean.Duration, tostring(record.SourceAccount or record.PartnerUserId or "")), "Funny", "info") end
		end
		local ids = {}
		for _, record in prepared do table.insert(ids, record.Id) end
		return true, msg("Situation lancée sur %s joueur(s).", "Scene started for %s player(s).", #prepared), { Scenario = scenario, Count = #prepared, Ids = ids, Reach = metadata.Reach or "Local" }
	end

	function api.Stop(actor, id)
		if not has(actor, "Funny.View") or type(id) ~= "string" or #id > 32 then return false, msg("Arrêt refusé.", "Stop denied.") end
		if id == "All" and not has(actor, "Funny.StopAll") then return false, msg("Permission d'arrêt étendu requise.", "Extended stop permission required.") end
		local matches = {}
		for _, record in active do
			if ((id == "Mine" and record.Actor.UserId == actor.UserId) or (id == "All" and mayStop(actor, record)) or (id == record.Id and mayStop(actor, record))) then table.insert(matches, record) end
		end
		if id ~= "Mine" and id ~= "All" and #matches == 0 then return false, msg("Scène absente ou protégée.", "Scene missing or protected.") end
		local grouped = 0
		for _, record in matches do
			if record.Reach ~= "Local" and not record.Cancelled then grouped += 1 end
		end
		if grouped > 0 and ctx.Log then ctx.Log(actor.Name, "FunnyStop", "*", ctx.Msg("Log.ScenesStopped", grouped), "Funny", "info") end
		for _, record in matches do stopTransaction(record, "Stopped") end
		return true, msg("Arrêt demandé ; restauration en cours.", "Stop requested; restoration in progress.")
	end

	function api.Snapshot(actor)
		if not has(actor, "Funny.View") then return nil end
		api.Reconcile()
		local rows, targets, partners, catalog = {}, {}, {}, {}
		for _, record in active do
			table.insert(rows, { Id = record.Id, Scenario = record.Scenario, Reach = record.Reach, NetworkId = record.NetworkId, Origin = record.Origin, ActorUserId = record.Actor.UserId,
				ActorName = record.Actor.Name, TargetUserId = record.Target.UserId, TargetName = record.Target.Name, Intensity = record.Intensity, Duration = record.Duration,
				EndsAt = record.EndsAt, State = record.State, Error = record.Error, SourceAccount = record.SourceAccount, PartnerUserId = record.PartnerUserId,
				BodyPart = record.BodyPart, Operation = record.Operation, CanStop = mayStop(actor, record) })
		end
		table.sort(rows, function(a, b) return tonumber(a.Id) < tonumber(b.Id) end)
		for _, p in players:GetPlayers() do
			local entry = { UserId = p.UserId, Name = p.Name, DisplayName = p.DisplayName, Available = character(p) ~= nil and not byTarget[p], CanSwap = canTarget(actor, p) }
			table.insert(partners, entry)
			if canTarget(actor, p) then table.insert(targets, entry) end
		end
		local function sort(a, b) return a.Name < b.Name end
		table.sort(targets, sort)
		table.sort(partners, sort)
		for _, entry in CATALOG do
			if effectOn(entry.Id) and (not entry.Permission or has(actor, entry.Permission)) then table.insert(catalog, table.clone(entry)) end
		end
		return { Allowed = true, Enabled = enabled(), Catalog = catalog, Targets = targets, Partners = partners, Active = rows, MaxDuration = maximum,
			MaxActiveScenes = maxActive, MaxGroupTargets = maxGroup, CanServer = has(actor, "Funny.Server"), CanCrossServer = has(actor, "Funny.CrossServer"),
			CanUse = has(actor, "Funny.Use"), CanGroup = has(actor, "Funny.Group"), CanStopAll = has(actor, "Funny.StopAll"), CanTransform = has(actor, "Funny.Transform"),
			CanPhysics = has(actor, "Funny.Physics"), SkinPresets = { { "Roblox", "Roblox" }, { "builderman", "builderman" }, { "mrflimflam", "mrflimflam" } } }
	end

	function api.CleanupPlayer(player)
		if api.Network then api.Network.StopMine(player) end
		local list = {}
		for _, r in active do
			if r.Actor == player or r.Target == player then table.insert(list, r) end
		end
		for _, r in list do stopTransaction(r, "PlayerLeft") end
	end

	function api.Destroy()
		destroyed = true
		if api.Network then api.Network.Destroy() end
		for _, c in connections do c:Disconnect() end
		local list = {}
		for _, r in active do table.insert(list, r) end
		for _, r in list do stopTransaction(r, "ServiceStopped") end
		if count() == 0 then sceneFolder:Destroy() end
	end

	table.insert(connections, players.PlayerRemoving:Connect(api.CleanupPlayer))
	table.insert(connections, run.Heartbeat:Connect(function()
		local now = clock()
		if now - lastTick < .1 then return end
		lastTick = now
		api.Reconcile()
		for _, r in active do
			if r.State == "Running" and BY_ID[r.Scenario].Permission then
				local ok = pcall(transforms.Update, r)
				if not ok then stopTransaction(r, "EffectError") end
			end
		end
	end))

	-- Interface utilisée par Funny.Network (diffusion entre serveurs)
	function api.Validate(request)
		return Catalog.ValidateRequest(request, maximum)
	end
	function api.ResolveScenario(id)
		if id == "Random" then return randomVisual() end
		return id
	end
	function api.ScenarioPermission(id)
		return BY_ID[id] and BY_ID[id].Permission
	end
	function api.StartRemote(envelope, valid)
		local _, resolved = ctx.Ranks.ResolveOfflineRank(envelope.Actor)
		if not resolved or valid and not valid() then return false end
		local actor = { UserId = envelope.Actor, Name = envelope.Name, Cap = { Level = envelope.Level, Permissions = envelope.Permissions } }
		remoteActors[actor] = true
		local metadata = { Reach = "CrossServer", NetworkId = envelope.Batch, Origin = envelope.Origin, Ends = envelope.Ends, Valid = valid }
		if not has(actor, "APM.AccessPanel") or not has(actor, "Funny.CrossServer") then
			remoteActors[actor] = nil
			return false
		end
		local success = api.Start(actor, envelope.Request, metadata)
		-- Keep the capability only while a restoration/scene holds a reference.
		if not success then remoteActors[actor] = nil end
		return success
	end
	function api.StopNetwork(batch, actorId, origin)
		local list = {}
		for _, r in active do
			if r.NetworkId == batch and r.Actor.UserId == actorId and r.Origin == origin then table.insert(list, r) end
		end
		for _, r in list do stopTransaction(r, "NetworkStopped") end
	end
	function api.NetworkIds(actor, id)
		local set = {}
		for _, r in active do
			if r.NetworkId and mayStop(actor, r) and (id == "All" or id == "Mine" and r.Actor.UserId == actor.UserId or id == r.Id) then set[r.NetworkId] = true end
		end
		return set
	end
	return api
end

return Scenes
