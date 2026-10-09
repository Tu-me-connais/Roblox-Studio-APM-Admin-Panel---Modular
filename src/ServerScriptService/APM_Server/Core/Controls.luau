--[[
	Controls : bannissements persistants, verrouillage du serveur et annonces.

	BANS : une table dans le DataStore de l'APM (clé "Bans") : [userId] = { name, display, time, expire, by, reason, filtered } ;
	expire = 0 : définitif. Relue toutes les CACHE_SECONDS : un ban posé sur un serveur s'applique aux autres à leur prochaine lecture.
	Un banni qui se connecte est expulsé (message dans SA langue) ; si la lecture échoue, la connexion est refusée.
	Mode mémoire (Studio sans DataStore) : les bans ne valent que pour ce serveur.
]]
local Players = game:GetService("Players")

local Controls = {}

local CACHE_SECONDS = 30

local ctx, Ranks, Guard, Lang, Msg
local bans = {} -- [userId] = dossier du ban
local bansAt = -math.huge
local readFailed = false
local locked = false

local function setBans(map)
	bans = {}
	for key, record in map do
		local userId = tonumber(key)
		if userId and type(record) == "table" then
			bans[userId] = record
		end
	end
end

local function readBans(force)
	local store = Ranks.GetStore()
	if not store then
		readFailed = Ranks.Memory ~= true
		return
	end
	if not force and os.clock() - bansAt < CACHE_SECONDS then
		return
	end
	local ok, data = pcall(store.GetAsync, store, "Bans")
	if ok then
		readFailed = false
		bansAt = os.clock()
		setBans(type(data) == "table" and data or {})
	else
		readFailed = true
	end
end

local function writeBans(change)
	local store = Ranks.GetStore()
	if not store then
		if Ranks.Memory ~= true then return false end -- une panne publiée ne devient jamais un mode mémoire
		local map = {}
		for userId, record in bans do
			map[tostring(userId)] = record
		end
		if change(map) == false then return false end
		setBans(map)
		return true
	end
	local ok, result = pcall(store.UpdateAsync, store, "Bans", function(old)
		local map = type(old) == "table" and old or {}
		if change(map) == false then return nil end
		return map
	end)
	if ok and type(result) == "table" then
		setBans(result)
		bansAt = os.clock()
		return true
	end
	warn("[APM] Écriture des bans impossible : " .. tostring(result))
	return false
end

-- « pour 2 h 05 min » dans la langue donnée
local function remaining(expire, lang)
	local rest = math.max(0, (expire or 0) - os.time())
	local minutes = rest // 60
	if minutes >= 60 then
		return Lang.Get(lang, "Time.ForHM", minutes // 60, minutes % 60)
	elseif minutes > 0 then
		return Lang.Get(lang, "Time.ForM", minutes)
	end
	return Lang.Get(lang, "Time.ForS", rest)
end

-- Le compte est-il banni ? Renvoie le dossier du ban (un ban temporaire terminé est levé au passage)
function Controls.GetBan(userId)
	readBans(false)
	local record = bans[userId]
	if record and (tonumber(record.expire) or 0) > 0 and record.expire <= os.time() then
		task.spawn(Controls.Unban, userId, nil, record)
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
	local expire = minutes > 0 and (os.time() + minutes * 60) or 0
	local record = {
		name = name or tostring(userId),
		display = display or name or tostring(userId),
		time = os.time(),
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
	if live then
		local lang = Lang.ForPlayer(live)
		local why = (type(personal) == "string" and personal ~= "") and personal or record.reason
		local text = Lang.Get(lang, "Kick.BannedBy", expire > 0 and remaining(expire, lang) or "", why and Lang.Get(lang, "Kick.Reason", why) or "")
		pcall(function()
			live:Kick(text)
		end)
	end
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

function Controls.Init(context)
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
			if not resolved then return false, "Grade hors ligne inaccessible ; sanction refusée par prudence." end
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

	-- verrouillage du serveur (onglet Paramètres)
	R.SetServerLock.OnServerInvoke = function(admin, state)
		if not Ranks.HasPermission(admin, "APM.ManagePermissions") or type(state)~="boolean" then
			return false, Msg("Srv.ManageOnly", "Rank." .. Ranks.Manager)
		end
		Controls.SetLocked(state == true)
		ctx.Log(admin.Name, "ServerLock", nil, Msg(locked and "Log.Locked" or "Log.Unlocked"), "System", "danger")
		return true, Msg(locked and "Srv.Locked" or "Srv.Unlocked")
	end
	R.GetServerLock.OnServerInvoke = function(player)
		return Ranks.IsAdmin(player) and locked
	end

	-- annonce à tout le serveur (Settings.AnnounceRank et plus), filtrée par Roblox
	local lastAnnounce = {}
	R.Announce.OnServerEvent:Connect(function(admin, text)
		if admin.Parent~=Players or not Ranks.IsAdmin(admin) or not Ranks.HasRankAtLeast(admin, Ranks.Announcer) then
			ctx.Notify(admin, Msg("Srv.AnnounceOnly", "Rank." .. Ranks.Announcer), false)
			return
		end
		if type(text) ~= "string" then
			return
		end
		text = ctx.Filter.Clamp(text, 200)
		if not text then
			return
		end
		text = string.gsub(text, "^%s+", "")
		text = string.gsub(text, "%s+$", "")
		if text == "" then
			ctx.Notify(admin, Msg("Srv.EmptyMessage"), false)
			return
		end
		local now = os.clock()
		if lastAnnounce[admin.UserId] and now - lastAnnounce[admin.UserId] < 3 then
			ctx.Notify(admin, Msg("Srv.AnnounceWait"), false)
			return
		end
		lastAnnounce[admin.UserId] = now
		local filtered = ctx.Filter.Strings(text, admin.UserId)
		if not filtered then
			ctx.Notify(admin, Msg("Srv.AnnounceFilterDown"), false)
			return
		end
		if admin.Parent~=Players or not Ranks.IsAdmin(admin) or not Ranks.HasRankAtLeast(admin, Ranks.Announcer) then
			return
		end
		R.Announcement:FireAllClients(filtered.Broadcast, admin.Name)
		ctx.Notify(admin, Msg("Srv.AnnounceSent"), true)
		ctx.Log(admin.Name, "Announce", nil, filtered.Broadcast, "System", "info")
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastAnnounce[player.UserId] = nil
	end)

	-- statut de ban dans la fiche profil
	ctx.AddProfileProvider(function(userId)
		local record = Controls.GetBan(userId)
		local value = "Common.No"
		if record then
			value = (tonumber(record.expire) or 0) > 0 and Msg("Profile.BannedUntil", { d = record.expire }) or Msg("Profile.BannedForever")
		end
		return { { Label = "Profile.Banned", Value = value } }
	end)

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
		local record = Controls.GetBan(player.UserId)
		if readFailed then player:Kick("Vérification des bannissements indisponible. Veuillez réessayer.") return end
		if record and player.Parent then
			local message = Lang.Get(lang, "Kick.Banned", (tonumber(record.expire) or 0) > 0 and remaining(record.expire, lang) or "")
			task.defer(function()
				pcall(function()
					player:Kick(message)
				end)
			end)
		end
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end
end

return Controls
