--[[
	Assistant (client) : Sentinel, l'assistant de commandes FLOTTANT. Indépendant de la fenêtre de l'APM : sa propre interface (APM_Sentinel),
	trois états indépendants — APM ouvert / fermé, Sentinel activé / désactivé, Sentinel déployé / rétracté — donc fermer l'APM ne le touche pas.

	Deux flèches (voir Glyph : chacune est un double chevron courbé, deux flèches colorées de teintes opposées qui échangent leurs couleurs en douceur à chaque onde) :
	  · flèche du haut : la zone de discussion (en-tête + historique) se replie seule vers le bas, la flèche suit sa bordure ;
	  · flèche latérale : replie TOUT, l'historique ET la zone de saisie (vers le bord de l'écran le plus proche) ; de nouveau, elle déploie tout.
	Les deux repliées : mode ultra-compact, UNE flèche (la dernière utilisée), ni texte, ni cadre, non déplaçable ; elle restaure tout.
	Le client n'envoie que du texte (RunAssistant) : le serveur analyse, vérifie les droits et exécute. Rien n'est jamais décidé ici ;
	une réussite n'est affichée qu'après la réponse du serveur (ou, pour un outil client comme Fly, après son application réelle).
	Position, rétractions et historique survivent à une reconstruction du panneau (langue, grade) ; seule la désactivation les efface de l'écran.
]]
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local Root = script.Parent
local Assistant = {}

-- Identité graphique propre à Sentinel : graphite et blanc, aucun bleu d'accent (seuls les voyants de résultat portent une couleur)
local PALETTE = {
	Panel = Color3.fromRGB(17, 18, 21), Head = Color3.fromRGB(25, 26, 30), Field = Color3.fromRGB(29, 30, 35), Edge = Color3.fromRGB(74, 76, 84),
	Text = Color3.fromRGB(228, 230, 234), Sub = Color3.fromRGB(138, 141, 149), Dim = Color3.fromRGB(86, 88, 96),
	Good = Color3.fromRGB(98, 198, 132), Bad = Color3.fromRGB(224, 94, 94), Warn = Color3.fromRGB(228, 178, 72), Idle = Color3.fromRGB(150, 152, 160),
}
local DOT = { ok = PALETTE.Good, error = PALETTE.Bad, warn = PALETTE.Warn, info = PALETTE.Idle, user = PALETTE.Dim, busy = PALETTE.Warn }

