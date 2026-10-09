--[[
	Players : onglet « Joueurs ». À gauche la liste (Serveur : joueurs présents ; Global : tous ceux venus dans le jeu, même hors ligne),
	à droite la fiche du joueur choisi et ses actions : un bouton par module serveur de catégorie « Players » (Mode « target »),
	rangés par groupe (champ Group, ordre et couleurs dans Config.PlayerGroups). Le champ Inputs d'un module dit quels paramètres
	il lit : "Reason" (motif) et / ou "Minutes" (durée). Le serveur revalide tout : ici on ne fait qu'afficher et envoyer.
]]
local Players = game:GetService("Players")

local Page = { Id = "Players", Order = 1, Label = "Tab.Players", Handles = { "Players" } }

local MAX_ROWS = 120
local ROSTER_PAGE_SIZE = 200
local MAX_LOOKUP_RESULTS = 20

function Page.Build(Core, page)
	local UI, T, R, L, Config = Core.UI, Core.T, Core.R, Core.L, Core.Config
	local session = Core.Session
	local function alive()
		return Core.Alive(session) and page.Parent ~= nil and Core.HasPermission("APM.AccessPanel")
	end
	local function text(fr, en) return Core.Text({ fr = fr, en = en }) end

	local mode = "server"
	local selected -- { userId, name, displayName, online, player }
	local roster, rosterLoaded, rosterLoading = {}, false, false
	local rosterOffset, nextRosterOffset, rosterTotal, rosterError = 0, nil, 0, nil
	local extra = {} -- comptes trouvés par recherche exacte (GlobalSearch)

	-- Colonne de gauche --------------------------------------------------------------------------------------------
	local left = UI.new("Frame", { Size = UDim2.new(0, 224, 1, 0), BackgroundTransparency = 1 }, page)
	local modeRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, left)
	local serverButton = UI.button({ Size = UDim2.new(0.5, -3, 1, 0), Text = L("Players.Server"), TextSize = 13 }, modeRow)
	local globalButton = UI.button({ Size = UDim2.new(0.5, -3, 1, 0), Position = UDim2.new(0.5, 3, 0, 0), Text = L("Players.Global"), TextSize = 13 }, modeRow)
	local search = UI.input({ Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 36), PlaceholderText = L("Common.Search"), TextSize = 13 }, left)
	local listFrame = UI.scroll({ Size = UDim2.new(1, 0, 1, -72), Position = UDim2.fromOffset(0, 72) }, left)
	UI.list(listFrame, 4)
	local pagination = UI.new("Frame", { Name = "RosterPagination", Size = UDim2.new(1, 0, 0, 58),
		Position = UDim2.new(0, 0, 1, -58), BackgroundTransparency = 1, Visible = false }, left)
	local pageInfo = UI.label({ Name = "RosterPageInfo", Size = UDim2.new(1, 0, 0, 25), TextSize = 10, TextColor3 = T.sub,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, Text = "" }, pagination)
	local previousButton = UI.button({ Name = "RosterPrevious", Size = UDim2.new(0.5, -3, 0, 28), Position = UDim2.fromOffset(0, 30),
		Text = text("Précédent", "Previous"), TextSize = 12 }, pagination)
	local nextButton = UI.button({ Name = "RosterNext", Size = UDim2.new(0.5, -3, 0, 28), Position = UDim2.new(0.5, 3, 0, 30),
		Text = text("Suivant", "Next"), TextSize = 12 }, pagination)
	local function refreshPagination()
		local global = mode == "global"
		pagination.Visible = global
		listFrame.Size = UDim2.new(1, 0, 1, global and -134 or -72)
		local previousAllowed = global and not rosterLoading and rosterOffset > 0
		local nextAllowed = global and not rosterLoading and nextRosterOffset ~= nil
		previousButton.Active, previousButton.Selectable = previousAllowed, previousAllowed
		nextButton.Active, nextButton.Selectable = nextAllowed, nextAllowed
		previousButton.TextTransparency = previousAllowed and 0 or 0.5
		nextButton.TextTransparency = nextAllowed and 0 or 0.5
		if rosterLoading then
			pageInfo.Text = L("Common.Loading")
		else
			local range = #roster > 0 and ((rosterOffset + 1) .. "–" .. (rosterOffset + #roster)) or "0"
			pageInfo.Text = range .. " / " .. rosterTotal .. "\n" .. text("Le filtre recherche dans cette page.", "The filter searches this page.")
		end
	end

	-- Colonne de droite ---------------------------------------------------------------------------------------------
	local right = UI.scroll({ Size = UDim2.new(1, -236, 1, 0), Position = UDim2.fromOffset(236, 0) }, page)
	UI.list(right, 10)
	local placeholder = UI.emptyState(page, L("Players.Pick"))
	placeholder.Size = UDim2.new(1, -236, 1, 0)
	placeholder.Position = UDim2.fromOffset(236, 0)

	local infoCard = UI.card(right, 1)
	local nameLabel = UI.label({ Size = UDim2.new(1, 0, 0, 24), Font = T.fontBold, TextSize = 18, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 1, Text = "" }, infoCard)
	local subLabel = UI.label({ Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = T.sub, LayoutOrder = 2, Text = "" }, infoCard)
	local rankLabel = UI.label({ Size = UDim2.new(1, 0, 0, 16), TextSize = 12, Font = T.fontBold, LayoutOrder = 3, Text = "" }, infoCard)
	local warnLabel = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextColor3 = T.warn, TextWrapped = true, LayoutOrder = 4,
		Text = "", Visible = false }, infoCard)
	local profileButton = UI.button({ Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.accent, Text = L("Players.OpenProfile"), TextSize = 13, LayoutOrder = 5 }, infoCard)

	local paramCard = UI.card(right, 2)
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextColor3 = T.sub, TextWrapped = true, LayoutOrder = 1,
		Text = L("Players.ParamsHint") }, paramCard)
	local reasonBox = UI.input({ Size = UDim2.new(1, 0, 0, 30), PlaceholderText = L("Players.ReasonHint"), TextSize = 13, LayoutOrder = 2 }, paramCard)
	local minutesBox = UI.input({ Size = UDim2.new(1, 0, 0, 30), PlaceholderText = L("Players.MinutesHint"), TextSize = 13, LayoutOrder = 3 }, paramCard)

	-- valeur envoyée avec un module, d'après son champ Inputs
	local function valueFor(module)
		if type(module.Inputs) ~= "table" then
			return nil
		end
		local value = {}
		for _, input in module.Inputs do
			if input == "Reason" then
				value.Reason = reasonBox.Text
			elseif input == "Minutes" then
				value.Minutes = tonumber(minutesBox.Text) or 0
			end
		end
		return value
	end

	local groupCards = {} -- { card, buttons }
	local offlineCard = UI.card(right, 100)
	offlineCard.Visible = false
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextColor3 = T.sub, TextWrapped = true, LayoutOrder = 1,
		Text = L("Players.OfflineHint") }, offlineCard)
	local offlineBan = UI.button({ Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(190, 60, 60), Text = L("Players.BanAccount"), TextSize = 13, LayoutOrder = 2 }, offlineCard)

	local function isOnlineTarget()
		return selected ~= nil and selected.player ~= nil and selected.player.Parent ~= nil
	end

	local function refreshButtons()
		local online = isOnlineTarget()
		for _, entry in groupCards do
			local any = false
			for _, button in entry.buttons do
				local allowed = Core.CanUse(button.Name)
				button.Visible = allowed
				any = any or allowed
				button.BackgroundTransparency = online and 0 or 0.6
				button.TextTransparency = online and 0 or 0.5
			end
			entry.card.Visible = any
		end
		paramCard.Visible = selected ~= nil
		offlineCard.Visible = selected ~= nil and not online and Core.CanUse("Ban")
	end

	-- Données du joueur choisi -------------------------------------------------------------------------------------
	local function refreshWarnings()
		local target = selected
		if not target then
			return
		end
		task.spawn(function()
			if not alive() then return end
			local ok, list = pcall(function()
				return R.GetWarnings:InvokeServer(target.userId)
			end)
			if not alive() or selected ~= target or not warnLabel.Parent then
				return
			end
			if ok and type(list) == "table" and #list > 0 then
				local last = list[1]
				warnLabel.Text = L("Players.Warnings", #list, Core.Text(last.reason), tostring(last.by or "?"), Core.FormatDate(last.time))
				warnLabel.Visible = true
			else
				warnLabel.Visible = false
			end
		end)
	end

	local selectionToken = 0
	local function renderSelection()
		placeholder.Visible = selected == nil
		right.Visible = selected ~= nil
		if not selected then
			refreshButtons()
			return
		end
		nameLabel.Text = selected.displayName ~= selected.name and ("%s  (@%s)"):format(selected.displayName, selected.name) or selected.name
		subLabel.Text = L(isOnlineTarget() and "Players.OnServer" or "Players.OffServer", selected.userId)
		rankLabel.Text = L("Players.Rank", "...")
		rankLabel.TextColor3 = T.sub
		warnLabel.Visible = false
		refreshButtons()
		selectionToken += 1
		local mine = selectionToken
		local userId = selected.userId
		task.spawn(function()
			if not alive() then return end
			local ok, rank = pcall(function()
				return R.GetRank:InvokeServer(userId)
			end)
			if not alive() or mine ~= selectionToken or not selected or not rankLabel.Parent then
				return
			end
			rank = ok and rank or nil
			rankLabel.Text = L("Players.Rank", Core.RankName(rank))
			rankLabel.TextColor3 = rank and Core.RankColor(rank) or T.sub
		end)
		refreshWarnings()
	end

	-- Boutons d'action, par groupe -------------------------------------------------------------------------------------
	local function buildGroups()
		local modules = {}
		for _, module in Core.ServerModules do
			if module.Category == "Players" and module.Mode == "target" then
				table.insert(modules, module)
			end
		end
		table.sort(modules, function(a, b)
			return (a.Order or 100) < (b.Order or 100)
		end)
		local groups, colors = {}, {}
		for _, group in Config.PlayerGroups or {} do
			table.insert(groups, group.Id)
			colors[group.Id] = group.Color
		end
		for _, module in modules do
			local id = module.Group or "Other"
			if not table.find(groups, id) then
				table.insert(groups, id)
			end
		end
		for index, groupId in groups do
			local card = UI.card(right, 10 + index)
			UI.sectionHeader(Core.Text("Group." .. groupId), colors[groupId] or T.accent, card, 1)
			local holder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, card)
			local layout = UI.list(holder, 6, true)
			layout.Wraps = true
			local entry = { card = card, buttons = {} }
			for _, module in modules do
				if (module.Group or "Other") == groupId then
					local button = UI.button({ Name = module.Name, Size = UDim2.fromOffset(108, 34), BackgroundColor3 = (module.Color or T.panel):Lerp(T.panel2, 0.35),
						Text = Core.Text(module.Label), TextSize = 12, TextWrapped = true, LayoutOrder = module.Order or 100 }, holder)
					UI.hover(button)
					UI.Confirmable(button, module.Confirm == true, function()
						if not isOnlineTarget() then
							Core.Toast(L("Players.Gone"), false)
							return
						end
						Core.Action(module.Name, selected.player, valueFor(module))
						task.delay(1, function()
							if selected and warnLabel.Parent then
								refreshWarnings()
							end
						end)
					end)
					table.insert(entry.buttons, button)
				end
			end
			if #entry.buttons > 0 then
				table.insert(groupCards, entry)
			else
				card:Destroy()
			end
		end
	end

	local function select(entry)
		selected = entry
		Core.SetSelected(entry and entry.player or nil)
		renderSelection()
		for _, child in listFrame:GetChildren() do
			if child:IsA("TextButton") and string.sub(child.Name, 1, 1) == "u" then
				child.BackgroundColor3 = (entry and child.Name == "u" .. entry.userId) and T.accent or T.panel2
			end
		end
	end

	-- Liste ---------------------------------------------------------------------------------------------------------
	local function entries()
		local query = string.lower(search.Text)
		local list, seen = {}, {}
		local function matches(entry)
			return query == "" or string.find(string.lower(entry.name or ""), query, 1, true) ~= nil
				or string.find(string.lower(entry.displayName or ""), query, 1, true) ~= nil or tostring(entry.userId) == query
		end
		if mode == "server" then
			for _, other in Players:GetPlayers() do
				local entry = { userId = other.UserId, name = other.Name, displayName = other.DisplayName, online = true, player = other }
				if matches(entry) then
					table.insert(list, entry)
				end
			end
			table.sort(list, function(a, b)
				return string.lower(a.name) < string.lower(b.name)
			end)
		else
			for _, source in { extra, roster } do
				for _, entry in source do
					if not seen[entry.userId] and matches(entry) then
						seen[entry.userId] = true
						local online = Players:GetPlayerByUserId(entry.userId)
						table.insert(list, { userId = entry.userId, name = entry.name, displayName = entry.displayName or entry.name, online = online ~= nil,
							player = online, lastSeen = entry.lastSeen })
					end
				end
			end
		end
		return list
	end

	local refreshList
	local function lookupButton()
		local query = search.Text
		local lookup = UI.button({ Name = "Lookup", Size = UDim2.new(1, -6, 0, 30), BackgroundColor3 = T.panel, Text = L("Players.Lookup", query), TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = 100000 }, listFrame)
		lookup.Activated:Connect(function()
			if not alive() then return end
			lookup.Text = L("Players.Searching")
			task.spawn(function()
				if not alive() then return end
				local ok, result = pcall(function()
					return R.GlobalSearch:InvokeServer(query)
				end)
				if not alive() or not lookup.Parent then
					return
				end
				if ok and type(result) == "table" and #result > 0 then
					for _, found in result do
						table.insert(extra, found)
						while #extra > MAX_LOOKUP_RESULTS do table.remove(extra, 1) end
					end
					refreshList()
				else
					Core.Toast(L("Players.NotFound", query), false)
					lookup.Text = L("Players.NoResult")
				end
			end)
		end)
	end

	refreshList = function()
		if not alive() then return end
		for _, child in listFrame:GetChildren() do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
		serverButton.BackgroundColor3 = mode == "server" and T.accent or T.panel2
		globalButton.BackgroundColor3 = mode == "global" and T.accent or T.panel2
		refreshPagination()
		if mode == "global" and not rosterLoaded then
			UI.label({ Size = UDim2.new(1, -6, 0, 30), TextColor3 = rosterError and T.bad or T.sub, TextSize = 12,
				TextWrapped = true, Text = rosterError or L("Players.LoadingRoster"), LayoutOrder = 1 }, listFrame)
			return
		end
		local maximumRows = mode == "global" and ROSTER_PAGE_SIZE + MAX_LOOKUP_RESULTS or MAX_ROWS
		for index, entry in entries() do
			if index > maximumRows then
				UI.label({ Size = UDim2.new(1, -6, 0, 24), TextColor3 = T.sub, TextSize = 11, Text = L("Players.Refine"), LayoutOrder = index }, listFrame)
				break
			end
			local row = UI.button({ Name = "u" .. entry.userId, Size = UDim2.new(1, -6, 0, 40), BackgroundColor3 = (selected and selected.userId == entry.userId) and T.accent or T.panel2,
				Text = "", LayoutOrder = index }, listFrame)
			UI.new("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(9, 16), BackgroundColor3 = entry.online and T.good or T.sub, Corner = 4 }, row)
			local suffix = entry.player == Core.Player and L("Common.You") or ""
			UI.label({ Size = UDim2.new(1, -30, 0, 18), Position = UDim2.fromOffset(24, 4), Font = T.fontBold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = entry.displayName .. suffix }, row)
			local detail = "@" .. entry.name
			if mode == "global" and not entry.online and entry.lastSeen and entry.lastSeen > 0 then
				detail ..= "  -  " .. Core.FormatDate(entry.lastSeen)
			end
			UI.label({ Size = UDim2.new(1, -30, 0, 14), Position = UDim2.fromOffset(24, 21), TextSize = 11, TextColor3 = T.sub, TextTruncate = Enum.TextTruncate.AtEnd, Text = detail }, row)
			row.Activated:Connect(function()
				select(entry)
			end)
		end
		-- recherche exacte hors annuaire (pseudo complet ou UserId)
		if mode == "global" and #search.Text >= 3 then
			lookupButton()
		end
	end

	local function loadRoster(offset)
		if not alive() or rosterLoading then
			return
		end
		offset = math.clamp(math.floor(tonumber(offset) or rosterOffset), 0, 20000)
		if offset ~= rosterOffset then
			rosterLoaded = false
			extra = {}
		end
		rosterError = nil
		rosterLoading = true
		refreshList()
		task.spawn(function()
			if not alive() then return end
			local ok, list, nextOffset, totalCount = pcall(function()
				return R.GetRoster:InvokeServer(offset)
			end)
			rosterLoading = false
			if not alive() or not listFrame.Parent then
				return
			end
			if ok and type(list) == "table" then
				roster = list
				while #roster > ROSTER_PAGE_SIZE do table.remove(roster) end
				rosterOffset = offset
				nextRosterOffset = type(nextOffset) == "number" and nextOffset == nextOffset and nextOffset % 1 == 0
					and nextOffset > offset and nextOffset <= 20000 and nextOffset or nil
				rosterTotal = type(totalCount) == "number" and totalCount == totalCount and math.abs(totalCount) ~= math.huge
					and math.max(0, math.floor(totalCount)) or (offset + #roster)
				rosterLoaded = true
				listFrame.CanvasPosition = Vector2.zero
			else
				rosterError = text("Annuaire indisponible. Réessaie avec Global.", "Directory unavailable. Retry with Global.")
				Core.Toast(rosterError, false)
			end
			if mode == "global" then
				refreshList()
			end
		end)
	end
	previousButton.Activated:Connect(function()
		if mode == "global" and not rosterLoading and rosterOffset > 0 then loadRoster(math.max(0, rosterOffset - ROSTER_PAGE_SIZE)) end
	end)
	nextButton.Activated:Connect(function()
		if mode == "global" and not rosterLoading and nextRosterOffset then loadRoster(nextRosterOffset) end
	end)

	serverButton.Activated:Connect(function()
		mode = "server"
		refreshList()
	end)
	globalButton.Activated:Connect(function()
		mode = "global"
		loadRoster(rosterOffset)
		refreshList()
	end)
	search:GetPropertyChangedSignal("Text"):Connect(refreshList)

	profileButton.Activated:Connect(function()
		if selected and Core.ShowProfile then
			Core.ShowProfile(selected.userId, selected.displayName)
		end
	end)

	UI.Confirmable(offlineBan, true, function()
		if not selected then
			return
		end
		local target = selected
		task.spawn(function()
			if not alive() then return end
			local ok, success, message = pcall(function()
				return R.BanUserId:InvokeServer(target.userId, tonumber(minutesBox.Text) or 0)
			end)
			if not alive() then return end
			Core.Toast(ok and (message or "") or L("Common.ServerError"), ok and success == true)
		end)
	end)

	Core.On(Players.PlayerAdded, function()
		task.defer(refreshList)
	end)
	Core.On(Players.PlayerRemoving, function(leaving)
		if selected and selected.player == leaving then
			selected.player = nil
			selected.online = false
			Core.SetSelected(nil)
			renderSelection()
		end
		task.defer(refreshList)
	end)
	Core.On(Core.AccessChanged.Event, refreshButtons)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			refreshList()
			if mode == "global" then
				loadRoster(rosterOffset)
			end
		end
	end)

	buildGroups()
	renderSelection()
	refreshList()
end

return Page
