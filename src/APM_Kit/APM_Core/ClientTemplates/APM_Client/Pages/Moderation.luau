--[[
	Moderation : onglet « Modération ». Annonce à tout le serveur, puis les outils personnels de l'admin.
	  - annonce : titre facultatif + message. Un seul admin rédige à la fois sur le serveur (verrou AnnounceDraft) : les autres
	    voient qui rédige et ne peuvent pas envoyer en même temps ; rien ne part tant qu'une annonce est à l'écran.
	    Réglages du style (APM.AnnounceStyle) : Components.AnnounceDesigner.
	  - outils SERVEUR (modules de catégorie « Moderation », Mode « toggle » ou « slider » : Invisible, Godmode, Vitesse, Saut...) :
	    le serveur les applique et les revalide ;
	  - outils CLIENT (dossier Tools : Fly, Noclip, ESP, Spectateur) : appliqués ici, déclarés dans la matrice d'accès du serveur.
	Ajouter un module (serveur ou client) l'ajoute automatiquement dans cet onglet.
]]
local Page = { Id = "Moderation", Order = 4, Label = "Tab.Moderation", Handles = { "Moderation" } }

function Page.Build(Core, page)
	local mine = Core.Session
	local UI, T, R, L = Core.UI, Core.T, Core.R, Core.L

	local scroll = UI.scroll({ Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)

	-- Annonce -----------------------------------------------------------------------------------------------------
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local AnnounceStyle = require(ReplicatedStorage:WaitForChild("APM_Shared"):WaitForChild("Announcements"))
	local GOLD = Color3.fromRGB(220, 170, 70)
	local canStyle = Core.HasPermission("APM.AnnounceStyle")
	local announceCard = UI.card(scroll, 1)
	local announceHeader = UI.sectionHeader(L("Moderation.Announce"), GOLD, announceCard, 1)
	local statusPill = UI.label({ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 0, BackgroundColor3 = T.panel, Font = T.fontBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = "", ZIndex = 2,
		Corner = 9 }, announceHeader)
	UI.padding(statusPill, 0, 9, 9)
	local titleBox = UI.input({ Size = UDim2.new(1, 0, 0, 30), PlaceholderText = L("Announce.TitleHint"), TextSize = 13, LayoutOrder = 2 }, announceCard)
	local messageBox = UI.input({ Size = UDim2.new(1, 0, 0, 66), PlaceholderText = L("Moderation.AnnounceHint"), TextSize = 13, LayoutOrder = 3, MultiLine = true,
		TextWrapped = true, TextTruncate = Enum.TextTruncate.None, TextYAlignment = Enum.TextYAlignment.Top }, announceCard)
	local messagePadding = messageBox:FindFirstChildOfClass("UIPadding")
	messagePadding.PaddingTop, messagePadding.PaddingBottom = UDim.new(0, 8), UDim.new(0, 18)
	local counter = UI.label({ Size = UDim2.fromOffset(70, 14), Position = UDim2.new(1, 0, 1, 14), AnchorPoint = Vector2.new(1, 1), TextSize = 10, TextColor3 = T.sub,
		TextXAlignment = Enum.TextXAlignment.Right, Text = "0/" .. AnnounceStyle.MaxMessage, ZIndex = 2 }, messageBox)
	local lockNote = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextColor3 = T.warn, TextWrapped = true, Text = "",
		Visible = false, LayoutOrder = 4 }, announceCard)
	local actions = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 5 }, announceCard)
	UI.list(actions, 8, true)
	local previewButton = UI.button({ Size = canStyle and UDim2.new(0.25, -4, 1, 0) or UDim2.new(0.3, -4, 1, 0), BackgroundColor3 = T.panel, Stroke = T.stroke,
		Text = L("Announce.Preview"), TextSize = 12, LayoutOrder = 1 }, actions)
	local settingsButton = UI.button({ Size = UDim2.new(0.25, -4, 1, 0), BackgroundColor3 = T.panel, Stroke = T.stroke, Text = L("Announce.Settings"), TextSize = 12,
		LayoutOrder = 2, Visible = canStyle }, actions)
	local sendButton = UI.button({ Size = canStyle and UDim2.new(0.5, -8, 1, 0) or UDim2.new(0.7, -4, 1, 0), BackgroundColor3 = Color3.fromRGB(150, 115, 50),
		Text = L("Moderation.AnnounceSend"), TextSize = 13, LayoutOrder = 3 }, actions)
	announceCard.Visible = Core.HasPermission("APM.Announce")
	settingsButton.Visible = canStyle
	if canStyle and not announceCard.Visible then
		-- réglages sans droit d'annoncer : seule la carte des réglages reste
		announceCard.Visible = true
		titleBox.Visible, messageBox.Visible, previewButton.Visible, sendButton.Visible, statusPill.Visible = false, false, false, false, false
		settingsButton.Size = UDim2.new(1, 0, 1, 0)
	end

	-- longueur maximale en caractères (pas en octets : accents et emoji comptent pour un)
	local function clip(box, max)
		local count = utf8.len(box.Text)
		if count and count > max then
			box.Text = string.sub(box.Text, 1, utf8.offset(box.Text, max + 1) - 1)
		end
		return math.min(count or #box.Text, max)
	end
	local function hasDraft()
		return string.find(messageBox.Text, "%S") ~= nil or string.find(titleBox.Text, "%S") ~= nil
	end
	local function focused()
		return messageBox:IsFocused() or titleBox:IsFocused()
	end

	-- État partagé par le serveur : qui rédige, annonce à l'écran
	local state = { Holder = nil, Mine = false, ShowingBy = nil, ShowingUntil = 0 }
	local function showingLeft()
		return math.max(0, math.ceil(state.ShowingUntil - os.clock()))
	end
	local function renderState()
		local left = showingLeft()
		local blocked = false
		if state.Holder and not state.Mine then
			statusPill.Text, statusPill.TextColor3 = L("Announce.StatusBusy", state.Holder), T.warn
			lockNote.Text = L("Announce.BusyNote", state.Holder)
			blocked = true
		elseif left > 0 then
			statusPill.Text, statusPill.TextColor3 = L("Announce.StatusShowing", left), GOLD
			lockNote.Text = L("Announce.ShowingNote", state.ShowingBy or "?", left)
			blocked = true
		elseif state.Mine then
			statusPill.Text, statusPill.TextColor3 = L("Announce.StatusMine"), T.accent
		else
			statusPill.Text, statusPill.TextColor3 = L("Announce.StatusFree"), T.good
		end
		lockNote.Visible = blocked and sendButton.Visible
		sendButton.BackgroundColor3 = blocked and T.panel or Color3.fromRGB(150, 115, 50)
		sendButton.TextColor3 = blocked and T.sub or T.text
		sendButton.AutoButtonColor = not blocked
	end
	local function applyState(data)
		if type(data) ~= "table" then return end
		state.Holder = type(data.Holder) == "string" and data.Holder or nil
		state.Mine = data.Mine == true
		state.ShowingBy = type(data.ShowingBy) == "string" and data.ShowingBy or nil
		state.ShowingUntil = os.clock() + (tonumber(data.ShowingLeft) or 0)
		renderState()
	end

	-- Verrou de rédaction : pris dès qu'on écrit, gardé vivant toutes les 5 s, rendu quand les champs sont vides,
	-- quand le panneau se ferme, ou après IDLE_RELEASE s sans toucher aux champs (brouillon oublié : il ne bloque pas les autres).
	local IDLE_RELEASE = 120
	local claiming, refusedAt, lastEdit = false, -math.huge, os.clock()
	local function draft(action)
		local ok, accepted, data = pcall(function()
			return R.AnnounceDraft:InvokeServer(action)
		end)
		if ok and Core.Alive(mine) then
			applyState(data)
		end
		return ok and accepted == true
	end
	local function claim()
		if claiming or state.Mine or not sendButton.Visible or os.clock() - refusedAt < 2 then return end
		claiming = true
		task.spawn(function()
			if not draft("claim") then refusedAt = os.clock() end
			claiming = false
		end)
	end
	local function release()
		if not state.Mine then return end
		state.Mine = false
		renderState()
		task.spawn(draft, "release")
	end
	local function onEdit()
		lastEdit = os.clock()
		counter.Text = clip(messageBox, AnnounceStyle.MaxMessage) .. "/" .. AnnounceStyle.MaxMessage
		clip(titleBox, AnnounceStyle.MaxTitle)
		if hasDraft() then claim() elseif not focused() then release() end
	end
	messageBox:GetPropertyChangedSignal("Text"):Connect(onEdit)
	titleBox:GetPropertyChangedSignal("Text"):Connect(onEdit)
	for _, box in { messageBox, titleBox } do
		box.Focused:Connect(function()
			lastEdit = os.clock()
			claim()
		end)
		box.FocusLost:Connect(function()
			task.delay(0.25, function() -- passage d'un champ à l'autre : on garde la main
				if Core.Alive(mine) and not hasDraft() and not focused() then release() end
			end)
		end)
	end
	Core.On(R.AnnounceState.OnClientEvent, applyState)
	task.spawn(function()
		local ok, data = pcall(function() return R.GetAnnounceState:InvokeServer() end)
		if ok and Core.Alive(mine) then applyState(data) end
	end)
	task.spawn(function()
		local tick = 0
		while Core.Alive(mine) do
			task.wait(1)
			tick += 1
			if not Core.Alive(mine) then break end
			if state.ShowingUntil > 0 and showingLeft() >= 0 then renderState() end
			if state.Mine then
				if not (Core.Gui and Core.Gui.Enabled) or os.clock() - lastEdit > IDLE_RELEASE then
					release()
				elseif tick % 5 == 0 and (hasDraft() or focused()) then
					-- signe de vie seulement si l'admin rédige vraiment ; sans lui, le serveur libère seul après 15 s
					task.spawn(draft, "ping")
				end
			end
		end
	end)
	-- panneau fermé : la main est rendue tout de suite (le brouillon reste dans les champs)
	if Core.Gui then
		Core.On(Core.Gui:GetPropertyChangedSignal("Enabled"), function()
			if not Core.Gui.Enabled then release() end
		end)
	end
	page.Destroying:Connect(function()
		if state.Mine then
			task.spawn(function() pcall(function() R.AnnounceDraft:InvokeServer("release") end) end)
		end
	end)

	local function sample()
		return { Title = titleBox.Text, Message = messageBox.Text }
	end
	-- Aperçu sur MON écran uniquement (rien n'est envoyé), au style actuel des joueurs
	local previewing = false
	previewButton.Activated:Connect(function()
		if previewing then return end
		previewing = true
		local publicFolder = ReplicatedStorage:FindFirstChild("APM_Public")
		local gui = Core.TrackGui(UI.new("ScreenGui", { Name = "APM_AnnouncePreview", ResetOnSpawn = false, IgnoreGuiInset = true,
			DisplayOrder = (Core.Gui and Core.Gui.DisplayOrder or 80) + 5 }, Core.Player:WaitForChild("PlayerGui")))
		local text = sample()
		task.spawn(function()
			pcall(function()
				local view = AnnounceStyle.Render(gui, AnnounceStyle.Decode(publicFolder and publicFolder:GetAttribute("AnnounceStyle")), {
					Title = string.find(text.Title, "%S") and text.Title or nil,
					Message = string.find(text.Message, "%S") and text.Message or L("Announce.SampleMessage"),
					Author = Core.Player.Name,
					Time = os.time(),
				}, { Translate = L })
				view.Play()
			end)
			if gui.Parent then gui:Destroy() end
			previewing = false
		end)
	end)
	settingsButton.Activated:Connect(function()
		require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("AnnounceDesigner")).Open(Core, sample)
	end)

	sendButton.Activated:Connect(function()
		local text = messageBox.Text
		if not string.find(text, "%S") then
			Core.Toast(L("Moderation.WriteMessage"), false)
			return
		end
		if state.Holder and not state.Mine then
			Core.Toast(L("Announce.BusyNote", state.Holder), false)
			return
		end
		if showingLeft() > 0 then
			Core.Toast(L("Announce.ShowingNote", state.ShowingBy or "?", showingLeft()), false)
			return
		end
		R.Announce:FireServer(text, titleBox.Text)
		messageBox.Text, titleBox.Text = "", ""
	end)
	renderState()

	-- Outils --------------------------------------------------------------------------------------------------------
	local rows = {} -- [nom] = ligne
	local sliders = {} -- [nom] = { object, module }
	local switches = {} -- [nom] = { object, module }

	local serverCard = UI.card(scroll, 2)
	UI.sectionHeader(L("Moderation.ServerTools"), Color3.fromRGB(88, 128, 232), serverCard, 1)
	local clientCard = UI.card(scroll, 3)
	UI.sectionHeader(L("Moderation.ClientTools"), Color3.fromRGB(80, 175, 110), clientCard, 1)

	local function defaultOf(module)
		return module.Default or module.Min or 0
	end
	-- valeur affichée à la construction : l'état réel renvoyé par le serveur (State), sinon la valeur par défaut
	local function currentOf(module)
		if type(module.State) == "number" then
			return math.clamp(module.State, module.Min or 0, module.Max or 100)
		end
		return defaultOf(module)
	end

	local function addRow(module, parentCard, order)
		local tall = module.Mode == "slider"
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, tall and 54 or 34), BackgroundTransparency = 1, LayoutOrder = order }, parentCard)
		local title = UI.label({ Size = UDim2.new(1, -60, 0, 18), Position = UDim2.fromOffset(0, tall and 0 or 8), Font = T.fontBold, TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = Core.Text(module.Label) }, row)
		if module.Description and not tall then
			title.Position = UDim2.fromOffset(0, 0)
			UI.label({ Size = UDim2.new(1, -60, 0, 14), Position = UDim2.fromOffset(0, 18), TextSize = 11, TextColor3 = T.sub, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = Core.Text(module.Description) }, row)
		end
		rows[module.Name] = row

		if module.Mode == "slider" then
			local valueLabel = UI.label({ Size = UDim2.fromOffset(60, 18), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right,
				TextSize = 13, TextColor3 = T.accent, Text = tostring(currentOf(module)) }, row)
			local slider = UI.Slider(row, module.Min or 0, module.Max or 100, currentOf(module), function(value)
				Core.Action(module.Name, nil, value)
			end, UDim2.new(1, -70, 0, 24), UDim2.fromOffset(0, 24))
			slider.Changed = function(value)
				valueLabel.Text = tostring(value)
			end
			local reset = UI.button({ Size = UDim2.fromOffset(60, 22), Position = UDim2.new(1, 0, 0, 25), AnchorPoint = Vector2.new(1, 0), Text = L("Common.Reset"), TextSize = 11 }, row)
			reset.Activated:Connect(function()
				slider.Set(defaultOf(module))
				valueLabel.Text = tostring(defaultOf(module))
				Core.Action(module.Name, nil, defaultOf(module))
			end)
			sliders[module.Name] = { object = slider, module = module }
		else
			local switch
			switch = UI.Switch(row, Core.ToolState[module.Name] == true or module.State == true, function(state)
				if module.ClientSide then
					local ok, result = pcall(module.Set, state)
					local applied = state and ok and result ~= false
					Core.ToolState[module.Name] = applied and true or nil
					switch.Set(applied)
					if not ok then
						warn("[APM] Outil " .. module.Name .. " : " .. tostring(result))
					elseif state and result == false then
						Core.Toast(Core.Text({ fr = "Outil indisponible : réessaie quand le personnage est prêt.", en = "Tool unavailable: retry when the character is ready." }), false)
					end
				else
					Core.Action(module.Name, nil, state)
				end
			end, UDim2.new(1, -46, 0, 5))
			switches[module.Name] = { object = switch, module = module }
		end
	end

	local serverOrder, clientOrder = 1, 1
	for _, module in Core.AllModules() do
		if module.Category == "Moderation" and (module.Mode == "toggle" or module.Mode == "slider") then
			if module.ClientSide then
				clientOrder += 1
				addRow(module, clientCard, clientOrder)
			else
				serverOrder += 1
				addRow(module, serverCard, serverOrder)
			end
		end
	end

	local function refreshAccess()
		local anyServer, anyClient = false, false
		for name, row in rows do
			local allowed = Core.CanUse(name)
			row.Visible = allowed
			if allowed then
				local entry = switches[name]
				if entry and entry.module.ClientSide then entry.object.Set(Core.ToolState[name] == true) end
				if row.Parent == serverCard then
					anyServer = true
				else
					anyClient = true
				end
			else
				-- accès retiré : on coupe l'outil client s'il tournait
				local entry = switches[name]
				if entry and entry.module.ClientSide and entry.object.Get() then
					entry.object.Set(false)
					Core.ToolState[name] = nil
					pcall(entry.module.Set, false)
				end
			end
		end
		serverCard.Visible = anyServer
		clientCard.Visible = anyClient
		Core.SetTabVisible("Moderation", anyServer or anyClient or announceCard.Visible)
	end
	refreshAccess()
	Core.On(Core.AccessChanged.Event, refreshAccess)

	-- à chaque réapparition : Roblox remet vitesse / saut par défaut, on réapplique ce que l'admin avait réglé
	Core.On(Core.Player.CharacterAdded, function(character)
		local humanoid = character:WaitForChild("Humanoid", 10)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if not Core.Alive(mine) or Core.Player.Character ~= character or not humanoid or not root then return end
		task.wait(1)
		if not Core.Alive(mine) or Core.Player.Character ~= character then return end
		for name, entry in sliders do
			local value = entry.object.Get()
			if value ~= defaultOf(entry.module) and Core.CanUse(name) then
				Core.Action(name, nil, value)
			end
		end
		for _, entry in switches do
			if Core.CanUse(entry.module.Name) and entry.module.ClientSide and entry.object.Get() and type(entry.module.Refresh) == "function" then
				pcall(entry.module.Refresh)
			end
		end
	end)
end

return Page
