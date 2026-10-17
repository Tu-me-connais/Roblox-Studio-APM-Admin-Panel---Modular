-- Ranks.Sync : démarrage et synchronisation entre serveurs.
local Players = game:GetService("Players")
local MessagingService = game:GetService("MessagingService")

return function(Ranks, S)
	-- Démarrage et synchronisation

	local started = false
	function Ranks.Init()
		if started then
			return
		end
		started = true
		Ranks.LoadRanks()
		Ranks.LoadAccess()
		Ranks.LoadOwnerAuthority()
		Ranks.InitModuleAccess({})
		Players.PlayerAdded:Connect(S.resolve)
		for _, player in Players:GetPlayers() do
			task.spawn(S.resolve, player)
		end
		Players.PlayerRemoving:Connect(function(player)
			local userId = player.UserId
			S.groupRanks[userId], S.groupOwners[userId], S.resolved[userId] = nil, nil, nil
			S.resolving[player] = nil
			S.offlineResolvedAt[userId] = nil
			if S.simulations[userId] and S.simulations[userId].timer then task.cancel(S.simulations[userId].timer) end
			S.simulations[userId] = nil
		end)
	end

	-- Relit grades et matrice quand un autre serveur les change (MessagingService). La relecture périodique n'est qu'un filet de
	-- sécurité : toutes les 2 à 3 min quand tout est prêt et l'abonnement actif (économie DataStore), sinon toutes les 25-35 s.
	local SAFETY_SECONDS, SAFETY_JITTER = 120, 60
	local RETRY_SECONDS, RETRY_JITTER = 25, 10
	local syncing = false
	local subscribed = false
	function Ranks.StartSync()
		if syncing then
			return
		end
		syncing = true
		local function refresh()
			local ranksBefore, accessBefore, ownerBefore = S.rankRevision, S.accessRevision, S.ownerRevision
			local wasReady = Ranks.SecurityReady and Ranks.AccessReady and Ranks.OwnerAuthorityReady
			Ranks.LoadRanks()
			Ranks.LoadAccess()
			Ranks.LoadOwnerAuthority()
			local ownerBeforeId = S.creatorGroupOwnerId
			S.readCreatorGroupOwner(false)
			local isReady = Ranks.SecurityReady and Ranks.AccessReady and Ranks.OwnerAuthorityReady
			if ranksBefore ~= S.rankRevision or accessBefore ~= S.accessRevision or ownerBefore ~= S.ownerRevision or wasReady ~= isReady or ownerBeforeId ~= S.creatorGroupOwnerId then
				if S.reconcileSimulations then S.reconcileSimulations() end
				if Ranks.OnChanged then Ranks.OnChanged() end
			end
		end
		if S.store then
			task.spawn(function()
				subscribed = pcall(function()
					MessagingService:SubscribeAsync(S.TOPIC, function(message)
						if message.Data ~= game.JobId then
							task.spawn(refresh)
						end
					end)
				end)
			end)
		end
		-- relecture DataStore de secours
		task.spawn(function()
			while true do
				local ready = Ranks.SecurityReady and Ranks.AccessReady and Ranks.OwnerAuthorityReady
				if ready and subscribed then
					task.wait(SAFETY_SECONDS + math.random() * SAFETY_JITTER)
				else
					task.wait(RETRY_SECONDS + math.random() * RETRY_JITTER)
				end
				if S.store then
					refresh()
				end
			end
		end)
		-- Retry unknown sources and poll confirmed membership in bounded batches (GroupService, no DataStore).
		task.spawn(function()
			while true do
				task.wait(RETRY_SECONDS + math.random() * RETRY_JITTER)
				S.retryUnresolvedPlayers()
				S.refreshResolvedGroupPlayers()
			end
		end)
	end
end
