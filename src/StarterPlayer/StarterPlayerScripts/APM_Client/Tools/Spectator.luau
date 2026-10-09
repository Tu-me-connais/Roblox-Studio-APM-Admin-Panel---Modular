-- Spectator (outil client) : la caméra suit le joueur choisi dans l'onglet Joueurs (sinon le premier de la liste). Flèches < / > : précédent / suivant.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local M = {}
M.Name, M.Order = "Spectator", 23

local Core
local active = false
local index = 0
local inputConnection, removingConnection

local function candidates()
	local list = {}
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
			table.insert(list, player)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

local function watch(player)
	local camera = workspace.CurrentCamera
	local humanoid = player and player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraSubject = humanoid
		if Core then
			Core.Toast(Core.L("Tool.Spectator.Watching", player.DisplayName), true)
		end
		return true
	end
	return false
end

local function step(direction)
	local list = candidates()
	if #list == 0 then
		return
	end
	index = ((index - 1 + direction) % #list) + 1
	watch(list[index])
end

local function stop()
	active = false
	if inputConnection then
		inputConnection:Disconnect()
		inputConnection = nil
	end
	if removingConnection then
		removingConnection:Disconnect()
		removingConnection = nil
	end
	local camera = workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if camera and humanoid then
		camera.CameraSubject = humanoid
	end
end

function M.Init(core)
	Core = core
end

function M.Set(on)
	stop()
	if not on then
		return
	end
	active = true
	local list = candidates()
	local picked = Core and Core.Selected
	if picked and picked ~= Players.LocalPlayer and watch(picked) then
		index = table.find(list, picked) or 0
	else
		index = 0
		step(1)
	end
	inputConnection = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.Right then
			step(1)
		elseif input.KeyCode == Enum.KeyCode.Left then
			step(-1)
		end
	end)
	removingConnection = Players.PlayerRemoving:Connect(function()
		if active then
			task.defer(step, 1)
		end
	end)
end

return M

