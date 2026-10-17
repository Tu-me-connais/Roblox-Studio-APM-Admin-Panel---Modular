--[[
	Settings : onglet « Paramètres » (permission APM.ManagePermissions ; le serveur revérifie chaque changement).
	  - SERVEUR : verrouillage du serveur (permission APM.ServerLock) ;
	  - GRADES : qui a quel grade ; donner / retirer un grade par pseudo ou UserId (grades inférieurs au sien) ;
	  - FONCTIONNALITÉS : tout l'APM rangé par catégorie (catalogue envoyé par le serveur, module Features) :
	      « Actif »             allume / coupe une fonctionnalité pour tout le jeu (grade le plus haut et propriétaire du jeu) ;
	      une colonne par grade  qui peut s'en servir ;
	      ligne d'une catégorie  coche / décoche toute la catégorie d'un coup ; « Tout l'APM » fait de même pour tout.
	    Orange : catégorie mélangée. Grisé : hors de ta portée. Un clic sur le titre d'une catégorie la déplie ou la replie.
]]
local Page = { Id = "Settings", Order = 7, Label = "Tab.Settings" }

-- Gardés d'une reconstruction à l'autre (le panneau se reconstruit après chaque changement de droits)
local expanded = {} -- [catégorie] = true : dépliée
local memory = { Search = "", Scroll = nil }

local CHUNK = 40 -- noms par appel groupé (limite de taille des arguments de la session privée)

function Page.Visible(Core)
	return Core.HasPermission("APM.ManagePermissions")
end

