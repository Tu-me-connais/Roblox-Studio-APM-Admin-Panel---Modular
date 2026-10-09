-- Sentinel dashboard: real bounded server diagnostics; synthetic tests are clearly identified.
local Page = { Id = "Sentinel", Order = 9, Label = { fr = "Sentinel Guard", en = "Sentinel Guard" } }
function Page.Visible(Core) return Core.HasPermission("Sentinel.View") end
function Page.Build(Core, page)
	local UI, T, R = Core.UI, Core.T, Core.R
	local mine = Core.Session
	local function text(fr, en) return Core.Text({ fr = fr, en = en }) end
	local function alive() return Core.Alive(mine) and page.Parent ~= nil end
	local scroll = UI.scroll({ Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)
	local heading = UI.card(scroll, 1)
	UI.sectionHeader("SENTINEL GUARD", T.accent, heading, 1)
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12,
		TextColor3 = T.sub, LayoutOrder = 2, Text = text("Observation par défaut. Les alertes sont des indices à examiner, avec tolérances de latence, apparition, sièges et physique. Un signal isolé ne déclenche aucune sanction.",
		"Observation by default. Alerts are evidence to investigate, with latency, spawn, seat and physics tolerances. An isolated signal triggers no sanction.") }, heading)
	local summary = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 3, Text = Core.L("Common.Loading") }, heading)
	local refreshButton = UI.button({ Size = UDim2.new(1, 0, 0, 32), Text = Core.L("Common.Refresh"), LayoutOrder = 4 }, heading)
	local configCard = UI.card(scroll, 2)
	configCard.Visible = Core.HasPermission("Sentinel.Configure")
	UI.sectionHeader(text("RÉGLAGES", "SETTINGS"), T.warn, configCard, 1)
	local function switchRow(label, order)
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order }, configCard)
		UI.label({ Size = UDim2.new(1, -58, 1, 0), TextSize = 12, TextWrapped = true, Text = label }, row)
		return UI.Switch(row, false, nil, UDim2.new(1, -46, 0, 5)), row
	end
	local enabled = switchRow(text("Activer la surveillance", "Enable monitoring"), 2)
	local modeRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 }, configCard)
	local mode = UI.picker(modeRow, { { "Observation", text("Observation", "Observation") }, { "Balanced", text("Équilibré", "Balanced") }, { "Strict", text("Strict", "Strict") } }, "Observation")
	local numericFields = {}
	local fieldList = { { "Interval", "Intervalle (s, ≥ 0,5)", "Interval (s, ≥ 0.5)" }, { "MaxHorizontalSpeed", "Vitesse horizontale tolérée", "Horizontal speed tolerance" },
		{ "TeleportDistance", "Distance de téléportation (studs)", "Teleport distance (studs)" }, { "RequiredSamples", "Échantillons suspects répétés (≥ 3)", "Repeated suspicious samples (≥ 3)" },
		{ "SpawnGrace", "Grâce après apparition (s)", "Spawn grace (s)" }, { "LatencyAllowance", "Marge réseau (studs)", "Network slack (studs)" } }
	for index, field in fieldList do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 + index }, configCard)
		UI.label({ Size = UDim2.new(0.7, -8, 1, 0), TextSize = 12, TextWrapped = true, Text = text(field[2], field[3]) }, row)
		numericFields[field[1]] = UI.input({ Size = UDim2.new(0.3, 0, 1, 0), Position = UDim2.fromScale(0.7, 0), TextSize = 13 }, row)
	end
	local notifyAdmins = switchRow(text("Alerter les administrateurs autorisés", "Notify authorized administrators"), 10)
	local correction = switchRow(text("Correction de position après preuves répétées (optionnelle)", "Position correction after repeated evidence (optional)"), 11)
	local kick, kickRow = switchRow(text("Kick par règle explicite à signaux multiples", "Kick by explicit multi-signal rule"), 12)
	kickRow.Visible = false
	local save = UI.button({ Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.accent, LayoutOrder = 13, Text = text("APPLIQUER ET ENREGISTRER", "APPLY AND SAVE") }, configCard)
	local testCard = UI.card(scroll, 3)
	testCard.Visible = Core.HasPermission("Sentinel.Test")
	UI.sectionHeader(text("DIAGNOSTIC SYNTHÉTIQUE", "SYNTHETIC DIAGNOSTIC"), T.good, testCard, 1)
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub, LayoutOrder = 2,
		Text = text("Teste le classificateur serveur avec des données synthétiques. Aucun déplacement, grade ou sanction réel. Pour tester les capacités du jeu, utiliser les exemptions serveur documentées.",
		"Tests the server classifier with synthetic data. No real movement, rank or sanction. Use documented server exemptions to test game abilities.") }, testCard)
	local scenarioRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 }, testCard)
	local scenario = UI.picker(scenarioRow, { { "normal", text("Mouvement normal", "Normal movement") }, { "speed", text("Vitesse excessive", "Excessive speed") },
		{ "teleport", text("Téléportation excessive", "Excessive teleport") }, { "grace", text("Grâce : signal ignoré", "Grace: signal ignored") } }, "normal")
	local testButton = UI.button({ Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.good, LayoutOrder = 4, Text = text("EXÉCUTER LE DIAGNOSTIC", "RUN DIAGNOSTIC") }, testCard)
	local historyCard = UI.card(scroll, 4)
	UI.sectionHeader(text("HISTORIQUE DES ALERTES", "ALERT HISTORY"), T.warn, historyCard, 1)
	local history = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, historyCard)
	UI.list(history, 7)
	local rows, loading = {}, false
	local function render(snapshot)
		if not alive() then return end
		if type(snapshot) ~= "table" or snapshot.Allowed ~= true then summary.Text = text("Accès refusé ou service indisponible.", "Access denied or service unavailable."); return end
		local cfg = snapshot.Config or {}
		summary.Text = tostring(cfg.Mode or "Observation") .. " · " .. tostring(snapshot.TrackedPlayers or 0) .. text(" joueurs suivis · ", " tracked players · ")
			.. tostring(snapshot.TotalAlerts or 0) .. text(" alertes · ", " alerts · ") .. tostring(snapshot.SamplePasses or 0) .. text(" cycles.", " passes.")
		if not cfg.Enabled then summary.Text = text("Surveillance désactivée. ", "Monitoring disabled. ") .. summary.Text end
		if snapshot.Disabled then summary.Text = text("Module désactivé par Settings.Modules côté serveur.", "Module disabled by server Settings.Modules.") end
		configCard.Visible = not snapshot.Disabled and Core.HasPermission("Sentinel.Configure")
		enabled.Set(cfg.Enabled == true)
		mode.Set(cfg.Mode or "Observation")
		for key, box in numericFields do box.Text = tostring(cfg[key] or "") end
		notifyAdmins.Set(cfg.NotifyAdmins == true)
		correction.Set(cfg.CorrectPosition == true)
		kick.Set(cfg.EnableKick == true)
		kickRow.Visible = snapshot.KickAllowedByServer == true
		for _, row in rows do row:Destroy() end
		table.clear(rows)
		for index, alert in snapshot.Alerts or {} do
			if index > 100 then break end
			local card = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel,
				LayoutOrder = index, Corner = 8, Stroke = alert.Test and T.good or T.warn }, history)
			table.insert(rows, card)
			UI.list(card, 5)
			UI.padding(card, 8)
			UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, Font = T.fontBold,
				TextSize = 12, LayoutOrder = 1, Text = (alert.Test and "TEST · " or "") .. tostring(alert.Name or "?") .. " · " .. tostring(alert.Kind or "") .. " · " .. Core.FormatDate(alert.Time) }, card)
			UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub, LayoutOrder = 2, Text = tostring(alert.Detail or "") }, card)
			UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = alert.Test and T.good or T.warn, LayoutOrder = 3,
				Text = tostring(alert.Reaction or "Logged") .. " · " .. tostring(alert.Confidence or "") }, card)
		end
		if #rows == 0 then
			local empty = UI.label({ Size = UDim2.new(1, 0, 0, 30), TextSize = 12, TextColor3 = T.sub, Text = text("Aucune alerte enregistrée.", "No alerts recorded.") }, history)
			table.insert(rows, empty)
		end
	end
	local function refresh()
		if loading or not alive() then return end
		loading = true
		refreshButton.Text = Core.L("Common.Loading")
		task.spawn(function()
			local ok, snapshot = pcall(function() return R.GetSentinel:InvokeServer() end)
			loading = false
			if not alive() then return end
			refreshButton.Text = Core.L("Common.Refresh")
			if ok then render(snapshot) else summary.Text = Core.L("Common.ServerError") end
		end)
	end
	UI.Confirmable(save, true, function()
		local patch = { Enabled = enabled.Get(), Mode = mode.Get(), NotifyAdmins = notifyAdmins.Get(), CorrectPosition = correction.Get(), EnableKick = kick.Get() }
		for key, box in numericFields do
			local number = tonumber(box.Text)
			if number == nil then Core.Toast(text("Nombre invalide.", "Invalid number."), false); return end
			patch[key] = number
		end
		task.spawn(function()
			local ok, success, reply = pcall(function() return R.ConfigureSentinel:InvokeServer(patch) end)
			if not alive() then return end
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success then refresh() end
		end)
	end)
	testButton.Activated:Connect(function()
		task.spawn(function()
			local ok, success, reply = pcall(function() return R.TestSentinel:InvokeServer(scenario.Get()) end)
			if not alive() then return end
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success then refresh() end
		end)
	end)
	refreshButton.Activated:Connect(refresh)
	Core.On(Core.AccessChanged.Event, function()
		configCard.Visible = Core.HasPermission("Sentinel.Configure")
		testCard.Visible = Core.HasPermission("Sentinel.Test")
		Core.SetTabVisible("Sentinel", Core.HasPermission("Sentinel.View"))
		if page.Visible then refresh() end
	end)
	page:GetPropertyChangedSignal("Visible"):Connect(function() if page.Visible then refresh() end end)
end
return Page
