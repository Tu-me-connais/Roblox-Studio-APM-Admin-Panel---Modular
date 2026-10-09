--[[
	Moderation : onglet « Modération ». Annonce à tout le serveur, puis les outils personnels de l'admin :
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
	local announceCard = UI.card(scroll, 1)
	UI.sectionHeader(L("Moderation.Announce"), Color3.fromRGB(220, 170, 70), announceCard, 1)
	local announceBox = UI.input({ Size = UDim2.new(1, 0, 0, 32), PlaceholderText = L("Moderation.AnnounceHint"), TextSize = 13, LayoutOrder = 2 }, announceCard)
	local announceButton = UI.button({ Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(150, 115, 50), Text = L("Moderation.AnnounceSend"), TextSize = 13, LayoutOrder = 3 }, announceCard)
	announceButton.Activated:Connect(function()
		local text = announceBox.Text
		if string.gsub(text, "%s", "") == "" then
			Core.Toast(L("Moderation.WriteMessage"), false)
			return
		end
		R.Announce:FireServer(text)
		announceBox.Text = ""
	end)
	announceCard.Visible = Core.HasRankAtLeast(Core.AnnounceRank)

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
				TextSize = 13, TextColor3 = T.accent, Text = tostring(defaultOf(module)) }, row)
			local slider = UI.Slider(row, module.Min or 0, module.Max or 100, defaultOf(module), function(value)
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
			local switch = UI.Switch(row, Core.ToolState[module.Name] == true, function(state)
				if module.ClientSide then
					Core.ToolState[module.Name] = state or nil
					local ok, err = pcall(module.Set, state)
					if not ok then
						warn("[APM] Outil " .. module.Name .. " : " .. tostring(err))
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
	Core.On(Core.Player.CharacterAdded, function()
		task.wait(1)
		if not Core.Alive(mine) then return end
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
