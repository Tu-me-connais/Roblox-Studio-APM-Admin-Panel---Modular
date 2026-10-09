-- Noclip (outil client) : ton personnage traverse les murs. À combiner avec Fly pour ne pas tomber dans le vide.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local M = {}
M.Name, M.Order = "Noclip", 21

local connection
local original = {} -- [pièce] = true : collision coupée par l'outil
local activeCharacter

local function restore()
	for part in original do
		if part.Parent then
			part.CanCollide = true
		end
	end
	table.clear(original)
end

function M.Set(on)
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if not on then
		restore()
		return
	end
	connection = RunService.Stepped:Connect(function()
		local character = Players.LocalPlayer.Character
		if not character then
			return
		end
		if activeCharacter ~= character then
			restore()
			activeCharacter = character
		end
		for _, part in character:GetDescendants() do
			if part:IsA("BasePart") and part.CanCollide then
				original[part] = true
				part.CanCollide = false
			end
		end
	end)
end

function M.Refresh()
	local character = Players.LocalPlayer.Character
	if activeCharacter ~= character then
		restore()
		activeCharacter = character
	end
end

return M