function Page.Build(Core, page)
	local UI, T, R, L = Core.UI, Core.T, Core.R, Core.L
	local myLevel = Core.RankLevel(Core.MyRank)
	local isSuper = Core.IsSuper()
	local function tr(fr, en, es, pt, de)
		return Core.Text({ fr = fr, en = en, es = es, pt = pt, de = de })
	end

	local scroll = UI.scroll({ Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)

	local function call(remote, ...)
		local args = table.pack(...)
		local ok, success, message, extra = pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not ok then
			return false, L("Common.ServerError")
		end
		return success, message, extra
	end

	local function resolve(text)
		text = string.match(text, "^%s*(.-)%s*$")
		if text == "" then
			return nil
		end
		if string.match(text, "^%-?%d+$") then
			return tonumber(text)
		end
		local ok, result = pcall(function()
			return R.GlobalSearch:InvokeServer(text)
		end)
		if ok and type(result) == "table" and result[1] then
			return result[1].userId
		end
		return nil
	end

	-- Serveur -------------------------------------------------------------------------------------------------------
	local serverCard = UI.card(scroll, 1)
	serverCard.Visible = Core.HasPermission("APM.ServerLock")
	UI.sectionHeader(L("Settings.Server"), Color3.fromRGB(205, 95, 95), serverCard, 1)
	local lockRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 2 }, serverCard)
	UI.label({ Size = UDim2.new(1, -60, 1, 0), TextSize = 13, TextWrapped = true, Text = L("Settings.Lock") }, lockRow)
	local lockSwitch
	lockSwitch = UI.Switch(lockRow, false, function(state)
		local success, message = call(R.SetServerLock, state)
		Core.Toast(message or "", success == true)
		if not success then
			lockSwitch.Set(not state)
		end
		end, UDim2.new(1, -46, 0, 4))
	task.spawn(function()
		local ok, locked = pcall(function()
			return R.GetServerLock:InvokeServer()
		end)
		if ok and lockRow.Parent then
			lockSwitch.Set(locked == true)
		end
	end)

	-- Grades ---------------------------------------------------------------------------------------------------------
	local gradesCard = UI.card(scroll, 2)
	UI.sectionHeader(L("Settings.Ranks"), Color3.fromRGB(220, 170, 70), gradesCard, 1)
	local staffHolder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, gradesCard)
	UI.list(staffHolder, 4)

	-- grades qu'on peut donner : non fixes, inférieurs au sien (le SuperRank peut tous les donner)
	local assignable = {}
	for _, rank in Core.RankList do
		if not rank.Fixed and (isSuper or rank.Level < myLevel) then
			table.insert(assignable, { rank.Id, Core.RankName(rank.Id) })
		end
	end

	local addRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 3, Visible = #assignable > 0 }, gradesCard)
	local accountBox = UI.input({ Size = UDim2.new(1, -276, 1, 0), PlaceholderText = L("Settings.AccountHint"), TextSize = 13 }, addRow)
	local rankPicker = UI.picker(addRow, assignable, assignable[#assignable] and assignable[#assignable][1] or nil, UDim2.fromOffset(130, 32), UDim2.new(1, -270, 0, 0))
	local assignButton = UI.button({ Size = UDim2.fromOffset(132, 32), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), BackgroundColor3 = T.accent,
		Text = L("Settings.Assign"), TextSize = 12 }, addRow)
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextColor3 = T.sub, TextWrapped = true, LayoutOrder = 4,
		Text = L("Settings.RanksHint") }, gradesCard)

	local function sourceNames(sources)
		local labels = {
			Users = tr("Configuration fixe", "Fixed configuration"),
			Creator = tr("Propriétaire du jeu", "Game owner"),
			Panel = tr("Attribution du panneau", "Panel assignment"),
			DefaultUsers = tr("Configuration de départ", "Starting configuration"),
			Group = tr("Groupe Roblox", "Roblox group"),
			Studio = tr("Test Studio", "Studio test"),
			OwnerOverride = tr("Attribution du propriétaire", "Owner override"),
		}
		local names = {}
		for _, source in type(sources) == "table" and sources or {} do table.insert(names, labels[source] or source) end
		return table.concat(names, " + ")
	end

	local staffRows = {}
	local refreshing = false
	local function refreshStaff()
		if refreshing then
			return
		end
		refreshing = true
		task.spawn(function()
			local ok, list = pcall(function()
				return R.GetStaff:InvokeServer()
			end)
			refreshing = false
			if not ok or type(list) ~= "table" or not staffHolder.Parent then
				return
			end
			for _, row in staffRows do
				row:Destroy()
			end
			table.clear(staffRows)
			for index, entry in list do
				local removable, revocable = entry.canRemove == true, entry.canRevoke == true
				local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, (removable or revocable) and 88 or 52), BackgroundColor3 = T.panel, LayoutOrder = index, Corner = 8 }, staffHolder)
				table.insert(staffRows, row)
				UI.new("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(10, 11), BackgroundColor3 = entry.online and T.good or T.sub, Corner = 4 }, row)
				UI.label({ Size = UDim2.new(1, -154, 0, 24), Position = UDim2.fromOffset(26, 2), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
					Text = ("%s  (%s)%s"):format(tostring(entry.name), tostring(entry.userId), entry.fixed and ("  ·  " .. L("Settings.Fixed")) or "") }, row)
				UI.label({ Size = UDim2.fromOffset(110, 20), Position = UDim2.new(1, -10, 0, 4), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 0,
					BackgroundColor3 = Core.RankColor(entry.rank), Font = T.fontBold, TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd, Text = Core.RankName(entry.rank), Corner = 10 }, row)
				local source = tr("Source : ", "Source: ") .. sourceNames(entry.sources)
				if entry.panelRank and entry.panelRank ~= entry.rank then
					source ..= tr(" · Attribution du panneau : ", " · Panel assignment: ") .. Core.RankName(entry.panelRank)
				end
				UI.label({ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 27), TextSize = 11, TextColor3 = T.sub,
					TextTruncate = Enum.TextTruncate.AtEnd, Text = source }, row)
				if removable then
					local after = entry.remainingRank and Core.RankName(entry.remainingRank) or tr("aucun accès", "no access")
					local remainingSources = sourceNames(entry.remainingSources)
					if remainingSources ~= "" then after ..= " (" .. remainingSources .. ")" end
					UI.label({ Size = UDim2.new(1, revocable and -284 or -180, 0, 32), Position = UDim2.fromOffset(10, 49), TextSize = 11,
						TextColor3 = T.sub, TextWrapped = true, Text = tr("Après retrait : ", "After removal: ") .. after }, row)
					local remove = UI.button({ Size = UDim2.fromOffset(160, 30), Position = UDim2.new(1, revocable and -114 or -10, 0, 50), AnchorPoint = Vector2.new(1, 0),
						BackgroundColor3 = Color3.fromRGB(110, 50, 50), Text = tr("Retirer l'attribution", "Remove assignment"), TextSize = 11 }, row)
					UI.Confirmable(remove, true, function()
						task.spawn(function()
							local success, message = call(R.SetRank, entry.userId, "")
							Core.Toast(message or "", success == true)
							refreshStaff()
						end)
					end)
				elseif revocable then
					UI.label({ Size = UDim2.new(1, -124, 0, 32), Position = UDim2.fromOffset(10, 49), TextSize = 11, TextColor3 = T.sub, TextWrapped = true,
						Text = tr("La révocation retire aussi les accès fixes ou de groupe.", "Revoking also removes fixed or group access.") }, row)
				end
				if revocable then
					local revoke = UI.button({ Size = UDim2.fromOffset(94, 30), Position = UDim2.new(1, -10, 0, 50), AnchorPoint = Vector2.new(1, 0),
						BackgroundColor3 = Color3.fromRGB(110, 50, 50), Text = tr("Révoquer l'accès", "Revoke access"), TextSize = 11 }, row)
					UI.Confirmable(revoke, true, function()
						task.spawn(function()
							local success, message = call(R.SetOwnerAccessOverride, entry.userId, "None")
							Core.Toast(message or "", success == true)
							refreshStaff()
						end)
					end)
				end
			end
		end)
	end

	assignButton.Activated:Connect(function()
		local text, rank = accountBox.Text, rankPicker.Get()
		task.spawn(function()
			local userId = resolve(text)
			if not userId then
				Core.Toast(L("Common.AccountNotFound"), false)
				return
			end
			local success, message = call(R.SetRank, userId, rank)
			Core.Toast(message or "", success == true)
			if success then
				accountBox.Text = ""
				refreshStaff()
			end
		end)
	end)

	-- Fonctionnalités, par catégorie ---------------------------------------------------------------------------------
	local featureCard = UI.card(scroll, 3)
	UI.sectionHeader(tr("FONCTIONNALITÉS ET ACCÈS, PAR CATÉGORIE", "FEATURES AND ACCESS, BY CATEGORY", "FUNCIONES Y ACCESO, POR CATEGORÍA",
		"FUNÇÕES E ACESSO, POR CATEGORIA", "FUNKTIONEN UND ZUGRIFF, NACH KATEGORIE"), Color3.fromRGB(88, 128, 232), featureCard, 1)
	local superName = Core.RankName(Core.SuperRank)
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextColor3 = T.sub, TextWrapped = true, LayoutOrder = 2,
		Text = tr(
			"Tout l'APM, rangé par catégorie. « Actif » allume ou coupe une fonctionnalité pour tout le jeu (%s et propriétaire du jeu). Les colonnes de grade règlent qui peut s'en servir. La ligne d'une catégorie coche ou décoche toute la catégorie d'un coup ; « Tout l'APM » fait de même pour toutes. Orange : mélangé. Grisé : hors de ta portée. L'accès au panneau et aux Paramètres ne se retire jamais en groupe.",
			"All of APM, by category. \"Active\" switches a feature on or off for the whole game (%s and the game owner). Rank columns set who can use it. A category row checks or unchecks the whole category at once; \"All of APM\" does the same for every category. Orange: mixed. Greyed: out of your reach. Panel and Settings access are never removed in bulk."):format(superName) }, featureCard)

	local toolbar = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 }, featureCard)
	local searchBox = UI.input({ Size = UDim2.new(1, -232, 1, 0), PlaceholderText = L("Common.Search"), TextSize = 13, Text = memory.Search }, toolbar)
	local expandAll = UI.button({ Size = UDim2.fromOffset(110, 30), Position = UDim2.new(1, -116, 0, 0), AnchorPoint = Vector2.new(1, 0), TextSize = 12,
		BackgroundColor3 = T.panel, Stroke = T.stroke,
		Text = tr("Tout déplier", "Expand all", "Desplegar todo", "Expandir tudo", "Alle öffnen") }, toolbar)
	local collapseAll = UI.button({ Size = UDim2.fromOffset(110, 30), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), TextSize = 12,
		BackgroundColor3 = T.panel, Stroke = T.stroke,
		Text = tr("Tout replier", "Collapse all", "Plegar todo", "Recolher tudo", "Alle schließen") }, toolbar)
	local defaultInfo = tr("Survole une ligne pour voir son nom technique et sa description.", "Hover a row to see its technical name and description.")
	local info = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextColor3 = T.sub, TextWrapped = true,
		LayoutOrder = 4,
		Text = defaultInfo }, featureCard)

	-- colonnes : « Actif », puis un grade par colonne (du plus haut au plus bas)
	local columns = { { Id = "*", Global = true, Label = L("Settings.Active"), Color = T.good } }
	for _, rank in Core.RankList do
		table.insert(columns, { Id = rank.Id, Rank = rank, Label = Core.RankName(rank.Id), Color = Core.RankColor(rank.Id) })
	end
	local WIDTH = math.clamp(math.floor(340 / #columns), 48, 60)
	local NAME_INSET = #columns * WIDTH + 12
	local function columnX(index)
		return -(#columns - index + 1) * WIDTH
	end

	local columnHeader = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 5 }, featureCard)
	UI.label({ Size = UDim2.new(1, -NAME_INSET, 1, 0), Position = UDim2.fromOffset(10, 0), Font = T.fontBold, TextSize = 12, TextColor3 = T.sub,
		Text = tr("Fonctionnalité", "Feature", "Función", "Função", "Funktion") }, columnHeader)
	for index, column in columns do
		UI.label({ Size = UDim2.fromOffset(WIDTH - 2, 22), Position = UDim2.new(1, columnX(index), 0, 0), Font = T.fontBold, TextSize = 11, TextColor3 = column.Color,
			TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Text = column.Label }, columnHeader)
	end

	local holder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 6 }, featureCard)
	UI.list(holder, 4)
	local status = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextColor3 = T.sub, TextWrapped = true,
		LayoutOrder = 7,
		Text = L("Common.Loading") }, featureCard)

	-- Interrupteur à trois états : "on", "off", "mixed" (catégorie mélangée), "none" (sans objet : tiret)
	local function cell(parent, index, onClick)
		local slot = UI.new("Frame", { Size = UDim2.fromOffset(WIDTH, 30), Position = UDim2.new(1, columnX(index), 0.5, -15), BackgroundTransparency = 1 }, parent)
		local button = UI.button({ Size = UDim2.fromOffset(46, 24), Position = UDim2.fromOffset(math.floor((WIDTH - 46) / 2), 3), BackgroundColor3 = T.panel,
			Text = "", Corner = 12, Stroke = T.stroke }, slot)
		local knob = UI.new("Frame", { Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
			BackgroundColor3 = Color3.new(1, 1, 1), Corner = 9 }, button)
		local dash = UI.label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.sub, TextSize = 13, Text = "-",
			Visible = false }, slot)
		local object = { State = "off", Editable = false, Reason = nil }
		function object.Set(state, editable, reason)
			object.State, object.Editable, object.Reason = state, editable == true, reason
			button.Visible = state ~= "none"
			dash.Visible = state == "none"
			button.BackgroundColor3 = state == "on" and T.good or state == "mixed" and T.warn or T.panel
			button.BackgroundTransparency = object.Editable and 0 or 0.55
			knob.BackgroundTransparency = object.Editable and 0 or 0.45
			knob.Position = UDim2.new(0, state == "on" and 25 or state == "mixed" and 14 or 3, 0.5, 0)
		end
		button.Activated:Connect(function()
			if object.State == "none" then return end
			if object.Editable then
				onClick(object.State)
			else
				local explanation = Core.Text(object.Reason or tr("Cet accès est verrouillé pour ton compte.", "This access is locked for your account."))
				info.Text = explanation
				Core.Toast(explanation, false)
			end
		end)
		button.MouseEnter:Connect(function()
			if not object.Editable and object.Reason then info.Text = Core.Text(object.Reason) end
		end)
		return object
	end

	local snapshot -- dernier catalogue reçu du serveur
	local signature -- noms du catalogue : on ne reconstruit les lignes que s'il change
	local sections = {} -- { Category, Frame, Body, Arrow, Masters, Rows, Built, Visible }
	local byName = {} -- [nom] = fiche
	local allMasters, allVisible = {}, {}
	local busy = false
	local armedKey, armedAt = nil, 0
	local sync, refresh

	local function query()
		return string.lower(string.match(searchBox.Text, "^%s*(.-)%s*$") or "")
	end
	local function labelOf(item)
		local text = Core.Text(item.Label or item.Name)
		return text ~= "" and text or item.Name
	end
	local function matches(item, q)
		return q == "" or string.find(string.lower(labelOf(item)), q, 1, true) ~= nil or string.find(string.lower(item.Name), q, 1, true) ~= nil
	end

	-- mêmes règles que le serveur (qui revérifie tout)
	local function lockReason(item, column)
		return type(item.LockReason) == "table" and item.LockReason[column.Id]
			or tr("Cet accès est verrouillé pour ton compte.", "This access is locked for your account.")
	end
	local function canEdit(item, column)
		return snapshot ~= nil and type(item.CanEdit) == "table" and item.CanEdit[column.Id] == true
	end
	local function valueOf(item, column)
		if column.Global then
			return item.Enabled ~= false
		end
		if item.Global then
			return nil
		end
		return type(item.Access) == "table" and item.Access[column.Id] == true
	end
	local function setValue(item, column, value)
		if column.Global then
			item.Enabled = value
		elseif type(item.Access) == "table" then
			item.Access[column.Id] = value
		end
	end
	local function aggregate(list, column)
		local on, off = 0, 0
		for _, item in list do
			local value = valueOf(item, column)
			if value == true then on += 1 elseif value == false then off += 1 end
		end
		if on + off == 0 then return "none", false end
		local state = off == 0 and "on" or on == 0 and "off" or "mixed"
		local desired, editable, reason = state ~= "on", false, nil
		for _, item in list do
			local value = valueOf(item, column)
			if value ~= nil and value ~= desired then
				if item.Protected and not desired then
					reason = reason or tr("L'accès au panneau et aux Paramètres se retire uniquement ligne par ligne.", "Panel and Settings access can be removed only one row at a time.")
				elseif canEdit(item, column) then
					editable = true
				else
					reason = reason or lockReason(item, column)
				end
			end
		end
		return state, editable, not editable and reason or nil
	end

	-- deuxième clic dans les 3 s pour les changements risqués
	local function confirm(key, warning)
		if armedKey == key and os.clock() - armedAt < 3 then
			armedKey = nil
			return true
		end
		armedKey, armedAt = key, os.clock()
		Core.Toast(warning, false)
		return false
	end

	local function send(names, column, value)
		busy = true
		for _, name in names do
			local item = byName[name]
			if item then
				setValue(item, column, value)
			end
		end
		sync()
		task.spawn(function()
			local saved, message, allOk = 0, nil, true
			for start = 1, #names, CHUNK do
				local chunk = table.move(names, start, math.min(start + CHUNK - 1, #names), 1, {})
				local success, reply, count = call(R.SetAccessBulk, chunk, column.Id, value)
				message = reply
				if success ~= true then
					allOk = false
					break
				end
				saved += tonumber(count) or 0
			end
			busy = false
			if not holder.Parent then
				return
			end
			if allOk and #names > CHUNK then
				message = tr("%d réglage(s) enregistré(s).", "%d setting(s) saved.", "%d ajuste(s) guardado(s).", "%d ajuste(s) salvo(s).", "%d Einstellung(en) gespeichert."):format(saved)
			end
			Core.Toast(message or "", allOk)
			refresh()
		end)
	end

	local function waitMessage()
		Core.Toast(tr("Enregistrement en cours, patiente un instant.", "Saving, please wait a moment."), false)
	end

	local function onCell(item, column, state)
		if busy then
			waitMessage()
			return
		end
		if not canEdit(item, column) then
			Core.Toast(Core.Text(lockReason(item, column)), false)
			return
		end
		local value = state ~= "on"
		if not value and item.Protected and not confirm(item.Name .. "|" .. column.Id,
			tr("Clique encore pour confirmer : ce grade pourrait perdre l'accès au panneau.", "Click again to confirm: this rank could lose panel access.")) then
			return
		end
		send({ item.Name }, column, value)
	end

	-- une catégorie entière (ou tout l'APM) : seulement les lignes visibles avec la recherche en cours
	local function onMaster(list, column, state, key)
		if busy then
			waitMessage()
			return
		end
		local value = state ~= "on"
		local names = {}
		for _, item in list do
			local current = valueOf(item, column)
			if current ~= nil and current ~= value and canEdit(item, column) and not (item.Protected and not value) then
				table.insert(names, item.Name)
			end
		end
		if #names == 0 then
			Core.Toast(tr("Rien à changer dans ta portée.", "Nothing to change within your reach."), false)
			return
		end
		if key == "all" and not value and not confirm("all|" .. column.Id,
			tr("Clique encore pour décocher %d fonctionnalité(s) d'un coup.", "Click again to uncheck %d feature(s) at once.", "Haz clic de nuevo para desmarcar %d función(es) de una vez.",
			"Clique novamente para desmarcar %d função(ões) de uma vez.", "Klicke erneut, um %d Funktion(en) auf einmal abzuwählen."):format(#names)) then
			return
		end
		send(names, column, value)
	end

	local function showInfo(item)
		local description = item.Description and Core.Text(item.Description) or ""
		info.Text = ("%s  [%s]%s"):format(labelOf(item), item.Name, description ~= "" and ("  -  " .. description) or "")
	end

	local function buildRows(section)
		section.Built = true
		for order, item in section.Category.Items do
			local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, BackgroundTransparency = 0.35, LayoutOrder = order, Corner = 6 }, section.Body)
			local tag = item.ClientSide and L("Settings.ClientTag") or ""
			local label = UI.label({ Size = UDim2.new(1, -(NAME_INSET + 26), 1, 0), Position = UDim2.fromOffset(26, 0), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = labelOf(item) .. tag }, row)
			local cells = {}
			for index, column in columns do
				cells[index] = cell(row, index, function(state)
					onCell(item, column, state)
				end)
			end
			row.MouseEnter:Connect(function()
				showInfo(item)
			end)
			table.insert(section.Rows, { Item = item, Frame = row, Label = label, Cells = cells })
		end
	end

	local function buildSections()
		for _, child in holder:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		table.clear(sections)
		table.clear(byName)
		local total = 0
		for _, category in snapshot.Categories do
			for _, item in category.Items do
				byName[item.Name] = item
				total += 1
			end
		end

		-- « Tout l'APM »
		local allRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.panel, LayoutOrder = 0, Corner = 8, Stroke = T.accent }, holder)
		UI.label({ Size = UDim2.new(1, -(NAME_INSET + 12), 1, 0), Position = UDim2.fromOffset(12, 0), Font = T.fontBold, TextSize = 13, TextColor3 = T.accent,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = tr("TOUT L'APM", "ALL OF APM", "TODO EL APM", "TODO O APM", "GANZES APM") .. ("  (%d)"):format(total) }, allRow)
		for index, column in columns do
			allMasters[index] = cell(allRow, index, function(state)
				onMaster(allVisible, column, state, "all")
			end)
		end

		for order, category in snapshot.Categories do
			local color = typeof(category.Color) == "Color3" and category.Color or T.accent
			local frame = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = order }, holder)
			UI.list(frame, 3)
			local head = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.panel, LayoutOrder = 1, Corner = 8 }, frame)
			UI.new("Frame", { Size = UDim2.new(0, 4, 1, -10), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = color, Corner = 2 }, head)
			local toggle = UI.button({ Size = UDim2.new(1, -(NAME_INSET + 12), 1, 0), Position = UDim2.fromOffset(12, 0), BackgroundTransparency = 1, Text = "",
				Corner = 0 }, head)
			local arrow = UI.label({ Size = UDim2.fromOffset(16, 32), Font = T.fontBold, TextSize = 15, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center,
				Text = "+" }, toggle)
			UI.label({ Size = UDim2.new(1, -22, 1, 0), Position = UDim2.fromOffset(22, 0), Font = T.fontBold, TextSize = 13, TextColor3 = color, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = ("%s  (%d)"):format(Core.Text(category.Label or category.Id), #category.Items) }, toggle)
			local body = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2,
				Visible = false }, frame)
			UI.list(body, 3)
			local section = { Category = category, Frame = frame, Body = body, Arrow = arrow, Masters = {}, Rows = {}, Built = false, Visible = {} }
			for index, column in columns do
				section.Masters[index] = cell(head, index, function(state)
					onMaster(section.Visible, column, state, category.Id)
				end)
			end
			toggle.Activated:Connect(function()
				expanded[category.Id] = not expanded[category.Id] or nil
				sync()
			end)
			table.insert(sections, section)
		end
	end

	sync = function()
		if not snapshot then
			return
		end
		local q = query()
		local searching = q ~= ""
		local everything = {}
		for _, section in sections do
			local visible = {}
			for _, item in section.Category.Items do
				if matches(item, q) then
					table.insert(visible, item)
					table.insert(everything, item)
				end
			end
			section.Visible = visible
			section.Frame.Visible = #visible > 0
			local open = #visible > 0 and (searching or expanded[section.Category.Id] == true)
			section.Arrow.Text = open and "-" or "+"
			if open and not section.Built then
				buildRows(section)
			end
			section.Body.Visible = open
			for index, column in columns do
				section.Masters[index].Set(aggregate(visible, column))
			end
			for _, row in section.Rows do
				row.Frame.Visible = matches(row.Item, q)
				row.Label.TextColor3 = row.Item.Enabled ~= false and T.text or T.sub
				for index, column in columns do
					local value = valueOf(row.Item, column)
					row.Cells[index].Set(value == nil and "none" or value and "on" or "off", canEdit(row.Item, column), lockReason(row.Item, column))
				end
			end
		end
		allVisible = everything
		for index, column in columns do
			allMasters[index].Set(aggregate(everything, column))
		end
		status.Visible = #everything == 0
		if #everything == 0 then
			status.Text = tr("Aucune fonctionnalité ne correspond à la recherche.", "No feature matches the search.")
		end
	end

	-- position de défilement gardée d'une reconstruction à l'autre
	local tracking = false
	scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if tracking then
			memory.Scroll = scroll.CanvasPosition
		end
	end)
	local function restoreScroll()
		local target = memory.Scroll
		task.delay(0.05, function()
			if scroll.Parent and target then
				scroll.CanvasPosition = target
			end
			tracking = true
		end)
	end

	local function apply(data)
		Core.FeatureCatalogue = data
		local parts = {}
		for _, category in data.Categories do
			table.insert(parts, tostring(category.Id))
			for _, item in category.Items do
				table.insert(parts, tostring(item.Name))
			end
		end
		local newSignature = table.concat(parts, "|")
		local first = snapshot == nil
		if newSignature ~= signature then
			snapshot = data
			signature = newSignature
			buildSections()
		else
			-- même catalogue : seules les valeurs changent
			for _, category in data.Categories do
				for _, item in category.Items do
					local old = byName[item.Name]
					if old then
						old.Enabled, old.Access, old.CanEdit, old.LockReason = item.Enabled, item.Access, item.CanEdit, item.LockReason
					end
				end
			end
			snapshot.CanToggle, snapshot.Owner = data.CanToggle, data.Owner
		end
		sync()
		if first then
			restoreScroll()
		end
	end

	local fetching = false
	refresh = function()
		if fetching then
			return
		end
		fetching = true
		task.spawn(function()
			local ok, data = pcall(function()
				return R.GetFeatures:InvokeServer()
			end)
			fetching = false
			if not holder.Parent then
				return
			end
			if ok and type(data) == "table" and type(data.Categories) == "table" then
				apply(data)
			elseif not snapshot then
				status.Visible = true
				status.Text = tr("Catalogue indisponible : réessaie dans un instant.", "Catalogue unavailable: try again in a moment.")
			end
		end)
	end

	function Core.OpenPermissionEditor(searchText)
		if not page.Parent or not searchBox.Parent then return false end
		Core.SelectPage("Settings")
		if type(searchText) == "string" then searchBox.Text = searchText end
		task.defer(function()
			if scroll.Parent and featureCard.Parent then
				local top = featureCard.AbsolutePosition.Y - scroll.AbsolutePosition.Y + scroll.CanvasPosition.Y
				scroll.CanvasPosition = Vector2.new(0, math.max(0, top))
			end
		end)
		return true
	end

	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		memory.Search = searchBox.Text
		sync()
	end)
	expandAll.Activated:Connect(function()
		for _, section in sections do
			expanded[section.Category.Id] = true
		end
		sync()
	end)
	collapseAll.Activated:Connect(function()
		table.clear(expanded)
		sync()
	end)
	featureCard.MouseLeave:Connect(function()
		info.Text = defaultInfo
	end)

	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			refreshStaff()
			if not busy then
				refresh()
			end
		end
	end)
	Core.On(Core.AccessChanged.Event, function()
		if not busy then
			refresh()
		end
	end)
	refreshStaff()
	refresh()
end

return Page
