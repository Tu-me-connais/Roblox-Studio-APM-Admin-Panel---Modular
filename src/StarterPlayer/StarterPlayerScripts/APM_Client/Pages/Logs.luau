--[[
	Logs : onglet « Logs ». Journal des actions (tous serveurs), en direct pour les nouvelles ; filtres par catégorie, gravité et texte.
	Chaque entrée est affichée dans la langue de l'admin qui la lit (le serveur enregistre des messages traduisibles).
]]
local Page = { Id = "Logs", Order = 6, Label = "Tab.Logs" }

local MAX_SHOWN = 150
local BASE_CATEGORIES = { "Players", "Moderation", "Game", "Bans", "Ranks", "Access", "System" }

function Page.Build(Core, page)
	local UI, T, R, L = Core.UI, Core.T, Core.R, Core.L
	local COLORS = { info = T.sub, warning = T.warn, danger = T.bad }

	-- catégories connues + celles des modules
	local categories = { { "all", "Logs.AllCategories" } }
	local seen = {}
	local function addCategory(id)
		if not seen[id] then
			seen[id] = true
			table.insert(categories, { id, "Cat." .. id })
		end
	end
	for _, id in BASE_CATEGORIES do
		addCategory(id)
	end
	for _, module in Core.ServerModules do
		if type(module.Category) == "string" then
			addCategory(module.Category)
		end
	end

	local filterRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, page)
	local categoryPicker = UI.picker(filterRow, categories, "all", UDim2.new(0, 150, 1, 0), UDim2.new())
	local levelPicker = UI.picker(filterRow, { { "all", "Logs.AllLevels" }, { "info", "Logs.Info" }, { "warning", "Logs.Warning" }, { "danger", "Logs.Danger" } }, "all",
		UDim2.new(0, 130, 1, 0), UDim2.fromOffset(158, 0))
	local search = UI.input({ Size = UDim2.new(1, -404, 1, 0), Position = UDim2.fromOffset(296, 0), PlaceholderText = L("Common.Search"), TextSize = 13 }, filterRow)
	local refreshButton = UI.button({ Size = UDim2.fromOffset(100, 30), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Text = L("Common.Refresh"), TextSize = 12 }, filterRow)

	local scroll = UI.scroll({ Size = UDim2.new(1, 0, 1, -38), Position = UDim2.fromOffset(0, 38) }, page)
	UI.list(scroll, 5)

	local logs = {}
	local rowFrames = {}
	local loading = false

	local function texts(entry)
		return {
			action = Core.ActionLabel(entry.action),
			detail = Core.Text(entry.detail),
			category = Core.Text("Cat." .. tostring(entry.category)),
		}
	end

	local function passes(entry, text)
		if categoryPicker.Get() ~= "all" and entry.category ~= categoryPicker.Get() then
			return false
		end
		if levelPicker.Get() ~= "all" and entry.level ~= levelPicker.Get() then
			return false
		end
		local query = string.lower(search.Text)
		if query ~= "" then
			local haystack = string.lower(table.concat({ entry.actor or "", text.action, entry.target or "", text.detail }, " "))
			return string.find(haystack, query, 1, true) ~= nil
		end
		return true
	end

	local function escape(text)
		text = string.gsub(tostring(text), "&", "&amp;")
		text = string.gsub(text, "<", "&lt;")
		text = string.gsub(text, ">", "&gt;")
		return text
	end

	local function render()
		for _, frame in rowFrames do
			frame:Destroy()
		end
		table.clear(rowFrames)
		local shown = 0
		for _, entry in logs do
			local text = texts(entry)
			if passes(entry, text) then
				shown += 1
				if shown > MAX_SHOWN then
					break
				end
				local row = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = T.panel2, LayoutOrder = shown, Corner = 8 }, scroll)
				table.insert(rowFrames, row)
				UI.new("Frame", { Size = UDim2.new(0, 4, 1, -10), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = COLORS[entry.level] or T.sub, Corner = 2 }, row)
				local label = UI.label({ Size = UDim2.new(1, -24, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.fromOffset(16, 0), TextSize = 12, TextWrapped = true, RichText = true,
					Text = ('<font color="#9aa0b0">%s  [%s]</font>\n<b>%s</b>  >  %s  >  %s\n<font color="#9aa0b0">%s</font>'):format(
						escape(Core.FormatDate(entry.time)), escape(text.category), escape(entry.actor or "?"), escape(text.action), escape(entry.target or "-"), escape(text.detail)) }, row)
				UI.padding(label, 6, 0, 0)
			end
		end
		if shown == 0 then
			local empty = UI.label({ Size = UDim2.new(1, -6, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.sub,
				Text = loading and L("Common.Loading") or L("Logs.Empty") }, scroll)
			table.insert(rowFrames, empty)
		end
	end

	local function refresh()
		if loading then
			return
		end
		loading = true
		render()
		task.spawn(function()
			local ok, list = pcall(function()
				return R.GetLogs:InvokeServer()
			end)
			loading = false
			if not scroll.Parent then
				return
			end
			if ok and type(list) == "table" then
				logs = list
			end
			render()
		end)
	end

	Core.On(R.LogAdded.OnClientEvent, function(entry)
		if type(entry) ~= "table" then
			return
		end
		table.insert(logs, 1, entry)
		while #logs > 300 do
			table.remove(logs)
		end
		if page.Visible then
			render()
		end
	end)

	categoryPicker.Changed = render
	levelPicker.Changed = render
	search:GetPropertyChangedSignal("Text"):Connect(render)
	refreshButton.Activated:Connect(refresh)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			refresh()
		end
	end)
	render()
end

return Page

