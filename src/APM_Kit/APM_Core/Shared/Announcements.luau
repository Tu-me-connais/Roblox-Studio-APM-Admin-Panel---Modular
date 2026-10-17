--[[
	Announcements : style des annonces (valeurs par défaut, modèles, validation) et moteur d'affichage.
	Partagé par le serveur (validation de ce que l'Owner enregistre), APM_Notices (l'annonce que voient les joueurs)
	et le panneau (aperçu en direct dans les réglages) : ce que l'Owner voit dans l'aperçu est exactement ce qui s'affiche.

	Un style ne contient que des valeurs simples (chaînes, nombres entiers, booléens) : il passe par les remotes, le DataStore
	et l'attribut public APM_Public.AnnounceStyle (JSON) sans conversion. Toute valeur reçue passe par Sanitize : un champ
	inconnu est ignoré, un champ invalide reprend sa valeur par défaut, les nombres sont bornés.

	Les textes de l'annonce (Titre, Message, Signature) ont chacun : affiché, taille, couleur, police, alignement et position
	dans l'annonce (ordre). L'annonce entière : disposition, emplacement à l'écran, marge, largeur, fond, opacité, couleur
	d'accent, bordure, arrondi, barre d'accent, animation, durée et son.
]]
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local Announcements = {}

Announcements.Version = 1
Announcements.Layouts = { "Card", "Banner", "Toast", "Cinema" }
Announcements.Positions = { "Top", "Center", "Bottom", "TopLeft", "TopRight", "BottomLeft", "BottomRight" }
Announcements.Animations = { "Slide", "Fade", "Pop", "None" }
Announcements.Aligns = { "Left", "Center", "Right" }
Announcements.FooterContents = { "Author", "AuthorTime", "Time" }
Announcements.Fonts = { "GothamMedium", "GothamBold", "GothamBlack", "SourceSans", "SourceSansBold", "Merriweather", "RobotoMono", "FredokaOne", "Bangers" }
Announcements.Texts = { "Title", "Message", "Footer" }
-- Bornes des réglages numériques (toutes entières : les curseurs du panneau le sont aussi)
Announcements.Limits = {
	Margin = { 0, 200 }, Width = { 240, 1000 }, Duration = { 0, 30 }, Opacity = { 10, 100 }, Border = { 0, 6 }, Corner = { 0, 32 }, Size = { 8, 48 },
}
Announcements.MaxTitle = 40
Announcements.MaxMessage = 200
Announcements.Sound = "rbxasset://sounds/electronicpingshort.wav"

-- Style par défaut : le rendu historique de l'APM (carte en haut, accent doré)
local DEFAULT = {
	Version = 1,
	Preset = "Classic",
	Layout = "Card",
	Position = "Top",
	Margin = 24,
	Width = 560,
	Background = "#20232B",
	Opacity = 100,
	Accent = "#DCAA46",
	Border = 2,
	Corner = 12,
	AccentBar = false,
	Animation = "Slide",
	Duration = 0, -- 0 = automatique (selon la longueur du message)
	Sound = false,
	Title = { Visible = true, Size = 12, Color = "#DCAA46", Font = "GothamBold", Align = "Left", Order = 1, Upper = true, Author = true },
	Message = { Visible = true, Size = 16, Color = "#EEF0F6", Font = "GothamMedium", Align = "Left", Order = 2 },
	Footer = { Visible = false, Size = 11, Color = "#969DAC", Font = "GothamMedium", Align = "Right", Order = 3, Content = "AuthorTime" },
}

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in value do copy[key] = deepCopy(item) end
	return copy
end
Announcements.Copy = deepCopy

local function merge(base, patch)
	local result = deepCopy(base)
	for key, value in patch do
		if type(value) == "table" and type(result[key]) == "table" then
			for k, v in value do result[key][k] = v end
		else
			result[key] = value
		end
	end
	return result
end