-- Géométrie (pixels de conception ; un UIScale adapte à l'écran)
local WIDTH, DISC_HEIGHT, INPUT_HEIGHT, GAP, HEAD = 340, 196, 38, 4, 28
local HIT, GLYPH = 38, 26
local MARGIN = 6
local LOCAL_COMMANDS = { help = true, aide = true, list = true, commands = true, commandes = true, clear = true, cls = true, effacer = true }

-- État conservé d'une construction à l'autre (jamais envoyé au serveur sauf la position / rétraction via les préférences)
local persistent = { Layout = nil, History = {}, Sent = {}, CatalogOpen = false }

-- Côté vers lequel la zone de saisie se replie : le plus proche bord de l'écran (moitié gauche -> "L", moitié droite -> "R"). Calculé de la même façon au chargement et au repli,
-- donc retrouvé à l'identique d'une session à l'autre sans changer le format enregistré (x,y,v,h).
local function dockFor(x)
	return x < .5 and "L" or "R"
end

local function parseLayout(text)
	local x, y, v, h = string.match(tostring(text or ""), "^(%d%.?%d*),(%d%.?%d*),([01]),([01])$")
	x, y = tonumber(x), tonumber(y)
	if not x or not y then return nil end
	x = math.clamp(x, 0, 1)
	return { X = x, Y = math.clamp(y, 0, 1), V = v == "1", H = h == "1", Last = "H", Dock = dockFor(x) }
end

function Assistant.Attach(Core)
	local UI, T = Core.UI, Core.T
	local mine = Core.Session
	local Glyph = require(Root:WaitForChild("Glyph"))
	local Suggest = require(Root:WaitForChild("Components"):WaitForChild("SentinelSuggest"))
	local Panels = require(Root:WaitForChild("Components"):WaitForChild("SentinelPanels"))
	local playerGui = Core.Player:FindFirstChildOfClass("PlayerGui")
	local api = { Gui = nil, Server = nil, Visible = false }
	local view -- objets de l'interface en cours (nil si Sentinel est masqué)
	local ready = Instance.new("BindableEvent")
	local readyHolder = Instance.new("Folder")
	Core.TrackGui(readyHolder)
	pcall(function() ready.Parent = readyHolder end)
	api.Ready = ready.Event
	local drag = nil -- geste de déplacement en cours : { Connections = { ... } }, hors de `view` pour être toujours coupé

	local function alive()
		return Core.Alive(mine) and playerGui ~= nil
	end
	local function text(value)
		return Core.Text(value)
	end
	local function msg(key, ...)
		return Core.Lang.Msg(key, ...)
	end
	local function config()
		return api.Server and api.Server.Config or {}
	end
	local function preference(name)
		return Core.PersonalPreferences and Core.PersonalPreferences[name]
	end

	----------------------------------------------------------------------------------------------------------
	-- Historique : lignes réutilisées (aucune création sans fin), contenu conservé en texte traduisible

	local function maxHistory()
		return math.clamp(tonumber(config().MaxHistory) or 40, 10, 100)
	end

	local function styleRow(row, entry)
		row.Dot.BackgroundColor3 = DOT[entry.Kind] or PALETTE.Idle
		row.Label.Text = text(entry.Text)
		row.Label.TextColor3 = entry.Kind == "user" and PALETTE.Sub or (entry.Kind == "error" and Color3.fromRGB(240, 170, 170) or PALETTE.Text)
		row.Frame.Visible = true
	end

	local function scrollToEnd()
		if not view then return end
		task.defer(function()
			if view and view.Scroll.Parent then
				view.Scroll.CanvasPosition = Vector2.new(0, math.max(0, view.Scroll.AbsoluteCanvasSize.Y - view.Scroll.AbsoluteSize.Y))
			end
		end)
	end

	local function newRow(scroll)
		local frame = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false }, scroll)
		local dot = UI.new("Frame", { Size = UDim2.fromOffset(6, 6), Position = UDim2.fromOffset(0, 6), BackgroundColor3 = PALETTE.Idle, Corner = 3 }, frame)
		local label = UI.label({ Size = UDim2.new(1, -14, 0, 0), Position = UDim2.fromOffset(14, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, RichText = false, Text = "" }, frame)
		return { Frame = frame, Dot = dot, Label = label }
	end

	local function render(entry)
		if not view then return end
		local row
		if #view.Rows < maxHistory() then
			row = newRow(view.Scroll)
		else
			row = table.remove(view.Rows, 1) -- la plus ancienne devient la plus récente
		end
		table.insert(view.Rows, row)
		view.Order += 1
		row.Frame.LayoutOrder = view.Order
		styleRow(row, entry)
	end

	local function remember(entry)
		table.insert(persistent.History, entry)
		while #persistent.History > maxHistory() do table.remove(persistent.History, 1) end
	end

	-- Voyant de résultat : visible même quand la zone de discussion est repliée (le dernier message occupe alors le champ de saisie quelques secondes)
	local function setStatus(kind, value)
		if not view then return end
		if kind == "ok" or kind == "error" or kind == "warn" then view.ResultKind = kind end
		view.StatusDot.BackgroundColor3 = DOT[kind] or PALETTE.Idle
		view.HeadDot.BackgroundColor3 = DOT[kind] or PALETTE.Idle
		if value and view.Layout.V then
			view.Box.PlaceholderText = text(value)
			view.PlaceholderToken += 1
			local token = view.PlaceholderToken
			task.delay(5, function()
				if view and view.PlaceholderToken == token then view.Box.PlaceholderText = text("Sentinel.Placeholder") end
			end)
		end
	end

	local function push(kind, value)
		local entry = { Kind = kind, Text = value }
		remember(entry)
		render(entry)
		scrollToEnd()
		if kind ~= "user" and kind ~= "info" then setStatus(kind, value) end
	end

	local function clearHistory()
		table.clear(persistent.History)
		if view then
			for _, row in view.Rows do row.Frame.Visible = false end
			table.clear(view.Rows)
			for _, child in view.Scroll:GetChildren() do
				if child:IsA("GuiObject") then child:Destroy() end
			end
		end
	end

	----------------------------------------------------------------------------------------------------------
	-- Envoi d'une commande

	local CODE_KIND = { Denied = "error", Protected = "error", Failed = "error", NotFound = "error", Invalid = "error", Unknown = "error", Error = "error",
		Partial = "warn", Ambiguous = "warn", Confirm = "warn", Busy = "warn", RateLimited = "warn", Disabled = "warn", Unavailable = "warn", External = "warn" }

	local function applyTool(client)
		local tool = Core.ClientModules[client.Tool]
		if not tool then push("error", msg("Sentinel.ToolFailed", tostring(client.Tool))) return end
		-- Target : joueur à observer (Spectator), choisi et vérifié par le serveur ; l'outil ne fait que suivre ce joueur
		local target = type(client.Target) == "number" and game:GetService("Players"):GetPlayerByUserId(client.Target) or nil
		local ok, applied = pcall(tool.Set, client.State == true, target)
		local success = ok and (client.State ~= true or applied ~= false)
		local label = text(tool.Label or client.Tool)
		if success then
			push("ok", msg(client.State and "Sentinel.ToolOn" or "Sentinel.ToolOff", label))
		else
			push("error", msg("Sentinel.ToolFailed", label))
		end
	end

	-- détail d'UNE commande (help <commande>) : une ligne d'usage ; la liste complète est le catalogue (showCatalog)
	local function showHelp(result)
		push("info", result.Text)
		for _, entry in result.Help or {} do
			local description = (entry.Description ~= nil or entry.Label ~= nil) and text(entry.Description ~= nil and entry.Description or entry.Label) or ""
			push("info", description ~= "" and (entry.Usage .. "  —  " .. description) or entry.Usage)
		end
	end

	-- déclarées ici, définies plus bas (catalogue, suggestions) : submit et handle s'en servent
	local submit, showCatalog, hideSuggestions, refreshSuggestions, acceptSuggestion, pickCommand, expandDiscussion

	-- Confirmation (commande sensible, ou phrase interprétée par l'IA externe) : deux boutons, aucun envoi tant que l'admin n'a pas dit oui
	local function askConfirmation(result, original)
		if not view then return end
		if view.ConfirmFrame then view.ConfirmFrame:Destroy() view.ConfirmFrame = nil end
		local frame = UI.new("Frame", { Name = "Confirmation", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = PALETTE.Field,
			Corner = 6, LayoutOrder = view.Order + 1 }, view.Scroll)
		view.Order += 1
		UI.padding(frame, 6)
		UI.list(frame, 5)
		UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, Text = text(result.Text), LayoutOrder = 1 }, frame)
		local buttons = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 2 }, frame)
		local yes = UI.button({ Name = "ConfirmYes", Size = UDim2.new(.5, -3, 1, 0), BackgroundColor3 = PALETTE.Text, TextColor3 = PALETTE.Panel, TextSize = 12,
			Text = text("Sentinel.Confirm"), Selectable = true }, buttons)
		local no = UI.button({ Name = "ConfirmNo", Size = UDim2.new(.5, -3, 1, 0), Position = UDim2.new(.5, 3, 0, 0), BackgroundColor3 = PALETTE.Head, TextColor3 = PALETTE.Text,
			TextSize = 12, Text = text("Sentinel.Cancel"), Selectable = true, Stroke = PALETTE.Edge }, buttons)
		view.ConfirmFrame = frame
		local token = result.Confirm.Token
		local command = result.Confirm.Command or original
		local function close()
			if view and view.ConfirmFrame == frame then view.ConfirmFrame = nil end
			frame:Destroy()
		end
		yes.Activated:Connect(function()
			close()
			submit(command, token, true)
		end)
		no.Activated:Connect(function()
			close()
			push("info", msg("Sentinel.Cancelled"))
		end)
		task.delay(tonumber(result.Confirm.Seconds) or 20, function()
			if frame.Parent then close() end
		end)
		scrollToEnd()
	end

	local function handle(original, result, token)
		if result.Code == "Confirm" and type(result.Confirm) == "table" and type(result.Confirm.Token) == "string" then
			askConfirmation(result, original)
		elseif result.Code == "Client" and type(result.Client) == "table" then
			applyTool(result.Client)
		elseif result.Code == "Help" then
			if result.Catalog == true then showCatalog(result) else showHelp(result) end
		elseif result.Code == "Clear" then
			if view and view.Catalog then view.Catalog.Hide() end
			clearHistory()
		else
			push(result.Ok and "ok" or (CODE_KIND[result.Code] or "error"), result.Text)
			for _, detail in result.Details or {} do push("info", detail) end
		end
	end

	submit = function(command, token, silent)
		if not view or view.Busy or not alive() then return end
		command = string.gsub(string.gsub(command or "", "^%s+", ""), "%s+$", "")
		if command == "" then return end
		view.Catalog.Hide() -- le résultat doit être visible : le catalogue se referme dès qu'une commande part
		hideSuggestions()
		-- 200 caracteres (pas octets : un texte chinois ou russe coupe en octets deviendrait de l'UTF-8 invalide)
		local length = utf8.len(command)
		if not length then return end
		if length > 200 then command = string.sub(command, 1, utf8.offset(command, 201) - 1) end
		if not silent then
			push("user", "› " .. command)
			table.insert(persistent.Sent, command)
			while #persistent.Sent > 30 do table.remove(persistent.Sent, 1) end
			view.SentIndex = #persistent.Sent + 1
		end
		view.Busy = true
		view.ResultKind = nil
		setStatus("busy")
		local current = view
		task.spawn(function()
			local ok, first, second = pcall(function()
				return Core.R.RunAssistant:InvokeServer(command, token)
			end)
			if view ~= current or not alive() then return end
			current.Busy = false
			if not ok then
				push("error", msg("Sentinel.Offline"))
			elseif first == false or type(first) ~= "table" then
				push("error", second ~= nil and second or msg("Sentinel.Offline")) -- demande refusée par la session privée (fréquence, arguments)
			else
				handle(command, first, token)
			end
			setStatus(current.ResultKind or "info")
		end)
	end

	----------------------------------------------------------------------------------------------------------
	-- Interface

	-- Disposition de départ : à gauche, à mi-hauteur. Sur un petit écran (téléphone en paysage) Sentinel démarre replié, en haut à gauche :
	-- il ne recouvre ni le joystick, ni le bouton de saut, et un appui sur sa flèche le déploie.
	local function defaultLayout()
		local camera = workspace.CurrentCamera
		local viewportSize = camera and camera.ViewportSize or Vector2.new(1280, 720)
		local small = viewportSize.Y < 460 or viewportSize.X < 520
		local deployed = config().DefaultDeployed ~= false and not small
		return { X = .02, Y = small and .06 or .5, V = not deployed, H = not deployed, Last = "H", Dock = dockFor(.02) }
	end

	local function build()
		local layout = persistent.Layout
		if not layout then
			layout = parseLayout(preference("AssistantLayout")) or defaultLayout()
			persistent.Layout = layout
		end
		local gui = UI.new("ScreenGui", { Name = "APM_Sentinel", ResetOnSpawn = false, DisplayOrder = 85, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			IgnoreGuiInset = false, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, ClipToDeviceSafeArea = true }, playerGui)
		gui:SetAttribute("APMPrivateSession", Root.Parent:GetAttribute("SessionId"))
		Core.TrackGui(gui)
		local v = { Gui = gui, Layout = layout, Rows = {}, Order = 0, Busy = false, PlaceholderToken = 0, SentIndex = 1, Glyphs = {}, Dragging = nil }

		local window = UI.new("Frame", { Name = "Window", Size = UDim2.fromOffset(WIDTH, DISC_HEIGHT + GAP + INPUT_HEIGHT), BackgroundTransparency = 1 }, gui)
		local scale = UI.new("UIScale", {}, window)
		v.Window, v.Scale = window, scale

		-- zone de discussion --------------------------------------------------------------------------------------
		local discClip = UI.new("Frame", { Name = "DiscussionClip", Size = UDim2.fromOffset(WIDTH, DISC_HEIGHT), BackgroundTransparency = 1, ClipsDescendants = true }, window)
		local disc = UI.new("Frame", { Name = "Discussion", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromOffset(WIDTH, DISC_HEIGHT),
			BackgroundColor3 = PALETTE.Panel, BackgroundTransparency = .03, Corner = 10, Stroke = PALETTE.Edge }, discClip)
		local header = UI.new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, HEAD), BackgroundColor3 = PALETTE.Head, Active = true }, disc)
		UI.new("UICorner", { CornerRadius = UDim.new(0, 10) }, header)
		UI.new("Frame", { Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BackgroundColor3 = PALETTE.Head }, header)
		local headDot = UI.new("Frame", { Name = "State", Size = UDim2.fromOffset(7, 7), Position = UDim2.fromOffset(12, 11), BackgroundColor3 = PALETTE.Idle, Corner = 4 }, header)
		UI.label({ Name = "Title", Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(26, 0), Font = T.fontBold, TextSize = 11, TextColor3 = PALETTE.Text,
			Text = "SENTINEL" }, header)
		UI.label({ Name = "Grip", Size = UDim2.fromOffset(40, HEAD), Position = UDim2.new(1, -48, 0, 0), TextSize = 12, TextColor3 = PALETTE.Dim, TextXAlignment = Enum.TextXAlignment.Right,
			Text = "• • •" }, header)
		local scroll = UI.scroll({ Name = "History", Size = UDim2.new(1, 0, 1, -(HEAD + 4)), Position = UDim2.fromOffset(0, HEAD + 2), ScrollBarThickness = 3,
			ScrollBarImageColor3 = PALETTE.Edge, ScrollingDirection = Enum.ScrollingDirection.Y }, disc)
		UI.list(scroll, 3)
		UI.padding(scroll, 7, 10, 10)
		v.Scroll, v.Header, v.HeadDot, v.Disc = scroll, header, headDot, disc
		-- catalogue de commandes (recouvre la zone de discussion, sous l'en-tête) ; créé une fois avec l'interface, détruit avec elle
		v.Catalog = Panels.Catalog({ UI = UI, T = T, Palette = PALETTE, Head = HEAD, OnPick = function(command) pickCommand(command) end,
			OnClose = function() persistent.CatalogOpen = false end }, disc)

		-- zone de saisie --------------------------------------------------------------------------------------------
		local inputTop = DISC_HEIGHT + GAP
		local inputClip = UI.new("Frame", { Name = "InputClip", Position = UDim2.fromOffset(0, inputTop), Size = UDim2.fromOffset(WIDTH, INPUT_HEIGHT), BackgroundTransparency = 1,
			ClipsDescendants = true }, window)
		local input = UI.new("Frame", { Name = "Input", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(WIDTH, INPUT_HEIGHT),
			BackgroundColor3 = PALETTE.Panel, BackgroundTransparency = .03, Corner = 10, Stroke = PALETTE.Edge }, inputClip)
		local grip = UI.new("Frame", { Name = "Grip", Size = UDim2.fromOffset(22, INPUT_HEIGHT), BackgroundTransparency = 1, Active = true }, input)
		local statusDot = UI.new("Frame", { Name = "Result", Size = UDim2.fromOffset(7, 7), Position = UDim2.fromOffset(9, 15), BackgroundColor3 = PALETTE.Idle, Corner = 4 }, grip)
		local box = UI.new("TextBox", { Name = "Command", Size = UDim2.new(1, -92, 1, -12), Position = UDim2.fromOffset(24, 6), BackgroundColor3 = PALETTE.Field, Font = T.font,
			TextSize = 13, TextColor3 = PALETTE.Text, PlaceholderColor3 = PALETTE.Sub, PlaceholderText = text("Sentinel.Placeholder"), Text = "", ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Corner = 7, MultiLine = false }, input)
		UI.padding(box, 0, 8, 8)
		local send = UI.button({ Name = "Send", Size = UDim2.fromOffset(58, INPUT_HEIGHT - 12), Position = UDim2.new(1, -64, 0, 6), BackgroundColor3 = PALETTE.Text,
			TextColor3 = PALETTE.Panel, TextSize = 12, Text = text("Sentinel.Send"), Corner = 7, Selectable = true }, input)
		v.Box, v.StatusDot, v.Grip, v.Input = box, statusDot, grip, input
		-- suggestions de l'autocomplétion (au-dessus du champ de saisie) : un seul panneau réutilisé à chaque frappe
		v.Popup = Panels.Popup({ UI = UI, T = T, Palette = PALETTE, Width = WIDTH - 32, OnAccept = function(index) acceptSuggestion(index) end }, window)

		-- flèches ---------------------------------------------------------------------------------------------------
		local function arrow(name, rotation)
			local button = UI.new("TextButton", { Name = name, Size = UDim2.fromOffset(HIT, HIT), AnchorPoint = Vector2.new(.5, .5), BackgroundTransparency = 1, Text = "", AutoButtonColor = false,
				ZIndex = 10, Selectable = true }, window)
			-- aucune pastille ni fond : la flèche est le trait seul, à l'INVERSE de sa teinte de cycle (clair <-> sombre), même onde de 30 s
			local glyph = Glyph.Create(button, { Size = GLYPH, Rotation = rotation, Tone = .78, Name = "Arrow", Double = true })
			table.insert(v.Glyphs, glyph)
			button.MouseEnter:Connect(function() glyph.SetTone(.98) end)
			button.MouseLeave:Connect(function() glyph.SetTone(.78) end)
			button.SelectionGained:Connect(function() glyph.SetTone(.98) end)
			button.SelectionLost:Connect(function() glyph.SetTone(.78) end)
			return button, glyph
		end
		local arrowV, glyphV = arrow("RetractDiscussion", 90)
		local arrowH, glyphH = arrow("RetractInput", 0)
		v.ArrowV, v.ArrowH, v.GlyphV, v.GlyphH = arrowV, arrowH, glyphV, glyphH
		return v
	end

	----------------------------------------------------------------------------------------------------------
	-- Mise en page : rétractions, position, échelle

	local function speed()
		return math.clamp(tonumber(config().AnimationSpeed) or 1, .5, 2)
	end

	-- Positions d'arrivée de chaque élément pour un état (v : discussion repliée, h : saisie repliée)
	local function targets(vRet, hRet, dock)
		local topOffset = vRet and DISC_HEIGHT or 0
		local hOffset = hRet and WIDTH or 0
		local hy = DISC_HEIGHT + GAP + INPUT_HEIGHT / 2
		-- zone de saisie : "L" se replie vers la gauche (la flèche est à son bord droit, tournée vers la gauche), "R" vers la droite (flèche à son bord gauche, tournée vers la droite) ;
		-- repliée, la flèche reste au bord par lequel la zone est partie et se retourne pour la rappeler
		local left = dock == "L"
		local hx = left and (WIDTH - hOffset + 17) or (hOffset - 17)
		return {
			DiscPos = UDim2.fromOffset(0, topOffset), DiscSize = UDim2.fromOffset(WIDTH, DISC_HEIGHT - topOffset),
			InputPos = UDim2.fromOffset(left and 0 or hOffset, DISC_HEIGHT + GAP), InputSize = UDim2.fromOffset(WIDTH - hOffset, INPUT_HEIGHT),
			ArrowV = UDim2.fromOffset(WIDTH - 24, topOffset - 17), ArrowH = UDim2.fromOffset(hx, hy),
			RotV = vRet and 270 or 90, RotH = left and (hRet and 0 or 180) or (hRet and 180 or 0),
			Vx = WIDTH - 24, Vy = topOffset - 17, Hx = hx, Hy = hy,
		}
	end

	-- Rectangle visible (pixels de conception, relatif à la fenêtre) : sert à garder Sentinel entièrement à l'écran, flèches comprises
	local function visibleBounds(layout)
		local target = targets(layout.V, layout.H, layout.Dock)
		local ultra = layout.V and layout.H
		local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
		local function add(x1, y1, x2, y2)
			minX, minY, maxX, maxY = math.min(minX, x1), math.min(minY, y1), math.max(maxX, x2), math.max(maxY, y2)
		end
		if not layout.V then add(0, 0, WIDTH, DISC_HEIGHT) end
		if not layout.H then add(0, DISC_HEIGHT + GAP, WIDTH, DISC_HEIGHT + GAP + INPUT_HEIGHT) end
		local pad = 3
		if not ultra or layout.Last == "V" then add(target.Vx - GLYPH / 2 - pad, target.Vy - GLYPH / 2 - pad, target.Vx + GLYPH / 2 + pad, target.Vy + GLYPH / 2 + pad) end
		if not ultra or layout.Last ~= "V" then add(target.Hx - GLYPH / 2 - pad, target.Hy - GLYPH / 2 - pad, target.Hx + GLYPH / 2 + pad, target.Hy + GLYPH / 2 + pad) end
		return minX, minY, maxX, maxY
	end

	-- Échelle : suit l'écran, mais jamais trop petite pour un doigt (tactile : zone de tir d'au moins ~33 px) ni trop grande pour la hauteur disponible
	local function computeScale(viewportSize)
		local base = math.clamp(math.min(viewportSize.X / 520, viewportSize.Y / 430), .75, 1)
		if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then base = math.max(base, .88) end
		base *= math.clamp(tonumber(preference("AssistantScale")) or 1, .6, 1.5)
		local fit = (viewportSize.Y - 2 * MARGIN) / (DISC_HEIGHT + GAP + INPUT_HEIGHT + 2 * 24) -- hauteur de la fenêtre + les deux flèches
		return math.max(.5, math.min(base, fit))
	end

	-- Position (pixels écran) ramenée dans l'écran
	local function clampedPosition(layout, scaleValue, viewportSize, x, y)
		local minX, minY, maxX, maxY = visibleBounds(layout)
		local lowX, highX = MARGIN - minX * scaleValue, viewportSize.X - MARGIN - maxX * scaleValue
		local lowY, highY = MARGIN - minY * scaleValue, viewportSize.Y - MARGIN - maxY * scaleValue
		local clampedX = highX < lowX and (lowX + highX) / 2 or math.clamp(x, lowX, highX)
		local clampedY = highY < lowY and (lowY + highY) / 2 or math.clamp(y, lowY, highY)
		return clampedX, clampedY
	end

	local pendingSave = false
	local function saveLayout()
		if pendingSave or not view then return end
		pendingSave = true
		task.delay(.8, function()
			pendingSave = false
			local layout = persistent.Layout
			if not layout or not alive() then return end
			local encoded = string.format("%.4f,%.4f,%d,%d", layout.X, layout.Y, layout.V and 1 or 0, layout.H and 1 or 0)
			if Core.PersonalPreferences then Core.PersonalPreferences.AssistantLayout = encoded end
			Core.SavePreferences({ AssistantLayout = encoded })
		end)
	end

	local function place(animated)
		if not view then return end
		local layout = persistent.Layout
		local viewportSize = view.Gui.AbsoluteSize
		if viewportSize.X <= 0 or viewportSize.Y <= 0 then return end
		view.Scale.Scale = computeScale(viewportSize)
		local x, y = clampedPosition(layout, view.Scale.Scale, viewportSize, layout.X * viewportSize.X, layout.Y * viewportSize.Y)
		local destination = UDim2.fromOffset(math.floor(x + .5), math.floor(y + .5))
		if animated then
			TweenService:Create(view.Window, TweenInfo.new(.22 / speed(), Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { Position = destination }):Play()
		else
			view.Window.Position = destination
		end
	end

	-- Fondu d'une flèche (très court) : un NumberValue éphémère pilote la transparence des traits
	local function fadeGlyph(glyph, from, to, duration)
		if duration <= 0 then glyph.SetTransparency(to) return end
		local driver = Instance.new("NumberValue")
		driver.Value = from
		glyph.SetTransparency(from)
		driver.Changed:Connect(function(value) glyph.SetTransparency(value) end)
		local tween = TweenService:Create(driver, TweenInfo.new(duration, Enum.EasingStyle.Sine), { Value = to })
		tween.Completed:Connect(function() driver:Destroy() end)
		tween:Play()
	end

	-- Applique l'état de rétraction. Les trois pièces (cadre, flèche, bordure) reçoivent la MÊME interpolation : la flèche accompagne la bordure.
	local function applyRetraction(animated)
		if not view then return end
		local layout = persistent.Layout
		local target = targets(layout.V, layout.H, layout.Dock)
		local ultra = layout.V and layout.H
		local duration = animated and .3 / speed() or 0
		-- la zone de saisie reste ancrée du côté opposé à son repli : elle est découpée par le cadre, jamais déformée (changer d'ancrage ne se voit pas : le cadre est plein à cet instant)
		local left = layout.Dock == "L"
		view.Input.AnchorPoint = left and Vector2.new(0, 0) or Vector2.new(1, 0)
		view.Input.Position = left and UDim2.fromScale(0, 0) or UDim2.fromScale(1, 0)
		local info = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.InOut)
		local function move(object, properties)
			if animated then TweenService:Create(object, info, properties):Play() else for name, value in properties do object[name] = value end end
		end
		move(view.Gui.Window.DiscussionClip, { Position = target.DiscPos, Size = target.DiscSize })
		move(view.Gui.Window.InputClip, { Position = target.InputPos, Size = target.InputSize })
		move(view.ArrowV, { Position = target.ArrowV })
		move(view.ArrowH, { Position = target.ArrowH })
		view.GlyphV.SetRotation(target.RotV, duration)
		view.GlyphH.SetRotation(target.RotH, duration)
		-- mode ultra-compact : une seule flèche (la dernière utilisée) ; l'autre s'efface puis devient inerte
		view.RetractToken = (view.RetractToken or 0) + 1
		local token, current = view.RetractToken, view
		local showV = not ultra or layout.Last == "V"
		local showH = not ultra or layout.Last ~= "V"
		for _, entry in { { view.ArrowV, view.GlyphV, showV }, { view.ArrowH, view.GlyphH, showH } } do
			local button, glyph, show = entry[1], entry[2], entry[3]
			button.Active, button.Selectable = show, show
			if show then
				if not button.Visible then
					button.Visible = true
					fadeGlyph(glyph, 1, 0, duration)
				end
			elseif button.Visible then
				fadeGlyph(glyph, 0, 1, duration)
				task.delay(duration, function()
					if view == current and current.RetractToken == token then button.Visible = false end
				end)
			end
		end
		view.Header.Active = not layout.V
		view.Grip.Active = not layout.H
		if ultra and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(view.Gui) then
			GuiService.SelectedObject = layout.Last == "V" and view.ArrowV or view.ArrowH
		end
	end

	local function retract(which)
		if not view then return end
		local layout = persistent.Layout
		if layout.V and layout.H then
			layout.V, layout.H = false, false -- la flèche restante restaure tout
		elseif which == "V" then
			layout.V = not layout.V
			layout.Last = "V"
		else
			-- la flèche latérale replie TOUT : l'historique (zone de discussion) ET la zone de saisie. Le côté du repli est choisi quand la saisie SE REPLIE
			-- (selon la position de la fenêtre) et reste figé jusqu'au déploiement. Il ne reste alors qu'une flèche (mode ultra-compact) qui déploie tout (cas ci-dessus).
			if not layout.H then layout.Dock = dockFor(layout.X) end
			layout.V, layout.H = true, true
			layout.Last = "H"
		end
		applyRetraction(true)
		place(true) -- une zone qui se rouvre peut déborder : on la ramène à l'écran
		saveLayout()
	end

	----------------------------------------------------------------------------------------------------------
	-- Catalogue de commandes (help) et autocomplétion : l'interface ne fait que PRÉPARER du texte ; rien n'est exécuté ici, le serveur juge de tout.

	-- zone de discussion repliée : on la déploie (le catalogue serait invisible)
	expandDiscussion = function()
		local layout = persistent.Layout
		if not view or not layout or not layout.V then return end
		layout.V, layout.Last = false, "V"
		applyRetraction(true)
		place(true)
		saveLayout()
	end

	-- introduction du catalogue : nombre de commandes utilisables sur le total, d'après les verrous que le serveur a calculés
	local function catalogIntro(commands)
		local usable = 0
		for _, command in commands do
			if command.Locked ~= true then usable += 1 end
		end
		return text(msg("Assistant.HelpCatalog", usable, #commands))
	end

	-- résultat de « help » : toutes les commandes, les interdites avec leur cadenas (calculé par le serveur)
	showCatalog = function(result)
		if not view then return end
		push("info", result.Text)
		expandDiscussion()
		hideSuggestions()
		persistent.CatalogOpen = true
		view.Catalog.Show(result.Help or {}, text(result.Text))
	end

	-- un bouton du catalogue a été touché : la commande est PRÉPARÉE dans le champ (jamais envoyée) ; une commande verrouillée ne s'insère pas
	pickCommand = function(command)
		if not view or type(command) ~= "table" then return end
		if command.Locked == true then
			view.Catalog.Notice(text(msg("Sentinel.Catalog.Locked", tostring(command.Name))))
			return
		end
		local box = view.Box
		box.Text = Suggest.CommandText(command)
		view.Catalog.Hide()
		task.defer(function()
			if view and view.Box == box and box.Parent then
				box:CaptureFocus()
				box.CursorPosition = #box.Text + 1
			end
		end)
	end

	local function suggestionOptions()
		local list = {}
		for _, player in game:GetService("Players"):GetPlayers() do
			table.insert(list, { UserId = player.UserId, Name = player.Name, DisplayName = player.DisplayName })
		end
		return { Players = list, SelfId = Core.Player.UserId }
	end

	hideSuggestions = function()
		if not view then return end
		view.Suggest = nil
		view.Popup.Hide()
	end

	-- au-dessus du champ ; au-dessous si l'écran n'a pas la place (fenêtre en haut de l'écran)
	local function placePopup(count, hasHint)
		local estimate = 12 + (hasHint and 22 or 0) + count * 25
		local scale = view.Scale.Scale
		local room = view.Input.AbsolutePosition.Y - view.Gui.AbsolutePosition.Y
		if room >= (estimate + 8) * scale then
			view.Popup.Place(true, 16, DISC_HEIGHT + GAP - 4)
		else
			view.Popup.Place(false, 16, DISC_HEIGHT + GAP + INPUT_HEIGHT + 4)
		end
	end

	-- recalcule les suggestions du texte (balayage mémoire, aucune requête) ; appelé à chaque changement du texte, jamais autrement
	refreshSuggestions = function()
		if not view then return end
		local box = view.Box
		if not api.Index or view.Catalog.IsOpen() or not box:IsFocused() or box.Text == "" then
			hideSuggestions()
			return
		end
		local result = Suggest.Analyze(api.Index, box.Text, box.CursorPosition, suggestionOptions())
		if result.Stage == "none" or (#result.Items == 0 and not result.Hint) then
			hideSuggestions()
			return
		end
		view.Suggest = { Result = result, Selected = nil, Explicit = false }
		local hintText = Panels.HintText(result.Hint, PALETTE)
		view.Popup.Show(result.Items, hintText, nil, text("Sentinel.Suggest.You"))
		placePopup(view.Popup.Count, hintText ~= "")
	end

	-- complète le texte avec une suggestion (Tab, clic, toucher, Entrée pendant une sélection au clavier) : le champ garde le focus, rien n'est envoyé
	acceptSuggestion = function(index)
		local state = view and view.Suggest
		local entry = state and state.Result.Items[index]
		if not entry then return end
		local box = view.Box
		local newText, cursor = Suggest.Apply(box.Text, state.Result.Range, entry)
		box.Text = newText
		task.defer(function()
			if view and view.Box == box and box.Parent then
				if not box:IsFocused() then box:CaptureFocus() end
				box.CursorPosition = cursor
				refreshSuggestions()
			end
		end)
	end

	local function moveSelection(delta)
		local state = view and view.Suggest
		local count = state and #state.Result.Items or 0
		if count == 0 then return false end
		local current = state.Selected or (delta > 0 and 0 or count + 1)
		current = ((current - 1 + delta) % count) + 1
		state.Selected, state.Explicit = current, true
		view.Popup.Highlight(current)
		return true
	end

	----------------------------------------------------------------------------------------------------------
	-- Déplacement (souris et tactile) : connexions créées au début du geste, toutes coupées à sa fin

	local function stopDrag()
		if not drag then return end
		for _, connection in drag.Connections do connection:Disconnect() end
		drag = nil
		-- la fenêtre a changé de moitié d'écran : les flèches se placent du bon côté (seulement quand la zone de saisie est déployée : repliée, son côté est figé)
		local layout = persistent.Layout
		if view and layout and not layout.H and layout.Dock ~= dockFor(layout.X) then
			layout.Dock = dockFor(layout.X)
			applyRetraction(false)
			place(false)
		end
		saveLayout()
	end

	local function beginDrag(input)
		if not view or drag then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		local layout = persistent.Layout
		if layout.V and layout.H then return end -- ultra-compact : la flèche n'est pas déplaçable
		local start = Vector2.new(input.Position.X, input.Position.Y)
		local origin = Vector2.new(view.Window.AbsolutePosition.X - view.Gui.AbsolutePosition.X, view.Window.AbsolutePosition.Y - view.Gui.AbsolutePosition.Y)
		local gesture = { Connections = {} }
		drag = gesture
		table.insert(gesture.Connections, UserInputService.InputChanged:Connect(function(change)
			if change ~= input and change.UserInputType ~= Enum.UserInputType.MouseMovement and change.UserInputType ~= Enum.UserInputType.Touch then return end
			if not view or drag ~= gesture then return end
			local pointer = Vector2.new(change.Position.X, change.Position.Y)
			local viewportSize = view.Gui.AbsoluteSize
			local x, y = clampedPosition(layout, view.Scale.Scale, viewportSize, origin.X + pointer.X - start.X, origin.Y + pointer.Y - start.Y)
			view.Window.Position = UDim2.fromOffset(x, y)
			layout.X, layout.Y = math.clamp(x / viewportSize.X, 0, 1), math.clamp(y / viewportSize.Y, 0, 1)
		end))
		table.insert(gesture.Connections, UserInputService.InputEnded:Connect(function(ended)
			if drag == gesture and (ended == input or ended.UserInputType == input.UserInputType) then stopDrag() end
		end))
		table.insert(gesture.Connections, input.Changed:Connect(function()
			if drag == gesture and input.UserInputState == Enum.UserInputState.End then stopDrag() end
		end))
	end

	----------------------------------------------------------------------------------------------------------
	-- Cycle de vie : Show / Hide ne laissent ni interface ni connexion orpheline

	local function waveNow()
		if not view then return end
		if preference("AssistantWave") == false or config().WaveEnabled == false then return end
		local layout = persistent.Layout
		local ultra = layout.V and layout.H
		if not ultra or layout.Last == "V" then view.GlyphV.PlayWave(speed()) end
		if not ultra or layout.Last ~= "V" then view.GlyphH.PlayWave(speed()) end
	end

	-- Taille ou résolution changée : remet l'échelle et la position à jour
	function api.Relayout()
		place(false)
	end

	-- Position, rétractions et taille par défaut (bouton de Sentinel Helper)
	function api.ResetLayout()
		stopDrag()
		persistent.Layout = defaultLayout()
		if view then
			view.Layout = persistent.Layout
			applyRetraction(false)
			place(true)
		end
		saveLayout()
	end

	-- Envoie une commande comme si elle était tapée (même chemin que le bouton : le serveur reste seul juge)
	function api.Submit(command)
		submit(command)
	end

	function api.Hide()
		stopDrag()
		if not view then return end
		local old = view
		view = nil
		for _, glyph in old.Glyphs do glyph.Destroy() end
		old.Catalog.Destroy() -- délie aussi les touches capturées par le catalogue
		old.Popup.Destroy()
		old.Gui:Destroy()
		api.Gui, api.Visible = nil, false
	end

	function api.Show()
		if view or not alive() or not playerGui then return end
		view = build()
		api.Gui, api.Visible = view.Gui, true
		local current = view
		-- connexions des objets de CETTE interface : elles disparaissent avec elle (Hide détruit le ScreenGui), rien ne s'accumule
		view.ArrowV.Activated:Connect(function() if view == current then retract("V") end end)
		view.ArrowH.Activated:Connect(function() if view == current then retract("H") end end)
		view.Header.InputBegan:Connect(function(input) if view == current then beginDrag(input) end end)
		view.Grip.InputBegan:Connect(function(input) if view == current then beginDrag(input) end end)
		view.Gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() if view == current then place(false) end end)
		view.Input.Send.Activated:Connect(function()
			if view ~= current then return end
			local command = view.Box.Text
			view.Box.Text = ""
			if view.Box:IsFocused() then view.Box:ReleaseFocus() end -- même règle que l'Entrée : le curseur quitte la zone de texte
			submit(command)
		end)
		view.Box.FocusLost:Connect(function(enterPressed)
			if view ~= current then return end
			if not enterPressed then
				-- focus perdu (autre zone touchée) : on laisse le temps à un appui sur une suggestion avant de fermer la liste
				task.delay(.25, function()
					if view == current and not current.Box:IsFocused() then hideSuggestions() end
				end)
				return
			end
			local selection = current.Suggest
			if selection and selection.Explicit and selection.Selected and current.Popup.IsVisible() then
				-- Entrée pendant une sélection faite aux flèches : on COMPLÈTE le texte, on n'envoie jamais (pas d'exécution accidentelle)
				acceptSuggestion(selection.Selected)
				return
			end
			-- Entrée : la commande part (même incorrecte : le serveur répond) et le curseur QUITTE la zone de texte. Le champ n'est jamais recapté après un envoi.
			hideSuggestions()
			local command = view.Box.Text
			view.Box.Text = ""
			submit(command)
		end)
		-- autocomplétion : UNE connexion sur le texte et UNE sur le focus, créées avec l'interface (rien ne s'accumule), calcul purement local
		view.Box:GetPropertyChangedSignal("Text"):Connect(function()
			if view ~= current then return end
			local typed = current.Box.Text
			if string.find(typed, "\t", 1, true) then
				current.Box.Text = string.gsub(typed, "\t", "") -- Tab sert à compléter, il n'est jamais inséré
				return
			end
			refreshSuggestions()
		end)
		view.Box.Focused:Connect(function()
			if view == current then refreshSuggestions() end
		end)
		-- l'historique déjà écrit (après une reconstruction) puis un mot d'accueil
		for _, entry in persistent.History do render(entry) end
		if #persistent.History == 0 then push("info", msg("Sentinel.Welcome")) end
		applyRetraction(false)
		place(false)
		scrollToEnd()
		-- panneau reconstruit (grade ou langue changés) pendant que le catalogue était ouvert : il se rouvre, verrous à jour
		if persistent.CatalogOpen and type(api.Server) == "table" and type(api.Server.Commands) == "table" then
			view.Catalog.Show(api.Server.Commands, catalogIntro(api.Server.Commands))
		end
		task.delay(1.2, waveNow)
	end

	--[[
		SOURCE DE VÉRITÉ UNIQUE de ce que voit CE compte. Deux niveaux distincts :
		  GlobalEnabled : Sentinel est actif pour tout le serveur (réglage administratif décidé et validé par le serveur : api.Server, relu par Refresh) ;
		  Personal      : ce compte choisit d'afficher ou non l'interface (préférence personnelle ; ne touche ni au serveur ni à Sentinel Guard).
		Accueil et Sentinel Helper lisent TOUS DEUX cet état et se redessinent sur api.Ready : aucun ne garde de copie locale qui pourrait se périmer.
		Ni cette préférence ni ce que l'interface affiche n'accorde le moindre droit : le serveur revérifie tout à chaque commande.
	]]
	function api.State()
		local server = api.Server or {}
		local allowed = server.Allowed == true
		local global = allowed and server.Enabled == true
		local personal = Core.PersonalPreferences == nil or Core.PersonalPreferences.AssistantEnabled ~= false
		return { Allowed = allowed, GlobalEnabled = global, Personal = personal, Visible = global and personal and Core.HasPermission("Assistant.Use") }
	end

	-- Applique l'état COURANT (sans question au serveur) : montre ou cache l'interface puis prévient Accueil et Sentinel Helper. Un changement purement personnel (interrupteur) n'a pas
	-- besoin d'un aller-retour : le serveur n'est interrogé que par Refresh (et son débit est limité, une rafale de clics ne doit pas le saturer).
	function api.Apply()
		if not alive() then return end
		if api.State().Visible then api.Show() else api.Hide() end
		ready:Fire()
	end

	-- Relit l'état serveur (droits, activation globale, réglages) puis montre ou cache Sentinel
	function api.Refresh()
		if not alive() then return end
		local ok, state = pcall(function() return Core.R.GetAssistant:InvokeServer() end)
		if not alive() then return end
		if ok and type(state) == "table" then api.Server = state else api.Server = { Allowed = false } end
		-- index de l'autocomplétion : reconstruit à chaque lecture de l'état (droits, réglages), jamais à la frappe
		api.Index = Suggest.Build(api.Server)
		if api.State().Visible then api.Show() else api.Hide() end
		-- les droits ont peut-être changé : un catalogue ouvert redessine ses cadenas d'après le serveur
		if view and view.Catalog.IsOpen() and type(api.Server.Commands) == "table" then view.Catalog.Update(api.Server.Commands, catalogIntro(api.Server.Commands)) end
		ready:Fire()
	end

	-- Interrupteur personnel (accueil de l'APM) : active ou désactive Sentinel pour CE compte, sans toucher à l'APM
	function api.SetEnabled(value, callback)
		Core.PersonalPreferences = Core.PersonalPreferences or {}
		Core.PersonalPreferences.AssistantEnabled = value == true
		api.Apply()
		task.spawn(function()
			local ok, accepted = pcall(function() return Core.R.SetPreferences:InvokeServer({ AssistantEnabled = value == true }) end)
			if callback and alive() then callback(ok and accepted == true) end
		end)
	end

	api.Core = Core
	Core.Assistant = api
	Core.On(Core.R.AssistantChanged.OnClientEvent, function() task.defer(api.Refresh) end)
	-- rappel des commandes envoyées (flèches haut / bas dans le champ de saisie)
	Core.On(UserInputService.InputBegan, function(input)
		if not view or not view.Box:IsFocused() then return end
		-- liste de suggestions ouverte : flèches = parcourir, Tab = compléter, Échap = fermer (le rappel de l'historique reprend quand la liste est fermée)
		local selection = view.Suggest
		if selection and view.Popup.IsVisible() then
			if input.KeyCode == Enum.KeyCode.Down and moveSelection(1) then return end
			if input.KeyCode == Enum.KeyCode.Up and moveSelection(-1) then return end
			if input.KeyCode == Enum.KeyCode.Tab and #selection.Result.Items > 0 then
				acceptSuggestion(selection.Selected or 1)
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape then
				hideSuggestions()
				return
			end
		end
		local sent = persistent.Sent
		if input.KeyCode == Enum.KeyCode.Up and #sent > 0 then
			view.SentIndex = math.max(1, view.SentIndex - 1)
		elseif input.KeyCode == Enum.KeyCode.Down and #sent > 0 then
			view.SentIndex = math.min(#sent + 1, view.SentIndex + 1)
		else
			return
		end
		view.Box.Text = sent[view.SentIndex] or ""
		view.Box.CursorPosition = #view.Box.Text + 1
	end)

	-- une seule boucle d'animation par construction du panneau : une onde toutes les `WaveInterval` secondes (30 par défaut)
	task.spawn(function()
		while alive() do
			task.wait(math.clamp(tonumber(config().WaveInterval) or 30, 10, 120))
			if alive() then waveNow() end
		end
	end)

	task.spawn(api.Refresh)
	return api
end

----------------------------------------------------------------------------------------------------------
-- Accueil de l'APM : l'interrupteur de Sentinel (visible seulement pour qui peut l'utiliser)

function Assistant.BuildHomeRow(Core, parent, order)
	local UI, T = Core.UI, Core.T
	local mine = Core.Session
	local api = Core.Assistant
	if not api or not Core.HasPermission("Assistant.Use") then return nil end
	local function text(key) return Core.Text(key) end
	local row = UI.new("Frame", { Name = "SentinelAssistantRow", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
	UI.list(row, 4)
	local line = UI.new("Frame", { Name = "Line", Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 1 }, row)
	UI.label({ Size = UDim2.new(1, -60, 1, 0), TextSize = 12, Text = text("Sentinel.Home.Title"), TextTruncate = Enum.TextTruncate.AtEnd }, line)
	local status = UI.label({ Name = "SentinelStatus", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.sub,
		LayoutOrder = 2, Text = "" }, row)
	local toggle
	local function render()
		if not Core.Alive(mine) or not row.Parent then return end
		local state = api.State()
		toggle.Set(state.Personal)
		toggle.Frame.Interactable = state.GlobalEnabled
		if state.Allowed and not state.GlobalEnabled then
			status.Text = text("Sentinel.Home.GloballyOff")
		elseif state.Personal then
			status.Text = text("Sentinel.Home.On")
		else
			status.Text = text("Sentinel.Home.Off")
		end
	end
	toggle = UI.Switch(line, true, function(value)
		status.Text = text("Common.Loading")
		api.SetEnabled(value, function(saved)
			if not Core.Alive(mine) or not row.Parent then return end
			render()
			if not saved then status.Text = text("Sentinel.Home.NotSaved") end
		end)
	end, UDim2.new(1, -46, 0, 2))
	toggle.Frame.Name = "SentinelEnabled"
	Core.On(api.Ready, render)
	render()
	return row
end

return Assistant
