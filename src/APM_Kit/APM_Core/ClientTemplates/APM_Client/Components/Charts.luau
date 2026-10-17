--[[
	Charts : graphiques simples en Frames pour les pages du panneau (onglet Stats).
	  Charts.Columns(Core, parent, { Title, Unit, Decimals, Height, Order }) -> { Set(points, capacity), Frame }
	     points : { { Time, Value, Bad } } ; Bad (facultatif) = part en échec, empilée en couleur T.bad.
	     capacity (facultatif) : nombre de points d'un historique plein ; les barres gardent leur largeur et se remplissent depuis la droite.
	     Une seule série par graphique ; la ligne de lecture affiche la barre survolée (sinon la dernière).
	  Charts.Bars(Core, parent, { Title, Order, Empty }) -> { Set(rows), Frame }
	     rows : { { Label, Value, Bad, Detail } } ; barres horizontales classées comme fournies.
]]
local Charts = {}

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

function Charts.Format(value, decimals)
	if not finite(value) then return "—" end
	if math.abs(value) >= 10000 then return string.format("%.1fk", value / 1000) end
	return string.format("%." .. tostring(decimals or 0) .. "f", value)
end

function Charts.Columns(Core, parent, options)
	local UI, T = Core.UI, Core.T
	local height = options.Height or 96
	local unit = options.Unit and (" " .. options.Unit) or ""
	local frame = UI.new("Frame", { Name = options.Name or "ColumnChart", Size = UDim2.new(1, 0, 0, height + 58), BackgroundTransparency = 1, LayoutOrder = options.Order or 1 }, parent)
	UI.label({ Name = "Title", Size = UDim2.new(0.5, 0, 0, 18), Font = T.fontBold, TextSize = 12, TextColor3 = T.text, Text = options.Title or "",
		TextTruncate = Enum.TextTruncate.AtEnd }, frame)
	local readout = UI.label({ Name = "Readout", Size = UDim2.new(0.5, 0, 0, 18), Position = UDim2.fromScale(0.5, 0), TextSize = 12, TextColor3 = T.sub,
		TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd, Text = "" }, frame)
	local axis = UI.new("Frame", { Name = "Axis", Size = UDim2.new(0, 44, 0, height), Position = UDim2.fromOffset(0, 24), BackgroundTransparency = 1 }, frame)
	local maxLabel = UI.label({ Size = UDim2.new(1, -6, 0, 12), TextSize = 10, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Right, Text = "" }, axis)
	local midLabel = UI.label({ Size = UDim2.new(1, -6, 0, 12), Position = UDim2.new(0, 0, 0.5, -6), TextSize = 10, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Right,
		Text = "" }, axis)
	UI.label({ Size = UDim2.new(1, -6, 0, 12), Position = UDim2.new(0, 0, 1, -12), TextSize = 10, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Right,
		Text = "0" }, axis)
	local plot = UI.new("Frame", { Name = "Plot", Size = UDim2.new(1, -48, 0, height), Position = UDim2.fromOffset(48, 24), BackgroundTransparency = 1,
		ClipsDescendants = true }, frame)
	for _, y in { 0, 0.5, 1 } do
		UI.new("Frame", { Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, y, y == 1 and -1 or 0), BackgroundColor3 = T.stroke, BackgroundTransparency = y == 1 and 0 or 0.5 }, plot)
	end
	local bars = UI.new("Frame", { Name = "Bars", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, plot)
	local startLabel = UI.label({ Size = UDim2.new(0.5, -24, 0, 14), Position = UDim2.fromOffset(48, height + 28), TextSize = 10, TextColor3 = T.sub,
		Text = "" }, frame)
	local endLabel = UI.label({ Size = UDim2.new(0.5, -24, 0, 14), Position = UDim2.new(0.5, 24, 0, height + 28), TextSize = 10, TextColor3 = T.sub,
		TextXAlignment = Enum.TextXAlignment.Right, Text = "" }, frame)
	local empty = UI.label({ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, TextColor3 = T.sub, Visible = false,
		Text = Core.Text({ fr = "Pas encore de relevé (un point toutes les 15 s).", en = "No readings yet (one point every 15 s)." }) }, plot)

	local object = { Frame = frame }
	local latest = ""
	local function describe(point)
		local text = os.date("%H:%M:%S", point.Time) .. " · " .. Charts.Format(point.Value, options.Decimals) .. unit
		if finite(point.Bad) and point.Bad > 0 then
			text ..= " · " .. Charts.Format(point.Bad, 0) .. Core.Text({ fr = " en échec", en = " failed" })
		end
		return text
	end
	function object.Set(points, capacity)
		for _, child in bars:GetChildren() do child:Destroy() end
		points = points or {}
		local count, top = #points, 0
		local slots = math.max(tonumber(capacity) or count, count, 1)
		for _, point in points do
			if finite(point.Value) then top = math.max(top, point.Value) end
		end
		empty.Visible = count == 0
		if top <= 0 then top = 1 end
		maxLabel.Text = Charts.Format(top, top < 10 and options.Decimals or 0)
		midLabel.Text = Charts.Format(top / 2, (top / 2) % 1 == 0 and 0 or math.max(options.Decimals or 0, 1))
		startLabel.Text = count > 0 and os.date("%H:%M", points[1].Time) or ""
		endLabel.Text = count > 0 and os.date("%H:%M", points[count].Time) or ""
		latest = count > 0 and describe(points[count]) or ""
		readout.Text = latest
		readout.TextColor3 = T.sub
		local slotWidth = plot.AbsoluteSize.X / slots
		local gap = slotWidth >= 6 and 2 or 0
		for index, point in points do
			local slot = UI.new("Frame", { Name = "Slot" .. index, Size = UDim2.new(1 / slots, 0, 1, 0), Position = UDim2.fromScale((slots - count + index - 1) / slots, 0),
				BackgroundColor3 = T.text, BackgroundTransparency = 1, Active = true }, bars)
			local value = finite(point.Value) and math.max(point.Value, 0) or 0
			local ratio = value / top
			if value > 0 then
				local bar = UI.new("Frame", { Size = UDim2.new(1, -gap, ratio, 0), Position = UDim2.new(0, gap / 2, 1 - ratio, 0), BackgroundColor3 = options.Color or T.accent,
					Corner = slotWidth >= 10 and 3 or nil }, slot)
				local bad = finite(point.Bad) and math.clamp(point.Bad, 0, value) or 0
				if bad > 0 then
					UI.new("Frame", { Size = UDim2.fromScale(1, bad / value), Position = UDim2.fromScale(0, 1 - bad / value), BackgroundColor3 = T.bad }, bar)
				end
			end
			slot.MouseEnter:Connect(function()
				slot.BackgroundTransparency = 0.9
				readout.Text = describe(point)
				readout.TextColor3 = T.text
			end)
			slot.MouseLeave:Connect(function()
				slot.BackgroundTransparency = 1
				readout.Text = latest
				readout.TextColor3 = T.sub
			end)
			slot.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.Touch then
					readout.Text = describe(point)
					readout.TextColor3 = T.text
				end
			end)
		end
	end
	return object
