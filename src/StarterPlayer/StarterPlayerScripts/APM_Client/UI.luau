--[[
	UI : constructeurs d'interface de l'APM (cartes, boutons, champs, listes de choix, interrupteurs, curseurs...).
	Les pages l'utilisent via Core.UI ; les couleurs viennent de ReplicatedStorage > APM_Shared > Config (Theme).
	Les connexions globales (clavier, souris) passent par Core.On : elles sont coupées quand le panneau se reconstruit.
]]
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = {}
local Core -- relié par UI.Bind(Core) à chaque construction du panneau
local T

function UI.Bind(core)
	Core = core
	T = core.T
	UI.T = T
end

function UI.corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

function UI.stroke(parent, color, thickness)
	local s = Instance.new("UIStroke")
	s.Color = color or T.stroke
	s.Thickness = thickness or 1
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UI.padding(parent, px, left, right)
	local p = Instance.new("UIPadding")
	p.PaddingTop, p.PaddingBottom = UDim.new(0, px), UDim.new(0, px)
	p.PaddingLeft, p.PaddingRight = UDim.new(0, left or px), UDim.new(0, right or left or px)
	p.Parent = parent
	return p
end

function UI.list(parent, padding, horizontal)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, padding or 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	if horizontal then
		l.FillDirection = Enum.FillDirection.Horizontal
	end
	l.Parent = parent
	return l
end

-- Crée une instance : UI.new("Frame", { Size = ..., Corner = 8, Stroke = couleur, StrokeThickness = 1.5 }, parent)
function UI.new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in props or {} do
		if key == "Corner" then
			UI.corner(instance, value)
		elseif key == "Stroke" then
			UI.stroke(instance, value, props.StrokeThickness)
		elseif key ~= "StrokeThickness" then
			instance[key] = value
		end
	end
	if className == "TextButton" and (not props or props.AutoButtonColor == nil) then
		instance.AutoButtonColor = false
	end
	if instance:IsA("GuiObject") then
		instance.BorderSizePixel = 0
	end
	instance.Parent = parent
	return instance
end

local function merge(base, props)
	for key, value in props do
		base[key] = value
	end
	return base
end

function UI.label(props, parent)
	return UI.new("TextLabel", merge({ BackgroundTransparency = 1, Font = T.font, TextSize = 14, TextColor3 = T.text, TextXAlignment = Enum.TextXAlignment.Left }, props), parent)
end

function UI.button(props, parent)
	return UI.new("TextButton", merge({ BackgroundColor3 = T.panel2, Font = T.fontBold, TextSize = 14, TextColor3 = T.text, Corner = 8 }, props), parent)
end

function UI.input(props, parent)
	local box = UI.new("TextBox", merge({ Text = "", BackgroundColor3 = T.panel, Font = T.font, TextSize = 14, TextColor3 = T.text, PlaceholderColor3 = T.sub,
		ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Corner = 8, Stroke = T.stroke }, props), parent)
	UI.padding(box, 0, 10, 10)
	return box
end

function UI.scroll(props, parent)
	return UI.new("ScrollingFrame", merge({ BackgroundTransparency = 1, ScrollBarThickness = 5, ScrollBarImageColor3 = T.stroke, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y }, props), parent)
end

-- Fait réagir un bouton au survol
function UI.hover(button, base)
	base = base or button.BackgroundColor3
	button.MouseEnter:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), 0.12) }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = base }):Play()
	end)
end

-- Titre de section : pastille de couleur + texte
function UI.sectionHeader(text, color, parent, order)
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = order or 1 }, parent)
	UI.new("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(0, 4), BackgroundColor3 = color, Corner = 3 }, row)
	UI.label({ Size = UDim2.new(1, -18, 1, 0), Position = UDim2.fromOffset(18, 0), Font = T.fontBold, TextSize = 13, TextColor3 = color, TextTruncate = Enum.TextTruncate.AtEnd, Text = text }, row)
	return row
end

-- Carte (section) à hauteur automatique, avec liste verticale
function UI.card(parent, order)
	local card = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel2, LayoutOrder = order, Corner = 10, Stroke = T.stroke }, parent)
	UI.list(card, 8)
	UI.padding(card, 10)
	return card
