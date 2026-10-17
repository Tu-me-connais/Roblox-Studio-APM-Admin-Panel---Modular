-- Ranks.Simulation : simulation temporaire d'un grade inférieur (jamais enregistrée).
local Players = game:GetService("Players")

return function(Ranks, S)
	local Settings = S.Settings

	function Ranks.GetSimulation(player)
		local simulation = S.simulations[player.UserId]
		if simulation and (simulation.expires <= os.clock() or not Ranks.HasRealPermission(player, "APM.Simulate")) then
			Ranks.ClearSimulation(player)
			simulation = nil
		end
		return {
			enabled = S.simulationEnabled(),
			active = simulation ~= nil,
			rank = simulation and simulation.rank or nil,
			realRank = Ranks.GetRealRank(player),
			permissions = Ranks.GetPermissions(player, false),
			realPermissions = Ranks.GetPermissions(player, true),
			custom = simulation ~= nil and simulation.permissions ~= nil,
			remaining = simulation and math.max(0, math.ceil(simulation.expires - os.clock())) or 0,
			actualOwner = Ranks.IsExperienceOwner(player),
		}
	end

	function Ranks.SetSimulation(player, rankId, permissions)
		if not S.simulationEnabled() then return false, { fr = "Simulation désactivée dans Settings.Modules côté serveur.", en = "Simulation disabled in server-side Settings.Modules." } end
		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
			or not Ranks.HasRealPermission(player, "APM.Simulate") or not Ranks.HasPermission(player, "APM.Simulate") then
			return false, { fr = "Permission de simulation refusée.", en = "Simulation permission denied." }
		end
		if rankId == "None" or rankId == "" then
			rankId = nil
		end
		if rankId ~= nil and (not S.rankOrNil(rankId) or Ranks.Level(rankId) > Ranks.GetRealLevel(player)) then
			return false, { fr = "La simulation ne peut pas dépasser votre grade réel.", en = "A simulation cannot exceed your real rank." }
		end
		local clean
		if permissions ~= nil then
			if type(permissions) ~= "table" or rankId == nil then
				return false, { fr = "Une configuration personnalisée exige un grade autorisé.", en = "A custom configuration requires an allowed rank." }
			end
			clean = {}
			local count = 0
			for name, allowed in permissions do
				count += 1
				if count > 200 or type(name) ~= "string" or #name > 64 or not Ranks.Defaults[name] or type(allowed) ~= "boolean" then
					return false, { fr = "Configuration de permissions invalide.", en = "Invalid permission configuration." }
				end
				if allowed and not Ranks.HasRealPermission(player, name) then
					return false, { fr = "La simulation ne peut pas accorder un droit absent de votre contexte réel.", en = "A simulation cannot grant a right missing from your real context." }
				end
				clean[name] = allowed
			end
		end
		S.simulationGeneration += 1
		local generation = S.simulationGeneration
		local previous = S.simulations[player.UserId]
		if previous and previous.timer then task.cancel(previous.timer) end
		S.simulations[player.UserId] = { rank = rankId, permissions = clean, expires = os.clock() + 300, generation = generation }
		-- Register expiry before session removal; expired callbacks cannot clear newer tests.
		S.simulations[player.UserId].timer = task.delay(300, function()
			local current = S.simulations[player.UserId]
			if current and current.generation == generation then
				current.timer = nil
				Ranks.ClearSimulation(player)
			end
		end)
		S.publish()
		return true, { fr = "Simulation activée pour cinq minutes. /apm-restore restaure le contexte réel.", en = "Simulation enabled for five minutes. /apm-restore restores the real context." }
	end

	function Ranks.ClearSimulation(playerOrId)
		local userId = typeof(playerOrId) == "Instance" and playerOrId.UserId or playerOrId
		if S.simulations[userId] then
			if S.simulations[userId].timer then task.cancel(S.simulations[userId].timer) end
			S.simulations[userId] = nil
			S.publish()
		end
		return true, { fr = "Contexte réel restauré.", en = "Real context restored." }
	end

	S.reconcileSimulations = function()
		for userId, simulation in S.simulations do
			local player = Players:GetPlayerByUserId(userId)
			local valid = player and simulation.expires > os.clock() and Ranks.HasRealPermission(player, "APM.Simulate")
				and Ranks.HasRealPermission(player, "APM.AccessPanel") and Ranks.Level(simulation.rank) <= Ranks.GetRealLevel(player)
			if valid and simulation.permissions then
				for name, allowed in simulation.permissions do
					if allowed and not Ranks.HasRealPermission(player, name) then
						valid = false
						break
					end
				end
			end
			if not valid then
				if simulation.timer then task.cancel(simulation.timer) end
				S.simulations[userId] = nil
			end
		end
	end
end
