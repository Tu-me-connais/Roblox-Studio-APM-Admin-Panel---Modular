-- Godmode (onglet Modération, outil de l'admin) : santé infinie. La santé maximale d'origine est rendue à la désactivation.
local Players = game:GetService("Players")

local M = {}
M.Category, M.Mode, M.Order = "Moderation", "toggle", 4
M.Color = Color3.fromRGB(200, 170, 60)

local god = {} -- [userId] = true
local watchers = {}

local function apply(player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if god[player.UserId] then
		if humanoid:GetAttribute("APM_MaxHealth") == nil then
			humanoid:SetAttribute("APM_MaxHealth", humanoid.MaxHealth)
		end
		humanoid.MaxHealth = math.huge
		humanoid.Health = math.huge
	else
		local original = humanoid:GetAttribute("APM_MaxHealth")
		if type(original) == "number" then
			humanoid.MaxHealth = original
			humanoid.Health = original
			humanoid:SetAttribute("APM_MaxHealth", nil)
		end
	end
end

function M.Init()
	local function hook(player)
		watchers[player] = player.CharacterAdded:Connect(function()
			task.wait(0.3)
			if god[player.UserId] then
				apply(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		god[player.UserId] = nil
		if watchers[player] then watchers[player]:Disconnect() watchers[player]=nil end
	end)
end

function M.Execute(ctx, admin, target, value)
	local on
	if type(value) == "boolean" then
		on = value
	else
		on = not god[admin.UserId]
	end
	god[admin.UserId] = on or nil
	apply(admin)
	return true, ctx.Msg(on and "Mod.Godmode.On" or "Mod.Godmode.Off"), on
end

-- État actuel pour le panneau (interrupteur de l'onglet Modération)
function M.GetState(ctx, player)
	return god[player.UserId] == true
end

function M.OnAccessRevoked(ctx,player)
	god[player.UserId]=nil apply(player)
end
return M
