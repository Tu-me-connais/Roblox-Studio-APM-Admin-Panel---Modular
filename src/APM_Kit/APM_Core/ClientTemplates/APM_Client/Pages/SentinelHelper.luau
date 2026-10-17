--[[
	Sentinel Helper : centre de configuration de Sentinel (l'assistant de commandes flottant) — ne pas confondre avec Sentinel Guard.
	Trois niveaux, séparés sur la page :
	  · MES PRÉFÉRENCES (locales, par compte) : afficher Sentinel, animation, taille, position ;
	  · RÉGLAGES ADMINISTRATIFS (tout le serveur) : comportement, moteur de commandes, commandes désactivées, alias ;
	  · COMMANDES PERSONNALISÉES et IA EXTERNE facultative : chacune derrière sa propre permission.
	Rien n'est appliqué avant « Appliquer » ; le serveur valide tout (droits par clé, bornes, noms libres, hôtes autorisés) et la clé
	d'API n'existe jamais côté client. Le moteur de commandes est un moteur LOCAL à règles, pas une IA générative.
]]
local Page = { Id = "SentinelHelper", Order = 9.5, Label = { fr = "Sentinel Helper", en = "Sentinel Helper" } }

function Page.Visible(Core)
	return Core.HasPermission("Assistant.Configure") or Core.HasPermission("Assistant.Commands")
end

local GENERAL_BOOLEANS = { "Enabled", "ConfirmDangerous", "AllowAll", "DefaultDeployed", "WaveEnabled" }
local EXTERNAL_KEYS = { "Enabled", "Provider", "Model", "Endpoint", "TimeoutSeconds", "MaxPerMinute" }

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in value do result[key] = copy(item) end
	return result
end
local function equal(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for key, value in a do if not equal(value, b[key]) then return false end end
	for key in b do if a[key] == nil then return false end end
	return true
end

function Page.Build(Core, page)
	local UI, T, R, L = Core.UI, Core.T, Core.R, Core.L
	local mine = Core.Session
	-- Live : rafraîchisseurs des cartes vivantes (état de Sentinel lu à la source unique) ; vidés à chaque reconstruction, alimentés par UNE seule connexion
	local S = { Draft = nil, Saved = nil, State = nil, Controls = {}, Live = {} }
	local function alive() return Core.Alive(mine) and page.Parent ~= nil end
	local function text(value) return Core.Text(value) end

	local scroll = UI.scroll({ Name = "HelperScroll", Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)
	local footer = UI.new("Frame", { Name = "ApplyBar", Size = UDim2.new(1, -6, 0, 46), AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), BackgroundColor3 = T.panel2,
		Visible = false, ZIndex = 5, Corner = 10, Stroke = T.warn }, page)
	local footerText = UI.label({ Size = UDim2.new(1, -230, 1, 0), Position = UDim2.fromOffset(12, 0), TextSize = 12, TextWrapped = true, TextColor3 = T.warn, ZIndex = 6,
		Text = L("Helper.Pending") }, footer)
	local applyButton = UI.button({ Name = "ApplyHelper", Size = UDim2.fromOffset(100, 30), AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -112, .5, 0), BackgroundColor3 = T.good,
		Text = L("Helper.Apply"), TextSize = 13, ZIndex = 6 }, footer)
	local cancelButton = UI.button({ Name = "CancelHelper", Size = UDim2.fromOffset(92, 30), AnchorPoint = Vector2.new(1, .5), Position = UDim2.new(1, -10, .5, 0), BackgroundColor3 = T.panel,
		Text = L("Helper.Cancel"), TextSize = 13, Stroke = T.stroke, ZIndex = 6 }, footer)

	S.Core, S.UI, S.T, S.L, S.text, S.alive, S.copy, S.equal, S.Scroll = Core, UI, T, L, text, alive, copy, equal, scroll

	-- messages d'état : une ligne sous chaque section
	function S.Say(label, value, good)
		if not alive() or not label.Parent then return end
		label.Text = text(value)
		label.TextColor3 = good == false and T.bad or (good == true and T.good or T.sub)
	end

	-- brouillon -> correctif (seulement ce qui change) ------------------------------------------------------------
	local function patch()
		local result = {}
		if not S.Draft then return result end
		for _, key in { "MaxHistory", "ReplyStyle", "MaxAllTargets", "RatePerWindow", "WaveInterval", "AnimationSpeed", "DisabledCommands", "Aliases", table.unpack(GENERAL_BOOLEANS) } do
			if not equal(S.Draft[key], S.Saved[key]) then result[key] = copy(S.Draft[key]) end
		end
		if not equal(S.Draft.External, S.Saved.External) then result.External = copy(S.Draft.External) end
		return result
	end
	function S.Dirty()
		if not alive() then return end
		footer.Visible = next(patch()) ~= nil
		scroll.Size = footer.Visible and UDim2.new(1, 0, 1, -54) or UDim2.fromScale(1, 1)
	end

	local reload
	local building = false

	local function applyDraft()
		local changes = patch()
		if next(changes) == nil then return end
		applyButton.Interactable, cancelButton.Interactable = false, false
		footerText.Text = L("Common.Loading")
		task.spawn(function()
			local ok, first, second = pcall(function() return R.ConfigureAssistant:InvokeServer("Save", changes) end)
			if not alive() then return end
			applyButton.Interactable, cancelButton.Interactable = true, true
			footerText.Text = L("Helper.Pending")
			if ok and first == true then
				Core.Toast(second or L("Helper.Saved"), true)
				reload()
			else
				Core.Toast(ok and (second or first) or L("Helper.Unavailable"), false)
				if ok and type(first) == "table" then Core.Toast(first, false) end
			end
		end)
	end
	applyButton.Activated:Connect(applyDraft)
	cancelButton.Activated:Connect(function()
		if S.Saved then
			S.Draft = copy(S.Saved)
			for _, refresh in S.Controls do refresh() end
			S.Dirty()
		end
	end)

	-- construction des sections -----------------------------------------------------------------------------------
	local sections = {}
	local loadingLabel = UI.label({ Size = UDim2.new(1, -6, 0, 40), TextSize = 13, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center, Text = L("Common.Loading"), LayoutOrder = 1 }, scroll)
	local function clearSections()
		for _, section in sections do section:Destroy() end
		table.clear(sections)
		table.clear(S.Controls)
		table.clear(S.Live)
	end

	local Parts = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("HelperSections"))

	local function build()
		clearSections()
		loadingLabel.Visible = false
		for index, builder in { Parts.Overview, Parts.Preferences, Parts.General, Parts.Custom, Parts.External, Parts.Languages, Parts.Test, Parts.Storage } do
			local ok, card = pcall(builder, S, scroll, index)
			if ok and card then
				table.insert(sections, card)
			elseif not ok then
				warn("[APM] Sentinel Helper, section " .. index .. " : " .. tostring(card))
			end
		end
		S.Dirty()
	end

	function S.Reload()
		reload()
	end
	reload = function()
		if building then return end
		building = true
		task.spawn(function()
			local ok, first, second = pcall(function() return R.ConfigureAssistant:InvokeServer("Get") end)
			building = false
			if not alive() then return end
			if ok and first == true and type(second) == "table" then
				S.State = second
				S.Saved = copy(second.Config)
				S.Draft = copy(second.Config)
				build()
			else
				clearSections()
				loadingLabel.Visible = true
				loadingLabel.Text = L("Helper.Unavailable")
			end
		end)
	end

	-- un changement fait ailleurs (autre admin, réinitialisation) rafraîchit la page quand elle n'a rien en attente
	Core.On(R.AssistantChanged.OnClientEvent, function()
		if alive() and next(patch()) == nil then reload() end
	end)
	-- Sentinel change d'état (interrupteur de l'Accueil, activation globale, droits) : chaque carte vivante se relit à Core.Assistant.State(), sans reconstruire la page
	if Core.Assistant and Core.Assistant.Ready then
		Core.On(Core.Assistant.Ready, function()
			if not alive() then return end
			for _, refresh in S.Live do pcall(refresh) end
		end)
	end
	reload()
end

return Page
