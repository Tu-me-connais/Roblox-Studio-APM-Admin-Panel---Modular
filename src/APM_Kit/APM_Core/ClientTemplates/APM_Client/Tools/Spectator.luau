-- Spectator (outil client) : suit le joueur choisi et ses réapparitions. Flèches < / > : précédent / suivant.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local M = {}
M.Name, M.Order = "Spectator", 23

local Core
local active = false
local observed
local index = 0
local generation = 0
local inputConnection, removingConnection, cameraConnection
local characterAddedConnection, characterRemovingConnection

local function restoreCamera()
	local camera = workspace.CurrentCamera
	local localPlayer = Players.LocalPlayer
	local character = localPlayer and localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then camera.CameraSubject = humanoid end
end

local function clearTargetConnections()
	if characterAddedConnection then characterAddedConnection:Disconnect() characterAddedConnection = nil end
	if characterRemovingConnection then characterRemovingConnection:Disconnect() characterRemovingConnection = nil end
end

local function stop()
	active = false
	generation += 1 -- A delayed character load must not reclaim the camera after stopping.
	observed = nil
	clearTargetConnections()
	if inputConnection then inputConnection:Disconnect() inputConnection = nil end
	if removingConnection then removingConnection:Disconnect() removingConnection = nil end
	if cameraConnection then cameraConnection:Disconnect() cameraConnection = nil end
	restoreCamera()
end

local function candidates(excluded)
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if player ~= Players.LocalPlayer and player ~= excluded and humanoid and humanoid.Health > 0 then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end

local function followCharacter(player, character)
	generation += 1
	local mine = generation
	task.spawn(function()
		local humanoid = character and (character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10))
		if not active or mine ~= generation or observed ~= player or player.Parent ~= Players
			or player.Character ~= character or not humanoid or not humanoid:IsA("Humanoid") or not humanoid.Parent then return end
		local camera = workspace.CurrentCamera
		if camera then camera.CameraSubject = humanoid end
	end)
end

local function watch(player)
	local camera = workspace.CurrentCamera
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not camera or not player or player.Parent ~= Players or player == Players.LocalPlayer
		or not humanoid or humanoid.Health <= 0 then return false end
	generation += 1
	clearTargetConnections()
	observed = player
	camera.CameraSubject = humanoid
	characterAddedConnection = player.CharacterAdded:Connect(function(nextCharacter)
		if active and observed == player then followCharacter(player, nextCharacter) end
	end)
	characterRemovingConnection = player.CharacterRemoving:Connect(function()
		if active and observed == player then
			generation += 1
			restoreCamera()
		end
	end)
	if Core then Core.Toast(Core.L("Tool.Spectator.Watching", player.DisplayName), true) end
	return true
end

local function finish()
	M.Set(false) -- The Core wrapper also clears the declared tool state on the server.
	if Core and Core.AccessChanged then Core.AccessChanged:Fire() end
end

local function step(direction, excluded)
	local list = candidates(excluded)
	if #list == 0 then
		finish()
		return false
	end
	local current = table.find(list, observed)
	index = current or index
	index = ((index - 1 + direction) % #list) + 1
	return watch(list[index])
end

function M.Init(core)
	Core = core
end

-- target (facultatif) : joueur à observer, fourni par Sentinel (« spectate pseudo ») ; sinon le joueur choisi dans l'onglet Joueurs
function M.Set(on, target)
	stop()
	if not on then return end
	local list = candidates()
	local picked = (typeof(target) == "Instance" and target:IsA("Player") and target) or (Core and Core.Selected)
	if #list == 0 then return false end
	active = true
	if picked and watch(picked) then
		index = table.find(list, picked) or 1
	else
		index = 1
		if not watch(list[index]) then stop() return false end
	end
	inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.Right then step(1)
		elseif input.KeyCode == Enum.KeyCode.Left then step(-1) end
	end)
	removingConnection = Players.PlayerRemoving:Connect(function(leaving)
		if not active or observed ~= leaving then return end
		task.defer(function()
			if not active or observed ~= leaving then return end
			local nextList = candidates(leaving)
			if #nextList == 0 then finish() return end
			index = ((index - 1) % #nextList) + 1
			if not watch(nextList[index]) then finish() end
		end)
	end)
	cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		if active and observed then followCharacter(observed, observed.Character) end
	end)
	return true
end

function M.Refresh()
	if active and observed then followCharacter(observed, observed.Character) end
end

return M
