--[[
	APM_Notices : ce que TOUS les joueurs voient de l'APM (pas seulement les admins), dans LEUR langue :
	  - la bannière d'annonce du serveur (remote Announcement) ;
	  - la fenêtre d'avertissement (remote Warned) ;
	  - l'info « ton chat est coupé » / « tu peux de nouveau écrire » (remote Muted).
	Le serveur envoie ces événements ; ce script ne fait que les afficher (aucune action possible ici).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("APM_Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Remotes = require(Shared:WaitForChild("Remotes"))
if not Remotes.Claim("Notices") then
	return -- déjà lancé par une autre copie du client
end

local T = Config.Theme
local player = Players.LocalPlayer
-- Ce script public reste vivant quand le bundle privé est supprimé.
-- Il ne copie aucun outil ; il nettoie uniquement les ressources d'une session reçue.
local playerGui = player:WaitForChild("PlayerGui")
local privateCleanups = {}
local function watchPrivate(holder)
	if holder.Name ~= "APM_Private" then return end
	task.spawn(function()
		local root=holder:WaitForChild("APM_Client",10)
		local source=root and root:WaitForChild("Core",10)
		if not source then return end
		local ok,core=pcall(require,source)
		if not ok or type(core)~="table" or type(core.Stop)~="function" then return end
		if holder.Parent~=playerGui then core.Stop() return end
		privateCleanups[holder]=core.Stop
	end)
end
playerGui.ChildAdded:Connect(watchPrivate)
playerGui.ChildRemoved:Connect(function(holder)
	local cleanup=privateCleanups[holder] privateCleanups[holder]=nil
	if cleanup then cleanup() end
	if holder.Name=="APM_Private" then
		local id=holder:GetAttribute("SessionId")
		for _,gui in playerGui:GetChildren() do
			if id and gui:GetAttribute("APMPrivateSession")==id then gui:Destroy() end
		end
	end
end)
for _,holder in playerGui:GetChildren() do watchPrivate(holder) end

local function L(key, ...)
	return Lang.Get(Lang.Local(), key, ...)
end
local function text(value)
	return Lang.Text(Lang.Local(), value)
end

local gui = Instance.new("ScreenGui")
gui.Name = "APM_Notices"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 90
gui.Parent = player:WaitForChild("PlayerGui")

local function make(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props do
		instance[key] = value
	end
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
	instance.Parent = parent
	return instance
end

local function decorate(frame, radius, strokeColor)
	make("UICorner", { CornerRadius = UDim.new(0, radius) }, frame)
	if strokeColor then
		make("UIStroke", { Color = strokeColor, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, frame)
	end
end

-- Annonces ---------------------------------------------------------------------------------------------------------
local queue, showing = {}, false
local banner = make("Frame", { Name = "Announcement", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -140), Size = UDim2.new(0, 560, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel }, gui)
decorate(banner, 12, Color3.fromRGB(220, 170, 70))
make("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12), PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, banner)
make("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, banner)
make("UISizeConstraint", { MaxSize = Vector2.new(560, math.huge) }, banner)
local bannerTitle = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 16), Font = T.fontBold, TextSize = 12, TextColor3 = Color3.fromRGB(220, 170, 70),
	TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1, Text = "" }, banner)
local bannerText = make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Font = T.font, TextSize = 16,
	TextColor3 = T.text, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Text = "" }, banner)

local function pump()
	if showing then
		return
	end
	showing = true
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1)
			local message = string.sub(text(item.message), 1, 300)
			bannerTitle.Text = L("Notice.Announcement", item.by)
			bannerText.Text = message
			TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 24) }):Play()
			task.wait(math.clamp(3 + #message / 18, 5, 12))
			TweenService:Create(banner, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -140) }):Play()
			task.wait(0.4)
		end
		showing = false
	end)
end

Remotes.Get("Announcement", "RemoteEvent").OnClientEvent:Connect(function(message, by)
	if type(message) ~= "string" and type(message) ~= "table" then
		return
	end
	if #queue < 5 then
		table.insert(queue, { message = message, by = type(by) == "string" and string.sub(by, 1, 40) or "Admin" })
	end
	pump()
end)

-- Avertissement -------------------------------------------------------------------------------------------------------
local warning = make("Frame", { Name = "Warning", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel, Visible = false, ZIndex = 5 }, gui)
decorate(warning, 14, T.warn)
make("UIPadding", { PaddingTop = UDim.new(0, 16), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18) }, warning)
make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, warning)

local function warningLabel(order, size, font, color)
	return make("TextLabel", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Font = font, TextSize = size, TextColor3 = color,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, ZIndex = 6, Text = "" }, warning)
end
local warningTitle = warningLabel(1, 20, T.fontBold, T.warn)
local warningReason = warningLabel(2, 16, T.font, T.text)
local warningInfo = warningLabel(3, 12, T.font, T.sub)
local okButton = make("TextButton", { Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = T.accent, AutoButtonColor = true, Font = T.fontBold, TextSize = 14,
	TextColor3 = Color3.new(1, 1, 1), LayoutOrder = 4, ZIndex = 6, Text = "" }, warning)
decorate(okButton, 8)
okButton.Activated:Connect(function()
	warning.Visible = false
end)

Remotes.Get("Warned", "RemoteEvent").OnClientEvent:Connect(function(reason, by, count)
	local shown = (type(reason) == "string" or type(reason) == "table") and string.sub(text(reason), 1, 200) or ""
	warningTitle.Text = L("Notice.Warning")
	warningReason.Text = shown ~= "" and shown or L("Notice.DefaultReason")
	warningInfo.Text = L("Notice.WarnInfo", type(by) == "string" and by or L("Notice.Admin"), tostring(tonumber(count) or 1))
	okButton.Text = L("Notice.Understood")
	warning.Visible = true
end)

-- Chat coupé ------------------------------------------------------------------------------------------------------------
local notice = make("TextLabel", { Name = "MuteNotice", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90), Size = UDim2.fromOffset(0, 36),
	AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = T.panel, BackgroundTransparency = 0.05, Font = T.font, TextSize = 14, TextColor3 = T.text, Visible = false, Text = "" }, gui)
decorate(notice, 10)
make("UIPadding", { PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16) }, notice)
local noticeToken = 0
Remotes.Get("Muted", "RemoteEvent").OnClientEvent:Connect(function(muted, minutes)
	noticeToken += 1
	local mine = noticeToken
	if muted then
		notice.Text = (tonumber(minutes) or 0) > 0 and L("Notice.MutedFor", tonumber(minutes)) or L("Notice.Muted")
		notice.TextColor3 = T.warn
	else
		notice.Text = L("Notice.Unmuted")
		notice.TextColor3 = T.good
	end
	notice.Visible = true
	task.delay(5, function()
		if noticeToken == mine then
			notice.Visible = false
		end
	end)
end)
