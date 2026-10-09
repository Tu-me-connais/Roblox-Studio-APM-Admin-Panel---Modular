--[[
	Mute : coupe le chat du joueur choisi (re-cliquer le rétablit). Durée en minutes (vide / 0 = jusqu'au rétablissement).
	Fonctionne avec le chat TextChatService (celui des jeux récents) : les messages du joueur ne sont plus délivrés.
	Seul l'admin qui a coupé le chat peut le rétablir (sauf le SuperRank). Le joueur est prévenu dans sa langue (APM_Notices).
	Le module conserve les callbacks du jeu et rétablit la valeur initiale de TextSource.CanSend.
]]
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Sanctions", 9
M.Color = Color3.fromRGB(160, 90, 170)
M.MinRank = "Staff"
M.Inputs = { "Minutes" }
M.Severity = "warning"

local muted, mutedBy, timers = {}, {}, {}
local hooked = setmetatable({}, { __mode = "k" })
local mutedEvent

local function hook(channel)
	if not channel:IsA("TextSource") then return end
	if muted[channel.UserId] then
		if hooked[channel] == nil then hooked[channel] = channel.CanSend end
		channel.CanSend = false
	elseif hooked[channel] ~= nil then
		channel.CanSend = hooked[channel] hooked[channel] = nil
	end
end
local function applySources()
	for _,source in TextChatService:GetDescendants() do hook(source) end
end

local function release(userId)
	if timers[userId] then
		task.cancel(timers[userId])
		timers[userId] = nil
	end
end

function M.Init(ctx)
	mutedEvent = ctx.Remotes.Muted
	task.spawn(function()
		local folder = TextChatService:FindFirstChild("TextChannels") or TextChatService:WaitForChild("TextChannels", 60)
		if not folder then
			return
		end
		for _, channel in folder:GetDescendants() do
			hook(channel)
		end
		folder.DescendantAdded:Connect(hook)
	end)
	Players.PlayerRemoving:Connect(function(player)
		muted[player.UserId], mutedBy[player.UserId] = nil, nil
		applySources()
		release(player.UserId)
	end)
end

function M.Execute(ctx, admin, target, value)
	local userId = target.UserId
	local already = muted[userId] == true
	if already and mutedBy[userId] ~= admin.UserId and not ctx.Ranks.IsSuper(admin) then
		return false, ctx.Msg("Mod.Mute.OnlyAuthor", target.Name)
	end
	release(userId)
	if already then
		muted[userId], mutedBy[userId] = nil, nil
		applySources()
		mutedEvent:FireClient(target, false)
		return true, ctx.Msg("Mod.Mute.Off", target.Name)
	end
	muted[userId], mutedBy[userId] = true, admin.UserId
	applySources()
	local minutes = math.clamp(value.Minutes or 0, 0, 60 * 24 * 30)
	mutedEvent:FireClient(target, true, minutes)
	if minutes > 0 then
		timers[userId] = task.delay(minutes * 60, function()
			timers[userId] = nil
			if muted[userId] then
				muted[userId], mutedBy[userId] = nil, nil
				applySources()
				if target.Parent then
					mutedEvent:FireClient(target, false)
				end
			end
		end)
		return true, ctx.Msg("Mod.Mute.OnFor", target.Name, minutes)
	end
	return true, ctx.Msg("Mod.Mute.On", target.Name)
end

return M
