--[[
	Bans : onglet « Bannissements ». Liste des bans enregistrés (tous serveurs), levée d'un ban (module Unban),
	bannissement d'un compte par pseudo exact ou UserId (même jamais venu dans le jeu).
]]
local Page = { Id = "Bans", Order = 5, Label = "Tab.Bans", Handles = { "Bans" } }

function Page.Build(Core, page)
	local UI, T, R, L = Core.UI, Core.T, Core.R, Core.L

	local scroll = UI.scroll({ Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 8)

	local banCard = UI.card(scroll, 1)
	UI.sectionHeader(L("Bans.Title"), Color3.fromRGB(205, 95, 95), banCard, 1)
	local accountBox = UI.input({ Size = UDim2.new(1, 0, 0, 30), PlaceholderText = L("Bans.AccountHint"), TextSize = 13, LayoutOrder = 2 }, banCard)
	local minutesBox = UI.input({ Size = UDim2.new(1, 0, 0, 30), PlaceholderText = L("Bans.MinutesHint"), TextSize = 13, LayoutOrder = 3 }, banCard)
	local banButton = UI.button({ Size = UDim2.new(1, 0, 0, 32), BackgroundColor3 = Color3.fromRGB(190, 60, 60), Text = L("Bans.Ban"), TextSize = 13, LayoutOrder = 4 }, banCard)

	local searchRow = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 30), BackgroundTransparency = 1, LayoutOrder = 2 }, scroll)
	local search = UI.input({ Size = UDim2.new(1, -110, 1, 0), PlaceholderText = L("Bans.Filter"), TextSize = 13 }, searchRow)
	local refreshButton = UI.button({ Size = UDim2.fromOffset(102, 30), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0), Text = L("Common.Refresh"), TextSize = 12 }, searchRow)

	local rows = {}
	local bans, loading = {}, false

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

	local function render()
		for _, row in rows do
			row:Destroy()
		end
		table.clear(rows)
		local query = string.lower(search.Text)
		local shown = 0
		for _, ban in bans do
			local reason = ban.reason and Core.Text(ban.reason) or nil
			local haystack = string.lower(table.concat({ ban.name or "", ban.display or "", tostring(ban.userId), ban.by or "", reason or "" }, " "))
			if query == "" or string.find(haystack, query, 1, true) then
				shown += 1
				local card = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 64), BackgroundColor3 = T.panel2, LayoutOrder = 10 + shown, Corner = 10, Stroke = T.stroke }, scroll)
				table.insert(rows, card)
				UI.label({ Size = UDim2.new(1, -120, 0, 20), Position = UDim2.fromOffset(12, 6), Font = T.fontBold, TextSize = 14, TextTruncate = Enum.TextTruncate.AtEnd,
					Text = ("%s  (@%s)"):format(ban.display or ban.name or "?", ban.name or "?") }, card)
				local expire = (ban.expire or 0) > 0 and L("Bans.Until", Core.FormatDate(ban.expire)) or L("Common.Permanent")
				UI.label({ Size = UDim2.new(1, -120, 0, 16), Position = UDim2.fromOffset(12, 26), TextSize = 12, TextColor3 = T.sub, TextTruncate = Enum.TextTruncate.AtEnd,
					Text = L("Bans.Line", ban.userId, ban.by or "?", Core.FormatDate(ban.time), expire) }, card)
				UI.label({ Size = UDim2.new(1, -120, 0, 16), Position = UDim2.fromOffset(12, 43), TextSize = 12, TextColor3 = T.warn, TextTruncate = Enum.TextTruncate.AtEnd,
					Text = reason and L("Bans.Reason", reason) or L("Bans.NoReason") }, card)
				local unban = UI.button({ Size = UDim2.fromOffset(100, 32), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Color3.fromRGB(70, 130, 90),
					Text = L("Bans.Unban"), TextSize = 12, Visible = Core.CanUse("Unban") }, card)
				UI.Confirmable(unban, true, function()
					Core.Action("Unban", nil, ban.userId)
					task.delay(1.2, function()
						if page.Parent then
							Core.RefreshBans()
						end
					end)
				end)
			end
		end
		if shown == 0 then
			local empty = UI.label({ Size = UDim2.new(1, -6, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = T.sub, LayoutOrder = 10,
				Text = loading and L("Common.Loading") or L("Bans.None") }, scroll)
			table.insert(rows, empty)
		end
	end

	function Core.RefreshBans()
		if loading then
			return
		end
		loading = true
		render()
		task.spawn(function()
			local ok, list = pcall(function()
				return R.GetBanned:InvokeServer()
			end)
			loading = false
			if not scroll.Parent then
				return
			end
			if ok and type(list) == "table" then
				bans = list
			end
			render()
		end)
	end

	UI.Confirmable(banButton, true, function()
		local text, minutes = accountBox.Text, tonumber(minutesBox.Text) or 0
		task.spawn(function()
			local userId = resolve(text)
			if not userId then
				Core.Toast(L("Common.AccountNotFound"), false)
				return
			end
			local ok, success, message = pcall(function()
				return R.BanUserId:InvokeServer(userId, minutes)
			end)
			Core.Toast(ok and (message or "") or L("Common.ServerError"), ok and success == true)
			if ok and success then
				accountBox.Text = ""
				minutesBox.Text = ""
				Core.RefreshBans()
			end
		end)
	end)

	local function refreshAccess()
		banCard.Visible = Core.CanUse("Ban")
		Core.SetTabVisible("Bans", Core.CanUse("Ban") or Core.CanUse("Unban"))
	end
	refreshButton.Activated:Connect(Core.RefreshBans)
	search:GetPropertyChangedSignal("Text"):Connect(render)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			Core.RefreshBans()
		end
	end)
	Core.On(Core.AccessChanged.Event, function()
		refreshAccess()
		render()
	end)
	refreshAccess()
	render()
end

return Page

