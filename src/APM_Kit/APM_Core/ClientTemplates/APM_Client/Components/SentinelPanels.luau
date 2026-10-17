--[[
	SentinelPanels : deux petits panneaux de l'interface flottante de Sentinel (client, dessin seulement : aucune décision, aucun droit).
	  Catalog : le catalogue de commandes (résultat de « help ») en grille de 3 colonnes, avec défilement vertical. Toucher une commande la PRÉPARE dans le champ de saisie
	            (jamais exécutée) ; une commande que le serveur déclare verrouillée porte un cadenas, son nom reste visible, et elle ne s'insère pas.
	  Popup   : la liste de suggestions de l'autocomplétion (au plus six lignes + une ligne d'aide sur les arguments attendus).
	L'environnement `env` fournit UI, T, Palette, les textes et les rappels ; chaque panneau crée ses objets une fois et les réutilise (aucune création à chaque frappe),
	ses connexions vivent et meurent avec lui (Destroy).
]]
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")

local Panels = {}

Panels.COLUMNS = 3
Panels.MAX_ROWS = 6

-- Cadenas DESSINÉ (aucune police emoji, donc identique sur toutes les plateformes) : un corps arrondi et une anse (cadre à contour dont le bas est caché par le corps)
function Panels.Padlock(UI, parent, color, position)
	local holder = UI.new("Frame", { Name = "Padlock", Size = UDim2.fromOffset(10, 12), Position = position, BackgroundTransparency = 1 }, parent)
	UI.new("Frame", { Name = "Shackle", Size = UDim2.fromOffset(6, 8), Position = UDim2.fromOffset(2, 0), BackgroundTransparency = 1, Corner = 3, Stroke = color, StrokeThickness = 1.4 }, holder)
	UI.new("Frame", { Name = "Body", Size = UDim2.fromOffset(10, 7), Position = UDim2.fromOffset(0, 5), BackgroundColor3 = color, Corner = 2 }, holder)
	return holder
end

local function escape(value)
	return (string.gsub(string.gsub(string.gsub(tostring(value), "&", "&amp;"), "<", "&lt;"), ">", "&gt;"))
end

-- Ligne d'aide en texte riche : le nom, puis chaque argument ; ceux qui sont attendus MAINTENANT sont en gras et en clair
function Panels.HintText(hint, palette)
	if type(hint) ~= "table" then return "" end
	local dim, bright = "#" .. palette.Sub:ToHex(), "#" .. palette.Text:ToHex()
	local pieces = { '<font color="' .. dim .. '">' .. escape(hint.Name) .. "</font>" }
	for _, part in hint.Parts do
		if part.Active then
			table.insert(pieces, '<font color="' .. bright .. '"><b>' .. escape(part.Text) .. "</b></font>")
		else
			table.insert(pieces, '<font color="' .. dim .. '">' .. escape(part.Text) .. "</font>")
		end
	end
	return table.concat(pieces, " ")
end

----------------------------------------------------------------------------------------------------------
-- Catalogue

