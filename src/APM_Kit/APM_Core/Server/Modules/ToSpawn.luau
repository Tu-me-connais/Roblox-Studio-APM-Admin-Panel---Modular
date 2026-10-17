-- ToSpawn : envoie le joueur choisi sur son point d'apparition (RespawnLocation, sinon un SpawnLocation de son équipe ou neutre), sans le tuer.
local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Movement", 10
M.Color = Color3.fromRGB(120, 100, 200)
M.AllowSelf = true

-- SpawnLocations connus : un seul parcours du Workspace au premier usage, puis suivi par événement
-- (évite de parcourir toute la map à chaque clic sur les grosses expériences).
local spawns, watching = {}, false
local function knownSpawns()
	if not watching then
		watching = true
		for _, item in workspace:GetDescendants() do
			if item:IsA("SpawnLocation") then spawns[item] = true end
		end
		workspace.DescendantAdded:Connect(function(item)
			if item.ClassName == "SpawnLocation" then spawns[item] = true end
		end)
	end
	for item in spawns do
		if not item:IsDescendantOf(workspace) then spawns[item] = nil end
	end
	return spawns
end

local function findSpawn(player)
	local own = player.RespawnLocation
	if own and own:IsDescendantOf(workspace) then
		return own
	end
	local neutral
	for item in knownSpawns() do
		if item.Enabled then
			if not item.Neutral and player.Team and item.TeamColor == player.TeamColor then
				return item
			end
			if item.Neutral and not neutral then
				neutral = item
			end
		end
	end
	return neutral
end

function M.Execute(ctx, admin, target)
	local character = target.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	local spawn = findSpawn(target)
	if not spawn then
		return false, ctx.Msg("Mod.ToSpawn.NoSpawn")
	end
	if ctx.Sentinel then ctx.Sentinel.NotifyServerTeleport(target,4,"APM ToSpawn") end
	character:PivotTo(spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3.5, 0))
	return true, ctx.Msg("Mod.ToSpawn.Done", target.Name)
end

return M
