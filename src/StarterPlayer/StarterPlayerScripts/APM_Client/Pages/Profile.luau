--[[
	Profile : fiche détaillée d'un compte (en ligne ou non), ouverte par Core.ShowProfile(userId, nom). Pas d'onglet : c'est un
	panneau par-dessus la fenêtre. Les lignes viennent du serveur (Core/Profiles) : ton jeu peut ajouter les siennes avec
	APMService.AddProfileProvider (voir le READ ME).
]]
local Page = { Id = "Profile", Order = 0, Tab = false }

function Page.Build(Core)
	local UI, T, R, L = Core.UI, Core.T, Core.R, Core.L

	local overlay = UI.new("Frame", { Name = "ProfileOverlay", Size = UDim2.new(1, 0, 1, -52), Position = UDim2.fromOffset(0, 52), BackgroundColor3 = T.bg,
		ZIndex = 30, Visible = false, Active = true }, Core.main)
	Core.ProfileOverlay = overlay
	UI.padding(overlay, 16)

	local avatar = UI.new("ImageLabel", { Size = UDim2.fromOffset(84, 84), BackgroundColor3 = T.panel2, ZIndex = 31, Corner = 12 }, overlay)
	local nameLabel = UI.label({ Size = UDim2.new(1, -230, 0, 28), Position = UDim2.fromOffset(100, 2), Font = T.fontBold, TextSize = 22, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 31, Text = "" }, overlay)
	local subLabel = UI.label({ Size = UDim2.new(1, -230, 0, 18), Position = UDim2.fromOffset(100, 32), TextColor3 = T.sub, ZIndex = 31, Text = "" }, overlay)
	local statusLabel = UI.label({ Size = UDim2.new(1, -230, 0, 18), Position = UDim2.fromOffset(100, 52), ZIndex = 31, Text = "" }, overlay)
	local rankBadge = UI.label({ Size = UDim2.fromOffset(120, 22), Position = UDim2.new(1, 0, 0, 4), AnchorPoint = Vector2.new(1, 0), BackgroundTransparency = 0, BackgroundColor3 = T.sub,
		Font = T.fontBold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 32, Corner = 11, Visible = false }, overlay)
	local closeProfile = UI.button({ Size = UDim2.fromOffset(110, 32), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1), Text = L("Common.Close"),
		BackgroundColor3 = T.accent, ZIndex = 32 }, overlay)
	local grid = UI.scroll({ Size = UDim2.new(1, 0, 1, -146), Position = UDim2.fromOffset(0, 100), ZIndex = 31 }, overlay)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0.5, -6, 0, 52)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	local note = UI.label({ Size = UDim2.new(1, -130, 0, 32), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1), TextColor3 = T.sub, TextSize = 12,
		TextWrapped = true, ZIndex = 31, Text = "" }, overlay)

	closeProfile.Activated:Connect(function()
		overlay.Visible = false
	end)

	local function stat(title, value, order)
		local card = UI.new("Frame", { BackgroundColor3 = T.panel2, LayoutOrder = order, ZIndex = 31, Corner = 10, Stroke = T.stroke }, grid)
		UI.label({ Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 6), TextSize = 12, TextColor3 = T.sub, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 32, Text = title }, card)
		UI.label({ Size = UDim2.new(1, -16, 0, 22), Position = UDim2.fromOffset(10, 24), Font = T.fontBold, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 32, Text = value }, card)
	end

	local token = 0
	function Core.ShowProfile(userId, nameHint)
		userId = tonumber(userId)
		if not userId then
			return
		end
		token += 1
		local mine = token
		overlay.Visible = true
		nameLabel.Text = nameHint or L("Profile.Account", userId)
		subLabel.Text = L("Profile.UserId", userId)
		statusLabel.Text = L("Common.Loading")
		statusLabel.TextColor3 = T.sub
		rankBadge.Visible = false
		note.Text = ""
		avatar.Image = userId > 0 and ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId) or ""
		for _, child in grid:GetChildren() do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		task.spawn(function()
			local ok, profile = pcall(function()
				return R.GetProfile:InvokeServer(userId)
			end)
			if mine ~= token or not overlay.Parent or not overlay.Visible then
				return
			end
			if not ok or type(profile) ~= "table" then
				statusLabel.Text = L("Profile.Unavailable")
				statusLabel.TextColor3 = T.bad
				return
			end
			local name = profile.Name or nameHint or tostring(userId)
			local display = profile.DisplayName or name
			nameLabel.Text = display ~= name and ("%s  (@%s)"):format(display, name) or name
			statusLabel.Text = L(profile.Online and "Profile.Online" or "Profile.Offline")
			statusLabel.TextColor3 = profile.Online and T.good or T.sub
			if profile.Rank then
				rankBadge.Text = Core.RankName(profile.Rank)
				rankBadge.BackgroundColor3 = Core.RankColor(profile.Rank)
				rankBadge.Visible = true
			end
			local rows = type(profile.Rows) == "table" and profile.Rows or {}
			for index, row in rows do
				stat(Core.Text(row.Label), Core.Text(row.Value), index)
			end
			if #rows == 0 then
				stat(L("Profile.NoData"), "-", 1)
			end
			note.Text = L(profile.Online and "Profile.Live" or "Profile.Saved")
		end)
	end
end

return Page

