--[[
	APM_Notices : ce que TOUS les joueurs voient de l'APM (pas seulement les admins), dans LEUR langue :
	  - l'annonce du serveur (remote Announcement), au style choisi par l'Owner (APM_Public.AnnounceStyle, rendu APM_Shared.Announcements) ;
	  - la fenêtre d'avertissement (remote Warned) ;
	  - l'info « ton chat est coupé » / « tu peux de nouveau écrire » (remote Muted).
	Le serveur envoie ces événements ; ce script ne fait que les afficher (aucune action possible ici).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("APM_Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Remotes = require(Shared:WaitForChild("Remotes"))
if not Remotes.Claim("Notices") then
	return -- déjà lancé par une autre copie du client
end
require(Shared:WaitForChild("FunnyVisuals")).Start()
-- Exécuteur des actions distribuées (Fly, Noclip...) : inactif tant que le serveur n'envoie rien, indépendant du panneau et du grade du joueur
task.spawn(function()
	local ok, problem = pcall(function() require(Shared:WaitForChild("ActionExecutor")).Start() end)
	if not ok then warn("[APM] ActionExecutor : " .. tostring(problem)) end
end)

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
		-- Removing a cloned holder must preserve the still-live canonical session.
		for _,live in playerGui:GetChildren()do
			if live.Name=="APM_Private"and live:GetAttribute("APMPrivate")==true and id and live:GetAttribute("SessionId")==id then return end
		end
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

-- Toujours devant les interfaces du jeu, et un cran au-dessus du panneau APM (qui se place à « plus haute + 1 »).
-- Recalculé seulement quand un message s'affiche : rien ne tourne en continu chez les joueurs.
local BASE_ORDER = 90
local function front()
	local order = BASE_ORDER
	for _, other in playerGui:GetChildren() do
		if other:IsA("ScreenGui") and other ~= gui and other.Enabled and string.sub(other.Name, 1, 4) ~= "APM_" then
			order = math.max(order, math.min(2147483647, other.DisplayOrder + 2))
		end
	end
	if gui.DisplayOrder ~= order then gui.DisplayOrder = order end
end

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
-- Même rendu que l'aperçu des réglages : ce que l'Owner voit dans le panneau est exactement ce que voient les joueurs.
local AnnounceStyle = require(Shared:WaitForChild("Announcements"))
local publicFolder = ReplicatedStorage:WaitForChild("APM_Public")
local queue, showing = {}, false

local function pump()
	if showing then
		return
	end
	showing = true
	task.spawn(function()
		while #queue > 0 do
			local item = table.remove(queue, 1)
			front()
			-- style relu à chaque annonce : un changement de l'Owner s'applique dès la suivante
			local ok, problem = pcall(function()
				local view = AnnounceStyle.Render(gui, AnnounceStyle.Decode(publicFolder:GetAttribute("AnnounceStyle")), {
					Message = string.sub(text(item.message), 1, 300),
					Author = item.by,
					Title = item.title,
					Time = item.time,
				}, { Translate = L })
				local played = pcall(view.Play)
				if not played and view.Root.Parent then
					view.Destroy()
				end
			end)
			if not ok then
				warn("[APM] Annonce non affichée : " .. tostring(problem))
			end
		end
		showing = false
	end)
end

-- (message, auteur, { Title, Time }) ; le 3e argument est facultatif (ex. annonce d'arrêt du serveur)
Remotes.Get("Announcement", "RemoteEvent").OnClientEvent:Connect(function(message, by, extra)
	if type(message) ~= "string" and type(message) ~= "table" then
		return
	end
	extra = type(extra) == "table" and extra or {}
	-- titre tapé par l'admin : affiché tel quel (jamais lu comme une clé de traduction) ; une table = message traduisible
	local title = type(extra.Title) == "string" and extra.Title or type(extra.Title) == "table" and text(extra.Title) or nil
	title = title and string.sub(title, 1, AnnounceStyle.MaxTitle * 4)
	if #queue < 5 then
		table.insert(queue, {
			message = message,
			by = type(by) == "string" and string.sub(by, 1, 40) or "Admin",
			title = title ~= "" and title or nil,
			time = tonumber(extra.Time),
		})
	end
	pump()
end)

-- Avertissement -------------------------------------------------------------------------------------------------------
local warning = make("Frame", { Name = "Warning", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -32, 0, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel, Visible = false, ZIndex = 5 }, gui)
make("UISizeConstraint", { MaxSize = Vector2.new(420, math.huge) }, warning)
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
	front()
	warning.Visible = true
end)

-- Chat coupé ------------------------------------------------------------------------------------------------------------
local notice = make("TextLabel", { Name = "MuteNotice", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90), Size = UDim2.fromOffset(0, 36),
	AutomaticSize = Enum.AutomaticSize.XY, TextWrapped = true, BackgroundColor3 = T.panel, BackgroundTransparency = 0.05, Font = T.font, TextSize = 14, TextColor3 = T.text, Visible = false, Text = "" }, gui)
local noticeBounds = make("UISizeConstraint", { MaxSize = Vector2.new(math.max(1, gui.AbsoluteSize.X - 32), math.huge) }, notice)
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	noticeBounds.MaxSize = Vector2.new(math.max(1, gui.AbsoluteSize.X - 32), math.huge)
end)
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
	front()
	notice.Visible = true
	task.delay(5, function()
		if noticeToken == mine then
			notice.Visible = false
		end
	end)
end)

-- Une interface du jeu ouverte pendant qu'un message est affiché (ex. l'avertissement attend « OK ») : on repasse devant.
playerGui.ChildAdded:Connect(function(child)
	if child:IsA("ScreenGui") and (showing or warning.Visible or notice.Visible) then task.defer(front) end
end)
