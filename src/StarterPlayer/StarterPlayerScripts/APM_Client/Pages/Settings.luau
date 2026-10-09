--[[
	Settings : onglet « Paramètres » (grade Settings.ManagerRank et plus ; le serveur revérifie chaque changement).
	  - SERVEUR : verrouillage (les nouveaux joueurs sans grade sont refusés) ;
	  - GRADES : qui a quel grade ; donner / retirer un grade par pseudo ou UserId (grades inférieurs au sien) ;
	  - ACCÈS AUX MODULES : la matrice « module x grade » (une colonne par grade, sauf le SuperRank qui a tout).
]]
local Page = { Id = "Settings", Order = 7, Label = "Tab.Settings" }

function Page.Visible(Core)
	return Core.HasPermission("APM.ManagePermissions")
end

function Page.Build(Core, page)
	local UI, T, R, L = Core.UI, Core.T, Core.R, Core.L
	local myLevel = Core.RankLevel(Core.MyRank)
	local isSuper = Core.IsSuper()

	local scroll = UI.scroll({ Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)

	local function call(remote, ...)
		local args = table.pack(...)
		local ok, success, message = pcall(function()
			return remote:InvokeServer(table.unpack(args, 1, args.n))
		end)
		if not ok then
			return false, L("Common.ServerError")
		end
		return success, message
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
				local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.panel, LayoutOrder = index, Corner = 8 }, staffHolder)
				table.insert(staffRows, row)
				UI.new("Frame", { Size = UDim2.fromOffset(8, 8), Position = UDim2.fromOffset(10, 13), BackgroundColor3 = entry.online and T.good or T.sub, Corner = 4 }, row)
				UI.label({ Size = UDim2.new(1, -270, 1, 0), Position = UDim2.fromOffset(26, 0), TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd,
					Text = ("%s  (%s)%s"):format(tostring(entry.name), tostring(entry.userId), entry.fixed and ("  ·  " .. L("Settings.Fixed")) or "") }, row)
				UI.label({ Size = UDim2.fromOffset(110, 20), Position = UDim2.new(1, -40, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 0,
					BackgroundColor3 = Core.RankColor(entry.rank), Font = T.fontBold, TextSize = 11, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd, Text = Core.RankName(entry.rank), Corner = 10 }, row)
				local rank = Core.RankById[entry.rank]
				local removable = not entry.fixed and rank and not rank.Fixed and (isSuper or rank.Level < myLevel) and entry.userId ~= Core.Player.UserId
				if removable then
					local remove = UI.button({ Size = UDim2.fromOffset(26, 24), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Color3.fromRGB(110, 50, 50),
						Text = "X", TextSize = 12 }, row)
					UI.Confirmable(remove, true, function()
						task.spawn(function()
							local success, message = call(R.SetRank, entry.userId, "")
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

	-- Matrice d'accès ------------------------------------------------------------------------------------------------
	local matrixCard = UI.card(scroll, 3)
	UI.sectionHeader(L("Settings.Access"), Color3.fromRGB(88, 128, 232), matrixCard, 1)
	UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 11, TextColor3 = T.sub, TextWrapped = true, LayoutOrder = 2,
		Text = L("Settings.AccessHint", Core.RankName(Core.SuperRank)) }, matrixCard)

	local columns = {}
	for _, rank in Core.RankList do
		if rank.Id ~= Core.SuperRank then
			table.insert(columns, rank)
		end
	end
	local WIDTH = 64
	local function columnX(index)
		return -(#columns - index + 1) * WIDTH
	end
	local header = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 3 }, matrixCard)
	UI.label({ Size = UDim2.new(1, -(#columns * WIDTH + 8), 1, 0), Font = T.fontBold, TextSize = 12, TextColor3 = T.sub, Text = L("Settings.Module") }, header)
	for index, rank in columns do
		UI.label({ Size = UDim2.fromOffset(WIDTH - 4, 22), Position = UDim2.new(1, columnX(index), 0, 0), Font = T.fontBold, TextSize = 11, TextColor3 = Core.RankColor(rank.Id),
			TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd, Text = Core.RankName(rank.Id) }, header)
	end
	local matrixHolder = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4 }, matrixCard)
	UI.list(matrixHolder, 3)

	local matrixSwitches = {} -- [module] = { [grade] = interrupteur }
	local syncing = false
	local function syncMatrix()
		syncing = true
		for name, switches in matrixSwitches do
			local entry = Core.ModuleAccess[name]
			for rankId, switch in switches do
				if type(entry) == "table" then
					switch.Set(entry[rankId] == true)
				else
					switch.Set(Core.ClientModules[name] ~= nil)
				end
			end
		end
		syncing = false
	end

	for index, module in Core.AllModules() do
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundColor3 = T.panel, LayoutOrder = index, Corner = 6 }, matrixHolder)
		UI.label({ Size = UDim2.new(1, -(#columns * WIDTH + 12), 1, 0), Position = UDim2.fromOffset(8, 0), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
			Text = Core.Text(module.Label) .. (module.ClientSide and L("Settings.ClientTag") or "") }, row)
		local switches = {}
		for columnIndex, rank in columns do
			local slot = UI.new("Frame", { Size = UDim2.fromOffset(WIDTH, 30), Position = UDim2.new(1, columnX(columnIndex), 0, 0), BackgroundTransparency = 1 }, row)
			local editable = isSuper or rank.Level < myLevel
			local switch
			switch = UI.Switch(slot, false, function(state)
				if syncing then
					return
				end
				local success, message = call(R.SetModuleAccess, module.Name, rank.Id, state)
				if not success then
					Core.Toast(message or L("Settings.Refused"), false)
					switch.Set(not state)
					return
				end
				Core.ModuleAccess[module.Name] = type(Core.ModuleAccess[module.Name]) == "table" and Core.ModuleAccess[module.Name] or {}
				Core.ModuleAccess[module.Name][rank.Id] = state
				Core.AccessChanged:Fire()
			end, UDim2.fromOffset(math.floor((WIDTH - 46) / 2), 3))
			if not editable then
				switch.Frame.BackgroundTransparency = 0.6
				switch.Frame.Active = false
				switch.Frame.AutoButtonColor = false
			end
			switches[rank.Id] = switch
		end
		matrixSwitches[module.Name] = switches
	end

	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			refreshStaff()
			task.spawn(function()
				Core.RefreshAccess()
				if matrixHolder.Parent then
					syncMatrix()
				end
			end)
		end
	end)
	Core.On(Core.AccessChanged.Event, function()
		if not syncing then
			syncMatrix()
		end
	end)
	syncMatrix()
	refreshStaff()
end

return Page
