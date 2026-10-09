-- Server-owned, temporary permission contexts. Real rank records are never edited.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local Simulation = {}

function Simulation.Init(ctx)
	local Ranks, Guard, R = ctx.Ranks, ctx.Guard, ctx.Remotes
	R.GetSimulation.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) or not Guard.Allow(player, "GetSimulation", 10, 10) then return nil end
		if type(ctx.Settings.Modules) == "table" and ctx.Settings.Modules.Simulation == false then
			return Ranks.GetSimulation(player)
		end
		if not Ranks.HasPermission(player, "APM.Simulate") and not Ranks.IsExperienceOwner(player) then return nil end
		return Ranks.GetSimulation(player)
	end
	R.SetSimulation.OnServerInvoke = function(player, rankId, permissions)
		if type(ctx.Settings.Modules) == "table" and ctx.Settings.Modules.Simulation == false then
			return false, "Simulation désactivée dans Settings.Modules côté serveur."
		end
		if not Guard.Allow(player, "SetSimulation", 6, 30) then return false, "Trop de changements de simulation." end
		if rankId ~= nil and (type(rankId) ~= "string" or #rankId > 64) then return false, "Grade invalide." end
		local before = Ranks.GetRealRank(player)
		local success, message = Ranks.SetSimulation(player, rankId, permissions)
		if success then
			ctx.Log(player.Name, "SetSimulation", player.Name, "Real=" .. tostring(before) .. "; effective=" .. tostring(rankId or "None"), "Security", "info")
		end
		return success, message
	end
	R.RestoreSimulation.OnServerInvoke = function(player)
		-- Clearing one's context is harmless even after real permission revocation.
		if not Guard.Allow(player, "RestoreSimulation", 6, 10) then return false, "Veuillez patienter." end
		local active = Ranks.GetSimulation(player).active
		local success, message = Ranks.ClearSimulation(player)
		if active then ctx.Log(player.Name, "RestoreSimulation", player.Name, "Real context restored", "Security", "info") end
		return success, message
	end
	R.SetOwnerAccessOverride.OnServerInvoke = function(owner, targetUserId, rankId)
		if not Guard.Allow(owner, "SetOwnerAccessOverride", 10, 30) then return false, "Trop de changements d'accès." end
		targetUserId = tonumber(targetUserId)
		if not Ranks.ValidUserId(targetUserId) or type(rankId) ~= "string" or #rankId > 64 then return false, "Paramètres invalides." end
		local success, message = Ranks.SetOwnerAccessOverride(owner, targetUserId, rankId)
		if success then
			ctx.Log(owner.Name, "OwnerAccessOverride", tostring(targetUserId), "Override=" .. rankId .. "; schema=2", "Access", "danger")
		end
		return success, message
	end

	local connections = {}
	local function hook(player)
		if connections[player] then return end
		connections[player] = player.Chatted:Connect(function(message)
			if type(message) == "string" and string.lower(string.match(message, "^%s*(.-)%s*$")) == "/apm-restore" then
				if Ranks.GetSimulation(player).active then
					Ranks.ClearSimulation(player)
					ctx.Log(player.Name, "RestoreSimulation", player.Name, "Chat recovery", "Security", "info")
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		if connections[player] then connections[player]:Disconnect(); connections[player] = nil end
		Ranks.ClearSimulation(player)
	end)
	for _, player in Players:GetPlayers() do hook(player) end
	-- TextChatCommand also handles modern chat, where slash commands may not fire Chatted.
	local command = TextChatService:FindFirstChild("APM_RestoreSimulation")
	if not command then
		command = Instance.new("TextChatCommand")
		command.Name = "APM_RestoreSimulation"
		command.PrimaryAlias = "/apm-restore"
		command.Parent = TextChatService
	end
	if command:IsA("TextChatCommand") and command.PrimaryAlias == "/apm-restore" then
		command.Triggered:Connect(function(source)
			local player = source and Players:GetPlayerByUserId(source.UserId)
			if player and Ranks.GetSimulation(player).active then
				Ranks.ClearSimulation(player)
				ctx.Log(player.Name, "RestoreSimulation", player.Name, "TextChatCommand recovery", "Security", "info")
			end
		end)
	else
		warn("[APM] Recovery chat command name is occupied; private RestoreSimulation remains available.")
	end
end

return Simulation
