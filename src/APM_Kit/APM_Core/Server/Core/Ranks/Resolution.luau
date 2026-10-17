-- Ranks.Resolution : lecture asynchrone des sources (groupes) à la connexion, grades hors ligne et contrôles de diffusion.
local Players = game:GetService("Players")

return function(Ranks, S)
	local Settings = S.Settings

	-- Attend que les sources asynchrones (groupes) du joueur soient lues
	function Ranks.WaitResolved(player, timeout)
		local deadline = os.clock() + (timeout or 10)
		while player.Parent and not S.resolved[player.UserId] and os.clock() < deadline do
			task.wait(0.1)
		end
		return player.Parent == Players and S.resolved[player.UserId] == true and Ranks.SecurityReady and Ranks.AccessReady and Ranks.OwnerAuthorityReady
	end

	-- Roblox's per-peer role cache has an unspecified expiry; polling cannot promise immediate revocation.
	local GROUP_REFRESH_SECONDS, MAX_GROUP_REFRESHES = 120, 2
	local refreshAt, refreshPending = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
	local activeRefreshes = 0
	function S.resolve(player, refresh)
		if S.resolving[player] or player.Parent ~= Players then return end
		S.resolving[player] = true
		local userId = player.UserId
		local ok, problem = pcall(function()
			local group = Settings.Group
			local groupId = type(group) == "table" and tonumber(group.Id) or 0
			local sourcesOK, groupRank = true, nil
			if groupId and groupId > 0 and type(group.Ranks) == "table" then
				local value, rankOK = S.readGroupRank(userId, groupId, player)
				sourcesOK = rankOK
				if rankOK then groupRank = S.mapGroupRank(value) end
			end
			-- The experience owner's identity has its own sync/cache path; a membership refresh does not clear it on a network error.
			local owner = refresh and S.groupOwners[userId] == true or false
			if not refresh and game.CreatorType == Enum.CreatorType.Group and game.CreatorId ~= 0 then
				local ownerOK = S.readCreatorGroupOwner(false)
				sourcesOK = sourcesOK and ownerOK
				owner = ownerOK and userId == S.creatorGroupOwnerId
			end
			-- Network calls can finish after a departure or reconnect. Only this Player may consume their result.
			if player.Parent ~= Players or Players:GetPlayerByUserId(userId) ~= player then return end
			if sourcesOK then
				local changed = S.resolved[userId] ~= true or S.groupRanks[userId] ~= groupRank or S.groupOwners[userId] ~= (owner or nil)
				S.groupRanks[userId], S.groupOwners[userId], S.resolved[userId] = groupRank, owner or nil, true
				refreshAt[player] = os.clock() + GROUP_REFRESH_SECONDS
				if changed then S.publish() end
			elseif not refresh then
				S.resolved[userId] = nil
			end
		end)
		S.resolving[player] = nil
		-- A failed refresh neither grants a new role nor turns an API outage into an arbitrary grade removal.
		if refresh then refreshAt[player] = os.clock() + GROUP_REFRESH_SECONDS end
		if not ok then warn("[APM] Group resolution failed; retry scheduled: " .. tostring(problem)) end
	end

	function S.retryUnresolvedPlayers()
		for _, player in Players:GetPlayers() do
			if not S.resolved[player.UserId] and not S.resolving[player] then task.spawn(S.resolve, player) end
		end
	end

	function S.refreshResolvedGroupPlayers()
		local group = Settings.Group
		local groupId = type(group) == "table" and tonumber(group.Id) or 0
		if not groupId or groupId <= 0 or type(group.Ranks) ~= "table" then return end
		local now, due = os.clock(), {}
		for _, player in Players:GetPlayers() do
			if S.resolved[player.UserId] and not S.resolving[player] and not refreshPending[player]
				and now >= (refreshAt[player] or 0) then table.insert(due, player) end
		end
		-- Oldest checks first; the bounded batch must not repeatedly select the same accounts.
		table.sort(due, function(a, b)
			local first, second = refreshAt[a] or 0, refreshAt[b] or 0
			return first == second and a.UserId < b.UserId or first < second
		end)
		local launched = 0
		for _, player in due do
			if launched >= MAX_GROUP_REFRESHES or activeRefreshes >= MAX_GROUP_REFRESHES then break end
			launched += 1
			activeRefreshes += 1
			refreshPending[player] = true
			refreshAt[player] = now + GROUP_REFRESH_SECONDS
			task.spawn(function()
				local ok, problem = pcall(S.resolve, player, true)
				refreshPending[player] = nil
				activeRefreshes -= 1
				if not ok then warn("[APM] Group refresh failed: " .. tostring(problem)) end
			end)
		end
	end

	function Ranks.ResolveOfflineRank(userId)
		if not Ranks.ValidUserId(userId) or not Ranks.SecurityReady or not Ranks.OwnerAuthorityReady then return nil, false end
		local live = Players:GetPlayerByUserId(userId)
		if live then
			if not Ranks.WaitResolved(live, 8) then return nil, false end
			return Ranks.GetRank(live), true
		end
		local groupId = type(Settings.Group) == "table" and tonumber(Settings.Group.Id) or 0
		if (groupId and groupId > 0) or game.CreatorType == Enum.CreatorType.Group then
			if S.offlineResolvedAt[userId] and os.clock() - S.offlineResolvedAt[userId] < 60 then
				return Ranks.GetRealRankByUserId(userId), true
			end
			if userId <= 0 then return nil, false end
			if groupId and groupId > 0 then
				local value, ok = S.readGroupRank(userId, groupId, nil)
				if not ok then return nil, false end
				S.groupRanks[userId] = S.mapGroupRank(value)
			end
			if not S.readCreatorGroupOwner(false) then return nil, false end
			S.offlineResolvedAt[userId] = os.clock()
		end
		return Ranks.GetRealRankByUserId(userId), true
	end

	-- Resolve any network-backed owner sources before entering a permission-write transaction.
	-- The actual check remains non-yielding and reads the current real rank on every retry.
	function Ranks.PreparePermissionChange(actor, name)
		if name ~= "APM.AccessPanel" and name ~= "APM.ManagePermissions" then return true end
		if not Ranks.IsAdmin(actor) or not Ranks.HasPermission(actor, "APM.ManagePermissions") then return false end
		if Ranks.IsExperienceOwner(actor) and not S.simulations[actor.UserId] then return true end
		local ownerId, known = Ranks.ResolveExperienceOwnerUserId()
		if not known then return false end
		if ownerId == nil then return true end
		local _, resolved = Ranks.ResolveOfflineRank(ownerId)
		local currentId, currentKnown = Ranks.GetExperienceOwnerUserId()
		return resolved and currentKnown and currentId == ownerId
	end

	-- Server messages may only narrow authority resolved locally. No rank supplied by a client is trusted.
	function Ranks.BroadcastPermission(userId, name, cap)
		if not Ranks.SecurityReady or not Ranks.AccessReady or not Ranks.OwnerAuthorityReady
			or type(cap)~="table" or type(cap.Permissions)~="table" or cap.Permissions[name]~=true then return false end
		local live=Players:GetPlayerByUserId(userId)
		local rank=live and Ranks.GetRank(live) or Ranks.GetRealRankByUserId(userId)
		if not rank or not Ranks.Defaults[name] or not Ranks.Allowed(name,rank) then return false end
		return not live or Ranks.HasPermission(live,name)
	end
	function Ranks.CanBroadcastTarget(userId, target, cap)
		if not Ranks.BroadcastPermission(userId,"APM.AccessPanel",cap) or (typeof(target)~="Instance" or not target:IsA("Player") or target.Parent~=Players or not S.resolved[target.UserId])then return false end
		if target.UserId==userId then return true end
		if S.isCreator(target.UserId) or Ranks.GetRealRank(target)==Ranks.Super then return false end
		local live=Players:GetPlayerByUserId(userId)
		local rank=live and Ranks.GetRank(live) or Ranks.GetRealRankByUserId(userId)
		return math.min(Ranks.Level(rank),cap.Level)>Ranks.GetRealLevel(target)
	end
end
