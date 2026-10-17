--[[
	Sentinel : page « Sentinel Guard » pensée pour quelqu'un qui ne l'a jamais vue.
	  1. En-tête : la protection est-elle active ? combien de joueurs surveillés, de suspects, d'alertes ? interrupteur général.
	  2. JOUEURS LES PLUS SUSPECTS (en haut) : les 5 premiers, « Voir plus » pour tous. Un clic ouvre le détail : ce que le joueur a
	     fait, les positions (téléportation), et SI LE MOUVEMENT VIENT DU SERVEUR OU DU JOUEUR, avec les raisons.
	  3. Réglages guidés : niveau de vigilance, une carte par détection (avec ses paramètres), réactions, exceptions, avancé.
	     Rien n'est appliqué avant « Appliquer » (barre en bas de page).
	  4. Activité du serveur reconnue, historique des alertes, test du détecteur.
	Les données viennent du serveur (R.GetSentinel) ; tous les textes sont traduits dans la langue du panneau.
]]
local Page = { Id = "Sentinel", Order = 9, Label = { fr = "Sentinel Guard", en = "Sentinel Guard" } }
function Page.Visible(Core)
	return Core.HasPermission("Sentinel.View")
end

local INTEGER = { RequiredSamples = true, MaxAlerts = true, SuspectMemory = true, TeleportConfirm = true, FlySeconds = true, SpeedTolerance = true }
local SHORT_LIST, LONG_LIST, HISTORY_SHORT = 5, 50, 10
local REFRESH_SECONDS = 5

