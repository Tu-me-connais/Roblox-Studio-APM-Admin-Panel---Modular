--[[
	Grades : gestion des grades et de la matrice d'accès depuis l'onglet Paramètres (grade Settings.ManagerRank et plus),
	recherche de comptes (pseudo exact / UserId) et déclaration des outils client dans la matrice. Le serveur revérifie tout :
	  - on ne donne / retire qu'un grade strictement inférieur au sien, à un compte de grade strictement inférieur ;
	  - on ne change que les colonnes de la matrice des grades inférieurs au sien (le SuperRank peut tout).
]]
local Players = game:GetService("Players")

local Grades = {}

function Grades.Init(ctx)
	local Ranks, Guard, R, Msg = ctx.Ranks, ctx.Guard, ctx.Remotes, ctx.Msg

	local function canManage(admin)
		return Ranks.IsAdmin(admin) and Ranks.HasPermission(admin, "APM.ManagePermissions")
	end
	local function canChangeRank(admin, userId, rankId)
		if admin.Parent ~= Players or not canManage(admin) or userId == admin.UserId or Ranks.IsFixed(userId) then
			return false
		end
		if rankId and not Ranks.IsAssignable(rankId) then return false end
		return Ranks.IsSuper(admin) or (Ranks.Level(Ranks.GetRealRankByUserId(userId)) < Ranks.GetLevel(admin)
			and (not rankId or Ranks.Level(rankId) < Ranks.GetLevel(admin)))
	end
	local function canChangeColumn(admin, name, rankId)
		local allowed, reason = Ranks.CanManagePermissionColumn(admin, name, rankId)
		if allowed then return true end
		if reason == "AccessDenied" then
			return false, { fr = "La permission de gérer les accès est nécessaire.", en = "Permission to manage access is required." }
		end
		if reason == "InvalidParams" then
			return false, { fr = "Grade ou fonctionnalité indisponible.", en = "Rank or feature unavailable." }
		end
		if reason == "OwnerProtected" then
			return false, { fr = "Seul le propriétaire du jeu peut modifier cet accès critique.", en = "Only the game owner can change this critical access." }
		end
		if reason == "OwnerUnresolved" then return false, Msg("Srv.AccessChanged") end
		return false, { fr = "Tu peux modifier uniquement les accès des grades inférieurs au tien.", en = "You can change access only for ranks below yours." }
	end
	-- mêmes règles pour les changements groupés (module Features)
	Grades.CanManage = canManage
	Grades.CanChangeColumn = canChangeColumn

	-- Nom d'un compte : joueur présent, puis cache, puis annuaire (Roster, déjà en mémoire), et seulement en dernier
	-- recours une requête web Roblox. Sans ce cache, la liste des grades refaisait une requête par compte à chaque ouverture.
	local nameCache = {} -- [userId] = nom
	local function nameOf(userId)
		local live = Players:GetPlayerByUserId(userId)
		if live then
			nameCache[userId] = live.Name
			return live.Name
		end
		if nameCache[userId] then
			return nameCache[userId]
		end
		local entry = ctx.Roster and ctx.Roster.Get(userId)
		if type(entry) == "table" and type(entry.n) == "string" then
			nameCache[userId] = entry.n
			return entry.n
		end
		local name = tostring(userId)
		if userId > 0 then
			local ok, found = pcall(Players.GetNameFromUserIdAsync, Players, userId)
			if ok and type(found) == "string" then
				name = found
				nameCache[userId] = found
			end
		end
		return name
	end

	-- donne (rankId) / retire ("" ou nil) un grade à un UserId
	R.SetRank.OnServerInvoke = function(admin, targetUserId, rankId)
		if not canManage(admin) then
			return false, Msg("Srv.ManageOnly", "Rank." .. Ranks.Manager)
		end
		if not Guard.Allow(admin, "SetRank", 10, 30) then
			return false, Msg("Srv.TooManyChanges")
		end
		targetUserId = tonumber(targetUserId)
		if not Ranks.ValidUserId(targetUserId) then
			return false, Msg("Srv.InvalidUserId")
		end
		if targetUserId == admin.UserId then
			return false, Msg("Srv.NotOnSelf")
		end
		local _, sourcesOK = Ranks.ResolveOfflineRank(targetUserId)
		if not sourcesOK or not canManage(admin) then return false, Msg("Srv.AccessChanged") end
		if Ranks.IsFixed(targetUserId) then
			return false, Msg("Srv.FixedRank")
		end
		if rankId ~= nil and type(rankId) ~= "string" then return false, Msg("Srv.InvalidParams") end
		rankId = (type(rankId) == "string" and rankId ~= "") and rankId or nil
		if rankId and not Ranks.IsAssignable(rankId) then
			return false, Msg("Srv.UnknownRank")
		end
		if not Ranks.IsSuper(admin) then
			local level = Ranks.GetLevel(admin)
			if Ranks.Level(Ranks.GetRealRankByUserId(targetUserId)) >= level then
				return false, Msg("Srv.TargetTooHigh")
			end
			if rankId and Ranks.Level(rankId) >= level then
				return false, Msg("Srv.RankTooHigh")
			end
		end
		local ok, message = Ranks.SetRank(targetUserId, rankId, function()
			return canChangeRank(admin, targetUserId, rankId)
		end)
		if not ok then
			return false, message
		end
		local name = nameOf(targetUserId)
		ctx.Log(admin.Name, "SetRank", name, Msg("Log.RankSet", rankId and ("Rank." .. rankId) or "Common.None"), "Ranks", "danger")
		local effective = Ranks.GetRankDetailsByUserId(targetUserId)
		local remaining = effective.rank or ""
		if rankId then
			if effective.rank ~= rankId then
				return true, ctx.Lang.Phrase({
					fr = "Attribution du panneau %s donnée à %s. Grade effectif : %s.",
					en = "Panel assignment %s given to %s. Effective rank: %s.",
				}, "Rank." .. rankId, name, effective.rank and ("Rank." .. effective.rank) or "Common.None"), remaining
			end
			return true, Msg("Srv.RankGiven", "Rank." .. rankId, name), remaining
		end
		return true, ctx.Lang.Phrase({
			fr = "Attribution du panneau retirée à %s. Grade restant : %s.",
			en = "Panel assignment removed from %s. Remaining rank: %s.",
		}, name, effective.rank and ("Rank." .. effective.rank) or "Common.None"), remaining
	end

	R.GetRank.OnServerInvoke = function(player, targetUserId)
		if not Ranks.IsAdmin(player) or not Guard.Allow(player, "GetRank", 20, 10) then
			return nil
		end
		targetUserId = tonumber(targetUserId)
		return Ranks.ValidUserId(targetUserId) and Ranks.GetRankByUserId(targetUserId) or nil
	end

	-- comptes qui ont un grade (fixe, enregistré, de départ, ou en ligne grâce à un groupe / Studio) : section GRADES des Paramètres
	R.GetStaff.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) or not Guard.Allow(player, "GetStaff", 4, 10) then
			return nil
		end
		local ids = {}
		for userId in ctx.Settings.Users or {} do
			ids[userId] = true
		end
		for userId in ctx.Settings.DefaultUsers or {} do
			ids[userId] = true
		end
		for userId in Ranks.Dynamic do
			ids[userId] = true
		end
		for userId in Ranks.GetOwnerAccessOverrides() do ids[userId] = true end
		for _, other in Players:GetPlayers() do
			ids[other.UserId] = true
		end
		if game.CreatorType == Enum.CreatorType.User and game.CreatorId ~= 0 then
			ids[game.CreatorId] = true
		end
		local list = {}
		local actualOwner = Ranks.IsExperienceOwner(player) and not Ranks.GetSimulation(player).active
		for userId in ids do
			local details = type(userId) == "number" and Ranks.GetRankDetailsByUserId(userId) or nil
			local rank = details and details.rank
			if rank then
				local live = Players:GetPlayerByUserId(userId)
				local remaining = Ranks.GetRankDetailsByUserId(userId, true)
				table.insert(list, {
					userId = userId,
					name = nameOf(userId),
					rank = rank,
					online = live ~= nil,
					fixed = Ranks.IsFixed(userId),
					ownerOverride = Ranks.GetOwnerAccessOverride(userId),
					sources = details.sources,
					panelAssignment = details.panelAssignment,
					panelRank = details.panelRank,
					remainingRank = remaining.rank,
					remainingSources = remaining.sources,
					canRemove = details.panelAssignment and canChangeRank(player, userId, nil),
					canRevoke = actualOwner and not details.experienceOwner,
				})
			end
		end
		table.sort(list, function(a, b)
			if Ranks.Level(a.rank) ~= Ranks.Level(b.rank) then
				return Ranks.Level(a.rank) > Ranks.Level(b.rank)
			end
			return string.lower(a.name) < string.lower(b.name)
		end)
		return list
	end

	-- matrice d'accès
	R.GetModuleAccess.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) or not Guard.Allow(player, "GetModuleAccess", 20, 10) then
			return {}
		end
		return Ranks.GetModuleAccess()
	end

	R.SetModuleAccess.OnServerInvoke = function(admin, moduleName, rankId, allowed)
		if not canManage(admin) then
			return false, Msg("Srv.ManageOnly", "Rank." .. Ranks.Manager)
		end
		if not Guard.Allow(admin, "SetModuleAccess", 30, 30) then
			return false, Msg("Srv.TooManyChanges")
		end
		if type(moduleName) ~= "string" or #moduleName > 64 or type(rankId) ~= "string" or type(allowed) ~= "boolean" then
			return false, Msg("Srv.InvalidParams")
		end
		if not Ranks.PreparePermissionChange(admin, moduleName) then return false, Msg("Srv.AccessChanged") end
		local editable, reason = canChangeColumn(admin, moduleName, rankId)
		if not editable then return false, reason end
		local ok, message = Ranks.SetModuleAccess(moduleName, rankId, allowed, function()
			return canChangeColumn(admin, moduleName, rankId)
		end)
		if not ok then
			return false, message
		end
		ctx.Log(admin.Name, "SetModuleAccess", moduleName, Msg("Log.AccessSet", "Rank." .. rankId, allowed and "Common.Yes" or "Common.No"), "Access", "danger")
		return true, message
	end

	-- The server owns the catalogue. The legacy call only acknowledges known tools.
	local known, definitions = {}, {}
	for key, config in ctx.Settings.ClientTools or { "Fly", "Noclip", "ESP", "Spectator" } do
		local name = type(key) == "string" and key or (type(config) == "string" and config or (type(config) == "table" and config.Name))
		if type(name) == "string" and #name > 0 and #name <= 64 and not known[name] then
			known[name] = true
			local minimum = type(config) == "table" and config.MinRank or (type(key) == "string" and type(config) == "string" and config or nil)
			table.insert(definitions, { Name = name, MinRank = minimum })
		end
	end
	Ranks.InitModuleAccess(definitions)
	R.RegisterClientModules.OnServerInvoke = function(player, names)
		if not Ranks.IsAdmin(player) or type(names) ~= "table" or not Guard.Allow(player, "RegisterClientModules", 3, 30) then
			return false
		end
		local count = 0
		for _, name in names do
			count += 1
			if count > 100 or type(name) ~= "string" or not known[name] then return false end
		end
		return true
	end

	-- résolution d'un compte par pseudo exact ou UserId
	R.GlobalSearch.OnServerInvoke = function(player, query)
		if not Ranks.IsAdmin(player) or not Guard.Allow(player, "GlobalSearch", 10, 20) then
			return {}
		end
		if type(query) ~= "string" or query == "" or #query > 40 then
			return {}
		end
		query = string.match(query, "^%s*(.-)%s*$")
		if query == "" then
			return {}
		end
		local userId
		if string.match(query, "^%-?%d+$") then
			userId = tonumber(query)
		else
			for _, other in Players:GetPlayers() do
				if string.lower(other.Name) == string.lower(query) then
					userId = other.UserId
				end
			end
			if not userId then
				local ok, id = pcall(Players.GetUserIdFromNameAsync, Players, query)
				if ok and id then
					userId = id
				end
			end
		end
		if not Ranks.ValidUserId(userId) then
			return {}
		end
		local name = nameOf(userId)
		local live = Players:GetPlayerByUserId(userId)
		return { { userId = userId, name = name, displayName = live and live.DisplayName or name, online = live ~= nil } }
	end
end

return Grades
