-- Exemple facultatif : installer via le manifest de votre extension, hors APM_Core.
local Page = {
	ApiVersion = 1,
	Id = "ExampleDashboard",
	Permission = "Extensions.Example.View",
	Order = 10,
	Label = { fr = "Mon expérience", en = "My experience" },
	-- Handles = { "ExampleCommands" }, -- uniquement une catégorie de cette extension
}

function Page.Visible(Core)
	return Core.HasPermission(Page.Permission)
end

function Page.Build(Core, page)
	local UI, T, mine = Core.UI, Core.T, Core.Session
	local scroll = UI.scroll({ Name = "ExampleScroll", Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)
	local card = UI.card(scroll, 1)
	UI.sectionHeader(Core.Text(Page.Label), T.accent, card, 1)
	local info = UI.label({
		Name = "ExampleInfo", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true, LayoutOrder = 2,
	}, card)
	local refresh = UI.button({
		Size = UDim2.new(1, 0, 0, 36), LayoutOrder = 3,
		Text = Core.Text({ fr = "Actualiser", en = "Refresh" }),
	}, card)
	local function render()
		if not Core.Alive(mine) or not Core.HasPermission(Page.Permission) then return end
		-- Valeurs existantes de la session, sans compteurs de démonstration.
		info.Text = ("%s (%d)\n%s"):format(Core.Player.Name, Core.Player.UserId, Core.RankName(Core.MyRank))
	end
	Core.On(refresh.Activated, render)
	render()
end

return Page
