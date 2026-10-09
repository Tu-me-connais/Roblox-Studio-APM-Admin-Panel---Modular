local HttpService = game:GetService("HttpService")
local Page = { Id = "Security", Order = 8, Label = { fr = "Sécurité", en = "Security" } }

function Page.Visible(Core)
	return Core.ActualOwner == true or Core.HasPermission("APM.Simulate") or Core.HasPermission("APM.ManagePermissions")
end

function Page.Build(Core, page)
	local UI, T, R = Core.UI, Core.T, Core.R
	local function text(fr, en) return Core.Language == "fr" and fr or en end
	local scroll = UI.scroll({ Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)
	local function invoke(remote, ...)
		local args = table.pack(...)
		local ok, success, message = pcall(function() return remote:InvokeServer(table.unpack(args, 1, args.n)) end)
		return ok and success == true, ok and message or text("Le serveur est indisponible.", "Server unavailable.")
	end
	local function hint(card, order, value)
		return UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			Text = value, TextWrapped = true, TextSize = 12, TextColor3 = T.sub, LayoutOrder = order }, card)
	end
	local function row(card, order, height)
		return UI.new("Frame", { Size = UDim2.new(1, 0, 0, height or 34), BackgroundTransparency = 1, LayoutOrder = order }, card)
	end

	if Core.HasPermission("APM.Simulate") and (type(Core.Simulation) ~= "table" or Core.Simulation.enabled ~= false) then
		local card = UI.card(scroll, 1)
		UI.sectionHeader(text("SIMULATION DES PERMISSIONS", "PERMISSION SIMULATION"), T.accent, card, 1)
		local state = type(Core.Simulation) == "table" and Core.Simulation or {}
		local ok, data = pcall(function() return R.GetSimulation:InvokeServer() end)
		if ok and type(data) == "table" then state = data end
		local realRank = state.realRank or Core.RealRank or Core.MyRank
		hint(card, 2, text("Grade réel : ", "Real rank: ") .. Core.RankName(realRank)
			.. text(". Test limité à cinq minutes ; /apm-restore restaure immédiatement vos droits réels.", ". Five-minute test; /apm-restore restores your real context immediately."))
		hint(card, 3, text("Un test commencé après connexion ne prouve jamais l'absence initiale de réplication. Utilisez un second joueur sans grade pour cette vérification.",
			"A test started after joining cannot prove that components were never replicated. Use a second unranked player to verify initial replication."))
		local choices = { { "None", text("Joueur ordinaire", "Ordinary player") } }
		for _, rank in Core.RankList do
			if rank.Level <= Core.RankLevel(realRank) then table.insert(choices, { rank.Id, Core.RankName(rank.Id) }) end
		end
		local rankRow = row(card, 4)
		UI.label({ Size = UDim2.new(0.45, 0, 1, 0), Text = text("Grade simulé", "Simulated rank"), TextSize = 13 }, rankRow)
		local picker = UI.picker(rankRow, choices, state.rank or "None", UDim2.new(0.55, -4, 0, 32), UDim2.new(0.45, 4, 0, 0))
		local custom = false
		local customRow = row(card, 5)
		UI.label({ Size = UDim2.new(1, -58, 1, 0), Text = text("Permissions personnalisées (liste JSON)", "Custom permissions (JSON allowlist)"), TextSize = 12, TextWrapped = true }, customRow)
		local editor = UI.input({ Size = UDim2.new(1, 0, 0, 145), MultiLine = true, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top, TextSize = 12, Font = Enum.Font.Code, LayoutOrder = 6,
			Text = "{}", Visible = false, ClearTextOnFocus = false }, card)
		local allowed = state.realPermissions or Core.Permissions or {}
		local defaultMap = {}
		for name, value in allowed do if value == true then defaultMap[name] = true end end
		local encoded, json = pcall(HttpService.JSONEncode, HttpService, defaultMap)
		if encoded then editor.Text = json end
		UI.Switch(customRow, false, function(value) custom = value; editor.Visible = value end, UDim2.new(1, -46, 0, 4))
		hint(card, 7, text("En mode personnalisé, seuls les droits présents dans la liste et réellement possédés sont autorisés. Pour tester sans panneau, retirez APM.AccessPanel ; la récupération reste disponible.",
			"Custom mode allows only listed permissions that you really hold. Remove APM.AccessPanel to test without the panel; recovery remains available."))
		local buttons = row(card, 8)
		local start = UI.button({ Size = UDim2.new(0.5, -4, 1, 0), Text = text("Démarrer le test", "Start test"), BackgroundColor3 = T.accent, TextSize = 12 }, buttons)
		local restore = UI.button({ Size = UDim2.new(0.5, -4, 1, 0), Position = UDim2.new(0.5, 4, 0, 0), Text = text("Revenir au grade réel", "Restore real context"), BackgroundColor3 = T.panel2, TextSize = 12 }, buttons)
		local busy = false
		start.Activated:Connect(function()
			if busy then return end
			local permissions
			if custom then
				if #editor.Text > 20000 then Core.Toast(text("Liste trop longue.", "List too long."), false); return end
				local decoded, result = pcall(HttpService.JSONDecode, HttpService, editor.Text)
				if not decoded or type(result) ~= "table" then Core.Toast(text("JSON invalide : utilisez un objet permission: true/false.", "Invalid JSON: use a permission: true/false object."), false); return end
				permissions = result
			end
			busy = true
			task.spawn(function()
				local success, message = invoke(R.SetSimulation, picker.Get(), permissions)
				busy = false
				Core.Toast(message or "", success)
			end)
		end)
		restore.Activated:Connect(function()
			task.spawn(function() local success, message = invoke(R.RestoreSimulation); Core.Toast(message or "", success) end)
		end)
	end

	if Core.HasPermission("APM.ManagePermissions") then
		local card = UI.card(scroll, 2)
		UI.sectionHeader(text("PERMISSIONS DÉDIÉES", "NAMED PERMISSIONS"), T.accent, card, 1)
		hint(card, 2, text("Les choix utilisent la sauvegarde Access existante. Les permissions dédiées sont personnalisables, Développeur inclus. Seul le propriétaire réel peut retirer ses accès critiques.",
			"Choices use the existing Access save. Named permissions are customizable, including Developer. Only the actual owner can remove their critical access."))
		local names, columns = {}, {}
		for name in Core.ModuleAccess do
			if string.match(name, "^APM%.") or string.match(name, "^Sentinel%.") or string.match(name, "^AutoBridge%.") then table.insert(names, { name, name }) end
		end
		table.sort(names, function(a, b) return a[1] < b[1] end)
		for _, rank in Core.RankList do table.insert(columns, { rank.Id, Core.RankName(rank.Id) }) end
		local permissionRow = row(card, 3)
		local namePicker = UI.picker(permissionRow, names, names[1] and names[1][1], UDim2.new(1, 0, 0, 32), UDim2.fromOffset(0, 0))
		local gradeRow = row(card, 4)
		local rankPicker = UI.picker(gradeRow, columns, Core.MyRank, UDim2.new(0.65, -4, 0, 32), UDim2.fromOffset(0, 0))
		local toggle, syncing = nil, false
		local status = hint(card, 5, "")
		local refresh = UI.button({ Size = UDim2.new(0.35, -4, 0, 32), Position = UDim2.new(0.65, 4, 0, 0), Text = text("Lire le choix", "Read choice"), BackgroundColor3 = T.panel2, TextSize = 12 }, gradeRow)
		local switchRow = row(card, 6)
		UI.label({ Size = UDim2.new(1, -60, 1, 0), Text = text("Autorisé (enregistre immédiatement)", "Allowed (saves immediately)"), TextSize = 12, TextWrapped = true }, switchRow)
		local function sync()
			local name, rank = namePicker.Get(), rankPicker.Get()
			local granted = name and Core.ModuleAccess[name] and Core.ModuleAccess[name][rank] == true
			syncing = true
			toggle.Set(granted == true)
			syncing = false
			status.Text = tostring(name or "-") .. " · " .. Core.RankName(rank) .. " · " .. text(granted and "autorisé" or "refusé", granted and "allowed" or "denied")
		end
		toggle = UI.Switch(switchRow, false, function(value)
			if syncing then return end
			local name, rank = namePicker.Get(), rankPicker.Get()
			if not name or not rank then sync(); return end
			task.spawn(function()
				local success, message = invoke(R.SetModuleAccess, name, rank, value)
				Core.Toast(message or "", success)
				Core.RefreshAccess()
				if switchRow.Parent then sync() end
			end)
		end, UDim2.new(1, -46, 0, 4))
		refresh.Activated:Connect(function() task.spawn(function() Core.RefreshAccess(); if switchRow.Parent then sync() end end) end)
		Core.On(Core.AccessChanged.Event, function() if switchRow.Parent then sync() end end)
		namePicker.Changed = sync
		rankPicker.Changed = sync
		sync()
	end

	if Core.ActualOwner then
		local card = UI.card(scroll, 3)
		UI.sectionHeader(text("AUTORITÉ DU PROPRIÉTAIRE", "EXPERIENCE OWNER AUTHORITY"), T.warn, card, 1)
		hint(card, 2, text("Cette attribution prioritaire peut révoquer un accès fixe ou de groupe. Hériter rétablit les sources originales. En simulation, toute modification de cette attribution est refusée.",
			"This priority override can revoke fixed or group access. Inherit restores original sources. Overrides cannot be changed while simulating."))
		local account = UI.input({ Size = UDim2.new(1, 0, 0, 32), PlaceholderText = "UserId", TextSize = 13, LayoutOrder = 3 }, card)
		local choices = { { "Inherit", text("Hériter des sources", "Inherit sources") }, { "None", text("Aucun accès", "No access") } }
		for _, rank in Core.RankList do table.insert(choices, { rank.Id, Core.RankName(rank.Id) }) end
		local choiceRow = row(card, 4)
		local ownerPicker = UI.picker(choiceRow, choices, "Inherit", UDim2.new(1, 0, 0, 32), UDim2.fromOffset(0, 0))
		local save = UI.button({ Size = UDim2.new(1, 0, 0, 34), Text = text("Appliquer l'attribution", "Apply override"), BackgroundColor3 = T.warn, TextColor3 = T.bg, TextSize = 13, LayoutOrder = 5 }, card)
		UI.Confirmable(save, true, function()
			local userId = tonumber(account.Text)
			if not userId or userId % 1 ~= 0 then Core.Toast(text("UserId invalide.", "Invalid UserId."), false); return end
			task.spawn(function() local success, message = invoke(R.SetOwnerAccessOverride, userId, ownerPicker.Get()); Core.Toast(message or "", success) end)
		end)
	end
end

return Page
