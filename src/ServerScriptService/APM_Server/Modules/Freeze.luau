--[[
	Freeze : immobilise le joueur choisi (re-cliquer le dégèle). Durée en minutes (vide / 0 = jusqu'au dégel).
	Seul l'admin qui l'a gelé peut le dégeler (sauf le SuperRank). Le gel survit à la réapparition.
]]
local Players = game:GetService("Players")

local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Sanctions", 4
M.Color = Color3.fromRGB(70, 130, 200)
M.MinRank = "Staff"
M.Inputs = { "Minutes" }
M.Severity = "warning"

local frozen, frozenBy, timers = {}, {}, {}
local originals = setmetatable({}, { __mode = "k" }) -- [Character] = valeurs d'avant le gel
local watchers = {}

local function apply(target, on)
	local character = target and target.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return false
	end
	if on then
		if not originals[character] then
			originals[character] = { Anchored = root.Anchored, WalkSpeed = humanoid.WalkSpeed, JumpPower = humanoid.JumpPower, JumpHeight = humanoid.JumpHeight }
		end
		root.Anchored = true
		humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = 0, 0, 0
	else
		local saved = originals[character]
		if saved then
			root.Anchored = saved.Anchored
			humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight = saved.WalkSpeed, saved.JumpPower, saved.JumpHeight
			originals[character] = nil
		end
	end
	return true
end

local function release(userId)
	if timers[userId] then
		task.cancel(timers[userId])
		timers[userId] = nil
	end
end

function M.Init()
	local function watch(player)
		watchers[player] = player.CharacterAdded:Connect(function(character)
			local root = character:WaitForChild("HumanoidRootPart", 10)
			local humanoid = character:WaitForChild("Humanoid", 10)
			if root and humanoid and player.Character == character and frozen[player.UserId] then
				apply(player, true)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if watchers[player] then
			watchers[player]:Disconnect()
			watchers[player] = nil
		end
		frozen[player.UserId], frozenBy[player.UserId] = nil, nil
		release(player.UserId)
	end)
end

function M.Execute(ctx, admin, target, value)
	local userId = target.UserId
	local already = frozen[userId] == true
	if already and frozenBy[userId] ~= admin.UserId and not ctx.Ranks.IsSuper(admin) then
		return false, ctx.Msg("Mod.Freeze.OnlyAuthor", target.Name)
	end
	if not apply(target, not already) then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	release(userId)
	if already then
		frozen[userId], frozenBy[userId] = nil, nil
		return true, ctx.Msg("Mod.Freeze.Off", target.Name)
	end
	frozen[userId], frozenBy[userId] = true, admin.UserId
	local minutes = math.clamp(value.Minutes or 0, 0, 60 * 24)
	if minutes > 0 then
		timers[userId] = task.delay(minutes * 60, function()
			timers[userId] = nil
			if frozen[userId] then
				frozen[userId], frozenBy[userId] = nil, nil
				apply(target, false)
			end
		end)
		return true, ctx.Msg("Mod.Freeze.OnFor", target.Name, minutes)
	end
	return true, ctx.Msg("Mod.Freeze.On", target.Name)
end

return M

