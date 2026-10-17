--[[
	Controls : bannissements persistants et verrouillage du serveur (les annonces sont dans Core.Announcements).

	BANS : une table dans le DataStore de l'APM (clé "Bans") : [userId] = { name, display, time, expire, by, reason, filtered } ;
	expire = 0 : définitif. Un ban (ou déban) est annoncé aux autres serveurs par MessagingService, qui relisent aussitôt ;
	sinon la table est relue au plus toutes les CACHE_SECONDS (économie de requêtes DataStore).
	Un banni qui se connecte est expulsé (message dans SA langue). Si les DataStores sont en panne, on applique la dernière
	liste connue et on revérifie le joueur en arrière-plan : une panne Roblox ne ferme pas le jeu à tout le monde.
	Mode mémoire (Studio sans DataStore) : les bans ne valent que pour ce serveur.
]]
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")
local clock, now, spawn, defer, wait = os.clock, os.time, task.spawn, task.defer, task.wait
local jobId = game.JobId

local Controls = {}

local CACHE_SECONDS = 120
local RETRY_SECONDS = 10 -- après une lecture ratée : une nouvelle tentative au plus toutes les 10 s pour tout le serveur
local MIN_FORCED_SECONDS = 5 -- regroupe les notifications et les rafraîchissements simultanés

local ctx, Ranks, Guard, Lang, Msg
local bans = {} -- [userId] = dossier du ban
local bansAt = -math.huge
local readFailed = false
local locked = false
local topic
local revision, reading, writing, refreshRequested = 0, false, false, false
local attemptedAt = -math.huge
local readOptions = Instance.new("DataStoreGetOptions")
readOptions.UseCache = false
local reconcileBans
local kicking = setmetatable({}, { __mode = "k" })

local function setBans(map)
	revision += 1
	bans = {}
	for key, record in map do
		local userId = tonumber(key)
		if userId and type(record) == "table" then
			bans[userId] = record
		end
	end
end

local function readBans(force)
	refreshRequested = refreshRequested or force == true
	local store = Ranks.GetStore()
	if not store then
		readFailed = Ranks.Memory ~= true
		if Ranks.Memory == true then
			-- The local map is authoritative in Studio memory mode; no remote refresh can arrive.
			refreshRequested = false
			if reconcileBans then reconcileBans() end
			return true
		end
		return false
	end
	if writing then return false end -- only an explicit force notification invalidates the pending mutation
	if reading then return false end
	if not refreshRequested and not readFailed and clock() - bansAt < CACHE_SECONDS then
		return true
	end
	if clock() - attemptedAt < (readFailed and RETRY_SECONDS or MIN_FORCED_SECONDS) then
		return false
	end
	reading, refreshRequested, attemptedAt = true, false, clock()
	local before = revision
	-- Bypass Roblox's short GetAsync cache when synchronizing a freshly changed ban.
	local ok, data = pcall(store.GetAsync, store, "Bans", readOptions)
	reading = false
	if ok then
		readFailed = false
		if revision == before and not refreshRequested then
			bansAt = clock()
			setBans(type(data) == "table" and data or {})
			if reconcileBans then reconcileBans() end
		else
			-- A local mutation or another notification invalidated this waiting read.
			refreshRequested = true
		end
	else
		readFailed = true
	end
	return ok
end

-- Prévient les autres serveurs qu'ils doivent relire la table des bans
local function announceChange()
	if topic and Ranks.GetStore() then
		spawn(function()
			pcall(MessagingService.PublishAsync, MessagingService, topic, jobId)
		end)
	end
end

