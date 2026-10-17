-- Central dashboard; optional sections use the same private, permission-filtered transport.
local Page = { Id = "Home", Order = 0, Label = { fr = "Accueil", en = "Home", es = "Inicio", pt = "Início", de = "Start" } }
function Page.Visible(Core)
	return Core.HasPermission("APM.AccessPanel")
end
function Page.Build(Core, page)
	local UI, T, R = Core.UI, Core.T, Core.R
	local mine = Core.Session
	local function text(fr, en)
		return Core.Text({ fr = fr, en = en })
	end
	local function alive()
		return Core.Alive(mine) and page.Parent ~= nil
	end
	local function diagnosticsAllowed()
		return Core.ActualOwner or Core.HasPermission("APM.Simulate")
	end
	local function number(value, decimals)
		if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return "—" end
		return string.format("%." .. tostring(decimals or 0) .. "f", value)
	end
	local function value(item)
		return item ~= nil and tostring(item) or text("Indisponible", "Unavailable")
	end
	local function yes(item)
		return item == nil and "—" or text(item and "Oui" or "Non", item and "Yes" or "No")
	end
	local function duration(seconds)
		if type(seconds) ~= "number" then return "—" end
		return Core.L("Time.HourMinSec", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, math.floor(seconds % 60))
	end
	local function timestamp(item)
		return type(item) == "number" and os.date("!" .. Core.L("Date.Format"), item) .. " UTC" or "—"
	end
	local playerQuery, playerOffset, nextPlayerOffset = "", 0, nil
	local expandedPlayers = {}
	local scroll = UI.scroll({ Name = "HomeScroll", Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)
	local heading = UI.card(scroll, 1)
	heading.Name = "DashboardHeader"
	UI.sectionHeader(text("TABLEAU DE BORD", "DASHBOARD"), T.accent, heading, 1)
	local status = UI.label({ Name = "DashboardStatus", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12,
		TextColor3 = T.sub, LayoutOrder = 2, Text = Core.L("Common.Loading") }, heading)
	local refreshButton = UI.button({ Name = "RefreshDashboard", Size = UDim2.new(1, 0, 0, 32), Text = Core.L("Common.Refresh"), BackgroundColor3=T.panel, Stroke=T.stroke, LayoutOrder = 3 }, heading)

 local configurationLabel=UI.label({Name="ActiveConfiguration",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true,TextSize=12,TextColor3=T.sub,LayoutOrder=4,Text=""},heading)
 local developerState=UI.label({Name="DeveloperState",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true,TextSize=12,TextColor3=T.sub,LayoutOrder=5,Text=""},heading)
 local quick=UI.new("Frame",{Name="DeveloperShortcuts",Size=UDim2.new(1,0,0,32),BackgroundTransparency=1,LayoutOrder=6},heading)
 local openSettings=UI.button({Name="OpenHomePermissions",Size=UDim2.new(1/3,-5,1,0),Text=text("Permissions","Permissions"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=12},quick)
 local openDiagnostics=UI.button({Name="OpenHomeDiagnostics",Size=UDim2.new(1/3,-5,1,0),Position=UDim2.new(1/3,2,0,0),Text=text("Diagnostics","Diagnostics"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=12},quick)
 local preferencesButton=UI.button({Name="ToggleOpeningPreferences",Size=UDim2.new(1/3,-5,1,0),Position=UDim2.new(2/3,4,0,0),Text=text("Préférences","Preferences"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=12},quick)
 local preferences=UI.new("Frame",{Name="PersonalPreferences",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,LayoutOrder=7,Visible=false},heading)
 UI.list(preferences,6)
 require(script.Parent.Parent:WaitForChild("Launcher")).BuildSettings(Core,preferences,1)
 preferencesButton.Activated:Connect(function() preferences.Visible=not preferences.Visible end)
 -- Sentinel : interrupteur personnel, visible dès l'accueil (la fermeture de l'APM ne l'éteint jamais)
 pcall(function() require(script.Parent.Parent:WaitForChild("Assistant")).BuildHomeRow(Core,heading,8) end)
 openSettings.Activated:Connect(function()
  if Core.OpenPermissionEditor then Core.OpenPermissionEditor("")
  elseif Core.TabButtons.Settings and Core.TabButtons.Settings.Visible then Core.SelectPage("Settings") end
 end)
 openDiagnostics.Activated:Connect(function()
  if Core.TabButtons.Diagnostics and Core.TabButtons.Diagnostics.Visible then Core.SelectPage("Diagnostics") end
 end)
	local grid = UI.new("Frame", { Name = "SummaryCards", Size = UDim2.new(1, -6, 0, 224), BackgroundTransparency = 1, LayoutOrder = 2 }, scroll)
	local layout = UI.new("UIGridLayout", { CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local metrics = {}
	local function metric(name, title, color, order)
		local card = UI.card(grid, order)
		card.Name = name
		card.AutomaticSize = Enum.AutomaticSize.None
		UI.sectionHeader(title, color, card, 1)
		local value = UI.label({ Name = "Value", Size = UDim2.new(1, 0, 0, 30), Font = T.fontBold, TextSize = 25, TextColor3 = color, Text = "—", LayoutOrder = 2 }, card)
		local detail = UI.label({ Name = "Detail", Size = UDim2.new(1, 0, 0, 28), TextSize = 11, TextWrapped = true, TextColor3 = T.sub, Text = "", LayoutOrder = 3 }, card)
		metrics[name] = { Card = card, Value = value, Detail = detail }
		return metrics[name]
	end
	local serverMetric = metric("ServerSummary", text("SERVEUR", "SERVER"), T.accent, 1)
	local systemsMetric = metric("SystemsSummary", text("SYSTÈMES DÉTECTÉS", "DETECTED SYSTEMS"), T.accent, 2)
	local operationalMetric = metric("OperationsSummary", text("OPÉRATIONNELS", "OPERATIONAL"), T.good, 3)
	local sentinelMetric = metric("SentinelSummary", "SENTINEL GUARD", T.warn, 4)
	sentinelMetric.Value.TextSize = 20
	local playersMetric = metric("PlayersSummary", text("JOUEURS EN JEU", "PLAYERS IN GAME"), T.good, 5)
	local performanceMetric = metric("PerformanceSummary", text("CYCLE SERVEUR", "SERVER HEARTBEAT"), T.accent, 6)
	local function reflow()
		if not alive() then return end
		local count = 0
		for _, entry in metrics do if entry.Card.Visible then count += 1 end end
		local cols = grid.AbsoluteSize.X >= 480 and 2 or 1
		layout.CellSize = UDim2.new(1 / cols, -(cols == 2 and 4 or 0), 0, 112)
		grid.Size = UDim2.new(1, -6, 0, math.ceil(count / cols) * 120 - 8)
	end
	Core.On(grid:GetPropertyChangedSignal("AbsoluteSize"), reflow)
	local serverCard = UI.card(scroll, 3)
	serverCard.Name = "ServerDetails"
	UI.sectionHeader(text("INFORMATIONS DU SERVEUR", "SERVER INFORMATION"), T.accent, serverCard, 1)
	local serverInfo = UI.label({ Name = "ServerInfo", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true,
		TextColor3 = T.sub, Text = Core.L("Common.Loading"), LayoutOrder = 2 }, serverCard)
	local serverIdentity = UI.label({ Name = "ServerIdentity", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12,
		TextWrapped = true, TextColor3 = T.sub, Text = "", LayoutOrder = 3 }, serverCard)
	local performanceCard = UI.card(scroll, 4)
	performanceCard.Name = "ServerPerformance"
	UI.sectionHeader(text("PERFORMANCES DU SERVEUR", "SERVER PERFORMANCE"), T.accent, performanceCard, 1)
	local performanceInfo = UI.label({ Name = "PerformanceInfo", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12,
		TextWrapped = true, TextColor3 = T.sub, Text = "", LayoutOrder = 2 }, performanceCard)
	local playersCard = UI.card(scroll, 5)
	playersCard.Name = "HomePlayers"
	UI.sectionHeader(text("JOUEURS CONNECTÉS", "CONNECTED PLAYERS"), T.accent, playersCard, 1)
	local playerSummary = UI.label({ Name = "PlayerSummary", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true,
		TextColor3 = T.sub, Text = "", LayoutOrder = 2 }, playersCard)
	local playerSearch = UI.input({ Name = "HomePlayerSearch", Size = UDim2.new(1, 0, 0, 32), PlaceholderText = text("Rechercher : pseudo, nom affiché ou UserId", "Search: username, display name or UserId"),
		TextSize = 12, LayoutOrder = 3 }, playersCard)
	local playerList = UI.new("Frame", { Name = "HomePlayerList", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		LayoutOrder = 4 }, playersCard)
	UI.list(playerList, 8)
	local playerPageStatus = UI.label({ Name = "HomePlayersPagination", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11,
		TextWrapped = true, TextColor3 = T.sub, Text = "", LayoutOrder = 5 }, playersCard)
	local paging = UI.new("Frame", { Name = "HomePlayerNavigation", Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 6 }, playersCard)
	local previousPlayers = UI.button({ Name = "PreviousPlayers", Size = UDim2.new(.5, -4, 1, 0), Text = text("Précédent", "Previous"), TextSize = 12 }, paging)
	local nextPlayers = UI.button({ Name = "NextPlayers", Size = UDim2.new(.5, -4, 1, 0), Position = UDim2.new(.5, 4, 0, 0), Text = text("Suivant", "Next"),
		TextSize = 12 }, paging)
	local bridgeCard = UI.card(scroll, 6)
	bridgeCard.Name = "AutoBridgeOverview"
	UI.sectionHeader("AUTOBRIDGE", T.accent, bridgeCard, 1)
	local bridgeInfo = UI.label({ Name = "IntegrationStatus", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true,
		TextColor3 = T.sub, LayoutOrder = 2 }, bridgeCard)
	local systems = UI.label({ Name = "DetectedSystems", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true,
		LayoutOrder = 3 }, bridgeCard)
	local bridgeErrors = UI.label({ Name = "IntegrationErrors", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12,
		TextWrapped = true, TextColor3 = T.bad, LayoutOrder = 4, Visible = false }, bridgeCard)
	local detailsButton = UI.button({ Name = "OpenAutoBridgeDetails", Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.accent, Text = text("INTÉGRATIONS ET RÉGLAGES", "INTEGRATIONS AND SETTINGS"),
		LayoutOrder = 5 }, bridgeCard)
	local rescan = UI.button({ Name = "RefreshAutoBridge", Size = UDim2.new(1, 0, 0, 32), Text = text("Actualiser la découverte", "Refresh discovery"),
		LayoutOrder = 6 }, bridgeCard)
	local detailFrame = UI.new("Frame", { Name = "AutoBridgeDetails", Size = UDim2.new(1, 0, 0, 540), BackgroundTransparency = 1, LayoutOrder = 7,
		Visible = false }, bridgeCard)
	local sentinelCard = UI.card(scroll, 7)
	sentinelCard.Name = "SentinelOverview"
	UI.sectionHeader("SENTINEL GUARD", T.warn, sentinelCard, 1)
	local sentinelInfo = UI.label({ Name = "SentinelStatus", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true,
		TextColor3 = T.sub, LayoutOrder = 2 }, sentinelCard)
	local alerts = UI.label({ Name = "RecentAlerts", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true,
		LayoutOrder = 3 }, sentinelCard)
	local sentinelOpen = UI.button({ Name = "OpenSentinel", Size = UDim2.new(1, 0, 0, 32), Text = text("Consulter Sentinel Guard", "Open Sentinel Guard"),
		LayoutOrder = 4 }, sentinelCard)
	local diagnosticCard = UI.card(scroll, 8)
	diagnosticCard.Name = "HomeDiagnostics"
	UI.sectionHeader(text("DIAGNOSTICS", "DIAGNOSTICS"), T.accent, diagnosticCard, 1)
	local diagnosticInfo = UI.label({ Name = "DiagnosticsStatus", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12,
		TextWrapped = true, TextColor3 = T.sub, LayoutOrder = 2 }, diagnosticCard)
	local diagnosticOpen = UI.button({ Name = "OpenDiagnostics", Size = UDim2.new(1, 0, 0, 32), Text = text("Diagnostics détaillés", "Detailed diagnostics"),
		LayoutOrder = 3 }, diagnosticCard)
	-- Crédits : toujours tout en bas de l'accueil (marge dessous pour rester lisible sous un bandeau d'information)
	UI.label({ Name = "Credits", Size = UDim2.new(1, -6, 0, 64), LayoutOrder = 1000, TextSize = 12, TextColor3 = T.sub,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top, Text = "APM · " .. text("Créé par ", "Made by ") .. "APM contributors" }, scroll)
	local STATUS = { Detected = { "Détecté", "Detected" }, Compatible = { "Compatible", "Compatible" }, Operational = { "Opérationnel", "Operational" },
		Unsupported = { "Non pris en charge", "Unsupported" }, Error = { "Erreur d'intégration", "Integration error" } }
	local function permissions()
		if not alive() then return end
  configurationLabel.Visible=diagnosticsAllowed()
  developerState.Visible=diagnosticsAllowed()
  openSettings.Visible=Core.HasPermission("APM.ManagePermissions")
  openDiagnostics.Visible=diagnosticsAllowed()
		local bridge = Core.HasPermission("AutoBridge.View")
		local sentinel = Core.HasPermission("Sentinel.View")
		systemsMetric.Card.Visible = bridge
		operationalMetric.Card.Visible = bridge
		bridgeCard.Visible = bridge
		sentinelMetric.Card.Visible = sentinel
		sentinelCard.Visible = sentinel
		diagnosticCard.Visible = diagnosticsAllowed()
		performanceMetric.Card.Visible = diagnosticsAllowed()
		performanceCard.Visible = diagnosticsAllowed()
		if not bridge then
			detailFrame.Visible = false
			systems.Text = ""
			bridgeInfo.Text = ""
			bridgeErrors.Text = ""
			bridgeErrors.Visible = false
			systemsMetric.Value.Text = "—"
			operationalMetric.Value.Text = "—"
		end
		if not sentinel then
			alerts.Text = ""
			sentinelInfo.Text = ""
			sentinelMetric.Value.Text = "—"
		end
		if not diagnosticsAllowed() then
			diagnosticInfo.Text = ""
			performanceInfo.Text = ""
			performanceMetric.Value.Text = "—"
			performanceMetric.Detail.Text = ""
		end
		reflow()
	end
	local function clearPlayers()
		for _, child in playerList:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
	end
	local CHARACTER = { Alive = { "Vivant", "Alive" }, Dead = { "Mort", "Dead" }, Absent = { "Sans personnage", "No character" }, Loading = { "Chargement",
		"Loading" } }
	local function renderPlayers(data)
		clearPlayers()
		if type(data) ~= "table" or type(data.Summary) ~= "table" then
			playerSummary.Text = text("Données joueurs indisponibles.", "Player data unavailable.")
			playerPageStatus.Text = ""
			playersMetric.Value.Text = "—"
			playersMetric.Detail.Text = ""
			previousPlayers.Active = false
			nextPlayers.Active = false
			return
		end
		local summary = data.Summary
		playersMetric.Value.Text = number(summary.Alive)
		playersMetric.Detail.Text = text("vivants · ", "alive · ") .. number(summary.Admins) .. text(" accès APM", " with APM access")
		playerSummary.Text = number(summary.Connected) .. text(" connectés · ", " connected · ") .. number(summary.Alive) .. text(" vivants · ", " alive · ") .. number(summary.Dead) .. text(" morts · ", " dead · ") .. number(summary.NoCharacter) .. text(" sans personnage prêt", " without ready character")
			.. "\n" .. number(summary.Admins) .. text(" accès APM · ", " with APM access · ") .. number(summary.TeamCount) .. text(" équipes · latence moyenne : ", " teams · average latency: ") .. number(summary.AveragePingMs, 1) .. " ms"
		playerOffset = data.Offset or 0
		nextPlayerOffset = data.NextOffset
		previousPlayers.Active = playerOffset > 0
		nextPlayers.Active = nextPlayerOffset ~= nil
		previousPlayers.TextTransparency = previousPlayers.Active and 0 or .5
		nextPlayers.TextTransparency = nextPlayers.Active and 0 or .5
		local rows = data.Rows or {}
		playerPageStatus.Text = (#rows > 0 and tostring(playerOffset + 1) .. "–" .. tostring(playerOffset + #rows) or "0") .. " / " .. tostring(data.Total or 0) .. text(" résultat(s) · recherche sur tous les joueurs connectés", " result(s) · searches all connected players")
		if #rows == 0 then UI.label({ Name = "NoMatchingPlayers", Size = UDim2.new(1, 0, 0, 28), TextColor3 = T.sub, Text = text("Aucun joueur ne correspond.", "No matching players.") }, playerList) end
		for index, entry in rows do
			local card = UI.card(playerList, index)
			card.Name = "HomePlayer_" .. tostring(entry.UserId)
			card.BackgroundColor3 = T.panel
			local rank = entry.RankResolved and (entry.Rank == "None" and text("Sans grade", "No rank") or Core.L("Rank." .. tostring(entry.Rank))) or text("Grade en cours de résolution", "Resolving rank")
			local headingButton = UI.button({ Name = "TogglePlayerDetails", Size = UDim2.new(1, 0, 0, 34), Text = value(entry.DisplayName) .. "  @" .. value(entry.Name),
				TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1 }, card)
			UI.label({ Name = "PlayerQuickInfo", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextWrapped = true, TextColor3 = T.sub,
				LayoutOrder = 2,
				Text = rank .. " · " .. (entry.Team or text("Sans équipe", "No team")) .. " · " .. number(entry.PingMs, 1) .. " ms · " .. duration(entry.SessionSeconds) }, card)
			local details = UI.label({ Name = "PlayerDetails", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextWrapped = true,
				TextColor3 = T.sub, LayoutOrder = 3, Visible = expandedPlayers[entry.UserId] == true }, card)
			local body = entry.Character or {}
			local labels = CHARACTER[body.Status] or CHARACTER.Loading
			local lines = { "UserId : " .. value(entry.UserId), text("Compte créé depuis : ", "Account age: ") .. number(entry.AccountAgeDays) .. text(" jours · badge vérifié : ", " days · verified badge: ") .. yes(entry.VerifiedBadge),
				text("Grade : ", "Rank: ") .. rank .. text(" · accès APM : ", " · APM access: ") .. yes(entry.PanelAccess),
				text("Équipe : ", "Team: ") .. (entry.Team or text("Aucune", "None")) .. text(" · neutre : ", " · neutral: ") .. yes(entry.Neutral),
				text("Arrivée suivie : ", "Observed arrival: ") .. timestamp(entry.JoinedAt), text("Temps suivi sur ce serveur : ", "Time tracked on this server: ") .. duration(entry.SessionSeconds),
				text("Ping aller-retour : ", "Round-trip ping: ") .. number(entry.PingMs, 1) .. " ms", text("Personnage : ", "Character: ") .. text(labels[1], labels[2]) }
			if body.Status ~= "Absent" and body.Status ~= "Loading" then
				table.insert(lines, text("Santé : ", "Health: ") .. number(body.Health, 1) .. " / " .. number(body.MaxHealth, 1) .. " · " .. value(body.RigType) .. " · " .. value(body.State))
				table.insert(lines, text("Vitesse : ", "Walk speed: ") .. number(body.WalkSpeed, 1) .. " · " .. text(body.JumpMode == "Power" and "Puissance de saut : " or "Hauteur de saut : ", body.JumpMode == "Power" and "Jump power: " or "Jump height: ") .. number(body.JumpValue, 1) .. text(" · assis : ", " · seated: ") .. yes(body.Seated))
			end
			if body.Position then table.insert(lines, text("Position : ", "Position: ") .. number(body.Position.X, 1) .. ", " .. number(body.Position.Y, 1) .. ", " .. number(body.Position.Z, 1)) end
			local stats = {}
			for _, stat in entry.Leaderstats or {} do table.insert(stats, value(stat.Name) .. " = " .. value(stat.Value)) end
			table.insert(lines, "Leaderstats : " .. (#stats > 0 and table.concat(stats, " · ") or text("aucune valeur", "no values")))
			if entry.LeaderstatsTruncated then table.insert(lines, text("Liste des leaderstats partielle : limite de 40 valeurs.", "Partial leaderstats list: limit of 40 values.")) end
			details.Text = table.concat(lines, "\n")
			headingButton.Activated:Connect(function()
				if alive() then
					expandedPlayers[entry.UserId] = not details.Visible
					details.Visible = expandedPlayers[entry.UserId]
				end
			end)
		end
	end
	local function renderBridge(data)
		if not alive() or not Core.HasPermission("AutoBridge.View") then return end
		if type(data) ~= "table" or data.Allowed ~= true or data.Unavailable then
			systemsMetric.Value.Text = "—"
			systemsMetric.Detail.Text = text("Données indisponibles", "Data unavailable")
			operationalMetric.Value.Text = "—"
			operationalMetric.Detail.Text = ""
			bridgeInfo.Text = text("AutoBridge indisponible. Réessayez l'actualisation.", "AutoBridge unavailable. Try refreshing.")
			systems.Text = ""
			bridgeErrors.Visible = false
			return
		end
		if data.Disabled or not data.Enabled then
			systemsMetric.Value.Text = "—"
			systemsMetric.Detail.Text = text("AutoBridge désactivé", "AutoBridge disabled")
			operationalMetric.Value.Text = "—"
			operationalMetric.Detail.Text = ""
			bridgeInfo.Text = text("Découverte désactivée ; aucun comptage courant disponible.", "Discovery disabled; current counts unavailable.")
			systems.Text = ""
			bridgeErrors.Visible = false
			return
		end
		local detected, compatible, operational, errors = 0, 0, 0, 0
		local rows, errorRows = {}, {}
		for _, entry in data.Systems or {} do
			local state = entry.Status
			if (entry.Count or 0) > 0 or state == "Detected" or state == "Compatible" or state == "Operational" then detected += 1 end
			if state == "Compatible" or state == "Operational" then compatible += 1 end
			if state == "Operational" then operational += 1 end
			if state == "Error" then
				errors += 1
				table.insert(errorRows, Core.Text(entry.DisplayName or entry.Name or entry.Id) .. " : " .. Core.Text(entry.Detail))
			end
			local labels = STATUS[state] or STATUS.Detected
			if #rows < 6 then table.insert(rows, Core.Text(entry.DisplayName or entry.Name or entry.Id) .. " · " .. text(labels[1], labels[2])) end
		end
		systemsMetric.Value.Text = tostring(detected)
		systemsMetric.Detail.Text = tostring(compatible) .. text(" compatible(s)", " compatible") .. (data.Truncated and text(" · partiel", " · partial") or "")
		operationalMetric.Value.Text = tostring(operational)
		operationalMetric.Detail.Text = tostring(errors) .. text(" erreur(s) d'intégration", " integration error(s)")
		bridgeInfo.Text = tostring(#(data.Systems or {})) .. text(" systèmes examinés. ", " systems checked. ")
			.. text("Les états concernent les fonctionnalités déclarées par les adaptateurs.", "States describe the features declared by adapters.")
		if data.ScanAge ~= nil then bridgeInfo.Text ..= text(" Scan datant de ", " Scan age: ") .. tostring(data.ScanAge) .. " s." end
		if data.Truncated then bridgeInfo.Text ..= text(" Analyse partielle : limite de parcours atteinte.", " Partial scan: traversal limit reached.") end
		systems.Text = table.concat(rows, "\n")
		if #(data.Systems or {}) > 6 then systems.Text ..= text("\nVoir les intégrations pour la liste complète.", "\nOpen integrations for the full list.") end
		bridgeErrors.Text = table.concat(errorRows, "\n")
		bridgeErrors.Visible = #errorRows > 0
	end
	local function render(data)
		if not alive() then return end
		permissions()
		if type(data) ~= "table" or type(data.Server) ~= "table" then
			status.Text = text("Données indisponibles. Réessayez l'actualisation.", "Data unavailable. Try refreshing.")
   configurationLabel.Text=text("Configuration active : relevé indisponible.","Active configuration: snapshot unavailable.")
   developerState.Text=Core.MemoryMode and text("Studio · changements limités à cette session.","Studio · changes last for this session only.") or ""
			for _, entry in metrics do
				entry.Value.Text = "—"
				entry.Detail.Text = text("Données indisponibles", "Data unavailable")
			end
			serverInfo.Text = text("Informations du serveur indisponibles.", "Server information unavailable.")
			serverIdentity.Text = ""
			performanceInfo.Text = text("Mesures indisponibles.", "Readings unavailable.")
			renderPlayers(nil)
			bridgeInfo.Text = Core.HasPermission("AutoBridge.View") and text("AutoBridge indisponible. Réessayez l'actualisation.", "AutoBridge unavailable. Try refreshing.") or ""
			systems.Text = ""
			bridgeErrors.Text = ""
			bridgeErrors.Visible = false
			detailFrame.Visible = false
			detailsButton.Text = text("INTÉGRATIONS ET RÉGLAGES", "INTEGRATIONS AND SETTINGS")
			sentinelInfo.Text = Core.HasPermission("Sentinel.View") and text("Sentinel indisponible.", "Sentinel unavailable.") or ""
			alerts.Text = ""
			diagnosticInfo.Text = diagnosticsAllowed() and text("Diagnostics indisponibles.", "Diagnostics unavailable.") or ""
			return
		end
		status.Text = text("Dernier relevé serveur : ", "Last server snapshot: ") .. os.date("%H:%M:%S", data.GeneratedAt)
		local s = data.Server
		serverMetric.Value.Text = tostring(s.Players) .. " / " .. tostring(s.MaxPlayers)
		serverMetric.Detail.Text = text("joueurs connectés", "players connected")
		local serverTypes = { Studio = { "Studio", "Studio" }, Private = { "Privé", "Private" }, Reserved = { "Réservé", "Reserved" }, Public = { "Public",
			"Public" } }
		local kind = serverTypes[s.Type] or serverTypes.Public
		serverInfo.Text = value(s.PlaceName) .. " · " .. text(kind[1], kind[2])
			.. text("\nDurée du serveur : ", "\nServer uptime: ") .. duration(s.UptimeSeconds) .. text(" · places libres : ", " · available slots: ") .. number(s.AvailableSlots)
			.. " · " .. text(s.Locked and "Entrées verrouillées" or "Entrées ouvertes", s.Locked and "Joining locked" or "Joining open")
			.. "\n" .. text(s.MemoryMode and "Mode mémoire : changements non enregistrés." or "Stockage persistant configuré.", s.MemoryMode and "Memory mode: changes are not saved." or "Persistent storage configured.")
			.. text("\nPic de joueurs : ", "\nPeak players: ") .. number(s.PeakPlayers) .. text(" · arrivées suivies : ", " · tracked arrivals: ") .. number(s.ObservedJoins) .. text(" · départs suivis : ", " · tracked departures: ") .. number(s.ObservedLeaves)
		serverIdentity.Text = "PlaceId : " .. value(s.PlaceId) .. " · UniverseId : " .. value(s.UniverseId) .. text(" · version de place : ", " · place version: ") .. value(s.PlaceVersion)
			.. "\nJobId : " .. value(s.JobId) .. "\nPrivateServerId : " .. value(s.PrivateServerId) .. text(" · propriétaire privé : ", " · private owner: ") .. value(s.PrivateServerOwnerId)
			.. text("\nCréateur : ", "\nCreator: ") .. value(s.CreatorName) .. " · " .. value(s.CreatorType) .. " " .. value(s.CreatorId)
			.. text("\nDébut du serveur : ", "\nServer start: ") .. timestamp(s.StartedAt)
			.. text("\nGravité : ", "\nGravity: ") .. number(s.Gravity, 1) .. text(" · seuil de destruction : ", " · destruction height: ") .. number(s.FallenPartsDestroyHeight, 1)
			.. text("\nStreaming : ", "\nStreaming: ") .. yes(s.StreamingEnabled) .. (s.StreamingEnabled and (text(" · rayons min/cible : ", " · min/target radius: ") .. number(s.StreamingMinRadius) .. " / " .. number(s.StreamingTargetRadius)) or "")
			.. text(" · heure du jeu : ", " · game clock: ") .. number(s.GameClockTime, 2)
			.. (type(s.APM) == "table" and ("\nAPM " .. value(s.APM.Version) .. " · " .. value(s.APM.Channel) .. " · API " .. value(s.APM.ApiVersion) .. text(" · schéma données ", " · data schema ") .. value(s.APM.DataSchema)) or "")
		renderPlayers(data.Players)
		if diagnosticsAllowed() then
			local perf = data.Performance
			if type(perf) == "table" then
				performanceMetric.Value.Text = number(perf.HeartbeatHz, 1) .. " Hz"
				performanceMetric.Detail.Text = text("moyenne du cycle serveur sur 5 s", "server heartbeat average over 5 s")
				performanceInfo.Text = text("Cycle serveur : ", "Server heartbeat: ") .. number(perf.HeartbeatHz, 1) .. " Hz" .. text(" · mémoire moteur : ", " · engine memory: ") .. number(perf.MemoryMb, 1) .. " MB"
					.. text("\nInstances : ", "\nInstances: ") .. number(perf.InstanceCount) .. text(" · éléments physiques : ", " · physical primitives: ") .. number(perf.PrimitivesCount)
					.. text("\nÉléments en mouvement : ", "\nMoving primitives: ") .. number(perf.MovingPrimitivesCount) .. text(" · contacts : ", " · contacts: ") .. number(perf.ContactsCount)
					.. text("\nRéseau reçu/envoyé : ", "\nNetwork receive/send: ") .. number(perf.DataReceiveKbps, 1) .. " / " .. number(perf.DataSendKbps, 1) .. text(" Ko/s", " KB/s")
					.. text("\nRéseau physique reçu/envoyé : ", "\nPhysics receive/send: ") .. number(perf.PhysicsReceiveKbps, 1) .. " / " .. number(perf.PhysicsSendKbps, 1) .. text(" Ko/s", " KB/s")
			else
				performanceMetric.Value.Text = "—"
				performanceMetric.Detail.Text = ""
				performanceInfo.Text = text("Mesures indisponibles.", "Readings unavailable.")
			end
		end
		if Core.HasPermission("AutoBridge.View") then renderBridge(data.AutoBridge) end
		if Core.HasPermission("Sentinel.View") then
			local guard = data.Sentinel
			if type(guard) ~= "table" or guard.Unavailable then
				sentinelMetric.Value.Text = "—"
				sentinelMetric.Detail.Text = text("Données indisponibles", "Data unavailable")
				sentinelInfo.Text = text("Sentinel indisponible.", "Sentinel unavailable.")
				alerts.Text = ""
			else
				local enabled = guard.Enabled and not guard.Disabled
				local mode = guard.Mode == "Balanced" and text("Équilibré", "Balanced") or guard.Mode == "Strict" and text("Strict", "Strict") or text("Observation", "Observation")
				sentinelMetric.Value.Text = enabled and mode or text("Désactivé", "Disabled")
				sentinelMetric.Detail.Text = tostring(guard.TotalAlerts) .. text(" alerte(s), tests inclus", " alert(s), tests included")
				sentinelInfo.Text = text("Historique conservé : ", "Retained history: ") .. tostring(guard.HistoryCount)
					.. text(" · joueurs suivis : ", " · tracked players: ") .. tostring(guard.TrackedPlayers)
					.. text("\nUn signal heuristique demande une vérification des mécaniques du jeu.", "\nA heuristic signal needs review against game mechanics.")
				local lines = {}
				for _, alert in guard.RecentAlerts or {} do
					table.insert(lines, os.date("%H:%M:%S", alert.Time) .. " · " .. (alert.Test and text("TEST · ", "TEST · ") or "") .. tostring(alert.Name) .. " · " .. tostring(alert.Kind) .. "\n" .. Core.Text(alert.Detail))
				end
				alerts.Text = #lines > 0 and table.concat(lines, "\n\n") or text("Aucune alerte dans l'historique courant.", "No alerts in the current history.")
			end
		end
		if diagnosticsAllowed() then
			local d = data.Diagnostics
   local config=type(d)=="table" and d.configuration
   if type(config)=="table" then
    configurationLabel.Text=text("Configuration active : ","Active configuration: ")..tostring(config.SourcePath or "—")
    local memory=config.MemoryMode==true
    local mode=memory and text("Mode mémoire : cette session uniquement.","Memory mode: this session only.") or text("Sauvegarde persistante.","Persistent storage.")
    if memory and config.StudioMemory then mode..=text(" Choisi par StudioMemory."," Selected by StudioMemory.") end
    if config.DuplicateConfigurations then mode..=text("\nDeux configurations : le dossier ServerStorage est prioritaire.","\nTwo configurations: the ServerStorage folder takes priority.") end
    local errors=0
    for _,entry in type(d.extensions)=="table" and d.extensions.Entries or {} do if entry.Status=="Error" then errors+=1 end end
    for _,entry in Core.ExtensionDiagnostics or {} do if entry.Status=="Error" then errors+=1 end end
    developerState.Text=mode.."\n"..errors..text(" erreur(s) d'extension · ouvrir Diagnostics pour les corrections."," extension error(s) · open Diagnostics for corrections.")
    developerState.TextColor3=(errors>0 or config.DuplicateConfigurations) and T.warn or T.sub
   else configurationLabel.Text=text("Configuration active : consulter Diagnostics.","Active configuration: see Diagnostics.");developerState.Text="" end
			diagnosticInfo.Text = type(d) == "table" and text(d.sessionActive and "Session privée active" or "Session privée inactive", d.sessionActive and "Private session active" or "Private session inactive")
				.. " · " .. text(d.globalAdminRemotes and "Transport administratif global détecté" or "Transport privé", d.globalAdminRemotes and "Global administrative transport detected" or "Private transport")
				.. "\n" .. text(d.simulation and d.simulation.active and "Simulation en cours" or "Contexte réel", d.simulation and d.simulation.active and "Simulation in progress" or "Real context")
				.. (type(d.core) == "table" and ("\nAPM " .. tostring(d.core.Version) .. " · " .. tostring(d.core.Channel) .. " · API " .. tostring(d.core.ApiVersion)) or "")
				.. (type(d.extensions) == "table" and ("\n" .. text("Extensions : consulter les diagnostics détaillés.", "Extensions: see detailed diagnostics.")) or "")
				or text("Diagnostics indisponibles.", "Diagnostics unavailable.")
		end
	end
	local loading = false
	local lastRefresh = -math.huge
	local panel
	local generation = 0
	local pendingRefresh = false
	local function refresh()
		if not alive() or not Core.HasPermission("APM.AccessPanel") then return end
		if loading or os.clock() - lastRefresh < 2 then
			pendingRefresh = true
			return
		end
		pendingRefresh = false
		loading = true
		lastRefresh = os.clock()
		refreshButton.Active = false
		refreshButton.Text = Core.L("Common.Loading")
		previousPlayers.Active = false
		nextPlayers.Active = false
		local requestGeneration = generation
		local options = { Search = playerQuery, Offset = playerOffset }
		task.spawn(function()
			local ok, data = pcall(function()
				return R.GetHomeSnapshot:InvokeServer(options)
			end)
			loading = false
			if not alive() then return end
			refreshButton.Active = true
			refreshButton.Text = Core.L("Common.Refresh")
			if requestGeneration == generation then render(ok and data or nil) end
			if pendingRefresh then
				task.delay(2, function()
					if alive() then refresh() end
				end)
			end
		end)
	end
	local function changeQuery()
		generation += 1
		refresh()
	end
	local searchGeneration = 0
	playerSearch:GetPropertyChangedSignal("Text"):Connect(function()
		searchGeneration += 1
		local token = searchGeneration
		task.delay(.35, function()
			if not alive() or token ~= searchGeneration then return end
			local input = playerSearch.Text
			local endAt = utf8.offset(input, 33)
			playerQuery = endAt and input:sub(1, endAt - 1) or input
			while #playerQuery > 64 do
				local boundary = utf8.offset(playerQuery, -1)
				playerQuery = playerQuery:sub(1, boundary - 1)
			end
			playerOffset = 0
			changeQuery()
		end)
	end)
	previousPlayers.Activated:Connect(function()
		if alive() and previousPlayers.Active then
			playerOffset = math.max(0, playerOffset - 20)
			changeQuery()
		end
	end)
	nextPlayers.Activated:Connect(function()
		if alive() and nextPlayers.Active and nextPlayerOffset then
			playerOffset = nextPlayerOffset
			changeQuery()
		end
	end)
	local bridgeLoading = false
	rescan.Activated:Connect(function()
		if bridgeLoading or not alive() or not Core.HasPermission("AutoBridge.View") then return end
		bridgeLoading = true
		rescan.Active = false
		rescan.Text = Core.L("Common.Loading")
		task.spawn(function()
			local ok, success, data = pcall(function()
				return R.RefreshAutoBridge:InvokeServer()
			end)
			bridgeLoading = false
			if not alive() then return end
			rescan.Active = true
			rescan.Text = text("Actualiser la découverte", "Refresh discovery")
			if not Core.HasPermission("AutoBridge.View") then
				permissions()
				return
			end
			if ok and success then
				renderBridge(data)
				if panel and detailFrame.Visible then panel.Refresh(false) end
			else
				Core.Toast(ok and data or Core.L("Common.ServerError"), false)
			end
		end)
	end)
	detailsButton.Activated:Connect(function()
		if not alive() or not Core.HasPermission("AutoBridge.View") then return end
		detailFrame.Visible = not detailFrame.Visible
		detailsButton.Text = detailFrame.Visible and text("FERMER LES INTÉGRATIONS", "CLOSE INTEGRATIONS") or text("INTÉGRATIONS ET RÉGLAGES", "INTEGRATIONS AND SETTINGS")
		if detailFrame.Visible then
			if not panel then panel = require(script.Parent.Parent.Components.AutoBridgePanel).Build(Core, detailFrame, renderBridge) end
			panel.Refresh(false)
		end
	end)
	local function openTab(name, allowed)
		if not alive() or not allowed then return end
		local tab = Core.TabButtons[name]
		if tab and tab.Visible then Core.SelectPage(name) end
	end
	sentinelOpen.Activated:Connect(function()
		openTab("Sentinel", Core.HasPermission("Sentinel.View"))
	end)
	diagnosticOpen.Activated:Connect(function()
		openTab("Diagnostics", diagnosticsAllowed())
	end)
	refreshButton.Activated:Connect(refresh)
	Core.On(Core.AccessChanged.Event, function()
		permissions()
		if page.Visible then refresh() end
	end)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then refresh() end
	end)
	permissions()
	refresh()
	task.spawn(function()
		while alive() do
			task.wait(1)
			if alive() and page.Visible and Core.Gui and Core.Gui.Enabled and (pendingRefresh or os.clock() - lastRefresh >= 15) then refresh() end
		end
	end)
end
return Page