-- Modèles prêts à l'emploi (l'Owner part d'un modèle puis ajuste)
Announcements.Presets = {
	{ Id = "Classic", Style = deepCopy(DEFAULT) },
	{ Id = "Info", Style = merge(DEFAULT, {
		Preset = "Info", Background = "#16263D", Accent = "#4F8EF7", Corner = 14, AccentBar = true, Border = 1,
		Title = { Color = "#8FB8FF", Size = 13 }, Footer = { Visible = true },
	}) },
	{ Id = "Alert", Style = merge(DEFAULT, {
		Preset = "Alert", Layout = "Banner", Position = "Top", Margin = 0, Background = "#3A1418", Accent = "#E5484D", Border = 0, Corner = 0,
		AccentBar = true, Sound = true, Title = { Color = "#FF8A8D", Size = 14, Font = "GothamBlack", Align = "Center" },
		Message = { Size = 17, Align = "Center", Font = "GothamBold" }, Footer = { Align = "Center" },
	}) },
	{ Id = "Event", Style = merge(DEFAULT, {
		Preset = "Event", Position = "Center", Width = 620, Background = "#2A1840", Accent = "#F2C14E", Border = 2, Corner = 18,
		Animation = "Pop", Sound = true, Title = { Color = "#F2C14E", Size = 20, Font = "GothamBlack", Align = "Center", Author = false },
		Message = { Size = 18, Align = "Center" }, Footer = { Visible = true, Align = "Center", Content = "Author" },
	}) },
	{ Id = "Minimal", Style = merge(DEFAULT, {
		Preset = "Minimal", Layout = "Toast", Position = "BottomRight", Width = 360, Background = "#111317", Opacity = 85, Accent = "#FFFFFF",
		Border = 0, Corner = 10, Animation = "Fade", Title = { Color = "#A0A6B4", Size = 11 }, Message = { Size = 15 },
	}) },
	{ Id = "Cinema", Style = merge(DEFAULT, {
		Preset = "Cinema", Layout = "Cinema", Background = "#000000", Opacity = 65, Accent = "#FFD166", AccentBar = true, Animation = "Fade",
		Duration = 8, Width = 820, Title = { Color = "#FFD166", Size = 30, Font = "GothamBlack", Align = "Center", Author = false },
		Message = { Size = 24, Align = "Center" }, Footer = { Visible = true, Size = 14, Align = "Center", Content = "Author" },
	}) },
}

function Announcements.Default()
	return deepCopy(DEFAULT)
end

function Announcements.Preset(id)
	for _, preset in Announcements.Presets do
		if preset.Id == id then return deepCopy(preset.Style) end
	end
	return nil
end

----------------------------------------------------------------------------------------------------------
-- Validation

local function oneOf(value, list, default)
	for _, item in list do
		if item == value then return value end
	end
	return default
end
local function int(value, bounds, default)
	value = tonumber(value)
	if not value or value ~= value or value == math.huge or value == -math.huge then return default end
	return math.clamp(math.floor(value + 0.5), bounds[1], bounds[2])
end
local function bool(value, default)
	if type(value) == "boolean" then return value end
	return default
end
local function hex(value, default)
	if type(value) == "string" and #value == 7 and string.match(value, "^#%x%x%x%x%x%x$") then return string.upper(value) end
	return default
end
Announcements.ValidHex = function(value) return hex(value, nil) ~= nil end