end

-- Texte d'état centré dans un conteneur
function UI.emptyState(parent, text)
	return UI.label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		TextColor3 = T.sub, TextWrapped = true, Text = text }, parent)
end

--[[
	Liste déroulante avec recherche. options : { { id, texte }, ... } ou une fonction qui renvoie cette liste (relue à chaque ouverture).
	Les textes peuvent être des clés de traduction. display(id) (facultatif) : texte du bouton.
	Renvoie { Get(), Set(id), Frame, Changed = function(id) (à définir) }.
]]
function UI.picker(parent, options, default, size, position, display)
	local function current()
		local list = type(options) == "function" and options() or options
		return type(list) == "table" and list or {}
	end
	local selected = default
	local function labelOf(id)
		for _, entry in current() do
			if entry[1] == id then
				return Core.Text(entry[2])
			end
		end
		return "—"
	end
	local button = UI.button({ Size = size or UDim2.new(1, 0, 0, 30), Position = position or UDim2.new(), BackgroundColor3 = T.panel, Font = T.font, TextSize = 13,
		Text = "", TextTruncate = Enum.TextTruncate.AtEnd, Stroke = T.stroke }, parent)
	local object = { Frame = button }
	local popup

	local function render()
		button.Text = display and display(object.Get()) or (labelOf(object.Get()) .. "  v")
	end
	local function close()
		if popup then
			popup:Destroy()
			popup = nil
		end
	end

	function object.Get()
		if selected == nil then
			local first = current()[1]
			return first and first[1] or nil
		end
		return selected
	end
	function object.Set(id)
		selected = id
		render()
	end
	function object.Refresh()
		render()
	end

	button.Activated:Connect(function()
		if popup then
			close()
			return
		end
		local gui = button:FindFirstAncestorOfClass("ScreenGui")
		if not gui then
			return
		end
		local scale = Core.main and Core.main:FindFirstChildOfClass("UIScale")
		local ui = scale and scale.Scale or 1
		local at = button.AbsolutePosition - gui.AbsolutePosition
		local height = 230
		local y = at.Y + button.AbsoluteSize.Y + 4
		if y + height * ui > gui.AbsoluteSize.Y then -- pas la place en dessous : la liste s'ouvre au-dessus
			y = math.max(0, at.Y - 4 - height * ui)
		end
		popup = UI.new("Frame", { Size = UDim2.fromOffset(math.max(button.AbsoluteSize.X / ui, 240), height), Position = UDim2.fromOffset(at.X, y),
			BackgroundColor3 = T.bg, ZIndex = 50, Corner = 8, Stroke = T.accent }, gui)
		UI.new("UIScale", { Scale = ui }, popup)
		local search = UI.input({ Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 6), PlaceholderText = Core.L("Common.Search"), ZIndex = 51, TextSize = 13 }, popup)
		local scroll = UI.scroll({ Size = UDim2.new(1, -12, 1, -42), Position = UDim2.fromOffset(6, 36), ZIndex = 51 }, popup)
		UI.list(scroll, 3)
		local function fill()
			for _, child in scroll:GetChildren() do
				if child:IsA("GuiObject") then
					child:Destroy()
				end
			end
			local query = string.lower(search.Text)
			local list = current()
			for index, entry in list do
				local text = Core.Text(entry[2])
				if query == "" or string.find(string.lower(text), query, 1, true) then
					local row = UI.button({ Size = UDim2.new(1, -6, 0, 28), BackgroundColor3 = entry[1] == object.Get() and T.accent or T.panel2, Font = T.font, TextSize = 13,
						Text = text, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = index, ZIndex = 52 }, scroll)
					UI.padding(row, 0, 8, 8)
					row.Activated:Connect(function()
						object.Set(entry[1])
						close()
						if object.Changed then
							object.Changed(entry[1])
						end
					end)
				end
			end
			if #list == 0 then
				UI.label({ Size = UDim2.new(1, -6, 0, 28), TextColor3 = T.sub, TextSize = 12, ZIndex = 52, Text = "—" }, scroll)
			end
		end
		search:GetPropertyChangedSignal("Text"):Connect(fill)
		fill()
	end)
	button.AncestryChanged:Connect(function()
		if not button:IsDescendantOf(game) then
			close()
		end
	end)
	button:GetPropertyChangedSignal("AbsolutePosition"):Connect(close)
	render()
	return object