function Page.Build(Core, page)
	local UI, T, R, L = Core.UI, Core.T, Core.R, Core.L
	local Players = game:GetService("Players")
	local mine = Core.Session
	local function alive()
		return Core.Alive(mine) and page.Parent ~= nil
	end
	local BLUE = Color3.fromRGB(88, 128, 232)
	local LEVEL_COLOR = { Low = T.warn, Medium = Color3.fromRGB(236, 140, 60), High = T.bad }
	local ORIGIN_COLOR = { Server = BLUE, ServerLikely = BLUE, SafeZone = T.good, Player = T.bad, Unknown = T.sub }
	local Y = Enum.AutomaticSize.Y

	local scroll = UI.scroll({ Size = UDim2.new(1, 0, 1, 0) }, page)
	UI.list(scroll, 10)
	local footer = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 46), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.panel2,
		Visible = false, ZIndex = 5, Corner = 10, Stroke = T.warn }, page)

	-- état ----------------------------------------------------------------------------------------------
	local snapshot, saved, draft = nil, nil, nil
	local bounds = {}
	local controls = {} -- fonctions qui recopient draft vers l'interface
	local openRows, helpOpen, advancedOpen, moreSuspects, moreHistory, movesOpen = {}, nil, false, false, false, false
	local receivedAt, loading, lastSignature = 0, false, nil
	local refresh, render, updateFooter
	local configuring, sourceOpen = false, false
	local function configText(fr, en) return Core.Text({ fr = fr, en = en }) end
	local function sourceName(source)
		if source == "Saved" then return configText("enregistré", "saved") end
		if source == "Session" then return configText("session Studio", "Studio session") end
		if source == "Server" then return configText("règle serveur", "server rule") end
		return configText("script", "script")
	end
	local function configValue(value)
		if type(value) == "boolean" then return value and configText("activé", "on") or configText("désactivé", "off") end
		if type(value) == "table" then return tostring(#value) .. configText(" zone(s)", " zone(s)") end
		return tostring(value)
	end

	local function canConfigure()
		return Core.HasPermission("Sentinel.Configure")
	end
	local function serverNow()
		return (snapshot and snapshot.Now or os.time()) + math.floor(os.clock() - receivedAt)
	end
	local function ago(timestamp)
		local seconds = math.max(0, serverNow() - (tonumber(timestamp) or 0))
		if seconds < 60 then
			return L("Sentinel.Ago.Seconds", seconds)
		elseif seconds < 3600 then
			return L("Sentinel.Ago.Minutes", seconds // 60)
		end
		return L("Sentinel.Ago.Hours", seconds // 3600)
	end
	local function pos(p)
		if type(p) ~= "table" then return "?" end
		return string.format("%d, %d, %d", tonumber(p.x) or 0, tonumber(p.y) or 0, tonumber(p.z) or 0)
	end
	local function eventText(kind, data)
		data = type(data) == "table" and data or {}
		if kind == "Teleport" then
			return L("Sentinel.Event.Teleport", data.Distance or 0, data.Dt or 0)
		elseif kind == "Speed" then
			if data.Vertical then return L("Sentinel.Event.Vertical", data.Speed or 0, data.Dt or 0) end
			return L("Sentinel.Event.Speed", data.Speed or 0, data.Limit or 0, data.Dt or 0)
		elseif kind == "Fly" then
			return L("Sentinel.Event.Fly", data.Seconds or 0)
		elseif kind == "Noclip" then
			return L("Sentinel.Event.Noclip", tostring(data.Part or "?"), data.Samples or 0)
		elseif kind == "Humanoid" then
			return L(data.Property == "WalkSpeed" and "Sentinel.Event.WalkSpeed" or "Sentinel.Event.JumpHeight", data.Value or 0, data.Limit or 0)
		elseif kind == "RemoteAbuse" then
			return L("Sentinel.Event.RemoteAbuse", Core.Text(data.Category or "?"), data.Count or 0)
		end
		return tostring(kind)
	end
	local function kindName(kind)
		return L("Sentinel.Kind." .. tostring(kind))
	end
	local function whyText(why)
		local list = {}
		for _, item in type(why) == "table" and why or {} do
			if type(item) == "table" and type(item.Code) == "string" then
				local value = item.V
				if type(value) == "string" then value = Core.Text(value) end
				table.insert(list, L("Sentinel.Why." .. item.Code, value or ""))
			end
		end
		return table.concat(list, "  ·  ")
	end
	local function originLabel(origin, confidence)
		local text = L("Sentinel.Origin." .. tostring(origin))
		if confidence and origin ~= "Server" and origin ~= "Unknown" and origin ~= "SafeZone" then
			text ..= " · " .. L("Sentinel.Confidence." .. tostring(confidence))
		end
		return text
	end

	-- constructeurs ------------------------------------------------------------------------------------
	local function wrap(parent, text, size, color, order, font)
		return UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, TextWrapped = true, TextSize = size or 12, TextColor3 = color or T.text,
			Font = font or T.font, LayoutOrder = order or 1, Text = text }, parent)
	end
	local function pill(parent, text, color, order)
		local label = UI.label({ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, BackgroundColor3 = color:Lerp(T.bg, 0.72),
			Font = T.fontBold, TextSize = 10, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = order or 1, Text = text, Corner = 9 }, parent)
		UI.padding(label, 0, 8, 8)
		return label
	end
	local function clear(frame)
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
	end
	local function register(fn)
		table.insert(controls, fn)
	end
	local function isDirty()
		if not saved or not draft then return false end
		for key, value in saved do
			if draft[key] ~= value then return true end
		end
		return false
	end
	local function syncControls()
		for _, fn in controls do fn() end
	end
	local function setValue(key, value)
		if not draft then return end
		draft[key] = value
		syncControls()
		updateFooter()
	end

	local function switchRow(parent, order, title, desc, key)
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		local text = UI.new("Frame", { Size = UDim2.new(1, -60, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1 }, row)
		UI.list(text, 2)
		wrap(text, title, 13, T.text, 1, T.fontBold)
		if desc then wrap(text, desc, 11, T.sub, 2) end
		local switch = UI.Switch(row, false, function(state)
			setValue(key, state)
		end, UDim2.new(1, -46, 0, 0))
		register(function()
			if draft and switch.Get() ~= (draft[key] == true) then switch.Set(draft[key] == true) end
		end)
		return row
	end
	local function numberField(parent, order, title, desc, key, step)
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		local text = UI.new("Frame", { Size = UDim2.new(1, -172, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1 }, row)
		UI.list(text, 2)
		wrap(text, title, 12, T.text, 1, T.fontBold)
		if desc then wrap(text, desc, 11, T.sub, 2) end
		local holder = UI.new("Frame", { Size = UDim2.fromOffset(160, 44), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1 }, row)
		local minus = UI.button({ Size = UDim2.fromOffset(30, 28), Text = "-", TextSize = 16 }, holder)
		local box = UI.input({ Size = UDim2.fromOffset(92, 28), Position = UDim2.fromOffset(34, 0), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center }, holder)
		local plus = UI.button({ Size = UDim2.fromOffset(30, 28), Position = UDim2.fromOffset(130, 0), Text = "+", TextSize = 16 }, holder)
		local range = UI.label({ Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 30), TextSize = 10, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Text = "" }, holder)
		local function fmt(value)
			if value == nil then return "" end
			return INTEGER[key] and tostring(math.floor(value + 0.5)) or tostring(math.floor(value * 10 + 0.5) / 10)
		end
		local function commit(value)
			local limit = bounds[key]
			if limit then value = math.clamp(value, limit[1], limit[2]) end
			if INTEGER[key] then value = math.floor(value + 0.5) else value = math.floor(value * 10 + 0.5) / 10 end
			setValue(key, value)
		end
		box.FocusLost:Connect(function()
			local number = tonumber((string.gsub(box.Text, ",", ".")))
			if number == nil or number ~= number or math.abs(number) == math.huge then
				Core.Toast(L("Sentinel.InvalidNumber", title), false)
				box.Text = fmt(draft and draft[key])
				return
			end
			commit(number)
		end)
		minus.Activated:Connect(function() commit((draft and draft[key] or 0) - step) end)
		plus.Activated:Connect(function() commit((draft and draft[key] or 0) + step) end)
		register(function()
			if draft and not box:IsFocused() then box.Text = fmt(draft[key]) end
			local limit = bounds[key]
			range.Text = limit and (fmt(limit[1]) .. " – " .. fmt(limit[2])) or ""
		end)
		return row
	end
	local function segmented(parent, order, options, key, isBoolean)
		local bar = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.panel, LayoutOrder = order, Corner = 8, Stroke = T.stroke }, parent)
		local buttons = {}
		for index, option in options do
			local button = UI.button({ Size = UDim2.new(1 / #options, -4, 1, -4), Position = UDim2.new((index - 1) / #options, 2, 0, 2), BackgroundColor3 = T.panel,
				Text = option[2], TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Corner = 6 }, bar)
			button.Activated:Connect(function() setValue(key, option[1]) end)
			buttons[option[1]] = button
		end
		register(function()
			for id, button in buttons do
				local on = draft and draft[key] == id
				button.BackgroundColor3 = on and T.accent or T.panel
				button.TextColor3 = on and Color3.new(1, 1, 1) or T.sub
			end
		end)
		return bar
	end
	-- carte repliable : renvoie (carte, contenu)
	local function section(order, title, color, subtitle)
		local card = UI.card(scroll, order)
		UI.sectionHeader(title, color, card, 1)
		if subtitle then wrap(card, subtitle, 11, T.sub, 2) end
		return card
	end

	-- 1. en-tête ------------------------------------------------------------------------------------------
	local head = UI.card(scroll, 1)
	local titleRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 1 }, head)
	UI.label({ Size = UDim2.new(1, -190, 1, 0), Font = T.fontBold, TextSize = 17, Text = L("Sentinel.Title") }, titleRow)
	local statePill = UI.label({ Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
		BackgroundTransparency = 0, BackgroundColor3 = T.panel, Font = T.fontBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Text = L("Common.Loading"), Corner = 12 }, titleRow)
	UI.padding(statePill, 0, 12, 12)
	wrap(head, L("Sentinel.Tagline"), 12, T.sub, 2)
	local tiles = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 54), BackgroundTransparency = 1, LayoutOrder = 3 }, head)
	UI.list(tiles, 8, true)
	local function tile(order, caption)
		local frame = UI.new("Frame", { Size = UDim2.new(1 / 3, -6, 1, 0), BackgroundColor3 = T.panel, LayoutOrder = order, Corner = 8 }, tiles)
		local value = UI.label({ Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 4), Font = T.fontBold, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, Text = "-" }, frame)
		UI.label({ Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 33), TextSize = 11, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Text = caption }, frame)
		return value
	end
	local watchedValue = tile(1, L("Sentinel.Stat.Watched"))
	local suspectsValue = tile(2, L("Sentinel.Stat.Suspects"))
	local alertsValue = tile(3, L("Sentinel.Stat.Alerts"))
	local masterHolder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 4 }, head)
	UI.list(masterHolder, 0)
	switchRow(masterHolder, 1, L("Sentinel.Master"), L("Sentinel.MasterDesc"), "Enabled")
	local buttonsRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 5 }, head)
	UI.list(buttonsRow, 8, true)
	local refreshButton = UI.button({ Size = UDim2.new(0.34, -6, 1, 0), BackgroundColor3 = T.panel, Stroke = T.stroke, Text = Core.L("Common.Refresh"), TextSize = 12, LayoutOrder = 1 }, buttonsRow)
	local helpButton = UI.button({ Size = UDim2.new(0.38, -6, 1, 0), BackgroundColor3 = T.panel, Stroke = T.stroke, Text = L("Sentinel.Help.Show"), TextSize = 12, LayoutOrder = 2 }, buttonsRow)
	local clearAllButton = UI.button({ Size = UDim2.new(0.28, -4, 1, 0), BackgroundColor3 = T.panel, Stroke = T.stroke, Text = L("Sentinel.ClearAll"), TextSize = 12, LayoutOrder = 3 }, buttonsRow)

	-- aide pour quelqu'un qui découvre ----------------------------------------------------------------------
	local helpCard = UI.card(scroll, 2)
	UI.sectionHeader(L("Sentinel.Help.Title"), BLUE, helpCard, 1)
	for index, key in { "Sentinel.Help.Step1", "Sentinel.Help.Step2", "Sentinel.Help.Step3", "Sentinel.Help.Origin", "Sentinel.Help.Dev" } do
		wrap(helpCard, L(key), 12, index <= 3 and T.text or T.sub, 1 + index)
	end

	-- 2. suspects -------------------------------------------------------------------------------------------
	local suspectsCard = section(3, L("Sentinel.Suspects.Title"), T.bad, L("Sentinel.Suspects.Sub"))
	local suspectsList = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 3 }, suspectsCard)
	UI.list(suspectsList, 6)
	local moreButton = UI.button({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, Stroke = T.stroke, TextSize = 12, LayoutOrder = 4, Visible = false, Text = "" }, suspectsCard)

	local function actionButton(parent, text, order, color)
		return UI.button({ Size = UDim2.fromOffset(0, 28), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color or T.panel2, TextSize = 11, LayoutOrder = order,
			Text = text, Stroke = T.stroke }, parent)
	end
	local function eventBlock(parent, event, order, showName)
		local block = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundColor3 = T.panel2, LayoutOrder = order, Corner = 6 }, parent)
		UI.list(block, 4)
		UI.padding(block, 8)
		local line = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1 }, block)
		UI.list(line, 6, true)
		local kindLabel = UI.label({ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, Font = T.fontBold, TextSize = 12, LayoutOrder = 1,
			Text = (showName and (tostring(event.Name or "?") .. " · ") or "") .. kindName(event.Kind) }, line)
		kindLabel.TextColor3 = T.text
		pill(line, originLabel(event.Origin, event.Confidence), ORIGIN_COLOR[event.Origin] or T.sub, 2)
		UI.label({ Size = UDim2.fromOffset(0, 20), AutomaticSize = Enum.AutomaticSize.X, TextSize = 11, TextColor3 = T.sub, LayoutOrder = 3, Text = ago(event.Time) }, line)
		wrap(block, eventText(event.Kind, event.Data), 12, T.text, 2)
		local data = type(event.Data) == "table" and event.Data or {}
		if type(data.From) == "table" and type(data.To) == "table" then
			-- trajet sur la fenêtre de 3 positions : avant-dernière -> dernière -> arrivée
			local trail = type(data.Before) == "table" and L("Sentinel.Positions3", pos(data.Before), pos(data.From), pos(data.To))
				or L("Sentinel.Positions", pos(data.From), pos(data.To))
			wrap(block, trail, 11, T.warn, 3)
		elseif type(data.Position) == "table" then
			wrap(block, L("Sentinel.Position", pos(data.Position)), 11, T.warn, 3)
		end
		local reasons = whyText(event.Why)
		if reasons == "" and event.Reason then reasons = L("Sentinel.Why.Declared", tostring(event.Reason)) end
		if reasons ~= "" then
			wrap(block, L("Sentinel.Why.Title") .. " " .. reasons, 11, T.sub, 4)
		end
		return block
	end

	local function suspectRow(entry, rank)
		local color = LEVEL_COLOR[entry.Level] or T.warn
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundColor3 = T.panel, LayoutOrder = rank, Corner = 8, Stroke = color }, suspectsList)
		UI.list(row, 0)
		local top = UI.new("TextButton", { Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Text = "", LayoutOrder = 1 }, row)
		UI.label({ Size = UDim2.fromOffset(30, 24), Position = UDim2.fromOffset(8, 6), Font = T.fontBold, TextSize = 14, TextColor3 = T.sub, Text = "#" .. rank }, top)
		local dot = UI.new("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(38, 14), BackgroundColor3 = entry.Online and T.good or T.sub, Corner = 4 }, top)
		UI.label({ Size = UDim2.new(1, -190, 0, 20), Position = UDim2.fromOffset(52, 8), Font = T.fontBold, TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = tostring(entry.DisplayName or entry.Name) .. (entry.DisplayName and entry.DisplayName ~= entry.Name and ("  @" .. tostring(entry.Name)) or "")
				.. (entry.Online and "" or ("  ·  " .. L("Sentinel.Suspects.Offline"))) }, top)
		local chips = {}
		for index, kind in entry.Kinds or {} do
			if index > 4 then break end
			table.insert(chips, kindName(kind.Kind) .. " ×" .. tostring(kind.Count))
		end
		UI.label({ Size = UDim2.new(1, -190, 0, 16), Position = UDim2.fromOffset(52, 30), TextSize = 11, TextColor3 = T.sub, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = table.concat(chips, "  ·  ") }, top)
		local last = entry.Events and entry.Events[1] or (entry.LastOrigin and { Origin = entry.LastOrigin, Confidence = entry.LastConfidence })
		if last then
			local badge = pill(top, originLabel(last.Origin, last.Confidence), ORIGIN_COLOR[last.Origin] or T.sub, 1)
			badge.Position = UDim2.fromOffset(52, 48)
		end
		UI.label({ Size = UDim2.fromOffset(120, 18), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), TextSize = 10, TextColor3 = T.sub,
			TextXAlignment = Enum.TextXAlignment.Right, Text = ago(entry.LastAt) }, top)
		UI.label({ Size = UDim2.fromOffset(120, 24), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 24), Font = T.fontBold, TextSize = 18, TextColor3 = color,
			TextXAlignment = Enum.TextXAlignment.Right, Text = tostring(entry.Score) .. "/100" }, top)
		local barBack = UI.new("Frame", { Size = UDim2.fromOffset(110, 6), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 52), BackgroundColor3 = T.panel2, Corner = 3 }, top)
		UI.new("Frame", { Size = UDim2.fromScale(math.clamp(entry.Score / 100, 0.04, 1), 1), BackgroundColor3 = color, Corner = 3 }, barBack)
		UI.label({ Size = UDim2.fromOffset(110, 12), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 59), TextSize = 9, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Right,
			Text = L("Sentinel.Level." .. tostring(entry.Level)) }, top)

		local details = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, Visible = openRows[entry.UserId] == true, LayoutOrder = 2 }, row)
		UI.list(details, 6)
		UI.padding(details, 8)
		-- dates et total enregistrés : tout l'historique de ce joueur, tous serveurs confondus
		wrap(details, L("Sentinel.History.Summary", entry.Total or entry.Count or 0, Core.FormatDate(entry.FirstAt), Core.FormatDate(entry.LastAt)), 11, T.sub, 0)
		local eventsHolder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 1 }, details)
		UI.list(eventsHolder, 6)
		local function fillEvents(events)
			clear(eventsHolder)
			for index, event in events do
				eventBlock(eventsHolder, event, index, false)
			end
		end
		fillEvents(entry.Events or {})
		local detailsLoaded = false
		local function loadDetails()
			if detailsLoaded or not entry.Persisted then return end
			detailsLoaded = true
			task.spawn(function()
				local ok, success, data = pcall(function() return R.SentinelAction:InvokeServer("Details", entry.UserId) end)
				if not alive() or not ok or success ~= true or type(data) ~= "table" or not eventsHolder.Parent then return end
				if #data > 0 then fillEvents(data) end
			end)
		end
		local actions = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 100 }, details)
		UI.list(actions, 8, true)
		local target = Players:GetPlayerByUserId(entry.UserId)
		if target and Core.CanUse and Core.CanUse("Teleport") then
			local go = actionButton(actions, L("Sentinel.Suspects.Go"), 1)
			go.Activated:Connect(function() Core.Action("Teleport", target) end)
		end
		if canConfigure() then
			local erase = actionButton(actions, L("Sentinel.Suspects.Clear"), 2)
			erase.Activated:Connect(function()
				task.spawn(function()
					local ok, success, reply = pcall(function() return R.SentinelAction:InvokeServer("ClearSuspect", entry.UserId) end)
					if not alive() then return end
					Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
					if ok and success then openRows[entry.UserId] = nil refresh(true) end
				end)
			end)
		end
		top.Activated:Connect(function()
			openRows[entry.UserId] = not (openRows[entry.UserId] == true)
			details.Visible = openRows[entry.UserId] == true
			if details.Visible then loadDetails() end
		end)
		if openRows[entry.UserId] == true then loadDetails() end
	end

	-- Saved overrides remain explicit even when their current value equals the script baseline.
	local sourceCard = section(4, configText("Origine des réglages", "Settings source"), T.accent)
	local sourceSummary = wrap(sourceCard, "", 12, T.sub, 2)
	local sourceToggle = UI.button({ Name = "ShowSentinelConfigSource", Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3, TextSize = 12,
		BackgroundColor3 = T.panel, Stroke = T.stroke, Text = configText("Voir les valeurs et leur origine", "Show values and their source") }, sourceCard)
	local sourceDetails = UI.new("Frame", { Name = "SentinelConfigSource", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y,
		BackgroundTransparency = 1, LayoutOrder = 4, Visible = false }, sourceCard)
	UI.list(sourceDetails, 4)
	local resetButton = UI.button({ Name = "ResetSentinelToScript", Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 5, TextSize = 12,
		BackgroundColor3 = T.panel, Stroke = T.warn, Text = configText("Revenir aux valeurs du script", "Return to script values") }, sourceCard)
	local resetHint = wrap(sourceCard, configText("Supprime les réglages enregistrés, y compris les zones ajoutées depuis le panneau. Les zones du script sont conservées et le brouillon est abandonné.",
		"Removes saved settings, including zones added from the panel. Script zones remain and your draft is discarded."), 11, T.sub, 6)
	local function renderSource()
		local source = snapshot.ConfigSource or {}
		local mode = source.Mode or "Script"
		sourceSummary.Text = mode == "Script" and configText("Valeurs du script actives.", "Script values are active.")
			or (sourceName(mode) .. " · " .. tostring(source.OverrideCount or 0) .. configText(" réglage(s) prioritaire(s) sur le script.", " setting(s) override the script."))
		if source.Storage == "Memory" then
			sourceSummary.Text ..= configText(" Mode mémoire : les changements durent jusqu'à l'arrêt du test.", " Memory mode: changes last until this test ends.")
		elseif source.Storage == "ReadOnly" then
			sourceSummary.Text ..= configText(" Sauvegarde indisponible : lecture seule.", " Storage unavailable: read-only.")
		end
		sourceDetails.Visible = sourceOpen
		sourceToggle.Text = sourceOpen and configText("Masquer les valeurs et leur origine", "Hide values and their source")
			or configText("Voir les valeurs et leur origine", "Show values and their source")
		clear(sourceDetails)
		if sourceOpen then
			local keys = {}
			for key in snapshot.Config or {} do table.insert(keys, key) end
			table.sort(keys)
			for index, key in keys do
				local value = snapshot.Config[key]
				local baseline = (source.ScriptConfig or {})[key]
				local row = key .. " = " .. configValue(value) .. " · " .. sourceName((source.Fields or {})[key])
				if baseline ~= nil and configValue(baseline) ~= configValue(value) then row ..= " · script = " .. configValue(baseline) end
				wrap(sourceDetails, row, 11, T.sub, index)
			end
		end
		resetButton.Visible = canConfigure() and source.HasOverrides == true
		resetHint.Visible = resetButton.Visible
		resetButton.Active, resetButton.Selectable = not configuring and source.Storage ~= "ReadOnly", not configuring and source.Storage ~= "ReadOnly"
	end

	-- 3. réglages -------------------------------------------------------------------------------------------
	local levelCard = section(5, L("Sentinel.Section.Level"), T.accent, L("Sentinel.Section.LevelSub"))
	local levelBar = segmented(levelCard, 3, { { "Observation", L("Sentinel.Mode.Observation") }, { "Balanced", L("Sentinel.Mode.Balanced") }, { "Strict", L("Sentinel.Mode.Strict") } }, "Mode")
	local levelDesc = wrap(levelCard, "", 12, T.sub, 4)
	register(function()
		if draft then levelDesc.Text = L("Sentinel.ModeDesc." .. tostring(draft.Mode)) end
	end)

	local detectCard = section(6, L("Sentinel.Section.Detections"), T.warn, L("Sentinel.Section.DetectionsSub"))
	local function detection(order, key, title, desc)
		local box = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundColor3 = T.panel, LayoutOrder = order, Corner = 8, Stroke = T.stroke }, detectCard)
		UI.list(box, 8)
		UI.padding(box, 10)
		switchRow(box, 1, title, desc, key)
		local params = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 2 }, box)
		UI.list(params, 10)
		register(function() params.Visible = draft ~= nil and draft[key] == true end)
		return params
	end
	local function conditional(parent, order, key, expected)
		local group = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		UI.list(group, 10)
		register(function() group.Visible = draft ~= nil and draft[key] == expected end)
		return group
	end

	local speed = detection(1, "DetectSpeed", L("Sentinel.Detect.Speed.Title"), L("Sentinel.Detect.Speed.Desc"))
	segmented(speed, 1, { { false, L("Sentinel.Detect.SpeedAuto") }, { true, L("Sentinel.Detect.SpeedFixed") } }, "SpeedLimitEnabled")
	local speedAuto = conditional(speed, 2, "SpeedLimitEnabled", false)
	wrap(speedAuto, L("Sentinel.Detect.SpeedAutoNote"), 11, T.sub, 1)
	local speedFixed = conditional(speed, 3, "SpeedLimitEnabled", true)
	numberField(speedFixed, 1, L("Sentinel.Detect.SpeedLimitValue"), L("Sentinel.Detect.SpeedLimitHint"), "SpeedLimit", 5)

	local teleport = detection(2, "DetectTeleport", L("Sentinel.Detect.Teleport.Title"), L("Sentinel.Detect.Teleport.Desc"))
	numberField(teleport, 1, L("Sentinel.Detect.TeleportDistance"), L("Sentinel.Detect.TeleportDistanceHint"), "TeleportDistance", 10)
	numberField(teleport, 2, L("Sentinel.Detect.TeleportConfirm"), L("Sentinel.Detect.TeleportConfirmHint"), "TeleportConfirm", 1)

	local fly = detection(3, "DetectFly", L("Sentinel.Detect.Fly.Title"), L("Sentinel.Detect.Fly.Desc"))
	numberField(fly, 1, L("Sentinel.Detect.FlySeconds"), L("Sentinel.Detect.FlySecondsHint"), "FlySeconds", 1)

	local noclip = detection(4, "DetectNoclip", L("Sentinel.Detect.Noclip.Title"), L("Sentinel.Detect.Noclip.Desc"))
	wrap(noclip, L("Sentinel.Detect.NoclipNote"), 11, T.sub, 1)

	local humanoid = detection(5, "DetectHumanoid", L("Sentinel.Detect.Humanoid.Title"), L("Sentinel.Detect.Humanoid.Desc"))
	local walkNote = conditional(humanoid, 1, "SpeedLimitEnabled", false)
	wrap(walkNote, L("Sentinel.Detect.HumanoidNeedsCap"), 11, T.warn, 1)
	switchRow(humanoid, 2, L("Sentinel.Detect.JumpLimit"), L("Sentinel.Detect.JumpLimitDesc"), "JumpLimitEnabled")
	local jumpFixed = conditional(humanoid, 3, "JumpLimitEnabled", true)
	numberField(jumpFixed, 1, L("Sentinel.Detect.JumpHeightLimit"), L("Sentinel.Detect.JumpHeightHint"), "JumpHeightLimit", 1)

	detection(6, "DetectAbuse", L("Sentinel.Detect.Abuse.Title"), L("Sentinel.Detect.Abuse.Desc"))

	local reactCard = section(7, L("Sentinel.Section.Reactions"), T.good, L("Sentinel.Section.ReactionsSub"))
	local reactBody = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 3 }, reactCard)
	UI.list(reactBody, 10)
	switchRow(reactBody, 1, L("Sentinel.React.Notify"), L("Sentinel.React.NotifyDesc"), "NotifyAdmins")
	switchRow(reactBody, 2, L("Sentinel.React.Correct"), L("Sentinel.React.CorrectDesc"), "CorrectPosition")
	switchRow(reactBody, 3, L("Sentinel.React.Enforce"), L("Sentinel.React.EnforceDesc"), "EnforceLimits")
	local kickRow = switchRow(reactBody, 4, L("Sentinel.React.Kick"), L("Sentinel.React.KickDesc"), "EnableKick")
	local kickNote = wrap(reactBody, L("Sentinel.React.KickLocked"), 11, T.sub, 5)
	wrap(reactBody, L("Sentinel.React.Always"), 11, T.sub, 6)

	local exceptCard = section(8, L("Sentinel.Section.Exceptions"), BLUE, L("Sentinel.Section.ExceptionsSub"))
	local exceptBody = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 3 }, exceptCard)
	UI.list(exceptBody, 10)
	switchRow(exceptBody, 1, L("Sentinel.Exc.Admins"), L("Sentinel.Exc.AdminsDesc"), "ExemptAdmins")
	numberField(exceptBody, 2, L("Sentinel.Exc.SpawnGrace"), L("Sentinel.Exc.SpawnGraceHint"), "SpawnGrace", 1)
	numberField(exceptBody, 3, L("Sentinel.Exc.PhysicsGrace"), L("Sentinel.Exc.PhysicsGraceHint"), "PhysicsGrace", 1)
	switchRow(exceptBody, 4, L("Sentinel.Exc.Lag"), L("Sentinel.Exc.LagDesc"), "LagFilter")

	-- zones sûres : positions (téléporteurs, lobby, arène...) où Sentinel ne signale rien, ni pour un déplacement qui en part ou y arrive
	local zonesBox = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundColor3 = T.panel, LayoutOrder = 5, Corner = 8, Stroke = T.stroke }, exceptBody)
	UI.list(zonesBox, 8)
	UI.padding(zonesBox, 10)
	wrap(zonesBox, L("Sentinel.Zones.Title"), 13, T.text, 1, T.fontBold)
	wrap(zonesBox, L("Sentinel.Zones.Desc"), 11, T.sub, 2)
	local zonesList = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 3 }, zonesBox)
	UI.list(zonesList, 4)
	local zoneForm = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 4 }, zonesBox)
	local zoneName = UI.input({ Size = UDim2.new(0.34, -4, 1, 0), PlaceholderText = L("Sentinel.Zones.Name"), TextSize = 12 }, zoneForm)
	local function coordBox(index, placeholder)
		return UI.input({ Size = UDim2.new(0.165, -4, 1, 0), Position = UDim2.new(0.34 + (index - 1) * 0.165, 0, 0, 0), PlaceholderText = placeholder, TextSize = 12 }, zoneForm)
	end
	local zoneX, zoneY, zoneZ, zoneRadius = coordBox(1, "X"), coordBox(2, "Y"), coordBox(3, "Z"), coordBox(4, L("Sentinel.Zones.Radius"))
	local zoneButtons = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 5 }, zonesBox)
	UI.list(zoneButtons, 8, true)
	local zoneHere = UI.button({ Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = T.panel2, Stroke = T.stroke, Text = L("Sentinel.Zones.MyPosition"), TextSize = 12, LayoutOrder = 1 }, zoneButtons)
	local zoneAdd = UI.button({ Size = UDim2.new(0.5, -4, 1, 0), BackgroundColor3 = T.accent, Text = L("Sentinel.Zones.Add"), TextSize = 12, LayoutOrder = 2 }, zoneButtons)
	zoneHere.Activated:Connect(function()
		local character = Core.Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if not root then
			Core.Toast(L("Sentinel.Zones.NoCharacter"), false)
			return
		end
		zoneX.Text, zoneY.Text, zoneZ.Text = tostring(math.floor(root.Position.X + 0.5)), tostring(math.floor(root.Position.Y + 0.5)), tostring(math.floor(root.Position.Z + 0.5))
		if zoneRadius.Text == "" then zoneRadius.Text = "30" end
	end)
	zoneAdd.Activated:Connect(function()
		local x, y, z, radius = tonumber(zoneX.Text), tonumber(zoneY.Text), tonumber(zoneZ.Text), tonumber(zoneRadius.Text)
		if not (x and y and z and radius) then
			Core.Toast(L("Sentinel.InvalidNumber", "X / Y / Z / " .. L("Sentinel.Zones.Radius")), false)
			return
		end
		task.spawn(function()
			local ok, success, reply = pcall(function()
				return R.SentinelAction:InvokeServer("AddZone", { Name = zoneName.Text, X = x, Y = y, Z = z, Radius = radius })
			end)
			if not alive() then return end
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success then
				zoneName.Text, zoneX.Text, zoneY.Text, zoneZ.Text, zoneRadius.Text = "", "", "", "", ""
				refresh(true)
			end
		end)
	end)

	-- historique permanent : dates, infractions, positions (DataStore de l'APM)
	local persistCard = section(9, L("Sentinel.Section.Persist"), BLUE, L("Sentinel.Section.PersistSub"))
	local persistBody = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 3 }, persistCard)
	UI.list(persistBody, 10)
	switchRow(persistBody, 1, L("Sentinel.Persist.Switch"), L("Sentinel.Persist.SwitchDesc"), "PersistHistory")
	local retention = conditional(persistBody, 2, "PersistHistory", true)
	numberField(retention, 1, L("Sentinel.Persist.Days"), L("Sentinel.Persist.DaysHint"), "RetentionDays", 5)
	local persistStatus = wrap(persistBody, "", 11, T.sub, 3)
	local auditTitle = wrap(persistBody, L("Sentinel.Audit.Title"), 11, T.accent, 4, T.fontBold)
	local auditList = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 5 }, persistBody)
	UI.list(auditList, 3)

	local advancedCard = section(10, L("Sentinel.Section.Advanced"), T.sub)
	local advancedToggle = UI.button({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, Stroke = T.stroke, TextSize = 12, LayoutOrder = 2, Text = "" }, advancedCard)
	local advancedBody = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 3, Visible = false }, advancedCard)
	UI.list(advancedBody, 10)
	numberField(advancedBody, 1, L("Sentinel.Adv.Interval"), L("Sentinel.Adv.IntervalHint"), "Interval", 0.5)
	local autoSpeed = conditional(advancedBody, 2, "SpeedLimitEnabled", false)
	numberField(autoSpeed, 1, L("Sentinel.Adv.MaxHorizontal"), L("Sentinel.Adv.MaxHorizontalHint"), "MaxHorizontalSpeed", 10)
	local fixedSpeed = conditional(advancedBody, 3, "SpeedLimitEnabled", true)
	numberField(fixedSpeed, 1, L("Sentinel.Adv.SpeedTolerance"), L("Sentinel.Adv.SpeedToleranceHint"), "SpeedTolerance", 5)
	numberField(advancedBody, 4, L("Sentinel.Adv.Latency"), L("Sentinel.Adv.LatencyHint"), "LatencyAllowance", 5)
	numberField(advancedBody, 5, L("Sentinel.Adv.Samples"), L("Sentinel.Adv.SamplesHint"), "RequiredSamples", 1)
	numberField(advancedBody, 6, L("Sentinel.Adv.Cooldown"), L("Sentinel.Adv.CooldownHint"), "AlertCooldown", 5)
	numberField(advancedBody, 7, L("Sentinel.Adv.MaxAlerts"), L("Sentinel.Adv.MaxAlertsHint"), "MaxAlerts", 25)
	numberField(advancedBody, 8, L("Sentinel.Adv.Memory"), L("Sentinel.Adv.MemoryHint"), "SuspectMemory", 10)
	local function renderAdvanced()
		advancedBody.Visible = advancedOpen
		advancedToggle.Text = advancedOpen and L("Sentinel.Advanced.Hide") or L("Sentinel.Advanced.Show")
	end
	advancedToggle.Activated:Connect(function()
		advancedOpen = not advancedOpen
		renderAdvanced()
	end)

	local settingsCards = { levelCard, detectCard, reactCard, exceptCard, persistCard, advancedCard }

	-- 4. activité serveur, historique, test -------------------------------------------------------------------
	local movesCard = section(11, L("Sentinel.Moves.Title"), BLUE, L("Sentinel.Moves.Sub"))
	local movesList = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 3 }, movesCard)
	UI.list(movesList, 6)
	local movesToggle = UI.button({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, Stroke = T.stroke, TextSize = 12, LayoutOrder = 4, Visible = false, Text = "" }, movesCard)

	local historyCard = section(12, L("Sentinel.History.Title"), T.warn)
	local historyList = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundTransparency = 1, LayoutOrder = 3 }, historyCard)
	UI.list(historyList, 6)
	local historyToggle = UI.button({ Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, Stroke = T.stroke, TextSize = 12, LayoutOrder = 4, Visible = false, Text = "" }, historyCard)

	local testCard = section(13, L("Sentinel.Test.Title"), T.good, L("Sentinel.Test.Desc"))
	local scenarioRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 }, testCard)
	local scenario = UI.picker(scenarioRow, { { "normal", L("Sentinel.Test.Normal") }, { "speed", L("Sentinel.Test.Speed") }, { "teleport", L("Sentinel.Test.Teleport") },
		{ "fly", L("Sentinel.Test.Fly") }, { "walkspeed", L("Sentinel.Test.WalkSpeed") }, { "grace", L("Sentinel.Test.Grace") } }, "teleport")
	local testButton = UI.button({ Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = T.good, LayoutOrder = 4, Text = L("Sentinel.Test.Run"), TextSize = 12 }, testCard)

	-- pied de page : modifications non enregistrées -------------------------------------------------------------
	UI.label({ Size = UDim2.new(1, -250, 1, 0), Position = UDim2.fromOffset(14, 0), TextSize = 12, TextColor3 = T.warn, TextWrapped = true, ZIndex = 6,
		Text = L("Sentinel.Footer.Dirty") }, footer)
	local cancelButton = UI.button({ Size = UDim2.fromOffset(84, 30), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -142, 0.5, 0), TextSize = 12, ZIndex = 6, BackgroundColor3 = T.panel, Stroke = T.stroke,
		Text = L("Sentinel.Footer.Cancel") }, footer)
	local applyButton = UI.button({ Size = UDim2.fromOffset(124, 30), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), TextSize = 12, ZIndex = 6,
		BackgroundColor3 = T.accent, Text = L("Sentinel.Footer.Apply") }, footer)

	updateFooter = function()
		local show = isDirty() and canConfigure()
		applyButton.Active, applyButton.Selectable = not configuring, not configuring
		footer.Visible = show
		scroll.Size = show and UDim2.new(1, 0, 1, -54) or UDim2.new(1, 0, 1, 0)
	end

	-- rendu ----------------------------------------------------------------------------------------------
	local function renderSuspects()
		clear(suspectsList)
		local list = snapshot.Suspects or {}
		if #list == 0 then
			local text = (saved and saved.Enabled == false) and L("Sentinel.Suspects.EmptyOff") or L("Sentinel.Suspects.Empty", snapshot.TrackedPlayers or 0)
			UI.label({ Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, TextSize = 12, TextColor3 = T.sub, Text = text, TextXAlignment = Enum.TextXAlignment.Center }, suspectsList)
			moreButton.Visible = false
			return
		end
		local limit = moreSuspects and math.min(#list, LONG_LIST) or math.min(#list, SHORT_LIST)
		for index = 1, limit do suspectRow(list[index], index) end
		moreButton.Visible = #list > SHORT_LIST
		moreButton.Text = moreSuspects and L("Sentinel.Suspects.Less") or L("Sentinel.Suspects.More", #list - SHORT_LIST)
	end
	local function renderMoves()
		clear(movesList)
		local list = snapshot.ServerMoves or {}
		if #list == 0 then
			UI.label({ Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, TextSize = 12, TextColor3 = T.sub, Text = L("Sentinel.Moves.Empty"), TextXAlignment = Enum.TextXAlignment.Center }, movesList)
			movesToggle.Visible = false
			return
		end
		local limit = movesOpen and #list or math.min(#list, 3)
		for index = 1, limit do eventBlock(movesList, list[index], index, true) end
		movesToggle.Visible = #list > 3
		movesToggle.Text = movesOpen and L("Sentinel.Suspects.Less") or L("Sentinel.Suspects.More", #list - 3)
	end
	local function renderHistory()
		clear(historyList)
		local list = snapshot.Alerts or {}
		if #list == 0 then
			UI.label({ Size = UDim2.new(1, 0, 0, 30), TextWrapped = true, TextSize = 12, TextColor3 = T.sub, Text = L("Sentinel.History.Empty"), TextXAlignment = Enum.TextXAlignment.Center }, historyList)
			historyToggle.Visible = false
			return
		end
		local limit = moreHistory and #list or math.min(#list, HISTORY_SHORT)
		for index = 1, limit do
			local alert = list[index]
			local block = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Y, BackgroundColor3 = T.panel, LayoutOrder = index, Corner = 6,
				Stroke = alert.Test and T.good or T.stroke }, historyList)
			UI.list(block, 3)
			UI.padding(block, 8)
			wrap(block, (alert.Test and (L("Sentinel.Test.Tag") .. " · ") or "") .. tostring(alert.Name or "?") .. " · " .. kindName(alert.Kind) .. " · " .. ago(alert.Time), 12, T.text, 1, T.fontBold)
			wrap(block, Core.Text(alert.Detail), 12, T.sub, 2)
			if not alert.Test then
				wrap(block, originLabel(alert.Origin, alert.ConfidenceLevel) .. "  ·  " .. Core.Text(alert.Reaction or ""), 11, ORIGIN_COLOR[alert.Origin] or T.sub, 3)
			end
		end
		historyToggle.Visible = #list > HISTORY_SHORT
		historyToggle.Text = moreHistory and L("Sentinel.Suspects.Less") or L("Sentinel.History.More", #list - HISTORY_SHORT)
	end

	local function renderZones()
		clear(zonesList)
		local zones = snapshot.Config and snapshot.Config.SafeZones or {}
		if #zones == 0 then
			wrap(zonesList, L("Sentinel.Zones.Empty"), 11, T.sub, 1)
			return
		end
		for index, zone in zones do
			local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel2, LayoutOrder = index, Corner = 6 }, zonesList)
			UI.label({ Size = UDim2.new(1, -96, 1, 0), Position = UDim2.fromOffset(8, 0), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
				Text = L("Sentinel.Zones.Item", (zone.Name ~= nil and zone.Name ~= "") and zone.Name or ("#" .. tostring(zone.Id)),
					string.format("%d, %d, %d", zone.X or 0, zone.Y or 0, zone.Z or 0), zone.Radius or 0) }, row)
			local remove = UI.button({ Size = UDim2.fromOffset(80, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), BackgroundColor3 = T.panel,
				Stroke = T.stroke, TextSize = 11, Text = L("Sentinel.Zones.Remove") }, row)
			remove.Activated:Connect(function()
				task.spawn(function()
					local ok, success, reply = pcall(function() return R.SentinelAction:InvokeServer("RemoveZone", zone.Id) end)
					if not alive() then return end
					Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
					if ok and success then refresh(true) end
				end)
			end)
		end
	end

	local function renderPersist()
		local p = snapshot.Persist or {}
		local text = p.Persist == false and L("Sentinel.Persist.Off") or L("Sentinel.Persist.Mode." .. tostring(p.Mode or "Unavailable"))
		text ..= "  ·  " .. L("Sentinel.Persist.Counts", p.Stored or 0, p.PendingEvents or 0)
		if (tonumber(p.LastWrite) or 0) > 0 then text ..= "  ·  " .. L("Sentinel.Persist.LastWrite", Core.FormatDate(p.LastWrite)) end
		persistStatus.Text = text
		clear(auditList)
		local entries = snapshot.Audit or {}
		auditTitle.Visible = #entries > 0
		for index, item in entries do
			if index > 6 then break end
			wrap(auditList, Core.FormatDate(item.t) .. "  ·  " .. tostring(item.by or "?") .. "  ·  " .. L("Sentinel.Audit." .. tostring(item.a), tostring(item.d or "")), 11, T.sub, index)
		end
	end

	render = function()
		if not alive() or not snapshot then return end
		if snapshot.Allowed ~= true then
			statePill.Text, statePill.TextColor3 = L("Sentinel.State.Denied"), T.bad
			return
		end
		renderSource()
		bounds = snapshot.Bounds or bounds
		local cfg = snapshot.Config or {}
		if not saved or not isDirty() then
			-- les zones sûres ont leurs propres actions (AddZone / RemoveZone) : elles ne passent pas par le brouillon
			saved = {}
			for key, value in cfg do
				if key ~= "SafeZones" then saved[key] = value end
			end
			draft = {}
			for key, value in cfg do
				if key ~= "SafeZones" then draft[key] = value end
			end
		end
		if snapshot.Disabled then
			statePill.Text, statePill.TextColor3 = L("Sentinel.State.ModuleOff"), T.bad
		elseif cfg.Enabled then
			statePill.Text, statePill.TextColor3 = L("Sentinel.State.On") .. " · " .. L("Sentinel.Mode." .. tostring(cfg.Mode)), T.good
		else
			statePill.Text, statePill.TextColor3 = L("Sentinel.State.Off"), T.warn
		end
		watchedValue.Text = tostring(snapshot.TrackedPlayers or 0)
		suspectsValue.Text = tostring(#(snapshot.Suspects or {}))
		alertsValue.Text = tostring(snapshot.TotalAlerts or 0)
		local manage = canConfigure() and not snapshot.Disabled
		for _, card in settingsCards do card.Visible = manage end
		masterHolder.Visible = manage
		clearAllButton.Visible = manage
		testCard.Visible = Core.HasPermission("Sentinel.Test") and not snapshot.Disabled
		kickRow.Visible = snapshot.KickAllowedByServer == true
		kickNote.Visible = snapshot.KickAllowedByServer ~= true
		if helpOpen == nil then
			helpOpen = #(snapshot.Suspects or {}) == 0 and (snapshot.TotalAlerts or 0) == 0
		end
		helpCard.Visible = helpOpen
		helpButton.Text = helpOpen and L("Sentinel.Help.Hide") or L("Sentinel.Help.Show")
		renderAdvanced()
		syncControls()
		updateFooter()
		renderSuspects()
		renderMoves()
		renderHistory()
		renderPersist()
		renderZones()
	end

	local function signatureOf(data)
		-- le dernier terme force un nouveau rendu toutes les 15 s : les « il y a X s » restent justes
		local parts = { tostring(data.ConfigSource and data.ConfigSource.Revision), tostring(data.ConfigSource and data.ConfigSource.Mode),
			tostring(data.TotalAlerts), tostring(data.ServerMoveCount), tostring(data.TrackedPlayers), tostring(#(data.Suspects or {})),
			tostring(math.floor(os.clock() / 15)) }
		for index, suspect in data.Suspects or {} do
			if index > LONG_LIST then break end
			table.insert(parts, suspect.UserId .. ":" .. suspect.Score .. ":" .. suspect.Count .. ":" .. tostring(suspect.Online))
		end
		for key, value in data.Config or {} do
			if key ~= "SafeZones" then table.insert(parts, key .. "=" .. tostring(value)) end
		end
		for _, zone in (data.Config and data.Config.SafeZones) or {} do
			table.insert(parts, "z" .. tostring(zone.Id) .. ":" .. tostring(zone.X) .. "," .. tostring(zone.Y) .. "," .. tostring(zone.Z) .. "," .. tostring(zone.Radius))
		end
		return table.concat(parts, "|")
	end
	refresh = function(force)
		if loading or not alive() then return end
		loading = true
		task.spawn(function()
			local ok, data = pcall(function() return R.GetSentinel:InvokeServer() end)
			loading = false
			if not alive() then return end
			if not ok or type(data) ~= "table" then
				statePill.Text, statePill.TextColor3 = Core.L("Common.ServerError"), T.bad
				return
			end
			receivedAt = os.clock()
			local signature = data.Allowed == true and signatureOf(data) or "denied"
			snapshot = data
			if force or signature ~= lastSignature then
				lastSignature = signature
				render()
			end
		end)
	end

	-- actions ---------------------------------------------------------------------------------------------
	sourceToggle.Activated:Connect(function()
		sourceOpen = not sourceOpen
		if snapshot and snapshot.Allowed == true then renderSource() end
	end)
	UI.Confirmable(resetButton, true, function()
		if configuring or not canConfigure() or not snapshot or snapshot.Allowed ~= true then return end
		if not snapshot.ConfigSource or not snapshot.ConfigSource.HasOverrides or snapshot.ConfigSource.Storage == "ReadOnly" then return end
		configuring = true
		renderSource()
		updateFooter()
		task.spawn(function()
			local ok, success, reply = pcall(function() return R.ConfigureSentinel:InvokeServer({ ResetToScript = true }) end)
			if not alive() then return end
			configuring = false
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success then saved, draft = nil, nil refresh(true) else renderSource() updateFooter() end
		end)
	end)
	refreshButton.Activated:Connect(function() refresh(true) end)
	helpButton.Activated:Connect(function()
		helpOpen = not helpOpen
		helpCard.Visible = helpOpen
		helpButton.Text = helpOpen and L("Sentinel.Help.Hide") or L("Sentinel.Help.Show")
	end)
	moreButton.Activated:Connect(function()
		moreSuspects = not moreSuspects
		if snapshot then renderSuspects() end
	end)
	movesToggle.Activated:Connect(function()
		movesOpen = not movesOpen
		if snapshot then renderMoves() end
	end)
	historyToggle.Activated:Connect(function()
		moreHistory = not moreHistory
		if snapshot then renderHistory() end
	end)
	UI.Confirmable(clearAllButton, true, function()
		task.spawn(function()
			local ok, success, reply = pcall(function() return R.SentinelAction:InvokeServer("ClearAll") end)
			if not alive() then return end
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success then table.clear(openRows) refresh(true) end
		end)
	end)
	cancelButton.Activated:Connect(function()
		if saved then
			draft = {}
			for key, value in saved do draft[key] = value end
			syncControls()
			updateFooter()
		end
	end)
	applyButton.Activated:Connect(function()
		if configuring or not canConfigure() or not draft or not isDirty() then return end
		configuring = true
		renderSource()
		updateFooter()
		local patch = {}
		for key, value in draft do patch[key] = value end
		applyButton.Text = "..."
		task.spawn(function()
			local ok, success, reply = pcall(function() return R.ConfigureSentinel:InvokeServer(patch) end)
			if not alive() then return end
			configuring = false
			applyButton.Text = L("Sentinel.Footer.Apply")
			renderSource()
			updateFooter()
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success then
				saved = nil
				refresh(true)
			end
		end)
	end)
	testButton.Activated:Connect(function()
		task.spawn(function()
			local ok, success, reply = pcall(function() return R.TestSentinel:InvokeServer(scenario.Get()) end)
			if not alive() then return end
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success then refresh(true) end
		end)
	end)
	Core.On(Core.AccessChanged.Event, function()
		Core.SetTabVisible("Sentinel", Core.HasPermission("Sentinel.View"))
		if snapshot then render() end
		if page.Visible then refresh(true) end
	end)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then refresh(true) end
	end)
	-- mise à jour douce tant que la page est ouverte
	task.spawn(function()
		while alive() do
			task.wait(REFRESH_SECONDS)
			if alive() and page.Visible and Core.Gui and Core.Gui.Enabled then refresh(false) end
		end
	end)
	renderAdvanced()
	helpCard.Visible = false
	refresh(true)
end

return Page
