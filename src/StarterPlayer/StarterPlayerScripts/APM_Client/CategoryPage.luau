--[[
	CategoryPage : page générique d'une catégorie de modules serveur (onglet Jeu, et tout onglet créé par une catégorie inconnue).
	Une carte par module : titre, description, un champ par entrée de Fields (nombre, texte, liste de choix) et un bouton EXÉCUTER
	(avec confirmation si le module a Confirm = true). Un module Mode « target » agit sur le joueur choisi dans l'onglet Joueurs.
	Ajouter un module avec Category = "MaCategorie" crée l'onglet « MaCategorie » (titre traduit : clé "Tab.MaCategorie").
]]
local CategoryPage = {}

-- Carte d'un module serveur. getTarget() renvoie le joueur visé (modules Mode « target »).
function CategoryPage.ModuleCard(Core, module, parent, order, getTarget)
	local UI, T, L = Core.UI, Core.T, Core.L
	local card = UI.card(parent, order)
	local top = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = 1 }, card)
	UI.sectionHeader(Core.Text(module.Label) .. (module.Mode == "target" and L("Common.OnTarget") or ""), module.Color or T.accent, top, 1)
	local rowOrder = 1
	if module.Description then
		rowOrder += 1
		UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextSize = 12, TextColor3 = T.sub, TextWrapped = true, LayoutOrder = rowOrder,
			Text = Core.Text(module.Description) }, card)
	end

	local getters = {}
	for _, field in module.Fields or {} do
		rowOrder += 1
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = rowOrder }, card)
		UI.label({ Size = UDim2.new(0.4, -6, 1, 0), TextSize = 12, TextColor3 = T.sub, TextWrapped = true, Text = Core.Text(field.Label) }, row)
		if field.Type == "choice" then
			local options = field.Options
			local source = type(options) == "string" and function()
				return Core.Options[options] or {}
			end or (options or {})
			local picker = UI.picker(row, source, field.Default, UDim2.new(0.6, 0, 1, 0), UDim2.fromScale(0.4, 0))
			getters[field.Name] = picker.Get
			if type(options) == "string" then
				card:GetPropertyChangedSignal("Visible"):Connect(picker.Refresh)
				Core.On(Core.AccessChanged.Event, picker.Refresh)
			end
		else
			local box = UI.input({ Size = UDim2.new(0.6, 0, 1, 0), Position = UDim2.fromScale(0.4, 0), TextSize = 13,
				Text = field.Default ~= nil and tostring(field.Default) or "", PlaceholderText = field.Type == "number" and L("Common.NumberHint") or L("Common.TextHint") }, row)
			getters[field.Name] = function()
				if field.Type == "number" then
					return tonumber(box.Text) or 0
				end
				return box.Text
			end
		end
	end

	rowOrder += 1
	local run = UI.button({ Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = (module.Color or T.accent):Lerp(T.panel2, 0.2), TextSize = 13, LayoutOrder = rowOrder,
		Text = L(module.Confirm and "Common.ExecuteConfirm" or "Common.Execute") }, card)
	UI.hover(run)
	UI.Confirmable(run, module.Confirm == true, function()
		local value
		if module.Fields and #module.Fields > 0 then
			value = {}
			for name, getter in getters do
				value[name] = getter()
			end
		end
		local target
		if module.Mode == "target" then
			target = getTarget and getTarget()
			if not target then
				Core.Toast(L("Common.PickPlayerFirst"), false)
				return
			end
		end
		Core.Action(module.Name, target, value)
	end)
	return card
end

-- Page complète d'une catégorie
function CategoryPage.Build(Core, page, category)
	local UI, T, L = Core.UI, Core.T, Core.L
	local tabId = page:GetAttribute("TabId")
	local scroll = UI.scroll({ Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)

	local modules, needsTarget = {}, false
	for _, module in Core.AllModules() do
		if module.Category == category and not module.ClientSide and module.Mode ~= "toggle" and module.Mode ~= "slider" then
			table.insert(modules, module)
			needsTarget = needsTarget or module.Mode == "target"
		end
	end

	local function target()
		local selected = Core.Selected
		return selected and selected.Parent and selected or nil
	end

	-- bandeau : sur qui agissent les modules « sur un joueur »
	local banner, bannerLabel
	if needsTarget then
		banner = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 38), BackgroundColor3 = T.panel2, LayoutOrder = 0, Corner = 10, Stroke = T.stroke }, scroll)
		bannerLabel = UI.label({ Size = UDim2.new(1, -20, 1, 0), Position = UDim2.fromOffset(10, 0), TextSize = 13, TextWrapped = true, Text = "" }, banner)
	end
	local function refreshBanner()
		if not bannerLabel then
			return
		end
		local selected = target()
		if selected then
			bannerLabel.Text = L("Category.Target", selected.DisplayName, selected.Name)
			bannerLabel.TextColor3 = T.good
		else
			bannerLabel.Text = L("Category.NoTarget")
			bannerLabel.TextColor3 = T.warn
		end
	end

	local cards = {}
	for index, module in modules do
		cards[module.Name] = CategoryPage.ModuleCard(Core, module, scroll, index, target)
	end
	local empty = UI.emptyState(page, L("Category.Empty"))

	local function refreshAccess()
		local any = false
		for name, card in cards do
			local allowed = Core.CanUse(name)
			card.Visible = allowed
			any = any or allowed
		end
		empty.Visible = not any
		if banner then
			banner.Visible = any
		end
		if tabId then
			Core.SetTabVisible(tabId, any)
		end
	end

	Core.On(Core.SelectionChanged.Event, refreshBanner)
	Core.On(Core.AccessChanged.Event, refreshAccess)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then
			refreshBanner()
			task.spawn(Core.RefreshOptions) -- listes de choix fraîches (joueurs, outils...)
		end
	end)
	refreshBanner()
	refreshAccess()
end

return CategoryPage

