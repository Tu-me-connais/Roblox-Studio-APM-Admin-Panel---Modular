-- Ranks.Authority : grade effectif d'un compte, ciblage et permissions (réelles ou simulées).
local Players = game:GetService("Players")

return function(Ranks, S)
	local Settings, IS_STUDIO, CREATOR_RANK, STUDIO_RANK = S.Settings, S.IS_STUDIO, S.CREATOR_RANK, S.STUDIO_RANK

	local function higher(a, b)
		if not a then
			return b
		end
		if not b then
			return a
		end
		return Ranks.Level(a) >= Ranks.Level(b) and a or b
	end

	-- Grade fixé dans Settings (Users ou créateur) : non modifiable depuis le panneau
	function Ranks.IsFixed(userId)
		return S.rankOrNil(Settings.Users and Settings.Users[userId]) ~= nil or (CREATOR_RANK ~= nil and S.isCreator(userId))
	end

	function Ranks.GetRealRankByUserId(userId)
		userId = tonumber(userId)
		if not Ranks.ValidUserId(userId) or not Ranks.SecurityReady or not Ranks.OwnerAuthorityReady then
			return nil
		end
		if not S.isCreator(userId) and S.ownerOverrides[userId] then
			return S.ownerOverrides[userId] ~= "None" and S.ownerOverrides[userId] or nil
		end
		local fixed = S.rankOrNil(Settings.Users and Settings.Users[userId])
		local rank = fixed
		if CREATOR_RANK and S.isCreator(userId) then
			rank = higher(rank, CREATOR_RANK)
		end
		if Ranks.SecurityReady then
			local dynamic = Ranks.Dynamic[userId]
			if dynamic and dynamic ~= "None" then
				rank = higher(rank, S.rankOrNil(dynamic))
			elseif dynamic == nil then
				rank = higher(rank, S.rankOrNil(Settings.DefaultUsers and Settings.DefaultUsers[userId]))
			end
		end
		rank = higher(rank, S.groupRanks[userId])
		if STUDIO_RANK and IS_STUDIO and Players:GetPlayerByUserId(userId) ~= nil and (userId > 0 or userId == -1) then
			rank = higher(rank, STUDIO_RANK)
		end
		return rank
	end

	-- Source du grade réel et prévision après retrait de l'attribution du panneau (aucune écriture).
	function Ranks.GetRankDetailsByUserId(userId, removePanelAssignment)
		userId = tonumber(userId)
		local details = { rank = nil, sources = {}, panelAssignment = false, experienceOwner = false }
		if not Ranks.ValidUserId(userId) or not Ranks.SecurityReady or not Ranks.OwnerAuthorityReady then return details end
		details.experienceOwner = S.isCreator(userId)
		local dynamic = Ranks.Dynamic[userId]
		local panelRank = dynamic and dynamic ~= "None" and S.rankOrNil(dynamic) or nil
		local defaultRank = dynamic == nil and S.rankOrNil(Settings.DefaultUsers and Settings.DefaultUsers[userId]) or nil
		details.panelRank = panelRank or defaultRank
		details.panelAssignment = details.panelRank ~= nil
		local candidates, rank = {}, nil
		local function add(source, rankId)
			if not rankId then return end
			table.insert(candidates, { source = source, rank = rankId })
			rank = higher(rank, rankId)
		end
		local override = not details.experienceOwner and S.ownerOverrides[userId] or nil
		if override then
			add("OwnerOverride", override ~= "None" and S.rankOrNil(override) or nil)
		else
			add("Users", S.rankOrNil(Settings.Users and Settings.Users[userId]))
			if details.experienceOwner then add("Creator", CREATOR_RANK) end
			if not removePanelAssignment then
				add("Panel", panelRank)
				add("DefaultUsers", defaultRank)
			end
			add("Group", S.groupRanks[userId])
			if STUDIO_RANK and IS_STUDIO and Players:GetPlayerByUserId(userId) ~= nil and (userId > 0 or userId == -1) then
				add("Studio", STUDIO_RANK)
			end
		end
		details.rank = rank
		for _, candidate in candidates do
			if candidate.rank == rank then table.insert(details.sources, candidate.source) end
		end
		return details
	end

	function Ranks.GetRankByUserId(userId)
		userId = tonumber(userId)
		local real = Ranks.GetRealRankByUserId(userId)
		local simulation = userId and S.simulations[userId]
		if simulation then
			if simulation.expires <= os.clock() then
				Ranks.ClearSimulation(userId)
				return real
			end
			return simulation.rank
		end
		return real
	end

	function Ranks.GetRealRank(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return nil
		end
		return Ranks.GetRealRankByUserId(player.UserId)
	end

	function Ranks.GetRealLevel(player)
		return Ranks.Level(Ranks.GetRealRank(player))
	end

	function Ranks.GetRank(player)
		if typeof(player) ~= "Instance" or not player:IsA("Player") then
			return nil
		end
		return Ranks.GetRankByUserId(player.UserId)
	end

	function Ranks.GetLevel(player)
		return Ranks.Level(Ranks.GetRank(player))
	end

	function Ranks.IsAdmin(player)
		return Ranks.HasPermission(player, "APM.AccessPanel")
	end

	function Ranks.IsSuper(player)
		return Ranks.GetRank(player) == Ranks.Super
	end

	function Ranks.HasRankAtLeast(player, rankId)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
			or type(rankId) ~= "string" or not Ranks.ById[rankId] then return false end
		local level = Ranks.GetLevel(player)
		return level > 0 and level >= Ranks.Level(rankId)
	end

	-- L'admin peut-il agir sur ce compte ? (grade strictement supérieur ; sur soi-même : SuperRank seulement)
	function Ranks.CanTargetUserId(admin, userId)
		if not Ranks.ValidUserId(userId) or not Ranks.IsAdmin(admin) then
			return false
		end
		if admin.UserId == userId then
			return Ranks.IsSuper(admin)
		end
		local live = Players:GetPlayerByUserId(userId)
		if live and not S.resolved[userId] then return false end
		local groupId = type(Settings.Group) == "table" and tonumber(Settings.Group.Id) or 0
		if not live and ((groupId and groupId > 0) or game.CreatorType == Enum.CreatorType.Group)
			and (not S.offlineResolvedAt[userId] or os.clock() - S.offlineResolvedAt[userId] > 60) then return false end
		if S.isCreator(userId) then return false end
		local targetRank = Ranks.GetRealRankByUserId(userId)
		if targetRank == Ranks.Super then
			return false
		end
		return Ranks.GetLevel(admin) > Ranks.Level(targetRank)
	end

	function Ranks.CanTarget(admin, target)
		if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players then
			return false
		end
		return Ranks.CanTargetUserId(admin, target.UserId)
	end

	-- Ce joueur peut-il utiliser ce module ?
	function Ranks.CanUse(player, name)
		return Ranks.IsAdmin(player) and Ranks.HasPermission(player, name)
	end

	function Ranks.HasRealPermission(player, name)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
			or type(name) ~= "string" or not Ranks.AccessReady or not Ranks.SecurityReady or not Ranks.OwnerAuthorityReady then
			return false
		end
		if name == "APM.Simulate" and not S.simulationEnabled() then return false end
		local rank = Ranks.GetRealRank(player)
		return rank ~= nil and Ranks.Defaults[name] ~= nil and Ranks.Allowed(name, rank)
	end

	function Ranks.HasPermission(player, name)
		if not Ranks.HasRealPermission(player, name) then
			return false
		end
		local simulation = S.simulations[player.UserId]
		if not simulation then
			return true
		end
		if simulation.expires <= os.clock() then
			Ranks.ClearSimulation(player)
			return Ranks.HasRealPermission(player, name)
		end
		if not simulation.rank then
			return false
		end
		if simulation.permissions then
			return simulation.permissions[name] == true
		end
		return Ranks.Allowed(name, simulation.rank)
	end

	function Ranks.GetPermissions(player, real)
		local result = {}
		for name in Ranks.Defaults do
			result[name] = real and Ranks.HasRealPermission(player, name) or (not real and Ranks.HasPermission(player, name))
		end
		return result
	end

	function Ranks.CanManagePermissionColumn(actor, name, rankId)
		if typeof(actor) ~= "Instance" or not actor:IsA("Player") or actor.Parent ~= Players
			or not Ranks.IsAdmin(actor) or not Ranks.HasPermission(actor, "APM.ManagePermissions") then return false, "AccessDenied" end
		if type(name) ~= "string" or Ranks.Defaults[name] == nil or type(rankId) ~= "string" or not Ranks.ById[rankId] then return false, "InvalidParams" end
		local owner = Ranks.IsExperienceOwner(actor) and not S.simulations[actor.UserId]
		if (name == "APM.AccessPanel" or name == "APM.ManagePermissions") and not owner then
			if rankId == Settings.CreatorRank then return false, "OwnerProtected" end
			local ownerId, known = Ranks.GetExperienceOwnerUserId()
			if not known then return false, "OwnerUnresolved" end
			if ownerId then
				local live = Players:GetPlayerByUserId(ownerId)
				local groupId = type(Settings.Group) == "table" and tonumber(Settings.Group.Id) or 0
				if (live and not S.resolved[ownerId]) or (not live and groupId and groupId > 0
					and (not S.offlineResolvedAt[ownerId] or os.clock() - S.offlineResolvedAt[ownerId] >= 60)) then
					return false, "OwnerUnresolved"
				end
				if Ranks.GetRealRankByUserId(ownerId) == rankId then return false, "OwnerProtected" end
			end
		end
		return owner or Ranks.IsSuper(actor) or Ranks.Level(rankId) < Ranks.GetLevel(actor), "ColumnTooHigh"
	end
end