end

function Charts.Bars(Core, parent, options)
	local UI, T = Core.UI, Core.T
	local frame = UI.new("Frame", { Name = options.Name or "BarChart", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
		LayoutOrder = options.Order or 1 }, parent)
	UI.list(frame, 5)
	UI.label({ Name = "Title", Size = UDim2.new(1, 0, 0, 18), Font = T.fontBold, TextSize = 12, TextColor3 = T.text, Text = options.Title or "", LayoutOrder = 0 }, frame)
	local object = { Frame = frame }
	function object.Set(rows)
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "Title" then child:Destroy() end
		end
		rows = rows or {}
		local top = 0
		for _, row in rows do
			if finite(row.Value) then top = math.max(top, row.Value) end
		end
		if #rows == 0 then
			UI.label({ Size = UDim2.new(1, 0, 0, 22), TextSize = 12, TextColor3 = T.sub, LayoutOrder = 1,
				Text = options.Empty or Core.Text({ fr = "Aucune donnée pour l'instant.", en = "No data yet." }) }, frame)
			return
		end
		for index, row in rows do
			local value = finite(row.Value) and math.max(row.Value, 0) or 0
			local ratio = top > 0 and value / top or 0
			local line = UI.new("Frame", { Name = "Row" .. index, Size = UDim2.new(1, 0, 0, row.Detail and 30 or 20), BackgroundTransparency = 1, LayoutOrder = index }, frame)
			UI.label({ Size = UDim2.new(0.34, -8, 0, 20), TextSize = 12, TextColor3 = T.text, TextTruncate = Enum.TextTruncate.AtEnd, Text = tostring(row.Label) }, line)
			local track = UI.new("Frame", { Size = UDim2.new(0.66, -56, 0, 10), Position = UDim2.new(0.34, 0, 0, 5), BackgroundColor3 = T.panel, Corner = 4 }, line)
			if ratio > 0 then
				local fill = UI.new("Frame", { Size = UDim2.fromScale(ratio, 1), BackgroundColor3 = row.Color or T.accent, Corner = 4 }, track)
				local bad = finite(row.Bad) and math.clamp(row.Bad, 0, value) or 0
				if bad > 0 then
					UI.new("Frame", { Size = UDim2.fromScale(bad / value, 1), Position = UDim2.fromScale(1 - bad / value, 0), BackgroundColor3 = T.bad, Corner = 4 }, fill)
				end
			end
			UI.label({ Size = UDim2.new(0, 50, 0, 20), Position = UDim2.new(1, -50, 0, 0), TextSize = 12, Font = T.fontBold, TextColor3 = T.text,
				TextXAlignment = Enum.TextXAlignment.Right, Text = row.ValueText or Charts.Format(value, row.Decimals) }, line)
			if row.Detail then
				UI.label({ Size = UDim2.new(0.66, -56, 0, 12), Position = UDim2.new(0.34, 0, 0, 18), TextSize = 10, TextColor3 = T.sub,
					TextTruncate = Enum.TextTruncate.AtEnd, Text = tostring(row.Detail) }, line)
			end
		end
	end
	return object
end

return Charts
