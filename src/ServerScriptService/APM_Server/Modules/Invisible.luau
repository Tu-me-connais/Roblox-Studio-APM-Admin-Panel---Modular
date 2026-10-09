-- Invisible (onglet Modération, outil de l'admin) : rend le personnage de l'admin invisible pour tous, nom compris. Survit à la réapparition.
local Players = game:GetService("Players")

local M = {}
M.Category, M.Mode, M.Order = "Moderation", "toggle", 3
M.Color = Color3.fromRGB(120, 110, 190)

local invisible = {} -- [userId] = true
local watchers = {}
local displayTypes = setmetatable({}, {__mode="k"})
local originals = setmetatable({}, { __mode = "k" }) -- [pièce] = transparence d'origine

local function apply(player)
	local character = player.Character
	if not character then
		return
	end
	local on = invisible[player.UserId] == true
	for _, item in character:GetDescendants() do
		if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then
			if on then
				if originals[item] == nil then
					originals[item] = item.Transparency
				end
				item.Transparency = 1
			elseif originals[item] ~= nil then
				item.Transparency = originals[item]
				originals[item] = nil
			end
		end
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if on then
			if not displayTypes[humanoid] then displayTypes[humanoid]=humanoid.DisplayDistanceType end
			humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
		elseif displayTypes[humanoid] then
			humanoid.DisplayDistanceType=displayTypes[humanoid] displayTypes[humanoid]=nil
		end
	end
	player:SetAttribute("APM_Invisible", on or nil)
end

function M.Init()
	local function hook(player)
		watchers[player] = player.CharacterAppearanceLoaded:Connect(function()
			task.wait(0.3)
			if invisible[player.UserId] then
				apply(player)
			end
		end)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		invisible[player.UserId] = nil
		if watchers[player] then watchers[player]:Disconnect() watchers[player]=nil end
	end)
end

function M.Execute(ctx, admin, target, value)
	local on
	if type(value) == "boolean" then
		on = value
	else
		on = not invisible[admin.UserId]
	end
	invisible[admin.UserId] = on or nil
	apply(admin)
	return true, ctx.Msg(on and "Mod.Invisible.On" or "Mod.Invisible.Off"), on
end

function M.OnAccessRevoked(ctx,player)
	invisible[player.UserId]=nil apply(player)
end
return M