local function writeBans(change)
	-- Serialize local mutations: a delayed older UpdateAsync response must not replace a newer one.
	while writing do wait(.05) end
	writing = true
	revision += 1 -- invalidate reads that began before this mutation, even while UpdateAsync is waiting
	local function finish(success)
		writing = false
		if reconcileBans then reconcileBans() end
		return success
	end
	local store = Ranks.GetStore()
	if not store then
		if Ranks.Memory ~= true then return finish(false) end -- une panne publiée ne devient jamais un mode mémoire
		local map = {}
		for userId, record in bans do
			map[tostring(userId)] = record
		end
		local ok, result = pcall(change, map)
		if not ok or result == false then return finish(false) end
		setBans(map)
		return finish(true)
	end
	local ok, result = pcall(store.UpdateAsync, store, "Bans", function(old)
		local map = type(old) == "table" and old or {}
		if change(map) == false then return nil end
		return map
	end)
	if ok and type(result) == "table" then
		setBans(result)
		bansAt = clock()
		readFailed = false
		writing = false
		announceChange()
		return finish(true)
	end
	warn("[APM] Écriture des bans impossible : " .. tostring(result))
	return finish(false)
end

-- « pour 2 h 05 min » dans la langue donnée
local function remaining(expire, lang)
	local rest = math.max(0, (expire or 0) - now())
	local minutes = rest // 60
	if minutes >= 60 then
		return Lang.Get(lang, "Time.ForHM", minutes // 60, minutes % 60)
	elseif minutes > 0 then
		return Lang.Get(lang, "Time.ForM", minutes)
	end
	return Lang.Get(lang, "Time.ForS", rest)
end

local function activeBan(record)
	if type(record) ~= "table" then return nil end
	local expire = tonumber(record.expire) or 0
	return (expire <= 0 or expire > now()) and record or nil
end

local function kickBanned(player, expected, personal)
	if player.Parent ~= Players or not activeBan(bans[player.UserId]) then kicking[player] = nil; return end
	local request = kicking[player]
	if not request then request = {} end
	if expected then request.Expected, request.Personal = expected, personal end
	if request.Scheduled then return end
	request.Scheduled = true
	kicking[player] = request
	defer(function()
		if kicking[player] ~= request then return end
		request.Scheduled = false
		-- A deferred kick must respect an Unban or expiration that completed in the meantime.
		local record = activeBan(bans[player.UserId])
		if record and not writing and not refreshRequested and player.Parent == Players then
			local lang = Lang.ForPlayer(player)
			local expire = tonumber(record.expire) or 0
			local message
			expected, personal = request.Expected, request.Personal
			if expected and record.time == expected.time and record.expire == expected.expire and record.by == expected.by then
				local why = (type(personal) == "string" and personal ~= "") and personal or record.reason
				message = Lang.Get(lang, "Kick.BannedBy", expire > 0 and remaining(expire, lang) or "", why and Lang.Get(lang, "Kick.Reason", why) or "")
			else
				message = Lang.Get(lang, "Kick.Banned", expire > 0 and remaining(expire, lang) or "")
			end
			pcall(function() player:Kick(message) end)
			kicking[player] = nil
		elseif not record or player.Parent ~= Players then
			kicking[player] = nil
		end
	end)
end

reconcileBans = function()
	-- Inspect the already loaded map, never read the DataStore once per connected player.
	for _, player in Players:GetPlayers() do kickBanned(player) end
end

-- Le compte est-il banni ? Renvoie le dossier du ban (un ban temporaire terminé est levé au passage)
function Controls.GetBan(userId)
	readBans(false)
	local record = bans[userId]
	if record and not activeBan(record) then
		spawn(Controls.Unban, userId, nil, record)
		return nil
	end
	return record
end

-- Bannit un compte (en ligne ou non). minutes <= 0 : définitif.
-- reason : motif déjà filtré pour tous (reasonFiltered = true obligatoire s'il y a un motif) ; personal : motif filtré pour le banni.
function Controls.Ban(adminName, userId, name, display, minutes, reason, reasonFiltered, personal, authorize)
	if authorize and not authorize() then return false, Msg("Srv.AccessChanged") end
	if type(reason) == "string" and reason ~= "" and reasonFiltered ~= true then
		return false, Msg("Srv.FilterDown")
	end
	minutes = tonumber(minutes) or 0
	if minutes ~= minutes or minutes == math.huge or minutes < 0 then
		minutes = 0
	end
	minutes = math.floor(math.min(minutes, 60 * 24 * 365))
	local expire = minutes > 0 and (now() + minutes * 60) or 0
	local record = {
		name = name or tostring(userId),
		display = display or name or tostring(userId),
		time = now(),
		expire = expire,
		by = adminName or "?",
		reason = (type(reason) == "string" and reason ~= "") and reason or nil,
		filtered = reasonFiltered == true,
	}
	if not writeBans(function(map)
		if authorize and not authorize() then return false end
		map[tostring(userId)] = record
	end) then
		return false, Msg("Srv.BanWriteFailed")
	end
	local live = Players:GetPlayerByUserId(userId)
	if live then kickBanned(live, record, personal) end
	local duration = expire > 0 and Msg("Srv.BanFor", minutes) or Msg("Srv.BanPermanent")
	return true, Msg("Srv.Banned", record.name, duration, record.reason and Msg("Msg.Reason", record.reason) or ""), record
end

-- Lève un ban : renvoie levé (true si le compte était banni), message d'erreur éventuel
function Controls.Unban(userId, authorize, expected)
	if authorize and not authorize() then return false,Msg("Srv.AccessChanged") end
	local was = bans[userId] ~= nil
	local written = writeBans(function(map)
		if authorize and not authorize() then return false end
		local current=map[tostring(userId)]
		if expected and (not current or current.time~=expected.time or current.expire~=expected.expire or current.by~=expected.by) then return false end
		if map[tostring(userId)] then
			was = true
		end
		map[tostring(userId)] = nil
	end)
	if not written then
		return false, Msg("Srv.UnbanWriteFailed")
	end
	return was, nil
end

function Controls.ListBans()
	readBans(true)
	local list = {}
	for userId, record in bans do
		table.insert(list, {
			userId = userId,
			name = record.name,
			display = record.display or record.name,
			time = record.time or 0,
			expire = record.expire or 0,
			by = record.by or "?",
			reason = record.filtered == true and record.reason or (record.reason and Msg("Srv.ReasonHidden") or nil),
		})
	end
	table.sort(list, function(a, b)
		return a.time > b.time
	end)
	return list
end

function Controls.IsLocked()
	return locked
end

-- Verrouille (true) / déverrouille le serveur : les nouveaux joueurs sans grade sont refusés
function Controls.SetLocked(state)
	locked = state == true
end

function Controls.Init(context, services)
	-- Optional service injection keeps regression tests independent of real players and published services.
	services = services or {}
	Players, MessagingService = services.Players or Players, services.MessagingService or MessagingService
	clock, now = services.Clock or clock, services.Time or now
	spawn, defer, wait = services.Spawn or spawn, services.Defer or defer, services.Wait or wait
	jobId = services.JobId or jobId
	ctx = context
	Ranks, Guard, Lang, Msg = ctx.Ranks, ctx.Guard, ctx.Lang, ctx.Msg
	local R = ctx.Remotes

	-- bannissement d'un compte par UserId, même hors ligne (onglet Bannissements, joueur hors serveur dans l'onglet Joueurs)
	R.BanUserId.OnServerInvoke = function(admin, targetUserId, minutes)
		if not Ranks.IsAdmin(admin) then
			return false, Msg("Srv.AccessDenied")
		end
		if not Ranks.CanUse(admin, "Ban") then
			return false, Msg("Srv.NoBanAccess")
		end
		if not Guard.Allow(admin, "BanUserId", 10, 30) then
			return false, Msg("Srv.TooManyBans")
		end
		targetUserId = tonumber(targetUserId)
		if not Ranks.ValidUserId(targetUserId) then
			return false, Msg("Srv.InvalidUserId")
		end
		if targetUserId == admin.UserId then
			return false, Msg("Srv.NotOnSelf")
		end
		local live = Players:GetPlayerByUserId(targetUserId)
		if not live and (tonumber(ctx.Settings.Group and ctx.Settings.Group.Id) or 0)>0 or (not live and game.CreatorType==Enum.CreatorType.Group) then
			local _, resolved = Ranks.ResolveOfflineRank(targetUserId)
			if not resolved then return false, { fr = "Grade hors ligne inaccessible ; sanction refusée par prudence.", en = "Offline rank unavailable; sanction refused as a precaution." } end
		end
		if not Ranks.CanTargetUserId(admin, targetUserId) then return false, Msg("Srv.TargetTooHigh") end
		local name = live and live.Name or tostring(targetUserId)
		if not live then
			pcall(function()
				name = Players:GetNameFromUserIdAsync(targetUserId)
			end)
		end
		if admin.Parent ~= Players or not Ranks.CanUse(admin, "Ban") or not Ranks.CanTargetUserId(admin, targetUserId) then
			return false, Msg("Srv.AccessChanged")
		end
		local ok, message = Controls.Ban(admin.Name, targetUserId, name, live and live.DisplayName or name, minutes,nil,nil,nil,function() return admin.Parent == Players and Ranks.IsAdmin(admin) and Ranks.CanUse(admin,"Ban") and Ranks.CanTargetUserId(admin,targetUserId) end)
		if ok then
			ctx.Log(admin.Name, "BanUserId", name, message, "Bans", "danger")
		end
		return ok, message
	end

	R.GetBanned.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) or not Guard.Allow(player, "GetBanned", 4, 10) then
			return nil
		end
		return Controls.ListBans()
	end

	-- verrouillage du serveur (onglet Paramètres, permission APM.ServerLock)
	R.SetServerLock.OnServerInvoke = function(admin, state)
		if not Ranks.IsAdmin(admin) or not Ranks.HasPermission(admin, "APM.ServerLock") or type(state)~="boolean" then
			return false, Msg("Srv.AccessDenied")
		end
		Controls.SetLocked(state == true)
		ctx.Log(admin.Name, "ServerLock", nil, Msg(locked and "Log.Locked" or "Log.Unlocked"), "System", "danger")
		return true, Msg(locked and "Srv.Locked" or "Srv.Unlocked")
	end
	R.GetServerLock.OnServerInvoke = function(player)
		return Ranks.IsAdmin(player) and locked
	end

	-- statut de ban dans la fiche profil
	ctx.AddProfileProvider(function(userId)
		local record = Controls.GetBan(userId)
		local value = "Common.No"
		if record then
			value = (tonumber(record.expire) or 0) > 0 and Msg("Profile.BannedUntil", { d = record.expire }) or Msg("Profile.BannedForever")
		end
		return { { Label = "Profile.Banned", Value = value } }
	end)

	-- synchronisation des bans entre serveurs
	topic = tostring(ctx.Settings.MessagingTopic or "APM_Sync_v1") .. "_Bans"
	if Ranks.GetStore() then
		spawn(function()
			pcall(function()
				MessagingService:SubscribeAsync(topic, function(message)
					if message.Data ~= jobId then
						spawn(readBans, true)
					end
				end)
			end)
		end)
	end

	-- connexion : verrou du serveur, puis ban (persistant)
	local function onJoin(player)
		Ranks.WaitResolved(player, 6)
		if not player.Parent then
			return
		end
		local lang = Lang.ForPlayer(player)
		if locked and not Ranks.IsAdmin(player) then
			pcall(function()
				player:Kick(Lang.Get(lang, "Kick.Locked"))
			end)
			return
		end
		local record = Controls.GetBan(player.UserId) -- en cas de panne : dernière liste connue
		if record and player.Parent then
			kickBanned(player)
			return
		end
		if readFailed then
			-- DataStores indisponibles : le joueur entre, et il est revérifié dès que la lecture refonctionne
			warn("[APM] Bans illisibles (DataStore) : " .. player.Name .. " sera revérifié en arrière-plan.")
			-- The shared polling loop retries once per server, including after the player has joined.
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		spawn(onJoin, player)
	end
	spawn(function()
		while true do
			wait(RETRY_SECONDS)
			readBans(false)
		end
	end)
end

return Controls