-- Renvoie TOUJOURS un style complet et sûr, quelle que soit l'entrée (nil, table partielle, données hostiles)
function Announcements.Sanitize(raw)
	local base = DEFAULT
	if type(raw) ~= "table" then return deepCopy(base) end
	local limits = Announcements.Limits
	local style = {
		Version = Announcements.Version,
		Preset = type(raw.Preset) == "string" and #raw.Preset <= 24 and raw.Preset or "Custom",
		Layout = oneOf(raw.Layout, Announcements.Layouts, base.Layout),
		Position = oneOf(raw.Position, Announcements.Positions, base.Position),
		Margin = int(raw.Margin, limits.Margin, base.Margin),
		Width = int(raw.Width, limits.Width, base.Width),
		Background = hex(raw.Background, base.Background),
		Opacity = int(raw.Opacity, limits.Opacity, base.Opacity),
		Accent = hex(raw.Accent, base.Accent),
		Border = int(raw.Border, limits.Border, base.Border),
		Corner = int(raw.Corner, limits.Corner, base.Corner),
		AccentBar = bool(raw.AccentBar, base.AccentBar),
		Animation = oneOf(raw.Animation, Announcements.Animations, base.Animation),
		Duration = int(raw.Duration, limits.Duration, base.Duration),
		Sound = bool(raw.Sound, base.Sound),
	}
	local usedOrders = {}
	for index, name in Announcements.Texts do
		local source = type(raw[name]) == "table" and raw[name] or {}
		local default = base[name]
		local text = {
			Visible = name == "Message" or bool(source.Visible, default.Visible), -- le message est toujours affiché
			Size = int(source.Size, limits.Size, default.Size),
			Color = hex(source.Color, default.Color),
			Font = oneOf(source.Font, Announcements.Fonts, default.Font),
			Align = oneOf(source.Align, Announcements.Aligns, default.Align),
			Order = int(source.Order, { 1, #Announcements.Texts }, default.Order),
		}
		if name == "Title" then
			text.Upper = bool(source.Upper, default.Upper)
			text.Author = bool(source.Author, default.Author)
		elseif name == "Footer" then
			text.Content = oneOf(source.Content, Announcements.FooterContents, default.Content)
		end
		style[name] = text
	end
	-- ordres uniques 1..3 (un doublon envoyé par un client est réparé dans l'ordre par défaut)
	local sorted = table.clone(Announcements.Texts)
	table.sort(sorted, function(a, b)
		if style[a].Order ~= style[b].Order then return style[a].Order < style[b].Order end
		return base[a].Order < base[b].Order
	end)
	for index, name in sorted do style[name].Order = index end
	return style
end

function Announcements.Equal(a, b)
	return HttpService:JSONEncode(Announcements.Sanitize(a)) == HttpService:JSONEncode(Announcements.Sanitize(b))
end

function Announcements.Encode(style)
	return HttpService:JSONEncode(Announcements.Sanitize(style))
end

function Announcements.Decode(json)
	if type(json) ~= "string" or #json > 4000 then return Announcements.Default() end
	local ok, data = pcall(HttpService.JSONDecode, HttpService, json)
	return Announcements.Sanitize(ok and data or nil)
end

-- Majuscules UTF-8 (string.upper ne touche qu'à l'ASCII : « Réunion » donnerait « RéUNION »)
-- Latin (accents français, espagnols, portugais, allemands) et cyrillique ; le reste est gardé tel quel.
function Announcements.Upper(text)
	if type(text) ~= "string" then return "" end
	if not utf8.len(text) then return string.upper(text) end
	local out = {}
	for _, code in utf8.codes(text) do
		if code >= 0x61 and code <= 0x7A then
			code -= 32
		elseif code >= 0xE0 and code <= 0xFE and code ~= 0xF7 then
			code -= 32
		elseif code == 0xFF then
			code = 0x178
		elseif code == 0x153 then
			code = 0x152
		elseif code >= 0x430 and code <= 0x44F then
			code -= 32
		elseif code >= 0x450 and code <= 0x45F then
			code -= 80
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

-- Durée d'affichage (secondes) : fixée par l'Owner, sinon selon la longueur du message
function Announcements.Duration(style, message)
	local fixed = type(style) == "table" and tonumber(style.Duration) or 0
	if fixed and fixed > 0 then return fixed end
	return math.clamp(3 + #tostring(message or "") / 18, 5, 12)
end
-- Temps des animations d'entrée + sortie (le serveur l'ajoute au verrou d'affichage)
Announcements.AnimationTime = 0.8

----------------------------------------------------------------------------------------------------------
-- Affichage

local ALIGN = { Left = Enum.TextXAlignment.Left, Center = Enum.TextXAlignment.Center, Right = Enum.TextXAlignment.Right }
local function fontOf(name)
	local ok, font = pcall(function() return Enum.Font[name] end)
	return ok and font or Enum.Font.GothamMedium
end
local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props do instance[key] = value end
	if instance:IsA("GuiObject") then instance.BorderSizePixel = 0 end
	instance.Parent = parent
	return instance
end

-- Point d'ancrage et position finale selon l'emplacement choisi
local function placement(position, margin)
	if position == "Center" then return Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.5) end
	if position == "Bottom" then return Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -margin) end
	if position == "TopLeft" then return Vector2.new(0, 0), UDim2.new(0, margin, 0, margin) end
	if position == "TopRight" then return Vector2.new(1, 0), UDim2.new(1, -margin, 0, margin) end
	if position == "BottomLeft" then return Vector2.new(0, 1), UDim2.new(0, margin, 1, -margin) end
	if position == "BottomRight" then return Vector2.new(1, 1), UDim2.new(1, -margin, 1, -margin) end
	return Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, margin)
end

--[[
	Affiche une annonce dans parent (ScreenGui ou cadre représentant l'écran).
	payload : { Title = titre facultatif, Message = texte, Author = nom, Time = os.time() }
	opts : { Translate = function(clé, ...) -> texte, Static = true (aperçu figé, sans animation), ZIndex = n }
	Renvoie { Root, Duration, Show(), Hide(), Destroy(), Play() } ; Play = son + entrée + attente + sortie + destruction.
]]
function Announcements.Render(parent, rawStyle, payload, opts)
	opts = opts or {}
	payload = type(payload) == "table" and payload or {}
	local style = Announcements.Sanitize(rawStyle)
	local L = opts.Translate or function(key, ...)
		local fallback = { ["Announce.DefaultTitle"] = "ANNOUNCEMENT", ["Announce.FooterAuthor"] = "- %s", ["Announce.FooterAuthorTime"] = "- %s  -  %s" }
		local ok, text = pcall(string.format, fallback[key] or key, ...)
		return ok and text or key
	end
	local z = opts.ZIndex or 1
	local layout = style.Layout
	local position = style.Position
	if layout == "Banner" then
		position = string.find(position, "Bottom", 1, true) and "Bottom" or "Top"
	elseif layout == "Cinema" then
		position = "Center"
	end
	local margin = layout == "Cinema" and 0 or style.Margin
	local background = Color3.fromHex(style.Background)
	local accent = Color3.fromHex(style.Accent)
	local baseTransparency = 1 - style.Opacity / 100

	local author = type(payload.Author) == "string" and string.sub(payload.Author, 1, 40) or "Admin"
	local message = type(payload.Message) == "string" and string.sub(payload.Message, 1, 300) or ""
	local customTitle = type(payload.Title) == "string" and string.sub(payload.Title, 1, 60) or ""
	local clock = os.date("%H:%M", tonumber(payload.Time) or os.time())

	local fades = {} -- { instance, propriété, valeur finale }
	local function fade(instance, property, value)
		table.insert(fades, { instance, property, value })
	end

	-- Racine : la boîte elle-même (Carte / Bandeau / Bulle) ou un voile plein écran (Cinéma)
	local anchor, final = placement(position, margin)
	local root
	if layout == "Cinema" then
		root = new("Frame", { Name = "APM_Announcement", Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0, 0), BackgroundColor3 = background,
			BackgroundTransparency = baseTransparency, ZIndex = z, Active = false }, parent)
		fade(root, "BackgroundTransparency", baseTransparency)
	else
		local maxWidth = layout == "Toast" and math.min(style.Width, 420) or style.Width
		root = new("Frame", { Name = "APM_Announcement", AnchorPoint = anchor, Position = final, Size = UDim2.new(1, -2 * margin, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = background, BackgroundTransparency = baseTransparency, ZIndex = z }, parent)
		fade(root, "BackgroundTransparency", baseTransparency)
		if layout ~= "Banner" then
			new("UISizeConstraint", { MaxSize = Vector2.new(maxWidth, math.huge) }, root)
		end
		if style.Corner > 0 then
			new("UICorner", { CornerRadius = UDim.new(0, style.Corner) }, root)
		end
		if style.Border > 0 then
			local stroke = new("UIStroke", { Color = accent, Thickness = style.Border, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, root)
			fade(stroke, "Transparency", 0)
		end
		if style.AccentBar then
			local bar = new("Frame", { Name = "AccentBar", Size = UDim2.new(0, 5, 1, 0), BackgroundColor3 = accent, ZIndex = z + 1 }, root)
			if style.Corner > 0 then new("UICorner", { CornerRadius = UDim.new(0, math.min(style.Corner, 3)) }, bar) end
			fade(bar, "BackgroundTransparency", 0)
		end
	end

	-- Contenu : les textes empilés dans l'ordre choisi
	local content
	if layout == "Cinema" then
		content = new("Frame", { Name = "Content", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -80, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = z + 1 }, root)
		new("UISizeConstraint", { MaxSize = Vector2.new(style.Width, math.huge) }, content)
	else
		content = new("Frame", { Name = "Content", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = z + 1 }, root)
	end
	local list = new("UIListLayout", { Padding = UDim.new(0, layout == "Cinema" and 12 or 4), SortOrder = Enum.SortOrder.LayoutOrder }, content)
	if layout == "Cinema" then
		list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	else
		local left = (layout == "Toast" and 14 or 18) + (style.AccentBar and 6 or 0)
		new("UIPadding", { PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 14), PaddingLeft = UDim.new(0, left), PaddingRight = UDim.new(0, layout == "Toast" and 14 or 18) }, content)
	end
	if layout == "Cinema" and style.AccentBar then
		local bar = new("Frame", { Name = "AccentBar", Size = UDim2.fromOffset(120, 3), BackgroundColor3 = accent, LayoutOrder = 0, ZIndex = z + 2 }, content)
		fade(bar, "BackgroundTransparency", 0)
	end

	local texts = {
		Title = (customTitle ~= "" and customTitle or L("Announce.DefaultTitle")) .. (style.Title.Author and ("  -  " .. author) or ""),
		Message = message,
		Footer = style.Footer.Content == "Author" and L("Announce.FooterAuthor", author)
			or style.Footer.Content == "Time" and clock or L("Announce.FooterAuthorTime", author, clock),
	}
	if style.Title.Upper then texts.Title = Announcements.Upper(texts.Title) end
	local labels = {}
	for _, name in Announcements.Texts do
		local spec = style[name]
		if spec.Visible and texts[name] ~= "" then
			local label = new("TextLabel", { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
				Font = fontOf(spec.Font), TextSize = spec.Size, TextColor3 = Color3.fromHex(spec.Color), TextWrapped = true, RichText = false,
				TextXAlignment = ALIGN[spec.Align], LayoutOrder = spec.Order * 2, Text = texts[name], ZIndex = z + 2 }, content)
			fade(label, "TextTransparency", 0)
			labels[name] = label
		end
	end

	local scale = new("UIScale", { Scale = 1 }, layout == "Cinema" and content or root)
	local object = { Root = root, Labels = labels, Style = style, Duration = Announcements.Duration(style, message) }

	local function setFaded(alpha) -- 0 = visible, 1 = invisible
		for _, entry in fades do
			entry[1][entry[2]] = entry[3] + (1 - entry[3]) * alpha
		end
	end
	local function tweenFaded(alpha, time)
		for _, entry in fades do
			TweenService:Create(entry[1], TweenInfo.new(time, Enum.EasingStyle.Quad), { [entry[2]] = entry[3] + (1 - entry[3]) * alpha }):Play()
		end
	end
	-- Position de départ / sortie pour le glissement : on sort par le bord le plus proche
	local function offscreen()
		local size = root.AbsoluteSize
		local dx, dy = 0, 0
		if position == "TopLeft" or position == "BottomLeft" then
			dx = -(size.X + margin + 40)
		elseif position == "TopRight" or position == "BottomRight" then
			dx = size.X + margin + 40
		elseif position == "Bottom" then
			dy = size.Y + margin + 40
		else
			dy = -(size.Y + margin + 40)
		end
		return final + UDim2.fromOffset(dx, dy)
	end
	local animation = style.Animation
	if layout == "Cinema" and animation == "Slide" then animation = "Fade" end

	if opts.Static then
		root.Visible = true
	else
		root.Visible = false
	end

	function object.Show()
		if not root.Parent then return end
		task.wait() -- le texte détermine la hauteur avant de placer la boîte hors de l'écran
		if not root.Parent then return end
		if animation == "Slide" then
			root.Position = offscreen()
			root.Visible = true
			TweenService:Create(root, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = final }):Play()
		elseif animation == "Fade" then
			setFaded(1)
			root.Visible = true
			tweenFaded(0, 0.35)
		elseif animation == "Pop" then
			setFaded(1)
			scale.Scale = 0.8
			root.Visible = true
			tweenFaded(0, 0.25)
			TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		else
			root.Visible = true
		end
	end

	function object.Hide()
		if not root.Parent then return end
		if animation == "Slide" then
			TweenService:Create(root, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = offscreen() }):Play()
		elseif animation == "Fade" then
			tweenFaded(1, 0.3)
		elseif animation == "Pop" then
			tweenFaded(1, 0.25)
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.85 }):Play()
		else
			root.Visible = false
			return
		end
		task.wait(0.35)
		if root.Parent then root.Visible = false end
	end

	function object.Destroy()
		root:Destroy()
	end

	-- Cycle complet (annonce réelle ou test plein écran)
	function object.Play(playSound)
		if playSound ~= false and style.Sound then
			pcall(function()
				local sound = Instance.new("Sound")
				sound.SoundId = Announcements.Sound
				sound.Volume = 0.6
				SoundService:PlayLocalSound(sound)
				task.delay(3, function() sound:Destroy() end)
			end)
		end
		object.Show()
		task.wait(object.Duration)
		object.Hide()
		object.Destroy()
	end

	return object
end

return Announcements
