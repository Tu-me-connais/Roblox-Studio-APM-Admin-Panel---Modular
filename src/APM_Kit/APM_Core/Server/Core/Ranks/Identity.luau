-- Ranks.Identity : créateur / propriétaire du groupe, rang dans Settings.Group et attribution prioritaire du propriétaire (clé OwnerAuthority_v2).
local Players = game:GetService("Players")
local GroupService = game:GetService("GroupService")

return function(Ranks, S)
	local Settings, Msg, OWNER_KEY = S.Settings, S.Msg, S.OWNER_KEY

	-- Grade d'un compte

	S.groupRanks = {} -- [userId] = grade venant de Settings.Group (calculé à la connexion)
	S.groupOwners = {} -- [userId] = true : propriétaire du groupe qui possède le jeu
	S.resolved = {} -- [userId] = true : sources asynchrones (groupes) déjà lues
	S.offlineResolvedAt = {}
	S.creatorGroupOwnerId, S.creatorOwnerAt = nil, -math.huge
	S.creatorOwnerReading = false
	S.resolving = {} -- keyed by Player identity, not UserId, so reconnects cannot share a pending lookup
	function S.simulationEnabled()
		return type(Settings.Modules) ~= "table" or Settings.Modules.Simulation ~= false
	end

	function S.readCreatorGroupOwner(force)
		if game.CreatorType ~= Enum.CreatorType.Group or game.CreatorId == 0 then return true end
		if S.creatorOwnerReading then
			local deadline = os.clock() + 10
			while S.creatorOwnerReading and os.clock() < deadline do task.wait(0.1) end
			return not S.creatorOwnerReading and S.creatorGroupOwnerId ~= nil
		end
		-- Keep successful reads cached; a failed lookup must be retryable at the next sync tick.
		local cacheSeconds = S.creatorGroupOwnerId and 60 or 10
		if not force and os.clock() - S.creatorOwnerAt < cacheSeconds then return S.creatorGroupOwnerId ~= nil end
		S.creatorOwnerReading = true
		local ok, data = pcall(GroupService.GetGroupInfoAsync, GroupService, game.CreatorId)
		S.creatorOwnerReading = false
		S.creatorOwnerAt = os.clock()
		if not ok or type(data) ~= "table" or type(data.Owner) ~= "table" or not Ranks.ValidUserId(data.Owner.Id) then
			S.creatorGroupOwnerId = nil
			return false
		end
		S.creatorGroupOwnerId = data.Owner.Id
		return true
	end

	local function groupRank(value)
		return type(value) == "number" and value == value and value >= 0 and value <= 255 and value % 1 == 0
	end

	function S.readGroupRank(userId, groupId, player)
		local ok, data = pcall(function() return GroupService:GetRolesInGroupAsync(userId, groupId) end)
		if ok and type(data) == "table" and type(data.IsMember) == "boolean" then
			if not data.IsMember then return 0, true end
			if type(data.Roles) ~= "table" then return nil, false end
			local maximum = 0
			for _, role in data.Roles do
				if type(role) ~= "table" or not groupRank(role.Rank) then return nil, false end
				maximum = math.max(maximum, role.Rank)
			end
			return maximum, true
		end
		-- Compatibility with runtimes that only implement the legacy API.
		if player then
			local legacyOK, value = pcall(player.GetRankInGroup, player, groupId)
			if legacyOK and groupRank(value) then return value, true end
		end
		return nil, false
	end

	function S.mapGroupRank(value)
		if not groupRank(value) or value == 0 then return nil end
		local best, bestRank = -1, nil
		for minimum, rankId in (Settings.Group and Settings.Group.Ranks) or {} do
			if groupRank(minimum) and minimum >= 1 and S.rankOrNil(rankId) and value >= minimum and minimum > best then
				best, bestRank = minimum, rankId
			end
		end
		return bestRank
	end

	function S.isCreator(userId)
		if game.CreatorType == Enum.CreatorType.User then
			return game.CreatorId ~= 0 and userId == game.CreatorId
		end
		return S.creatorGroupOwnerId ~= nil and userId == S.creatorGroupOwnerId
	end

	function Ranks.IsExperienceOwner(player)
		return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players and S.isCreator(player.UserId)
	end

	-- Non-yielding identity read, safe inside an UpdateAsync validator. Unknown ownership fails closed.
	function Ranks.GetExperienceOwnerUserId()
		if game.CreatorId == 0 then return nil, true end
		if game.CreatorType == Enum.CreatorType.User then
			return game.CreatorId, Ranks.ValidUserId(game.CreatorId)
		end
		if game.CreatorType == Enum.CreatorType.Group then
			return S.creatorGroupOwnerId, S.creatorGroupOwnerId ~= nil and os.clock() - S.creatorOwnerAt < 60
		end
		return nil, false
	end
	function Ranks.ResolveExperienceOwnerUserId()
		if game.CreatorType == Enum.CreatorType.Group and not S.readCreatorGroupOwner(false) then return nil, false end
		return Ranks.GetExperienceOwnerUserId()
	end

	function Ranks.LoadOwnerAuthority()
		local data, ok = S.load(OWNER_KEY)
		if not ok then
			Ranks.OwnerAuthorityReady = false
			return false
		end
		-- Unknown newer schemas are not silently overwritten by this version.
		if data ~= nil and (type(data) ~= "table" or data.SchemaVersion ~= 2 or type(data.Users) ~= "table") then
			Ranks.OwnerAuthorityReady = false
			warn("[APM] Unsupported OwnerAuthority_v2 schema; access remains closed.")
			return false
		end
		Ranks.OwnerAuthorityReady = true
		local revision = data and tonumber(data._Revision) or 0
		if revision < S.ownerRevision then
			return true
		end
		S.ownerRevision = revision
		local safe = {}
		for key, value in data and data.Users or {} do
			local userId = tonumber(key)
			if Ranks.ValidUserId(userId) and (value == "None" or S.rankOrNil(value)) then
				safe[userId] = value
			end
		end
		S.ownerOverrides = safe
		return true
	end

	function Ranks.SetOwnerAccessOverride(owner, userId, rankId)
		if not Ranks.IsExperienceOwner(owner) or S.simulations[owner.UserId] then
			return false, { fr = "Seul le propriétaire réel de l'expérience, hors simulation, peut modifier ces accès.", en = "Only the actual experience owner, outside a simulation, can change these accesses." }
		end
		if not Ranks.ValidUserId(userId) or S.isCreator(userId) then
			return false, { fr = "Compte invalide ou propriétaire protégé.", en = "Invalid account or protected owner." }
		end
		if rankId ~= "None" and rankId ~= "Inherit" and not S.rankOrNil(rankId) then
			return false, Msg("Srv.UnknownRank")
		end
		if not Ranks.OwnerAuthorityReady or (not S.store and not Ranks.Memory) then
			return false, Msg("Srv.RankSaveFailed")
		end
		local value = rankId ~= "Inherit" and rankId or nil
		if not S.store then
			S.ownerOverrides[userId] = value
			S.ownerRevision += 1
			S.publish()
			return true, { fr = "Accès propriétaire enregistré.", en = "Owner access saved." }
		end
		local cancelled = false
		local ok, result = pcall(S.store.UpdateAsync, S.store, OWNER_KEY, function(old)
			if not Ranks.IsExperienceOwner(owner) or S.simulations[owner.UserId] or S.isCreator(userId) then
				cancelled = true
				return nil
			end
			if old ~= nil and (type(old) ~= "table" or old.SchemaVersion ~= 2 or type(old.Users) ~= "table") then
				cancelled = true
				return nil
			end
			local data = old or { SchemaVersion = 2, _Revision = 0, Users = {} }
			data.Users[tostring(userId)] = value
			data._Revision = (tonumber(data._Revision) or 0) + 1
			return data
		end)
		if not ok or cancelled or type(result) ~= "table" then
			return false, Msg("Srv.RankSaveFailed")
		end
		local revision = tonumber(result._Revision) or 0
		if revision >= S.ownerRevision then
			S.ownerRevision = revision
			local safe = {}
			for key, rank in result.Users do
				local id = tonumber(key)
				if Ranks.ValidUserId(id) and (rank == "None" or S.rankOrNil(rank)) then
					safe[id] = rank
				end
			end
			S.ownerOverrides = safe
		end
		S.publish()
		return true, { fr = "Accès propriétaire enregistré.", en = "Owner access saved." }
	end

	function Ranks.GetOwnerAccessOverride(userId)
		return S.ownerOverrides[userId] or "Inherit"
	end

	function Ranks.GetOwnerAccessOverrides()
		return table.clone(S.ownerOverrides)
	end
end