--[[
	env : { UI, T, Palette, Head (hauteur de l'en-tête de Sentinel), Close = texte, OnPick(commande), OnClose() }
	Renvoie { Frame, Show(commandes, introduction), Update(commandes), Hide(), IsOpen(), Notice(texte), Destroy() }
]]
function Panels.Catalog(env, parent)
	local UI, P, T = env.UI, env.Palette, env.T
	local panel = { Buttons = {}, Commands = {}, Selected = nil, Intro = "" }
	local frame = UI.new("Frame", { Name = "Catalog", Size = UDim2.new(1, 0, 1, -env.Head), Position = UDim2.fromOffset(0, env.Head), BackgroundColor3 = P.Panel, Visible = false,
		ZIndex = 20, Active = true, Corner = 10 }, parent)
	panel.Frame = frame
	local intro = UI.label({ Name = "Intro", Size = UDim2.new(1, -46, 0, 34), Position = UDim2.fromOffset(10, 3), TextSize = 11, TextWrapped = true, TextColor3 = P.Sub, TextYAlignment = Enum.TextYAlignment.Top,
		Text = "", ZIndex = 21 }, frame)
	local close = UI.button({ Name = "CloseCatalog", Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -32, 0, 3), BackgroundColor3 = P.Head, TextColor3 = P.Text, TextSize = 16, Text = "×",
		Corner = 6, Selectable = true, ZIndex = 22 }, frame)
	local scroll = UI.scroll({ Name = "CatalogScroll", Size = UDim2.new(1, 0, 1, -40), Position = UDim2.fromOffset(0, 40), ScrollBarThickness = 3, ScrollBarImageColor3 = P.Edge, ZIndex = 21 }, frame)
	-- la grille laisse 7 px à gauche et 14 px à droite (barre de défilement comprise) : les enfants à échelle d'un cadre défilant ignorent son UIPadding
	local grid = UI.new("Frame", { Name = "Grid", Size = UDim2.new(1, -21, 0, 0), Position = UDim2.fromOffset(7, 2), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, ZIndex = 21 }, scroll)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / Panels.COLUMNS, -4, 0, 28)
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.FillDirectionMaxCells = Panels.COLUMNS
	layout.Parent = grid
	local connections = {}

	local function paintSelection()
		for index, button in panel.Buttons do
			local stroke = button:FindFirstChildOfClass("UIStroke")
			if stroke then stroke.Color = (index == panel.Selected) and P.Text or (panel.Commands[index].Locked and P.Dim or P.Edge) end
		end
	end

	local function select(index)
		if #panel.Buttons == 0 then return end
		panel.Selected = math.clamp(index, 1, #panel.Buttons)
		paintSelection()
		local button = panel.Buttons[panel.Selected]
		-- garde le bouton choisi visible dans la zone de défilement
		local top = button.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
		if top < scroll.CanvasPosition.Y then
			scroll.CanvasPosition = Vector2.new(0, math.max(0, top - 4))
		elseif top + button.AbsoluteSize.Y > scroll.CanvasPosition.Y + scroll.AbsoluteSize.Y then
			scroll.CanvasPosition = Vector2.new(0, top + button.AbsoluteSize.Y - scroll.AbsoluteSize.Y + 6)
		end
	end

	local function build(commands)
		local keep = scroll.CanvasPosition
		for _, button in panel.Buttons do button:Destroy() end
		table.clear(panel.Buttons)
		panel.Commands = commands
		for index, command in commands do
			local locked = command.Locked == true
			local button = UI.new("TextButton", { Name = "Cmd_" .. tostring(command.Name), Text = tostring(command.Name), Font = T.font, TextSize = 12, TextColor3 = locked and P.Dim or P.Text,
				BackgroundColor3 = locked and P.Head or P.Field, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Selectable = true,
				LayoutOrder = index, ZIndex = 22, Corner = 6, Stroke = locked and P.Dim or P.Edge }, grid)
			UI.padding(button, 0, locked and 23 or 8, 6)
			button:SetAttribute("Command", tostring(command.Name))
			button:SetAttribute("Locked", locked)
			if locked then
				-- le UIPadding du bouton décale aussi ses enfants : on compense (23 px de marge de texte) pour que le cadenas reste à 8 px du bord
				local padlock = Panels.Padlock(UI, button, P.Dim, UDim2.new(0, -15, 0.5, -6))
				for _, descendant in padlock:GetDescendants() do
					if descendant:IsA("GuiObject") then descendant.ZIndex = 23 end
				end
			end
			button.Activated:Connect(function()
				panel.Selected = index
				paintSelection()
				if env.OnPick then env.OnPick(command) end
			end)
			button.MouseEnter:Connect(function() if not locked then button.BackgroundColor3 = P.Field:Lerp(Color3.new(1, 1, 1), .1) end end)
			button.MouseLeave:Connect(function() if not locked then button.BackgroundColor3 = P.Field end end)
			panel.Buttons[index] = button
		end
		paintSelection()
		task.defer(function()
			if scroll.Parent then scroll.CanvasPosition = keep end
		end)
	end

	function panel.IsOpen()
		return frame.Visible
	end

	-- Au clavier (champ de saisie non actif) : flèches pour parcourir la grille, Entrée pour préparer, Échap pour fermer. Les flèches ne déplacent plus le personnage tant que le catalogue est ouvert.
	local ACTION = "APM_SentinelCatalogKeys"
	local function unbind()
		pcall(function() ContextActionService:UnbindAction(ACTION) end)
	end
	local function onKey(_, state, input)
		-- l'interface a disparu sans fermer le catalogue (panneau reconstruit) : on rend les touches et on se retire
		if not frame:IsDescendantOf(game) or not frame.Visible then
			unbind()
			return Enum.ContextActionResult.Pass
		end
		if state ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		if input.KeyCode == Enum.KeyCode.Escape then
			panel.Hide()
			return Enum.ContextActionResult.Sink
		end
		if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		local current = panel.Selected or 0
		if input.KeyCode == Enum.KeyCode.Down then select(current == 0 and 1 or current + Panels.COLUMNS)
		elseif input.KeyCode == Enum.KeyCode.Up then select(current == 0 and 1 or current - Panels.COLUMNS)
		elseif input.KeyCode == Enum.KeyCode.Right then select(current + 1)
		elseif input.KeyCode == Enum.KeyCode.Left then select(math.max(1, current - 1))
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			local command = panel.Commands[current]
			if command and env.OnPick then env.OnPick(command) end
		else
			return Enum.ContextActionResult.Pass
		end
		return Enum.ContextActionResult.Sink
	end

	function panel.Show(commands, text)
		panel.Intro = text or ""
		intro.Text = panel.Intro
		build(commands or {})
		frame.Visible = true
		scroll.CanvasPosition = Vector2.new(0, 0)
		unbind()
		ContextActionService:BindActionAtPriority(ACTION, onKey, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Down, Enum.KeyCode.Up, Enum.KeyCode.Left, Enum.KeyCode.Right,
			Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter, Enum.KeyCode.Escape)
		-- manette : la première commande reçoit la sélection pour que la croix directionnelle fonctionne tout de suite
		if string.find(UserInputService:GetLastInputType().Name, "Gamepad", 1, true) and panel.Buttons[1] then
			GuiService.SelectedObject = panel.Buttons[1]
		end
	end

	-- Les droits ont changé : mêmes boutons, nouveaux cadenas (sans refermer le catalogue) ; l'introduction (nombre de commandes utilisables) suit
	function panel.Update(commands, text)
		if not frame.Visible then return end
		if text then
			panel.Intro = text
			intro.Text = text
		end
		build(commands or {})
	end

	function panel.Hide()
		unbind()
		if not frame.Visible then return end
		frame.Visible = false
		panel.Selected = nil
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(frame) then GuiService.SelectedObject = nil end
		if env.OnClose then env.OnClose() end
	end

	-- Message passager dans l'en-tête (commande verrouillée touchée), puis retour à l'introduction
	local noticeToken = 0
	function panel.Notice(text)
		noticeToken += 1
		local token = noticeToken
		intro.Text = text
		intro.TextColor3 = P.Warn
		task.delay(3.5, function()
			if noticeToken == token and intro.Parent then
				intro.Text = panel.Intro
				intro.TextColor3 = P.Sub
			end
		end)
	end

	table.insert(connections, close.Activated:Connect(function() panel.Hide() end))
	table.insert(connections, frame.Destroying:Connect(unbind)) -- l'interface est détruite de l'extérieur : les touches sont rendues

	function panel.Destroy()
		unbind()
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(frame) then GuiService.SelectedObject = nil end
		frame:Destroy()
	end

	return panel
end

----------------------------------------------------------------------------------------------------------
-- Suggestions

--[[
	env : { UI, T, Palette, Width, OnAccept(indice) }
	Renvoie { Frame, Show(items, hint, selected, you), Hide(), IsVisible(), Count(), Place(above, anchorY), Destroy() }
]]
function Panels.Popup(env, parent)
	local UI, P, T = env.UI, env.Palette, env.T
	local popup = { Rows = {}, Count = 0, Shown = false }
	local frame = UI.new("Frame", { Name = "Suggestions", AnchorPoint = Vector2.new(0, 1), Size = UDim2.fromOffset(env.Width, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = P.Head, Visible = false, ZIndex = 40, Corner = 8, Stroke = P.Edge }, parent)
	UI.padding(frame, 3, 3, 3)
	UI.list(frame, 1)
	popup.Frame = frame
	local hint = UI.label({ Name = "Hint", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextWrapped = true, RichText = true, TextColor3 = P.Sub,
		LayoutOrder = 1, ZIndex = 41, Text = "" }, frame)
	UI.padding(hint, 2, 5, 5)
	local connections = {}
	local lastAccept = 0

	local function accept(index)
		-- appui (souris, doigt) puis Activated (tout le reste) : une seule validation par geste
		if os.clock() - lastAccept < .25 then return end
		lastAccept = os.clock()
		if env.OnAccept then env.OnAccept(index) end
	end

	for index = 1, Panels.MAX_ROWS do
		local row = UI.new("TextButton", { Name = "Suggestion" .. index, Size = UDim2.new(1, 0, 0, 24), BackgroundColor3 = P.Field, BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
			Selectable = true, LayoutOrder = index + 1, Visible = false, ZIndex = 41, Corner = 5 }, frame)
		local label = UI.label({ Name = "Label", Size = UDim2.new(.55, -6, 1, 0), Position = UDim2.fromOffset(7, 0), TextSize = 12, TextColor3 = P.Text, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 42,
			Text = "" }, row)
		local detail = UI.label({ Name = "Detail", Size = UDim2.new(.45, -8, 1, 0), Position = UDim2.new(.55, 0, 0, 0), TextSize = 11, TextColor3 = P.Dim, TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 42, Text = "" }, row)
		table.insert(connections, row.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then accept(index) end
		end))
		table.insert(connections, row.Activated:Connect(function() accept(index) end))
		popup.Rows[index] = { Button = row, Label = label, Detail = detail }
	end

	function popup.IsVisible()
		return popup.Shown
	end

	-- items : suggestions de SentinelSuggest ; selected : ligne en surbrillance (nil = aucune) ; you : texte traduit de « vous »
	function popup.Show(items, hintText, selected, you)
		popup.Count = math.min(#items, Panels.MAX_ROWS)
		hint.Text = hintText or ""
		hint.Visible = hintText ~= nil and hintText ~= ""
		for index, row in popup.Rows do
			local entry = items[index]
			row.Button.Visible = entry ~= nil
			if entry then
				row.Label.Text = entry.Label .. (entry.Self and ("  (" .. (you or "") .. ")") or "")
				local detail = entry.Detail or ""
				if entry.Kind == "Command" and entry.Command then detail = string.gsub(detail, "^%S+%s*", "") end
				row.Detail.Text = detail
				row.Button.BackgroundTransparency = (index == selected) and 0 or 1
			end
		end
		popup.Shown = popup.Count > 0 or (hintText ~= nil and hintText ~= "")
		frame.Visible = popup.Shown
	end

	function popup.Highlight(selected)
		for index, row in popup.Rows do
			row.Button.BackgroundTransparency = (index == selected and index <= popup.Count) and 0 or 1
		end
	end

	function popup.Hide()
		popup.Shown = false
		frame.Visible = false
	end

	-- au-dessus du champ (bord bas à y) ou, faute de place, au-dessous (bord haut à y)
	function popup.Place(above, x, y)
		frame.AnchorPoint = Vector2.new(0, above and 1 or 0)
		frame.Position = UDim2.fromOffset(x, y)
	end

	function popup.Destroy()
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
		frame:Destroy()
	end

	return popup
end

return Panels
