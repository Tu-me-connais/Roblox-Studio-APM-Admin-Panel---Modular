-- Reusable AutoBridge details for Home. Owns only its child UI; requests are initiated by Refresh or its refresh button.
local Players = game:GetService("Players")
local Panel = {}

function Panel.Build(Core, parent, onSnapshot)
	local UI, T, R = Core.UI, Core.T, Core.R
	local mine = Core.Session
	local destroyed, loading, requestVersion = false, false, 0
	local connections, systemRows = {}, {}
	local state = { Allowed = false, Config = {}, Teams = {}, Systems = {} }
	local object = {}
	local function text(fr, en) return Core.Text({ fr = fr, en = en }) end
	local function alive()
		return not destroyed and Core.Alive(mine) and parent.Parent ~= nil
	end
	local function allowed(permission)
		return alive() and Core.HasPermission("APM.AccessPanel") and Core.HasPermission(permission)
	end
	local function publish(snapshot)
		if not alive() or type(onSnapshot) ~= "function" then return end
		local ok, problem = pcall(onSnapshot, snapshot)
		if not ok then warn("[APM] Résumé AutoBridge : " .. tostring(problem)) end
	end
	local scroll = UI.scroll({ Name = "AutoBridgePanel", Size = UDim2.fromScale(1, 1), Visible = allowed("AutoBridge.View") }, parent)
	object.Frame = scroll
	UI.list(scroll, 10)
	local heading = UI.card(scroll, 1)
	UI.sectionHeader("AUTOBRIDGE", T.accent, heading, 1)
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12,
		TextColor3 = T.sub, LayoutOrder = 2, Text = text("Découverte structurelle bornée. Aucun code inconnu n'est exécuté. Une intégration personnalisée nécessite un adaptateur serveur explicite.",
		"Bounded structural discovery. Unknown code is never executed. Custom integrations require an explicit server adapter.") }, heading)
	local summary = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, LayoutOrder = 3,
		Text = text("Actualisez le diagnostic.", "Refresh diagnostics.") }, heading)
	local refreshButton = UI.button({ Name = "RefreshAutoBridge", Size = UDim2.new(1, 0, 0, 32), Text = Core.L("Common.Refresh"), LayoutOrder = 4 }, heading)
	local configCard = UI.card(scroll, 2)
	configCard.Visible = false
	UI.sectionHeader(text("CONFIGURATION", "CONFIGURATION"), T.warn, configCard, 1)
	local function switchRow(label, order)
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = order }, configCard)
		UI.label({ Size = UDim2.new(1, -58, 1, 0), TextSize = 12, TextWrapped = true, Text = label }, row)
		return UI.Switch(row, false, nil, UDim2.new(1, -46, 0, 5))
	end
	local enabled = switchRow(text("Activer AutoBridge", "Enable AutoBridge"), 2)
	local teamEnabled = switchRow(text("Autoriser les changements d'équipe validés", "Allow validated team changes"), 3)
	local fields = {}
	for index, entry in { { "ScanInterval", "Cache / secondes", "Cache / seconds" }, { "MaxScanInstances", "Instances analysées au maximum", "Maximum scanned instances" } } do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 + index }, configCard)
		UI.label({ Size = UDim2.new(0.7, -8, 1, 0), TextSize = 12, TextWrapped = true, Text = text(entry[2], entry[3]) }, row)
		fields[entry[1]] = UI.input({ Size = UDim2.new(0.3, 0, 1, 0), Position = UDim2.fromScale(0.7, 0), TextSize = 13 }, row)
	end
	local save = UI.button({ Name = "ConfigureAutoBridge", Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.accent, LayoutOrder = 6,
		Text = text("APPLIQUER ET ENREGISTRER", "APPLY AND SAVE") }, configCard)
	local teamCard = UI.card(scroll, 3)
	teamCard.Visible = false
	UI.sectionHeader(text("ÉQUIPE DU JOUEUR SÉLECTIONNÉ", "SELECTED PLAYER'S TEAM"), T.good, teamCard, 1)
	local targetLabel = UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, LayoutOrder = 2 }, teamCard)
	local teamHolder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 }, teamCard)
	local picker = UI.picker(teamHolder, function() return state.Teams or {} end, nil)
	local teamRun = UI.button({ Name = "AutoBridgeSetTeam", Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.good, LayoutOrder = 4,
		Text = text("CHANGER L'ÉQUIPE", "CHANGE TEAM") }, teamCard)
	local STATUS = { Detected = { "Détecté", "Detected" }, Compatible = { "Compatible", "Compatible" }, Operational = { "Opérationnel", "Operational" },
		Unsupported = { "Non pris en charge", "Unsupported" }, Error = { "Erreur d'intégration", "Integration error" } }
	local function clearRows()
		for _, row in systemRows do row:Destroy() end
		table.clear(systemRows)
	end
	local function teamAction()
		if not allowed("AutoBridge.View") or not state.Allowed or state.Disabled or not state.Enabled then return nil end
		for _, entry in state.Systems or {} do
			if entry.Id == "teams" then
				for _, action in entry.Actions or {} do
					if action.Id == "SetTeam" and type(action.Permission) == "string" and allowed(action.Permission) then return action end
				end
			end
		end
		return nil
	end
	local function syncPermissions()
		if not alive() then return end
		local view = allowed("AutoBridge.View")
		scroll.Visible = view
		refreshButton.Active, refreshButton.Selectable = view and not loading, view and not loading
		configCard.Visible = view and state.Allowed == true and not state.Disabled and allowed("AutoBridge.Configure")
		teamCard.Visible = teamAction() ~= nil
	end
	local function refreshTarget()
		if not alive() then return end
		local target = Core.Selected
		targetLabel.Text = target and target.Parent == Players and text("Cible : ", "Target: ") .. target.DisplayName or Core.L("Common.PickPlayerFirst")
	end
	local function deny()
		if not alive() then return end
		state = { Allowed = false, Enabled = false, Config = {}, Teams = {}, Systems = {} }
		clearRows()
		configCard.Visible, teamCard.Visible = false, false
		summary.Text = text("Accès refusé ou service indisponible.", "Access denied or service unavailable.")
		syncPermissions()
		publish(state)
	end
	local function render(snapshot)
		if not allowed("AutoBridge.View") then return end
		if type(snapshot) ~= "table" or snapshot.Allowed ~= true then deny(); return end
		state = snapshot
		summary.Text = snapshot.Enabled and text("Analyse : ", "Scan: ") .. tostring(snapshot.ScannedInstances or 0)
			.. text(" instances ; ", " instances; ") .. tostring(#(snapshot.Systems or {})) .. text(" systèmes.", " systems.") or text("AutoBridge désactivé.", "AutoBridge disabled.")
		if snapshot.Truncated then summary.Text ..= text(" Limite atteinte : résultat partiel.", " Limit reached: partial result.") end
		if snapshot.Disabled then summary.Text = text("Module désactivé par Settings.Modules côté serveur.", "Module disabled by server Settings.Modules.") end
		local cfg = snapshot.Config or {}
		enabled.Set(cfg.Enabled == true)
		teamEnabled.Set(cfg.EnableTeamActions == true)
		for key, box in fields do box.Text = tostring(cfg[key] or "") end
		local selectedTeam, selectionExists = picker.Get(), false
		for _, entry in state.Teams or {} do if entry[1] == selectedTeam then selectionExists = true; break end end
		if not selectionExists then picker.Set(nil) else picker.Refresh() end
		clearRows()
		for index, entry in snapshot.Systems or {} do
			local card = UI.card(scroll, 10 + index)
			table.insert(systemRows, card)
			local labels = STATUS[entry.Status] or STATUS.Detected
			local color = entry.Status == "Operational" and T.good or entry.Status == "Error" and T.bad or T.warn
			UI.sectionHeader(tostring(entry.Name or entry.Id) .. " · " .. text(labels[1], labels[2]), color, card, 1)
			UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12,
				TextColor3 = T.sub, LayoutOrder = 2, Text = tostring(entry.Count or 0) .. " · " .. tostring(entry.Detail or "") }, card)
		end
		syncPermissions()
		refreshTarget()
		if allowed("AutoBridge.View") then publish(snapshot) end
	end

	-- No automatic RPC on Build or parent.Visible changes. Home decides when to fetch the summary/details.
	function object.Refresh(force)
		if not alive() or loading then return false end
		if not allowed("AutoBridge.View") then deny(); return false end
		loading = true
		requestVersion += 1
		local version = requestVersion
		refreshButton.Text = Core.L("Common.Loading")
		syncPermissions()
		task.spawn(function()
			if not allowed("AutoBridge.View") or version ~= requestVersion then return end
			local ok, result, detail = pcall(function()
				if force == true then return R.RefreshAutoBridge:InvokeServer() end
				return R.GetAutoBridge:InvokeServer()
			end)
			if not alive() or version ~= requestVersion then return end
			loading = false
			refreshButton.Text = Core.L("Common.Refresh")
			syncPermissions()
			if not allowed("AutoBridge.View") then deny(); return end
			if force == true then
				if ok and result == true then render(detail) else Core.Toast(ok and detail or Core.L("Common.ServerError"), false) end
			elseif ok then render(result) else summary.Text = Core.L("Common.ServerError") end
		end)
		return true
	end
	UI.Confirmable(save, true, function()
		if not allowed("AutoBridge.View") or not allowed("AutoBridge.Configure") or not state.Allowed or state.Disabled then return end
		local patch = { Enabled = enabled.Get(), EnableTeamActions = teamEnabled.Get() }
		for key, box in fields do
			local value = tonumber(box.Text)
			if not value or value ~= value or math.abs(value) == math.huge then Core.Toast(text("Nombre invalide.", "Invalid number."), false); return end
			patch[key] = value
		end
		task.spawn(function()
			if not allowed("AutoBridge.View") or not allowed("AutoBridge.Configure") or state.Disabled then return end
			local ok, success, reply = pcall(function() return R.ConfigureAutoBridge:InvokeServer(patch) end)
			if not allowed("AutoBridge.View") or not allowed("AutoBridge.Configure") then return end
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success then object.Refresh(false) end
		end)
	end)
	UI.Confirmable(teamRun, true, function()
		local action, target, team = teamAction(), Core.Selected, picker.Get()
		if not action then return end
		if not target or target.Parent ~= Players then Core.Toast(Core.L("Common.PickPlayerFirst"), false); return end
		if type(team) ~= "string" then Core.Toast(text("Aucune équipe disponible.", "No team available."), false); return end
		task.spawn(function()
			if not teamAction() or not allowed(action.Permission) or target.Parent ~= Players then return end
			local ok, success, reply = pcall(function() return R.AutoBridgeAction:InvokeServer("teams", "SetTeam", target, { Team = team }) end)
			if not teamAction() or not allowed(action.Permission) or target.Parent ~= Players then return end
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
		end)
	end)
	table.insert(connections, refreshButton.Activated:Connect(function() object.Refresh(true) end))
	local selectionConnection = Core.On(Core.SelectionChanged.Event, refreshTarget)
	if selectionConnection then table.insert(connections, selectionConnection) end
	local accessConnection = Core.On(Core.AccessChanged.Event, function()
		if not alive() then return end
		if not allowed("AutoBridge.View") then
			requestVersion += 1
			loading = false
			refreshButton.Text = Core.L("Common.Refresh")
			deny()
		else syncPermissions() end
	end)
	if accessConnection then table.insert(connections, accessConnection) end
	function object.Destroy()
		if destroyed then return end
		destroyed = true
		requestVersion += 1
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
		clearRows()
		scroll:Destroy()
	end
	table.insert(connections, scroll.Destroying:Connect(function() object.Destroy() end))
	syncPermissions()
	refreshTarget()
	return object
end
return Panel
