--[[
	AnnounceDesigner : fenêtre « Réglages des annonces » (permission APM.AnnounceStyle, Owner par défaut).
	- Aperçu en direct sur un écran 16:9 simulé, avec le MÊME rendu que les joueurs (APM_Shared.Announcements.Render).
	- Modèles prêts à l'emploi, puis réglages fins :
	    Disposition : format (carte, bandeau, bulle, cinéma), emplacement à l'écran, marge, largeur, animation, durée, son ;
	    Apparence   : fond, opacité, couleur d'accent, bordure, arrondi, barre d'accent ;
	    Textes      : ordre des textes dans l'annonce, et pour Titre / Message / Signature : affiché, taille, couleur, police,
	                  alignement (+ majuscules et nom de l'auteur pour le titre, contenu pour la signature).
	- Rien n'est appliqué avant « Enregistrer » ; le serveur revérifie le droit et valide chaque valeur (Sanitize).
	- Si un autre admin enregistre pendant l'édition, c'est signalé (« Annuler » charge son style).
	  Designer.Open(Core, sample) ; sample() -> { Title, Message } : texte en cours de rédaction pour l'aperçu (facultatif).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local AnnounceStyle = require(ReplicatedStorage:WaitForChild("APM_Shared"):WaitForChild("Announcements"))

local Designer = {}

local SCREEN = Vector2.new(1280, 720) -- écran simulé de l'aperçu
local WINDOW = Vector2.new(1000, 600)
local PREVIEW_WIDTH = 600
local SIDE_X, SIDE_WIDTH = 632, 352
local SWATCHES = { "#FFFFFF", "#EEF0F6", "#969DAC", "#20232B", "#000000", "#DCAA46", "#E5484D", "#4F8EF7", "#3DD68C", "#B57CF2" }
local FONT_NAMES = { GothamMedium = "Gotham", GothamBold = "Gotham Bold", GothamBlack = "Gotham Black", SourceSans = "Source Sans",
	SourceSansBold = "Source Bold", Merriweather = "Merriweather", RobotoMono = "Roboto Mono", FredokaOne = "Fredoka", Bangers = "Bangers" }
local SPOTS = { TopLeft = { 0, 0 }, Top = { 0.5, 0 }, TopRight = { 1, 0 }, Center = { 0.5, 0.5 }, BottomLeft = { 0, 1 }, Bottom = { 0.5, 1 }, BottomRight = { 1, 1 } }

local current -- fenêtre ouverte (une seule à la fois)

local function ping()
	pcall(function()
		local sound = Instance.new("Sound")
		sound.SoundId = AnnounceStyle.Sound
		sound.Volume = 0.6
		SoundService:PlayLocalSound(sound)
		task.delay(3, function() sound:Destroy() end)
	end)
end

-- Emplacement réellement utilisé (le bandeau ne va qu'en haut ou en bas, le cinéma est toujours centré)
local function effectivePosition(style)
	if style.Layout == "Banner" then
		return string.find(style.Position, "Bottom", 1, true) and "Bottom" or "Top"
	elseif style.Layout == "Cinema" then
		return "Center"
	end
	return style.Position
end

function Designer.Open(Core, sample)
	if current and current.Parent then
		current.Enabled = true
		return
	end
	if not Core.HasPermission("APM.AnnounceStyle") then
		return
	end
	local UI, T, L, R = Core.UI, Core.T, Core.L, Core.R
	local Limits = AnnounceStyle.Limits
	local playerGui = Core.Player:WaitForChild("PlayerGui")
	local publicFolder = ReplicatedStorage:WaitForChild("APM_Public")
	local function published()
		return AnnounceStyle.Decode(publicFolder:GetAttribute("AnnounceStyle"))
	end
	local saved = published()
	local draft = AnnounceStyle.Copy(saved)
	local externalChange, saving, testing = false, false, false
	local refreshers = {}
	local changed -- défini plus bas

	local gui = Core.TrackGui(UI.new("ScreenGui", { Name = "APM_AnnounceDesigner", ResetOnSpawn = false, IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = (Core.Gui and Core.Gui.DisplayOrder or 80) + 2 }, playerGui))
	if not gui.Parent then
		return
	end
	if Core.Gui then
		gui:SetAttribute("APMPrivateSession", Core.Gui:GetAttribute("APMPrivateSession"))
		Core.On(Core.Gui:GetPropertyChangedSignal("Enabled"), function()
			if not testing then gui.Enabled = Core.Gui.Enabled end
		end)
	end
	current = gui

	local backdrop = UI.new("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Text = "" }, gui)
	local window = UI.new("Frame", { Name = "Window", Size = UDim2.fromOffset(WINDOW.X, WINDOW.Y), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = T.bg, Corner = 14, Stroke = T.stroke, StrokeThickness = 1.5 }, gui)
	local windowScale = UI.new("UIScale", {}, window)
	local function rescale()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		windowScale.Scale = math.clamp(math.min(viewport.X / (WINDOW.X + 40), viewport.Y / (WINDOW.Y + 40)), 0.3, 1.1)
	end
	rescale()
	if workspace.CurrentCamera then
		Core.On(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), rescale)
	end

	-- En-tête ------------------------------------------------------------------------------------------------
	local header = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = T.panel, Corner = 14 }, window)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.new(0, 0, 1, -14), BackgroundColor3 = T.panel }, header)
	UI.label({ Size = UDim2.new(1, -80, 0, 22), Position = UDim2.fromOffset(18, 6), Font = T.fontBold, TextSize = 17, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = L("Announce.DesignerTitle"), ZIndex = 2 }, header)
	UI.label({ Size = UDim2.new(1, -80, 0, 16), Position = UDim2.fromOffset(18, 28), TextSize = 12, TextColor3 = T.sub, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = L("Announce.DesignerSubtitle"), ZIndex = 2 }, header)
	local closeButton = UI.button({ Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -44, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(58, 44, 48), Text = "X", TextSize = 16, ZIndex = 3 }, header)

	-- Aperçu en direct ---------------------------------------------------------------------------------------
	local previewFrame = UI.new("Frame", { Name = "Preview", Size = UDim2.fromOffset(PREVIEW_WIDTH, PREVIEW_WIDTH * SCREEN.Y / SCREEN.X), Position = UDim2.fromOffset(16, 62),
		BackgroundColor3 = Color3.fromRGB(78, 128, 196), ClipsDescendants = true, Corner = 10, Stroke = T.stroke }, window)
	local screen = UI.new("Frame", { Name = "Screen", Size = UDim2.fromOffset(SCREEN.X, SCREEN.Y), BackgroundTransparency = 1 }, previewFrame)
	UI.new("UIScale", { Scale = PREVIEW_WIDTH / SCREEN.X }, screen)
	-- décor de jeu simplifié : ciel, sol, bâtiments, un personnage pour l'échelle (l'opacité du fond se juge dessus)
	local scenery = UI.new("Frame", { Name = "Scenery", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, screen)
	UI.new("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(78, 128, 196)), ColorSequenceKeypoint.new(0.619, Color3.fromRGB(178, 210, 234)),
		ColorSequenceKeypoint.new(0.62, Color3.fromRGB(98, 142, 94)), ColorSequenceKeypoint.new(1, Color3.fromRGB(56, 92, 58)),
	}) }, scenery)
	for _, building in { { 90, 170, 150 }, { 300, 120, 230 }, { 460, 90, 120 }, { 860, 210, 180 }, { 1110, 110, 140 } } do
		UI.new("Frame", { Size = UDim2.fromOffset(building[2], building[3]), Position = UDim2.fromOffset(building[1], 446 - building[3]),
			BackgroundColor3 = Color3.fromRGB(118, 130, 156), BackgroundTransparency = 0.2 }, scenery)
	end
	UI.new("Frame", { Size = UDim2.fromOffset(34, 74), Position = UDim2.fromOffset(623, 540), BackgroundColor3 = Color3.fromRGB(40, 48, 66), Corner = 14 }, scenery)
	UI.new("Frame", { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(625, 506), BackgroundColor3 = Color3.fromRGB(242, 216, 183), Corner = 15 }, scenery)

	local badge = UI.label({ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.fromOffset(10, 10), BackgroundTransparency = 0.2,
		BackgroundColor3 = Color3.new(0, 0, 0), Font = T.fontBold, TextSize = 10, TextColor3 = Color3.new(1, 1, 1), Text = L("Announce.LivePreview"), ZIndex = 20, Corner = 10 }, previewFrame)
	UI.padding(badge, 0, 9, 9)
	local durationChip = UI.label({ Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(0, 10, 1, -10), AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 0.2, BackgroundColor3 = Color3.new(0, 0, 0), TextSize = 11, TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 20, Corner = 11 }, previewFrame)
	UI.padding(durationChip, 0, 9, 9)
	local replayButton = UI.button({ Size = UDim2.fromOffset(0, 26), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(1, -10, 1, -10), AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Color3.fromRGB(20, 22, 28), TextSize = 12, Text = L("Announce.Replay"), ZIndex = 20, Corner = 13, Stroke = T.stroke }, previewFrame)
	UI.padding(replayButton, 0, 12, 12)

	local view, playToken = nil, 0
	local function payload()
		local text = type(sample) == "function" and sample() or {}
		local title = type(text) == "table" and type(text.Title) == "string" and string.find(text.Title, "%S") and text.Title or nil
		local message = type(text) == "table" and type(text.Message) == "string" and string.find(text.Message, "%S") and text.Message or L("Announce.SampleMessage")
		return { Title = title, Message = message, Author = Core.Player.Name, Time = os.time() }
	end
	local function renderPreview()
		playToken += 1
		if view then
			view.Destroy()
			view = nil
		end
		local data = payload()
		view = AnnounceStyle.Render(screen, draft, data, { Translate = L, Static = true, ZIndex = 5 })
		local seconds = math.floor(AnnounceStyle.Duration(draft, data.Message) + 0.5)
		durationChip.Text = L("Announce.DurationChip", seconds) .. (draft.Duration == 0 and ("  ·  " .. L("Announce.Auto")) or "")
	end
	local pending = false
	local function schedule()
		if pending then return end
		pending = true
		task.defer(function()
			pending = false
			if gui.Parent then renderPreview() end
		end)
	end
	replayButton.Activated:Connect(function()
		playToken += 1
		local token = playToken
		if view then
			view.Destroy()
			view = nil
		end
		local animated = AnnounceStyle.Render(screen, draft, payload(), { Translate = L, ZIndex = 5 })
		view = animated
		if draft.Sound then ping() end
		task.spawn(function()
			animated.Show()
			task.wait(math.min(animated.Duration, 3))
			if token ~= playToken then return end
			animated.Hide()
			task.wait(0.3)
			if token == playToken and gui.Parent then renderPreview() end
		end)
	end)

	-- Modèles -----------------------------------------------------------------------------------------------
	UI.label({ Size = UDim2.fromOffset(PREVIEW_WIDTH, 16), Position = UDim2.fromOffset(16, 410), Font = T.fontBold, TextSize = 11, TextColor3 = T.accent,
		Text = AnnounceStyle.Upper(L("Announce.Presets")) }, window)
	local presetRow = UI.new("Frame", { Size = UDim2.fromOffset(PREVIEW_WIDTH, 58), Position = UDim2.fromOffset(16, 430), BackgroundTransparency = 1 }, window)
	UI.list(presetRow, 8, true)
	local presetStrokes = {}
	for index, preset in AnnounceStyle.Presets do
		local style = preset.Style
		local button = UI.button({ Size = UDim2.new(1 / #AnnounceStyle.Presets, -7, 1, 0), BackgroundColor3 = T.panel, Text = "", LayoutOrder = index }, presetRow)
		presetStrokes[preset.Id] = UI.stroke(button, T.stroke, 1)
		local thumb = UI.new("Frame", { Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = Color3.fromHex(style.Background),
			Corner = math.min(style.Corner, 6), Stroke = Color3.fromHex(style.Accent) }, button)
		UI.new("Frame", { Size = UDim2.new(0.55, 0, 0, 3), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = Color3.fromHex(style.Title.Color), Corner = 2 }, thumb)
		UI.new("Frame", { Size = UDim2.new(0.8, 0, 0, 3), Position = UDim2.fromOffset(6, 14), BackgroundColor3 = Color3.fromHex(style.Message.Color), Corner = 2 }, thumb)
		UI.label({ Size = UDim2.new(1, -4, 0, 18), Position = UDim2.new(0, 2, 1, -22), Font = T.fontBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = L("Announce.Preset." .. preset.Id) }, button)
		button.Activated:Connect(function()
			draft = AnnounceStyle.Preset(preset.Id)
			changed()
		end)
	end
	table.insert(refreshers, function()
		for id, stroke in presetStrokes do
			stroke.Color = draft.Preset == id and T.accent or T.stroke
			stroke.Thickness = draft.Preset == id and 2 or 1
		end
	end)
	UI.label({ Size = UDim2.fromOffset(PREVIEW_WIDTH, 30), Position = UDim2.fromOffset(16, 496), TextSize = 11, TextColor3 = T.sub, TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top, Text = L("Announce.SampleHint") }, window)

	-- Contrôles ---------------------------------------------------------------------------------------------
	local function read(key, sub)
		if sub then return draft[sub][key] end
		return draft[key]
	end
	local function write(key, sub, value)
		local target = sub and draft[sub] or draft
		if target[key] == value then return end
		target[key] = value
		draft.Preset = "Custom"
		changed()
	end
	local function options(list, prefix)
		local result = {}
		for _, id in list do
			table.insert(result, { id, L(prefix .. id) })
		end
		return result
	end
	local function section(parent, text, order)
		return UI.label({ Size = UDim2.new(1, 0, 0, 18), Font = T.fontBold, TextSize = 11, TextColor3 = T.accent, Text = AnnounceStyle.Upper(text), LayoutOrder = order }, parent)
	end
	local function note(parent, order)
		return UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextColor3 = T.sub, TextWrapped = true, Text = "",
			LayoutOrder = order }, parent)
	end
	-- ligne : libellé à gauche, contrôle à droite (renvoie le cadre du contrôle)
	local function field(parent, text, order, height)
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, height or 28), BackgroundTransparency = 1, LayoutOrder = order }, parent)
		UI.label({ Size = UDim2.new(0, 104, 0, 28), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Text = text }, row)
		return UI.new("Frame", { Size = UDim2.new(1, -112, 1, 0), Position = UDim2.fromOffset(112, 0), BackgroundTransparency = 1 }, row)
	end
	local function segmented(body, list, key, sub)
		local bar = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = T.panel, Corner = 8, Stroke = T.stroke }, body)
		local buttons = {}
		for index, option in list do
			local button = UI.button({ Size = UDim2.new(1 / #list, -4, 1, -4), Position = UDim2.new((index - 1) / #list, 2, 0, 2), BackgroundColor3 = T.panel,
				Text = option[2], TextSize = 11, TextTruncate = Enum.TextTruncate.AtEnd, Corner = 6 }, bar)
			button.Activated:Connect(function() write(key, sub, option[1]) end)
			buttons[option[1]] = button
		end
		table.insert(refreshers, function()
			for id, button in buttons do
				local on = read(key, sub) == id
				button.BackgroundColor3 = on and T.accent or T.panel
				button.TextColor3 = on and Color3.new(1, 1, 1) or T.sub
			end
		end)
	end
	local function slider(body, key, sub, bounds, unit)
		local value = UI.label({ Size = UDim2.fromOffset(54, 28), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right,
			Font = T.fontBold, TextSize = 12, TextColor3 = T.accent }, body)
		local function show(number)
			value.Text = (key == "Duration" and number == 0) and L("Announce.Auto") or (tostring(number) .. unit)
		end
		local object = UI.Slider(body, bounds[1], bounds[2], read(key, sub), function(number) write(key, sub, number) end, UDim2.new(1, -62, 0, 24), UDim2.fromOffset(0, 2))
		object.Changed = function(number)
			show(number)
			write(key, sub, number)
		end
		table.insert(refreshers, function()
			object.Set(read(key, sub))
			show(read(key, sub))
		end)
	end
	local function switch(body, key, sub)
		local object = UI.Switch(body, read(key, sub) == true, function(state) write(key, sub, state) end, UDim2.fromOffset(0, 2))
		table.insert(refreshers, function()
			if object.Get() ~= (read(key, sub) == true) then object.Set(read(key, sub) == true) end
		end)
	end
	local flash -- défini avec le pied de fenêtre
	local function color(body, key, sub)
		local chip = UI.new("Frame", { Size = UDim2.fromOffset(28, 26), BackgroundColor3 = Color3.new(), Corner = 6, Stroke = T.stroke }, body)
		local box = UI.input({ Size = UDim2.new(1, -36, 0, 26), Position = UDim2.fromOffset(36, 0), TextSize = 12, Font = Enum.Font.RobotoMono, PlaceholderText = "#RRGGBB" }, body)
		local swatches = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 32), BackgroundTransparency = 1 }, body)
		UI.list(swatches, 4, true)
		for index, hex in SWATCHES do
			local swatch = UI.button({ Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.fromHex(hex), Text = "", Corner = 9, Stroke = T.stroke, LayoutOrder = index }, swatches)
			swatch.Activated:Connect(function() write(key, sub, hex) end)
		end
		box.FocusLost:Connect(function()
			local text = string.upper((string.gsub(box.Text, "%s", "")))
			if string.sub(text, 1, 1) ~= "#" then text = "#" .. text end
			if AnnounceStyle.ValidHex(text) then
				write(key, sub, text)
			elseif text ~= read(key, sub) then
				flash(L("Announce.BadColor"), false)
			end
			box.Text = read(key, sub)
		end)
		table.insert(refreshers, function()
			chip.BackgroundColor3 = Color3.fromHex(read(key, sub))
			if not box:IsFocused() then box.Text = read(key, sub) end
		end)
	end
	local function fontGrid(body, key, sub)
		local grid = UI.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body)
		UI.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -3, 0, 26), CellPadding = UDim2.fromOffset(4, 4), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
		local buttons = {}
		for index, name in AnnounceStyle.Fonts do
			local ok, font = pcall(function() return Enum.Font[name] end)
			-- nom écrit dans sa propre police, réduit au besoin pour tenir dans la case
			local button = UI.button({ BackgroundColor3 = T.panel, Text = FONT_NAMES[name] or name, Font = ok and font or T.font, TextScaled = true,
				LayoutOrder = index, Corner = 6, Stroke = T.stroke }, grid)
			UI.new("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, button)
			UI.padding(button, 5, 5)
			button.Activated:Connect(function() write(key, sub, name) end)
			buttons[name] = button
		end
		table.insert(refreshers, function()
			for name, button in buttons do
				local on = read(key, sub) == name
				button.BackgroundColor3 = on and T.accent or T.panel
				button.TextColor3 = on and Color3.new(1, 1, 1) or T.text
			end
		end)
	end
	-- emplacement : mini-écran avec les 7 positions cliquables
	local function positionPicker(body)
		local map = UI.new("Frame", { Size = UDim2.fromOffset(112, 63), BackgroundColor3 = Color3.fromRGB(28, 31, 38), Corner = 6, Stroke = T.stroke }, body)
		local name = UI.label({ Size = UDim2.new(1, -122, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(122, 2), Font = T.fontBold, TextSize = 12,
			TextWrapped = true, Text = "" }, body)
		local spots = {}
		local function inset(alpha)
			return alpha == 0 and 5 or alpha == 1 and -5 or 0
		end
		for id, at in SPOTS do
			local spot = UI.button({ Size = UDim2.fromOffset(26, 12), AnchorPoint = Vector2.new(at[1], at[2]), Position = UDim2.new(at[1], inset(at[1]), at[2], inset(at[2])),
				BackgroundColor3 = T.panel2, Text = "", Corner = 3 }, map)
			spot.Activated:Connect(function() write("Position", nil, id) end)
			spots[id] = spot
		end
		table.insert(refreshers, function()
			local effective = effectivePosition(draft)
			for id, spot in spots do
				spot.BackgroundColor3 = id == effective and T.accent or id == draft.Position and T.sub or T.panel2
				spot.Size = (draft.Layout == "Banner" and id == effective) and UDim2.new(1, -10, 0, 12) or UDim2.fromOffset(26, 12)
			end
			name.Text = L("Announce.Position." .. effective)
		end)
	end

	-- Onglets ---------------------------------------------------------------------------------------------
	local tabsBar = UI.new("Frame", { Size = UDim2.fromOffset(SIDE_WIDTH, 30), Position = UDim2.fromOffset(SIDE_X, 62), BackgroundColor3 = T.panel, Corner = 8, Stroke = T.stroke }, window)
	local TABS = { "Layout", "Look", "Texts" }
	local pages, tabButtons, selectedTab = {}, {}, "Layout"
	for index, id in TABS do
		local button = UI.button({ Size = UDim2.new(1 / #TABS, -4, 1, -4), Position = UDim2.new((index - 1) / #TABS, 2, 0, 2), BackgroundColor3 = T.panel, TextSize = 12,
			Text = L("Announce.Tab." .. id), Corner = 6 }, tabsBar)
		local page = UI.scroll({ Size = UDim2.fromOffset(SIDE_WIDTH, 436), Position = UDim2.fromOffset(SIDE_X, 100), Visible = false }, window)
		UI.list(page, 10)
		UI.padding(page, 4, 2, 12)
		pages[id], tabButtons[id] = page, button
		button.Activated:Connect(function()
			selectedTab = id
			changed()
		end)
	end
	table.insert(refreshers, function()
		for id, button in tabButtons do
			local on = id == selectedTab
			button.BackgroundColor3 = on and T.accent or T.panel
			button.TextColor3 = on and Color3.new(1, 1, 1) or T.sub
			pages[id].Visible = on
		end
	end)

	-- Disposition
	local layoutPage = pages.Layout
	section(layoutPage, L("Announce.Section.Format"), 1)
	segmented(field(layoutPage, L("Announce.Field.Layout"), 2), options(AnnounceStyle.Layouts, "Announce.Layout."), "Layout")
	local layoutHelp = note(layoutPage, 3)
	positionPicker(field(layoutPage, L("Announce.Field.Position"), 4, 63))
	slider(field(layoutPage, L("Announce.Field.Margin"), 5), "Margin", nil, Limits.Margin, " px")
	slider(field(layoutPage, L("Announce.Field.Width"), 6), "Width", nil, Limits.Width, " px")
	local layoutNote = note(layoutPage, 7)
	table.insert(refreshers, function()
		layoutHelp.Text = L("Announce.LayoutHelp." .. draft.Layout)
		local special = draft.Layout == "Banner" or draft.Layout == "Cinema"
		layoutNote.Visible = special
		layoutNote.Text = special and L("Announce.LayoutNote." .. draft.Layout) or ""
	end)
	section(layoutPage, L("Announce.Section.Motion"), 8)
	segmented(field(layoutPage, L("Announce.Field.Animation"), 9), options(AnnounceStyle.Animations, "Announce.Animation."), "Animation")
	slider(field(layoutPage, L("Announce.Field.Duration"), 10), "Duration", nil, Limits.Duration, " s")
	switch(field(layoutPage, L("Announce.Field.Sound"), 11), "Sound")

	-- Apparence
	local lookPage = pages.Look
	section(lookPage, L("Announce.Section.Background"), 1)
	color(field(lookPage, L("Announce.Field.Background"), 2, 52), "Background")
	slider(field(lookPage, L("Announce.Field.Opacity"), 3), "Opacity", nil, Limits.Opacity, " %")
	section(lookPage, L("Announce.Section.Accent"), 4)
	color(field(lookPage, L("Announce.Field.Accent"), 5, 52), "Accent")
	slider(field(lookPage, L("Announce.Field.Border"), 6), "Border", nil, Limits.Border, " px")
	slider(field(lookPage, L("Announce.Field.Corner"), 7), "Corner", nil, Limits.Corner, " px")
	switch(field(lookPage, L("Announce.Field.AccentBar"), 8), "AccentBar")

	-- Textes : ordre + un panneau par texte (construits une fois, on affiche celui choisi)
	local textsPage = pages.Texts
	local selectedText = "Message"
	section(textsPage, L("Announce.OrderTitle"), 1)
	local orderList = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 3 * 30 + 2 * 4), BackgroundTransparency = 1, LayoutOrder = 2 }, textsPage)
	UI.list(orderList, 4)
	note(textsPage, 3).Text = L("Announce.OrderHint")
	local function move(name, delta)
		local target = draft[name].Order + delta
		if target < 1 or target > #AnnounceStyle.Texts then return end
		for _, other in AnnounceStyle.Texts do
			if draft[other].Order == target then draft[other].Order = draft[name].Order end
		end
		draft[name].Order = target
		draft.Preset = "Custom"
		changed()
	end
	local orderRows, editors = {}, {}
	for index, name in AnnounceStyle.Texts do
		local row = UI.button({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, Text = "", Corner = 8 }, orderList)
		local rowStroke = UI.stroke(row, T.stroke, 1)
		local number = UI.label({ Size = UDim2.fromOffset(20, 30), Position = UDim2.fromOffset(10, 0), Font = T.fontBold, TextSize = 12, TextColor3 = T.sub, Text = "" }, row)
		local label = UI.label({ Size = UDim2.new(1, -104, 1, 0), Position = UDim2.fromOffset(32, 0), Font = T.fontBold, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = "" }, row)
		local up = UI.button({ Size = UDim2.fromOffset(28, 22), Position = UDim2.new(1, -64, 0, 4), BackgroundColor3 = T.panel2, Text = "▲", TextSize = 14, Corner = 6 }, row)
		local down = UI.button({ Size = UDim2.fromOffset(28, 22), Position = UDim2.new(1, -32, 0, 4), BackgroundColor3 = T.panel2, Text = "▼", TextSize = 14, Corner = 6 }, row)
		row.Activated:Connect(function()
			selectedText = name
			changed()
		end)
		up.Activated:Connect(function() move(name, -1) end)
		down.Activated:Connect(function() move(name, 1) end)
		orderRows[name] = { Row = row, Stroke = rowStroke, Number = number, Label = label, Up = up, Down = down }

		local editor = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4 + index, Visible = false }, textsPage)
		UI.list(editor, 10)
		section(editor, L("Announce.Editing", L("Announce.Text." .. name)), 1)
		if name == "Message" then
			note(editor, 2).Text = L("Announce.AlwaysShown")
		else
			switch(field(editor, L("Announce.Field.Visible"), 2), "Visible", name)
		end
		slider(field(editor, L("Announce.Field.Size"), 3), "Size", name, Limits.Size, " px")
		color(field(editor, L("Announce.Field.Color"), 4, 52), "Color", name)
		fontGrid(field(editor, L("Announce.Field.Font"), 5, 86), "Font", name)
		segmented(field(editor, L("Announce.Field.Align"), 6), options(AnnounceStyle.Aligns, "Announce.Align."), "Align", name)
		if name == "Title" then
			switch(field(editor, L("Announce.Field.Upper"), 7), "Upper", name)
			switch(field(editor, L("Announce.Field.Author"), 8), "Author", name)
		elseif name == "Footer" then
			segmented(field(editor, L("Announce.Field.Content"), 7), options(AnnounceStyle.FooterContents, "Announce.Footer."), "Content", name)
		end
		editors[name] = editor
	end
	table.insert(refreshers, function()
		for name, entry in orderRows do
			local spec = draft[name]
			local on = name == selectedText
			entry.Row.LayoutOrder = spec.Order
			entry.Number.Text = tostring(spec.Order)
			entry.Label.Text = L("Announce.Text." .. name) .. (spec.Visible and "" or ("  ·  " .. L("Announce.Hidden")))
			entry.Label.TextColor3 = spec.Visible and T.text or T.sub
			entry.Stroke.Color = on and T.accent or T.stroke
			entry.Stroke.Thickness = on and 1.5 or 1
			entry.Row.BackgroundColor3 = on and T.panel2 or T.panel
			entry.Up.TextColor3 = spec.Order > 1 and T.text or T.stroke
			entry.Down.TextColor3 = spec.Order < #AnnounceStyle.Texts and T.text or T.stroke
			editors[name].Visible = on
		end
	end)

	-- Pied de fenêtre : état + actions ---------------------------------------------------------------------
	local footer = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 1, -56), BackgroundColor3 = T.panel, Corner = 14 }, window)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 14), BackgroundColor3 = T.panel }, footer)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = T.stroke }, footer)
	local status = UI.label({ Size = UDim2.new(0, 420, 1, 0), Position = UDim2.fromOffset(18, 0), TextSize = 12, TextWrapped = true, Text = "", ZIndex = 2 }, footer)
	local actionBar = UI.new("Frame", { Size = UDim2.fromOffset(530, 34), Position = UDim2.new(1, -16, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1,
		ZIndex = 2 }, footer)
	local actionLayout = UI.list(actionBar, 8, true)
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local defaultButton = UI.button({ Size = UDim2.fromOffset(104, 34), TextSize = 12, Text = L("Announce.ResetDefault"), LayoutOrder = 1 }, actionBar)
	local revertButton = UI.button({ Size = UDim2.fromOffset(104, 34), TextSize = 12, Text = L("Announce.Revert"), LayoutOrder = 2 }, actionBar)
	local testButton = UI.button({ Size = UDim2.fromOffset(146, 34), TextSize = 12, Text = L("Announce.TestFull"), LayoutOrder = 3 }, actionBar)
	local saveButton = UI.button({ Size = UDim2.fromOffset(146, 34), BackgroundColor3 = T.accent, TextColor3 = Color3.new(1, 1, 1), TextSize = 13, Text = L("Announce.Save"),
		LayoutOrder = 4 }, actionBar)

	local flashed, flashToken = nil, 0
	local function isDirty()
		return not AnnounceStyle.Equal(draft, saved)
	end
	local function updateStatus()
		local dirty = isDirty()
		if flashed then
			status.Text, status.TextColor3 = flashed[1], flashed[2]
		elseif externalChange and dirty then
			status.Text, status.TextColor3 = L("Announce.ExternalChange"), T.warn
		elseif dirty then
			status.Text, status.TextColor3 = L("Announce.Dirty"), T.warn
		else
			status.Text, status.TextColor3 = L("Announce.Clean"), T.sub
		end
		revertButton.TextColor3 = dirty and T.text or T.sub
		saveButton.BackgroundColor3 = dirty and T.accent or T.panel2
		saveButton.TextColor3 = dirty and Color3.new(1, 1, 1) or T.sub
	end
	flash = function(text, ok)
		flashToken += 1
		local token = flashToken
		flashed = { text, ok == false and T.bad or T.good }
		updateStatus()
		task.delay(4, function()
			if flashToken == token and gui.Parent then
				flashed = nil
				updateStatus()
			end
		end)
	end
	changed = function()
		for _, refresh in refreshers do
			refresh()
		end
		updateStatus()
		schedule()
	end

	UI.Confirmable(defaultButton, true, function()
		draft = AnnounceStyle.Default()
		changed()
	end)
	revertButton.Activated:Connect(function()
		draft = AnnounceStyle.Copy(saved)
		externalChange = false
		changed()
	end)
	-- Test en vraie taille sur MON écran (la fenêtre s'efface le temps du test ; rien n'est envoyé aux joueurs)
	testButton.Activated:Connect(function()
		if testing then return end
		testing = true
		gui.Enabled = false
		local test = Core.TrackGui(UI.new("ScreenGui", { Name = "APM_AnnounceTest", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = gui.DisplayOrder + 1 }, playerGui))
		local style = AnnounceStyle.Copy(draft)
		task.spawn(function()
			pcall(function()
				AnnounceStyle.Render(test, style, payload(), { Translate = L }).Play()
			end)
			if test.Parent then test:Destroy() end
			testing = false
			if gui.Parent then gui.Enabled = not Core.Gui or Core.Gui.Enabled end
		end)
	end)
	saveButton.Activated:Connect(function()
		if saving then return end
		if not isDirty() and not externalChange then
			flash(L("Announce.Clean"), true)
			return
		end
		saving = true
		saveButton.Text = "..."
		local ok, success, message, stored = pcall(function()
			return R.SetAnnounceStyle:InvokeServer(draft)
		end)
		saving = false
		if not gui.Parent then return end
		saveButton.Text = L("Announce.Save")
		if ok and success == true then
			saved = AnnounceStyle.Sanitize(type(stored) == "table" and stored or draft)
			draft = AnnounceStyle.Copy(saved)
			externalChange = false
			changed()
			flash(message and Core.Text(message) or L("Announce.Saved"), true)
		else
			flash(ok and message and Core.Text(message) or L("Announce.SaveFailed"), false)
		end
	end)
	-- fermeture : un second clic est demandé s'il reste des modifications non enregistrées
	local closeArmed = 0
	local function close()
		if current == gui then current = nil end
		if gui.Parent then gui:Destroy() end
	end
	closeButton.Activated:Connect(function()
		if isDirty() and os.clock() - closeArmed > 3 then
			closeArmed = os.clock()
			flash(L("Announce.CloseUnsaved"), false)
			return
		end
		close()
	end)

	-- Un autre admin enregistre pendant l'édition : on garde le brouillon et on le signale
	Core.On(publicFolder:GetAttributeChangedSignal("AnnounceStyle"), function()
		if not gui.Parent then return end
		local incoming = published()
		if AnnounceStyle.Equal(incoming, saved) then return end
		local dirty = isDirty()
		saved = incoming
		if dirty then
			externalChange = true
		else
			draft = AnnounceStyle.Copy(saved)
		end
		changed()
	end)

	changed()
end

return Designer
