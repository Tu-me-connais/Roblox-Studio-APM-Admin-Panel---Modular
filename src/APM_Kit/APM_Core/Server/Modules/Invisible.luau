-- Invisible (onglet Modération, outil de l'admin) : rend le personnage de l'admin invisible pour tous, nom compris. Survit à la réapparition.
local Players = game:GetService("Players")

local M = {}
M.Category, M.Mode, M.Order = "Moderation", "toggle", 3
M.Color = Color3.fromRGB(120, 110, 190)

local invisible = {} -- [userId] = true
local watchers, characters = {}, {}
local initialized = false

local function restoreItem(record, item)
	local transparency = record.Transparencies[item]
	if transparency ~= nil then
		item.Transparency = transparency
		record.Transparencies[item] = nil
	end
	local display = record.Displays[item]
	if display ~= nil then
		item.DisplayDistanceType = display
		record.Displays[item] = nil
	end
end

local function releaseCharacter(player)
	local record = characters[player]
	if not record then return end
	characters[player] = nil
	record.Added:Disconnect()
	record.Removing:Disconnect()
	for item in record.Transparencies do restoreItem(record, item) end
	for item in record.Displays do restoreItem(record, item) end
end

local function hideItem(player, record, item)
	if characters[player] ~= record or player.Character ~= record.Character or not invisible[player.UserId] then return end
	if item:IsA("BasePart") or item:IsA("Decal") or item:IsA("Texture") then
		if record.Transparencies[item] == nil then record.Transparencies[item] = item.Transparency end
		item.Transparency = 1
	elseif item:IsA("Humanoid") and item.Parent == record.Character then
		if record.Displays[item] == nil then record.Displays[item] = item.DisplayDistanceType end
		item.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

local function apply(player)
	local on = invisible[player.UserId] == true
	player:SetAttribute("APM_Invisible", on or nil)
	local character = player.Character
	if not on or not character then
		releaseCharacter(player)
		return
	end
	local record = characters[player]
	if not record or record.Character ~= character then
		releaseCharacter(player)
		record = { Character = character, Transparencies = setmetatable({}, { __mode = "k" }), Displays = setmetatable({}, { __mode = "k" }) }
		characters[player] = record
		record.Added = character.DescendantAdded:Connect(function(item)
			hideItem(player, record, item)
		end)
		record.Removing = character.DescendantRemoving:Connect(function(item)
			-- Equipped tools and accessories recover their appearance when moved out of this character.
			if characters[player] == record then restoreItem(record, item) end
		end)
	end
	for _, item in character:GetDescendants() do hideItem(player, record, item) end
end

function M.Init()
	if initialized then return end
	initialized = true
	local function hook(player)
		if watchers[player] then return end
		watchers[player] = {
			player.CharacterAdded:Connect(function()
				if invisible[player.UserId] then apply(player) end
			end),
			player.CharacterRemoving:Connect(function(character)
				local record = characters[player]
				if record and record.Character == character then releaseCharacter(player) end
			end),
		}
	end
	for _, player in Players:GetPlayers() do hook(player) end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(player)
		invisible[player.UserId] = nil
		apply(player)
		for _, connection in watchers[player] or {} do connection:Disconnect() end
		watchers[player] = nil
	end)
end

function M.Execute(ctx, admin, target, value)
	local on
	if type(value) == "boolean" then on = value else on = not invisible[admin.UserId] end
	invisible[admin.UserId] = on or nil
	apply(admin)
	return true, ctx.Msg(on and "Mod.Invisible.On" or "Mod.Invisible.Off"), on
end

function M.GetState(ctx, player)
	return invisible[player.UserId] == true
end

function M.OnAccessRevoked(ctx, player)
	invisible[player.UserId] = nil
	apply(player)
end
return M