end

-- Bouton à confirmation : un premier clic arme le bouton (« Confirmer ? » pendant 3 s), le second exécute. needConfirm peut être une fonction.
function UI.Confirmable(button, needConfirm, run)
	local original = button.Text
	local token = 0
	local armed = false
	button.Activated:Connect(function()
		local need = (type(needConfirm) == "function" and needConfirm()) or needConfirm == true
		if not need then
			run()
			return
		end
		if armed then
			armed = false
			token += 1
			button.Text = original
			run()
			return
		end
		armed = true
		token += 1
		local mine = token
		original = button.Text
		button.Text = Core.L("Common.Confirm")
		task.delay(3, function()
			if armed and token == mine then
				armed = false
				button.Text = original
			end
		end)
	end)
end

-- Interrupteur ON/OFF : { Get, Set(valeur), Frame } ; onChange(état) à chaque clic
function UI.Switch(parent, default, onChange, position)
	local state = default == true
	local button = UI.button({ Size = UDim2.fromOffset(46, 24), Position = position or UDim2.new(), BackgroundColor3 = state and T.good or T.panel, Text = "", Corner = 12, Stroke = T.stroke }, parent)
	local knob = UI.new("Frame", { Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, state and 25 or 3, 0.5, 0), BackgroundColor3 = Color3.new(1, 1, 1), Corner = 9 }, button)
	local object = { Frame = button }
	local function render()
		TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = state and T.good or T.panel }):Play()
		TweenService:Create(knob, TweenInfo.new(0.12), { Position = UDim2.new(0, state and 25 or 3, 0.5, 0) }):Play()
	end
	function object.Get()
		return state
	end
	function object.Set(value)
		state = value == true
		render()
	end
	button.Activated:Connect(function()
		state = not state
		render()
		if onChange then
			onChange(state)
		end
	end)
	return object
end

-- Curseur : { Get, Set(valeur), Frame } ; onCommit(valeur) au relâchement, object.Changed(valeur) pendant le glissement
function UI.Slider(parent, min, max, default, onCommit, size, position)
	local value = math.clamp(default or min, min, max)
	local hit = UI.new("Frame", { Size = size or UDim2.new(1, 0, 0, 24), Position = position or UDim2.new(), BackgroundTransparency = 1, Active = true }, parent)
	local bar = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 8), Position = UDim2.fromScale(0, 0.5), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = T.panel, Corner = 4, Stroke = T.stroke }, hit)
	local fill = UI.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.accent, Corner = 4 }, bar)
	local knob = UI.new("Frame", { Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Corner = 8 }, bar)
	local object = { Frame = hit }
	local function render()
		local alpha = max > min and (value - min) / (max - min) or 0
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
	end
	local function fromX(x)
		local width = math.max(bar.AbsoluteSize.X, 1)
		local alpha = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
		value = math.floor(min + alpha * (max - min) + 0.5)
		render()
		if object.Changed then
			object.Changed(value)
		end
	end
	function object.Get()
		return value
	end
	function object.Set(newValue)
		value = math.clamp(newValue, min, max)
		render()
	end
	local dragging = false
	hit.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromX(input.Position.X)
		end
	end)
	Core.On(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromX(input.Position.X)
		end
	end)
	Core.On(UserInputService.InputEnded, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			if onCommit then
				onCommit(value)
			end
		end
	end)
	render()
	return object
end

return UI

