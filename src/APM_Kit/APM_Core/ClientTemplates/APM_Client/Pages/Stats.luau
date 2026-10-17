-- Statistiques de ce serveur : utilisation du panneau, joueurs, rendement, DataStores sollicités (relevés côté serveur, filtrés par droits).
local Page = { Id = "Stats", Order = 6.5, Label = { fr = "Statistiques", en = "Statistics", es = "Estadísticas", pt = "Estatísticas", de = "Statistiken" } }
function Page.Visible(Core)
	return Core.HasPermission("APM.AccessPanel")
end
function Page.Build(Core, page)
	local UI, T, R = Core.UI, Core.T, Core.R
	local Charts = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("Charts"))
	local mine = Core.Session
	local function text(fr, en)
		return Core.Text({ fr = fr, en = en })
	end
	local function alive()
		return Core.Alive(mine) and page.Parent ~= nil
	end
	local function infraAllowed()
		return Core.ActualOwner or Core.HasPermission("APM.Simulate")
	end
	local function usageAllowed()
		return Core.HasPermission("APM.ViewLogs")
	end
	local format = Charts.Format
	local function duration(seconds)
		if type(seconds) ~= "number" then return "—" end
		if seconds >= 3600 then return Core.L("Time.HourMin", math.floor(seconds / 3600), math.floor(seconds / 60) % 60) end
		return Core.L("Time.MinSec", math.floor(seconds / 60), math.floor(seconds % 60))
	end
	local scroll = UI.scroll({ Name = "StatsScroll", Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)
	local heading = UI.card(scroll, 1)
	heading.Name = "StatsHeader"
	UI.sectionHeader(text("STATISTIQUES DU SERVEUR", "SERVER STATISTICS"), T.accent, heading, 1)
	local status = UI.label({ Name = "StatsStatus", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12,
		TextColor3 = T.sub, LayoutOrder = 2, Text = Core.L("Common.Loading") }, heading)
	local refreshButton = UI.button({ Name = "RefreshStats", Size = UDim2.new(1, 0, 0, 32), Text = Core.L("Common.Refresh"), LayoutOrder = 3 }, heading)

	-- indicateurs clés
	local grid = UI.new("Frame", { Name = "StatsSummary", Size = UDim2.new(1, -6, 0, 112), BackgroundTransparency = 1, LayoutOrder = 2 }, scroll)
	local layout = UI.new("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local tiles = {}
	local function tile(name, title, color, order)
		local card = UI.card(grid, order)
		card.Name = name
		card.AutomaticSize = Enum.AutomaticSize.None
		UI.sectionHeader(title, color, card, 1)
		local value = UI.label({ Name = "Value", Size = UDim2.new(1, 0, 0, 30), Font = T.fontBold, TextSize = 24, TextColor3 = T.text, Text = "—", LayoutOrder = 2 }, card)
		local detail = UI.label({ Name = "Detail", Size = UDim2.new(1, 0, 0, 28), TextSize = 11, TextWrapped = true, TextColor3 = T.sub, Text = "", LayoutOrder = 3 }, card)
		tiles[name] = { Card = card, Value = value, Detail = detail }
		return tiles[name]
	end
	local usageTile = tile("UsageTile", text("COMMANDES EXÉCUTÉES", "COMMANDS RUN"), T.accent, 1)
	local playersTile = tile("PlayersTile", text("JOUEURS UNIQUES", "UNIQUE PLAYERS"), T.accent, 2)
	local sessionTile = tile("SessionTile", text("SESSION MOYENNE", "AVERAGE SESSION"), T.accent, 3)
	local heartbeatTile = tile("HeartbeatTile", text("CYCLE SERVEUR", "SERVER HEARTBEAT"), T.accent, 4)
	local storeTile = tile("DataStoreTile", text("APPELS DATASTORE", "DATASTORE CALLS"), T.accent, 5)
	local function reflow()
		if not alive() then return end
		local count = 0
		for _, entry in tiles do if entry.Card.Visible then count += 1 end end
		local cols = grid.AbsoluteSize.X >= 600 and 3 or grid.AbsoluteSize.X >= 380 and 2 or 1
		layout.CellSize = UDim2.new(1 / cols, -math.ceil((cols - 1) * 8 / cols) - 1, 0, 104)
		grid.Size = UDim2.new(1, -6, 0, math.max(1, math.ceil(count / cols)) * 112 - 8)
	end
	Core.On(grid:GetPropertyChangedSignal("AbsoluteSize"), reflow)

	-- utilisation du panneau
	local usageCard = UI.card(scroll, 3)
	usageCard.Name = "UsageStats"
	UI.sectionHeader(text("UTILISATION DU PANNEAU", "PANEL USAGE"), T.accent, usageCard, 1)
	local usageInfo = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub,
		LayoutOrder = 2, Text = "" }, usageCard)
	local usageChart = Charts.Columns(Core, usageCard, { Name = "ActionsOverTime", Title = text("Commandes par intervalle de 15 s", "Commands per 15 s interval"),
		Order = 3 })
	local modulesChart = Charts.Bars(Core, usageCard, { Name = "TopCommands", Title = text("Commandes les plus utilisées", "Most used commands"),
		Order = 4 })
	local actorsChart = Charts.Bars(Core, usageCard, { Name = "TopAdmins", Title = text("Membres du staff les plus actifs", "Most active staff"),
		Order = 5 })

	-- joueurs
	local playersCard = UI.card(scroll, 4)
	playersCard.Name = "PlayerStats"
	UI.sectionHeader(text("JOUEURS", "PLAYERS"), T.accent, playersCard, 1)
	local playersInfo = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub,
		LayoutOrder = 2, Text = "" }, playersCard)
	local onlineChart = Charts.Columns(Core, playersCard, { Name = "PlayersOverTime", Title = text("Joueurs connectés", "Players online"), Order = 3 })
	local pingChart = Charts.Columns(Core, playersCard, { Name = "PingOverTime", Title = text("Latence moyenne", "Average latency"), Unit = "ms",
		Decimals = 1, Order = 4 })
	local sessionsChart = Charts.Bars(Core, playersCard, { Name = "SessionLengths", Title = text("Durée des sessions terminées", "Finished session lengths"),
		Order = 5 })
	local longestChart = Charts.Bars(Core, playersCard, { Name = "LongestOnline", Title = text("Plus longues présences en cours", "Longest current sessions"),
		Order = 6 })

	-- rendement
	local perfCard = UI.card(scroll, 5)
	perfCard.Name = "PerformanceStats"
	UI.sectionHeader(text("RENDEMENT DU SERVEUR", "SERVER PERFORMANCE"), T.accent, perfCard, 1)
	local perfInfo = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub,
		LayoutOrder = 2, Text = "" }, perfCard)
	local hzChart = Charts.Columns(Core, perfCard, { Name = "HeartbeatOverTime", Title = text("Cycle serveur (60 = idéal)", "Server heartbeat (60 = ideal)"),
		Unit = "Hz", Decimals = 1, Order = 3 })
	local memoryChart = Charts.Columns(Core, perfCard, { Name = "MemoryOverTime", Title = text("Mémoire moteur", "Engine memory"), Unit = "MB", Order = 4 })
	local receiveChart = Charts.Columns(Core, perfCard, { Name = "ReceiveOverTime", Title = text("Réseau reçu", "Network received"), Unit = "KB/s",
		Decimals = 1, Order = 5 })
	local sendChart = Charts.Columns(Core, perfCard, { Name = "SendOverTime", Title = text("Réseau envoyé", "Network sent"), Unit = "KB/s", Decimals = 1,
		Order = 6 })

	-- DataStores
	local storeCard = UI.card(scroll, 6)
	storeCard.Name = "DataStoreStats"
	UI.sectionHeader("DATASTORES", T.accent, storeCard, 1)
	local storeInfo = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub,
		LayoutOrder = 2, Text = "" }, storeCard)
	local callsChart = Charts.Columns(Core, storeCard, { Name = "CallsOverTime", Title = text("Appels par intervalle de 15 s", "Calls per 15 s interval"),
		Order = 3 })
	local storesChart = Charts.Bars(Core, storeCard, { Name = "TopStores", Title = text("DataStores les plus sollicités", "Busiest DataStores"),
		Order = 4 })
	local keysChart = Charts.Bars(Core, storeCard, { Name = "TopKeys", Title = text("Clés les plus sollicitées", "Busiest keys"), Order = 5 })
	local budgetInfo = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub,
		LayoutOrder = 6, Text = "" }, storeCard)
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = T.sub, LayoutOrder = 7,
		Text = text("Le DataStore de l'APM est suivi automatiquement. Pour suivre ceux de ton jeu (script serveur) : store = APM.TrackDataStore(DataStoreService:GetDataStore(\"Nom\"), \"Nom\") puis utilise store comme d'habitude.",
			"The APM DataStore is tracked automatically. To track your game's stores (server script): store = APM.TrackDataStore(DataStoreService:GetDataStore(\"Name\"), \"Name\") then use store as usual.") }, storeCard)

	local function permissions()
		if not alive() then return end
		usageCard.Visible = usageAllowed()
		usageTile.Card.Visible = usageAllowed()
		perfCard.Visible = infraAllowed()
		heartbeatTile.Card.Visible = infraAllowed()
		storeCard.Visible = infraAllowed()
		storeTile.Card.Visible = infraAllowed()
		reflow()
	end
	local function series(history, key, badKey)
		local points = {}
		for _, point in history do
			table.insert(points, { Time = point.Time, Value = point[key], Bad = badKey and point[badKey] or nil })
		end
		return points
	end
	local function render(data)
		if not alive() then return end
		permissions()
		if type(data) ~= "table" or type(data.History) ~= "table" then
			status.Text = text("Statistiques indisponibles. Réessayez l'actualisation.", "Statistics unavailable. Try refreshing.")
			for _, entry in tiles do
				entry.Value.Text = "—"
				entry.Detail.Text = ""
			end
			return
		end
		local history = data.History
		status.Text = text("Dernier relevé : ", "Last snapshot: ") .. os.date("%H:%M:%S", data.GeneratedAt)
			.. text(" · un point toutes les ", " · one point every ") .. tostring(data.SampleSeconds) .. text(" s, ", " s, ") .. tostring(#history) .. " / " .. tostring(data.HistorySize)
			.. text(" points.\nRelevés gardés en mémoire sur ce serveur depuis son démarrage (rien n'est enregistré). Survolez une barre pour sa valeur.",
			" points.\nReadings are kept in memory on this server since it started (nothing is saved). Hover a bar for its value.")
		if usageAllowed() and type(data.Usage) == "table" then
			local usage = data.Usage
			usageTile.Value.Text = format(usage.Total)
			usageTile.Detail.Text = format(usage.Failures) .. text(" en échec", " failed")
			usageInfo.Text = format(usage.Total) .. text(" commande(s) exécutée(s) depuis le panneau sur ce serveur, dont ", " command(s) run from the panel on this server, ")
				.. format(usage.Failures) .. text(" en échec (rouge).", " failed (red).")
			usageChart.Set(series(history, "Actions", "Failures"), data.HistorySize)
			local rows = {}
			for _, entry in usage.Modules or {} do
				table.insert(rows, { Label = Core.ActionLabel(entry.Name), Value = entry.Count, Bad = entry.Failures,
					Detail = (entry.Category and (Core.Text("Cat." .. entry.Category) .. " · ") or "") .. format(entry.Failures) .. text(" échec(s) · dernière : ", " failure(s) · last: ") .. (entry.LastAt and os.date("%H:%M:%S", entry.LastAt) or "—") })
			end
			modulesChart.Set(rows)
			rows = {}
			for _, entry in usage.Actors or {} do table.insert(rows, { Label = entry.Name, Value = entry.Count }) end
			actorsChart.Set(rows)
		end
		local players = data.Players
		if type(players) == "table" then
			playersTile.Value.Text = format(players.Unique)
			playersTile.Detail.Text = format(players.Online) .. text(" en ligne · pic ", " online · peak ") .. format(players.Peak)
			sessionTile.Value.Text = duration(players.AverageSessionSeconds)
			sessionTile.Detail.Text = format(players.FinishedSessions) .. text(" session(s) terminée(s)", " finished session(s)")
			playersInfo.Text = format(players.Joins) .. text(" arrivée(s) · ", " join(s) · ") .. format(players.Leaves) .. text(" départ(s) · ", " leave(s) · ")
				.. format(players.Unique) .. text(" joueur(s) unique(s) · ", " unique player(s) · ") .. format(players.NewAccounts) .. text(" compte(s) de moins de 7 jours", " account(s) under 7 days old")
				.. text("\nSession la plus longue terminée : ", "\nLongest finished session: ") .. duration(players.LongestSessionSeconds)
			onlineChart.Set(series(history, "Players"), data.HistorySize)
			pingChart.Set(series(history, "PingMs"), data.HistorySize)
			local labels = { text("< 5 min", "< 5 min"), "5–15 min", "15–30 min", "30–60 min", text("> 1 h", "> 1 h") }
			local rows = {}
			for index, label in labels do table.insert(rows, { Label = label, Value = (players.SessionBuckets or {})[index] or 0 }) end
			sessionsChart.Set(players.FinishedSessions and players.FinishedSessions > 0 and rows or {})
			rows = {}
			for _, entry in players.LongestOnline or {} do
				table.insert(rows, { Label = tostring(entry.DisplayName) .. " (@" .. tostring(entry.Name) .. ")", Value = entry.Seconds, ValueText = duration(entry.Seconds) })
			end
			longestChart.Set(rows)
		end
		if infraAllowed() then
			local last = history[#history]
			heartbeatTile.Value.Text = last and format(last.HeartbeatHz, 1) .. " Hz" or "—"
			heartbeatTile.Detail.Text = last and (format(last.MemoryMb) .. text(" MB de mémoire moteur", " MB engine memory")) or ""
			local minHz, sumHz, countHz = math.huge, 0, 0
			for _, point in history do
				if type(point.HeartbeatHz) == "number" then
					minHz = math.min(minHz, point.HeartbeatHz)
					sumHz += point.HeartbeatHz
					countHz += 1
				end
			end
			perfInfo.Text = countHz > 0 and (text("Cycle moyen : ", "Average heartbeat: ") .. format(sumHz / countHz, 1) .. " Hz" .. text(" · plus bas : ", " · lowest: ") .. format(minHz, 1) .. " Hz"
					.. text(" · instances : ", " · instances: ") .. format(last and last.Instances) .. text("\nUn cycle sous 50 Hz signale un serveur surchargé (scripts lourds, physique).", "\nA heartbeat under 50 Hz means an overloaded server (heavy scripts, physics)."))
				or text("Pas encore de relevé.", "No readings yet.")
			hzChart.Set(series(history, "HeartbeatHz"), data.HistorySize)
			memoryChart.Set(series(history, "MemoryMb"), data.HistorySize)
			receiveChart.Set(series(history, "ReceiveKbps"), data.HistorySize)
			sendChart.Set(series(history, "SendKbps"), data.HistorySize)
			local stores = data.DataStores
			if type(stores) == "table" then
				storeTile.Value.Text = format(stores.Total)
				storeTile.Detail.Text = format(stores.Errors) .. text(" erreur(s)", " error(s)")
				storeInfo.Text = format(stores.Total) .. text(" appel(s) DataStore suivis sur ce serveur, dont ", " tracked DataStore call(s) on this server, ") .. format(stores.Errors) .. text(" en erreur (rouge).", " errored (red).")
				callsChart.Set(series(history, "Calls", "Errors"), data.HistorySize)
				local rows = {}
				for _, entry in stores.Stores or {} do
					table.insert(rows, { Label = entry.Name, Value = entry.Calls, Bad = entry.Errors, Detail = format(entry.Reads) .. text(" lecture(s) · ", " read(s) · ") .. format(entry.Writes)
							.. text(" écriture(s) · ", " write(s) · ") .. format(entry.Errors) .. text(" erreur(s) · ", " error(s) · ") .. format(entry.AverageMs) .. text(" ms en moyenne", " ms average") })
				end
				storesChart.Set(rows)
				rows = {}
				for _, entry in stores.Keys or {} do
					table.insert(rows, { Label = entry.Key, Value = entry.Calls, Bad = entry.Errors, Detail = entry.Store .. " · " .. format(entry.Reads) .. " R · " .. format(entry.Writes) .. " W" })
				end
				keysChart.Set(rows)
				local budgets = {}
				for _, entry in stores.Budgets or {} do table.insert(budgets, entry.Kind .. " : " .. format(entry.Budget)) end
				budgetInfo.Text = #budgets > 0 and (text("Budget de requêtes restant (tout le jeu, ce serveur) : ", "Remaining request budget (whole game, this server): ") .. table.concat(budgets, " · "))
					or text("Budget de requêtes indisponible (DataStores inaccessibles ou mode mémoire).", "Request budget unavailable (DataStores unreachable or memory mode).")
			end
		end
	end
	local loading = false
	local lastRefresh = -math.huge
	local function refresh()
		if not alive() or loading or os.clock() - lastRefresh < 2 then return end
		loading = true
		lastRefresh = os.clock()
		refreshButton.Active = false
		refreshButton.Text = Core.L("Common.Loading")
		task.spawn(function()
			local ok, data = pcall(function()
				return R.GetStats:InvokeServer()
			end)
			loading = false
			if not alive() then return end
			refreshButton.Active = true
			refreshButton.Text = Core.L("Common.Refresh")
			render(ok and data or nil)
		end)
	end
	refreshButton.Activated:Connect(refresh)
	Core.On(Core.AccessChanged.Event, function()
		permissions()
		if page.Visible then refresh() end
	end)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then refresh() end
	end)
	permissions()
	task.spawn(function()
		while alive() do
			task.wait(1)
			if alive() and page.Visible and Core.Gui and Core.Gui.Enabled and os.clock() - lastRefresh >= 15 then refresh() end
		end
	end)
end
return Page
