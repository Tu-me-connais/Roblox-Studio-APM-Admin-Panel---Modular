-- Private session only: opening controls, collision-aware placement and personal preferences.
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Root = script.Parent
local Launcher = {}
local allowed = { Home = true, End = true, Insert = true, Delete = true, PageUp = true, PageDown = true }
for byte = 65, 90 do allowed[string.char(byte)] = true end
for _, name in { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" } do allowed[name] = true end
for index = 1, 12 do allowed["F" .. index] = true end
function Launcher.ValidKey(name)
	return type(name) == "string" and allowed[name] == true
end
function Launcher.Defaults(config, prefs)
	prefs = type(prefs) == "table" and prefs or {}
	local default = config.OpenKey and config.OpenKey.Name or "F2"
	if not Launcher.ValidKey(default) then default = "F2" end
	local visible = prefs.LauncherVisible
	if type(visible) ~= "boolean" then visible = config.LauncherButton ~= false end
	return { LauncherVisible = visible, OpenKey = Launcher.ValidKey(prefs.OpenKey) and prefs.OpenKey or default }
end
local function rect(position, size)
	return { X = position.X, Y = position.Y, W = size.X, H = size.Y }
end
local function overlaps(a, b, pad)
	return b.W > 0 and b.H > 0 and a.X < b.X + b.W + pad and a.X + a.W > b.X - pad and a.Y < b.Y + b.H + pad and a.Y + a.H > b.Y - pad
end
local function intersect(a, b)
	local x, y = math.max(a.X, b.X), math.max(a.Y, b.Y)
	return { X = x, Y = y, W = math.max(0, math.min(a.X + a.W, b.X + b.W) - x), H = math.max(0, math.min(a.Y + a.H, b.Y + b.H) - y) }
end
local referencePoints = {
	{ "TopCenter", .5, 0 }, { "TopRightQuarter", .75, 0 }, { "TopLeftQuarter", .25, 0 }, { "TopRight", 1, 0 }, { "TopLeft", 0, 0 },
	{ "RightUpper", 1, .25 }, { "RightMiddle", 1, .5 }, { "RightLower", 1, .75 },
	{ "BottomRight", 1, 1 }, { "BottomRightQuarter", .75, 1 }, { "BottomCenter", .5, 1 }, { "BottomLeftQuarter", .25, 1 }, { "BottomLeft", 0, 1 },
	{ "LeftLower", 0, .75 }, { "LeftMiddle", 0, .5 }, { "LeftUpper", 0, .25 },
}
function Launcher.ReferencePoints(bounds, width, height)
	local left, top = bounds.X + 8, bounds.Y + 8
	local right, bottom = bounds.X + bounds.W - width - 8, bounds.Y + bounds.H - height - 8
	if right < left or bottom < top then return {} end
	local points = {}
	for _, point in referencePoints do
		table.insert(points, { Reference = point[1], X = left + (right - left) * point[2], Y = top + (bottom - top) * point[3], W = width, H = height })
	end
	return points
end
function Launcher.FindPlacement(bounds, width, height, obstacles, current)
	local points = Launcher.ReferencePoints(bounds, width, height)
	if #points == 0 then return nil end -- Wait for a usable viewport before showing the button.
	local available = {}
	-- Check every reference on each pass, even when the current reference remains free.
	for _, point in points do
		local free = true
		for _, obstacle in obstacles do
			if overlaps(point, obstacle, 6) then
				free = false
				break
			end
		end
		if free then table.insert(available, point) end
	end
	local selected = available[1]
	if current and not current.Forced then
		for _, point in available do
			if point.Reference == current.Reference then
				selected = point
				if point.X == current.X and point.Y == current.Y then selected = current end
				break
			end
		end
	end
	if not selected then
		selected = { Reference = "FallbackBottomLeft", X = bounds.X + 8, Y = bounds.Y + bounds.H - height - 8, W = width, H = height, Forced = true }
	end
	selected.CheckedPoints = #points
	selected.AvailablePoints = #available
	return selected
end
function Launcher.OverlayOrder(highest)
	return math.min(2147483647, math.max(79, highest) + 1)
end
-- Transparent layout containers are not obstacles; rendered or interactive objects are.
function Launcher.Obstacle(object, playerGui, excluded)
	if not object:IsA("GuiObject") or not object.Visible or object.AbsoluteSize.X <= 0 or object.AbsoluteSize.Y <= 0 then return nil end
	local visible = object.BackgroundTransparency < .95 or object.Active == true
	if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then visible = visible or object.Text ~= "" and object.TextTransparency < .95 end
	if object:IsA("ImageLabel") or object:IsA("ImageButton") then visible = visible or object.Image ~= "" and object.ImageTransparency < .95 end
	if object:IsA("ViewportFrame") then visible = visible or #object:GetChildren() > 0 end
	if not visible then return nil end
	if object:IsA("CanvasGroup") and object.GroupTransparency >= .95 then return nil end
	local result = rect(object.AbsolutePosition, object.AbsoluteSize)
	local rotation = math.rad(object.AbsoluteRotation)
	local width = math.abs(math.cos(rotation)) * result.W + math.abs(math.sin(rotation)) * result.H
	local height = math.abs(math.sin(rotation)) * result.W + math.abs(math.cos(rotation)) * result.H
	result = { X = result.X + (result.W - width) / 2, Y = result.Y + (result.H - height) / 2, W = width, H = height }
	local ancestor = object.Parent
	local screen = false
	while ancestor and ancestor ~= playerGui do
		if excluded and excluded[ancestor] then return nil end
		if ancestor:IsA("ScreenGui") then
			if not ancestor.Enabled then return nil end
			screen = true
		elseif ancestor:IsA("GuiObject") then
			if not ancestor.Visible or ancestor:IsA("CanvasGroup") and ancestor.GroupTransparency >= .95 then return nil end
			if ancestor.ClipsDescendants then result = intersect(result, rect(ancestor.AbsolutePosition, ancestor.AbsoluteSize)) end
		end
		ancestor = ancestor.Parent
	end
	if ancestor ~= playerGui or not screen or result.W <= 0 or result.H <= 0 then return nil end
	return result
end
function Launcher.Create(Core, mainGui)
	local UI, T, mine = Core.UI, Core.T, Core.Session
	local playerGui = Core.Player:FindFirstChildOfClass("PlayerGui")
	local holder = Core.TrackGui(UI.new("ScreenGui", { Name = "APM_Launcher", ResetOnSpawn = false, DisplayOrder = 79,
		IgnoreGuiInset = false, ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, SafeAreaCompatibility = Enum.SafeAreaCompatibility.None, ClipToDeviceSafeArea = true }, playerGui))
	holder:SetAttribute("APMPrivateSession", Root.Parent:GetAttribute("SessionId"))
	local bounds = UI.new("Frame", { Name = "SafeBounds", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, holder)
	local button = UI.button({ Name = "OpenAPM", Size = UDim2.fromOffset(52, 26), Visible = false, Text = "APM", TextSize = 11, Corner = 8,
		BackgroundColor3 = T.panel, BackgroundTransparency = .25, Stroke = T.stroke }, bounds)
	local api = { Button = button, Gui = holder, Capturing = false, Busy = false }
	local current, objects, screens = nil, {}, {}
	local normalOrder, normalMainOrder = holder.DisplayOrder, mainGui.DisplayOrder
	local excluded = { [holder] = true, [mainGui] = true }
	local changed = Instance.new("BindableEvent")
	changed.Parent = holder
	api.Changed = changed.Event
	local function alive()
		return Core.Alive(mine) and holder.Parent ~= nil
	end
	local function overlayOrder()
		local highest = normalOrder
		for _, screen in screens do if screen.Parent and screen.Enabled then highest = math.max(highest, screen.DisplayOrder) end end
		return Launcher.OverlayOrder(highest)
	end
	function api.Refresh()
		if not alive() then return end
		button.Visible = false
		holder.DisplayOrder = normalOrder
		local touchFallback = not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled
		if not Core.HasPermission("APM.AccessPanel") or not (Core.OpenPreferences.LauncherVisible or touchFallback) or mainGui.Enabled or GuiService.MenuIsOpen then return end
		local obstacles = {}
		for _, object in objects do
			local item = Launcher.Obstacle(object, playerGui, excluded)
			if item then table.insert(obstacles, item) end
		end
		local area = rect(bounds.AbsolutePosition, bounds.AbsoluteSize)
		current = Launcher.FindPlacement(area, 52, 26, obstacles, current)
		if not current then return end
		if current.Forced then
			holder.DisplayOrder = overlayOrder()
		end
		holder:SetAttribute("CheckedPoints", current.CheckedPoints)
		holder:SetAttribute("AvailablePoints", current.AvailablePoints)
		holder:SetAttribute("ReferencePoint", current.Reference)
		holder:SetAttribute("ForcedOverlay", current.Forced == true)
		button.Position = UDim2.fromOffset(current.X - area.X, current.Y - area.Y)
		button.Visible = true
	end
	function api.Apply(patch, callback)
		if not alive() or api.Busy then return false end
		api.Busy = true
		changed:Fire()
		task.spawn(function()
			local ok, accepted = pcall(function()
				return Core.R.SetPreferences:InvokeServer(patch)
			end)
			if ok and accepted == true and Core.HasPermission("APM.AccessPanel") then for name, value in patch do Core.OpenPreferences[name] = value end end
			if not alive() then return end
			api.Busy = false
			api.Refresh()
			changed:Fire()
			if callback then callback(ok and accepted == true) end
		end)
		return true
	end
	Core.On(button.Activated, function()
		if Core.SetOpen and alive() then
			Core.SetOpen(true) -- l'ordre d'affichage du panneau est réglé par front() à l'ouverture
		end
	end)
	-- Contrôle adaptatif : 0,35 s tant que l'écran bouge (interfaces ajoutées / retirées, bouton déplacé), 1 s une fois stable.
	local lastActivity, queued = os.clock(), false
	local function activity()
		lastActivity = os.clock()
		if queued then return end
		queued = true
		task.delay(.35, function()
			queued = false
			api.Refresh()
		end)
	end
	-- Panneau ouvert : toujours devant les interfaces du jeu (juste au-dessus de la plus haute), recalculé dès qu'une
	-- interface apparaît, disparaît, s'active ou change d'ordre. Les ScreenGui « APM_ » ne comptent pas : les annonces
	-- (APM_Notices) se placent elles-mêmes un cran au-dessus du panneau.
	local function front()
		if not mainGui.Enabled then
			if mainGui.DisplayOrder ~= normalMainOrder then mainGui.DisplayOrder = normalMainOrder end
			return
		end
		local order = normalMainOrder
		for _, screen in screens do
			if screen.Parent and screen.Enabled and string.sub(screen.Name, 1, 4) ~= "APM_" then
				order = math.max(order, math.min(2147483646, screen.DisplayOrder + 1))
			end
		end
		-- Keep the panel usable when it is opened through the forced overlay.
		if current and current.Forced then order = math.max(order, overlayOrder()) end
		if mainGui.DisplayOrder ~= order then mainGui.DisplayOrder = order end
	end
	local function collect(object)
		if object:IsA("GuiObject") and not object:IsDescendantOf(holder) and not object:IsDescendantOf(mainGui) then table.insert(objects, object) activity()
		elseif object:IsA("ScreenGui") and not excluded[object] then
			table.insert(screens, object)
			Core.On(object:GetPropertyChangedSignal("DisplayOrder"), front)
			Core.On(object:GetPropertyChangedSignal("Enabled"), front)
			front()
			activity()
		end
	end
	Core.On(playerGui.DescendantAdded, collect)
	Core.On(playerGui.DescendantRemoving, function(object)
		local list = object:IsA("ScreenGui") and screens or objects
		local index = table.find(list, object)
		if index then
			table.remove(list, index)
			if list == screens then task.defer(front) end
			activity()
		end
	end)
	Core.On(bounds:GetPropertyChangedSignal("AbsoluteSize"), api.Refresh)
	Core.On(mainGui:GetPropertyChangedSignal("Enabled"), function()
		front()
		api.Refresh()
	end)
	Core.On(GuiService:GetPropertyChangedSignal("MenuIsOpen"), api.Refresh)
	for _, object in playerGui:GetDescendants() do collect(object) end
	api.Refresh() -- Resolve collisions before first visibility.
	task.spawn(function()
		while alive() do
			task.wait(os.clock() - lastActivity < 3 and .35 or 1)
			local before = current
			api.Refresh()
			local after = current
			if (before == nil) ~= (after == nil) or before and after and (before.X ~= after.X or before.Y ~= after.Y or before.Forced ~= after.Forced) then
				lastActivity = os.clock()
			end
		end
	end)
	return api
end
function Launcher.BuildSettings(Core, parent, order)
	local UI, T, api, mine = Core.UI, Core.T, Core.Launcher, Core.Session
	local function text(fr, en)
		return Core.Text({ fr = fr, en = en })
	end
	local function alive()
		return Core.Alive(mine) and parent.Parent ~= nil
	end
	local card = UI.card(parent, order)
	card.Name = "OpeningSettings"
	UI.sectionHeader(text("OUVERTURE DU PANNEAU", "OPENING THE PANEL"), T.accent, card, 1)
	local row = UI.new("Frame", { Name = "LauncherRow", Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 2 }, card)
	UI.label({ Size = UDim2.new(1, -60, 1, 0), Text = text("Afficher le bouton discret", "Show the discreet button"), TextSize = 12 }, row)
	local status = UI.label({ Name = "OpeningStatus", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11,
		TextColor3 = T.sub, LayoutOrder = 5, Text = "" }, card)
	local toggle
	local keyButton = UI.button({ Name = "ChangeOpenKey", Size = UDim2.new(1, 0, 0, 32), TextSize = 12, LayoutOrder = 3 }, card)
	local reset = UI.button({ Name = "ResetOpening", Size = UDim2.new(1, 0, 0, 30), Text = text("Rétablir le bouton et la touche par défaut", "Restore the button and default key"),
		TextSize = 11, LayoutOrder = 4 }, card)
	local function render()
		if not alive() then return end
		toggle.Set(Core.OpenPreferences.LauncherVisible)
		keyButton.Text = api.Capturing and text("Appuyez sur une touche · Échap pour annuler", "Press a key · Esc to cancel") or text("Touche : ", "Key: ") .. Core.OpenPreferences.OpenKey .. text(" · Modifier", " · Change")
		keyButton.Interactable = not api.Busy
		reset.Interactable = not api.Busy
		toggle.Frame.Interactable = not api.Busy
		if not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled and not Core.OpenPreferences.LauncherVisible then
			status.Text = text("Le bouton reste disponible sur cet appareil sans clavier ni manette.", "The button remains available on this device without a keyboard or controller.")
		end
	end
	local function save(patch)
		status.Text = text("Enregistrement…", "Saving…")
		if not api.Apply(patch, function(ok)
			if not alive() then return end
			status.Text = ok and (Core.MemoryMode and text("Préférence appliquée pour cette session Studio (mode mémoire).", "Preference applied for this Studio session (memory mode).") or text("Préférence appliquée. Le raccourci reste actif si le bouton est masqué.", "Preference applied. The shortcut remains available when the button is hidden.")) or text("Enregistrement refusé ou indisponible. Réessayez.", "Saving was denied or unavailable. Please retry.")
			render()
			end) then render() end
	end
	toggle = UI.Switch(row, Core.OpenPreferences.LauncherVisible, function(value)
		if not value and not UserInputService.KeyboardEnabled and not UserInputService.GamepadEnabled then
			status.Text = text("Gardez le bouton sur cet appareil : aucun clavier ni manette n'est connecté.", "Keep the button on this device: no keyboard or controller is connected.")
			render()
			return
		end
		save({ LauncherVisible = value })
		end, UDim2.new(1, -46, 0, 2))
	toggle.Frame.Name = "LauncherVisibility"
	Core.On(api.Changed, render)
	Core.On(keyButton.Activated, function()
		if not UserInputService.KeyboardEnabled then
			status.Text = text("Connectez un clavier pour choisir une touche.", "Connect a keyboard to choose a key.")
			return
		end
		api.Capturing = not api.Capturing
		status.Text = text("Lettres, chiffres, F1 à F12 ou touches de navigation. Aucune action pendant la saisie.", "Letters, numbers, F1–F12 or navigation keys. Shortcuts pause during capture.")
		render()
	end)
	Core.On(reset.Activated, function()
		api.Capturing = false
		save({ LauncherVisible = true, OpenKey = Launcher.Defaults(Core.Config).OpenKey })
	end)
	Core.On(UserInputService.InputBegan, function(input)
		if not api.Capturing or input.UserInputType ~= Enum.UserInputType.Keyboard or UserInputService:GetFocusedTextBox() then return end
		if input.KeyCode == Enum.KeyCode.Escape then
			api.Capturing = false
			api.SuppressUntil = os.clock() + .15
			render()
			return
		end
		if not Launcher.ValidKey(input.KeyCode.Name) then
			status.Text = text("Cette touche est réservée. Choisissez une lettre, un chiffre ou F1–F12.", "This key is reserved. Choose a letter, a number or F1–F12.")
			return
		end
		api.Capturing = false
		api.SuppressUntil = os.clock() + .15
		save({ OpenKey = input.KeyCode.Name })
	end)
	Core.On(Core.Gui:GetPropertyChangedSignal("Enabled"), function()
		if not Core.Gui.Enabled then
			api.Capturing = false
			render()
		end
	end)
	render()
	return card
end
return Launcher
