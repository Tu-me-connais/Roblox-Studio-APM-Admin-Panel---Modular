-- Diagnostics : bilan de l'installation APM (session, configuration, extensions, distribution privée).
-- Mêmes données qu'avant (R.GetDiagnostics + Core.ExtensionDiagnostics) ; seule la présentation change :
-- un bilan clair en tête, des tuiles de synthèse, les erreurs d'abord, le détail technique replié.
-- Même langage visuel que les autres onglets (titres en capitales + pastille carrée, tuiles titre / valeur / détail, bouton secondaire).
-- Aucun texte n'est tronqué : tout se replie à la ligne et chaque bloc prend sa hauteur (langues longues, panneau étroit).
local Page = { Id = "Diagnostics", Order = 7.8, Label = { fr = "Diagnostics", en = "Diagnostics" } }
function Page.Visible(Core)
	return Core.HasPermission("APM.Simulate") or Core.ActualOwner
end

local MAX_OBJECTS_SHOWN = 12
local MAX_OBJECTS_REPORT = 40
local SCAN_LIMIT = 5000
local AUTO_Y = Enum.AutomaticSize.Y

function Page.Build(Core, page)
	local UI, T = Core.UI, Core.T
	local mine = Core.Session
	local function text(fr, en) return Core.Text({ fr = fr, en = en }) end
	local function yes(value) return text(value and "oui" or "non", value and "yes" or "no") end
	local function int(value) return math.floor(tonumber(value) or 0) end
	local function alive() return Core.Alive(mine) and page.Parent ~= nil end
	local function lastSegment(path)
		path = tostring(path or "")
		return string.match(path, "[^%.]+$") or path
	end
	-- Facteur d'échelle de l'interface (UIScale des ancêtres) : AbsoluteSize est en pixels écran, les Size en pixels d'interface.
	local function uiScale()
		local scale, node = 1, page
		while node do
			local found = node:FindFirstChildOfClass("UIScale")
			if found then scale *= found.Scale end
			node = node.Parent
		end
		return scale > 0 and scale or 1
	end

	----------------------------------------------------------------------------------------------------------
	-- Petits constructeurs (tout texte est replié à la ligne, jamais tronqué ; hauteur minimale = texte centré sur sa pastille)

	local function label(parent, value, order, color, size, font, minHeight)
		return UI.label({ Size = UDim2.new(1, 0, 0, minHeight or 0), AutomaticSize = AUTO_Y, TextWrapped = true, Font = font or T.font,
			TextSize = size or 13, TextColor3 = color or T.text, LayoutOrder = order, Text = value }, parent)
	end
	local function column(parent, order, gap)
		local frame = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		UI.list(frame, gap or 8)
		return frame
	end
	local function clear(container)
		for _, child in container:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
	end
	-- Pastille ronde d'état (bilan, lignes d'extensions)
	local function dot(parent, color, y, size, x)
		size = size or 10
		return UI.new("Frame", { Size = UDim2.fromOffset(size, size), Position = UDim2.fromOffset(x or 0, y or 4), BackgroundColor3 = color, Corner = size // 2 }, parent)
	end
	-- Titre de section : même géométrie que UI.sectionHeader (pastille carrée + texte gras 13), mais replié à la ligne
	local function sectionTitle(parent, order, color, value)
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 18), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		UI.new("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(0, 4), BackgroundColor3 = color, Corner = 3 }, row)
		return UI.label({ Size = UDim2.new(1, -18, 0, 18), Position = UDim2.fromOffset(18, 0), AutomaticSize = AUTO_Y, TextWrapped = true,
			Font = T.fontBold, TextSize = 13, TextColor3 = color, Text = value }, row)
	end
	local function linkButton(parent, order, value)
		local button = UI.button({ Size = UDim2.new(1, 0, 0, 24), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, Font = T.font, TextSize = 12,
			TextColor3 = T.accent, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order, Text = value }, parent)
		UI.padding(button, 4, 0, 0)
		return button
	end
	local function bulletRow(parent, order, color, value)
		local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = order }, parent)
		dot(row, color, 5, 8)
		UI.label({ Size = UDim2.new(1, -18, 0, 18), Position = UDim2.fromOffset(18, 0), AutomaticSize = AUTO_Y, TextWrapped = true,
			TextSize = 13, Text = value }, row)
		return row
	end
	-- Carte d'un élément de liste : pastille à gauche, contenu à droite (hauteur automatique)
	local function entryCard(parent, index, color, stroke)
		local item = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = AUTO_Y, BackgroundColor3 = T.panel, LayoutOrder = index,
			Corner = 8, Stroke = stroke }, parent)
		dot(item, color, 13, 8, 10)
		local content = column(item, 1, 4)
		content.Size = UDim2.new(1, -38, 0, 0)
		content.Position = UDim2.fromOffset(28, 0)
		UI.padding(content, 8, 0, 0)
		return content
	end

	local scroll = UI.scroll({ Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)

	-- Section repliable : en-tête cliquable (titre + résumé), corps masqué par défaut.
	local function collapsible(order, title)
		local card = UI.card(scroll, order)
		local header = UI.button({ Size = UDim2.new(1, 0, 0, 18), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, Text = "", LayoutOrder = 1 }, card)
		UI.new("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(0, 4), BackgroundColor3 = T.accent, Corner = 3 }, header)
		local inner = UI.new("Frame", { Size = UDim2.new(1, -118, 0, 0), Position = UDim2.fromOffset(18, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1 }, header)
		UI.list(inner, 2)
		label(inner, title, 1, T.accent, 13, T.fontBold, 18)
		local summary = label(inner, "", 2, T.sub, 11)
		local showText, hideText = text("Afficher", "Show"), text("Masquer", "Hide")
		local toggle = UI.label({ Size = UDim2.fromOffset(96, 18), AutomaticSize = AUTO_Y, Position = UDim2.new(1, -96, 0, 0), TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Right, TextSize = 12, TextColor3 = T.accent, Text = showText }, header)
		local body = column(card, 2, 8)
		body.Visible = false
		header.Activated:Connect(function()
			body.Visible = not body.Visible
			toggle.Text = body.Visible and hideText or showText
		end)
		return { Body = body, Summary = summary }
	end

	----------------------------------------------------------------------------------------------------------
	-- 1. Bilan : l'état général en une phrase, ce qu'il faut faire, et le bouton d'actualisation

	local refreshLabel = text("Actualiser le diagnostic", "Refresh diagnostics")
	local hero = UI.card(scroll, 1)
	sectionTitle(hero, 1, T.accent, text("BILAN DE L'INSTALLATION", "INSTALLATION STATUS"))
	local statusRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 24), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = 2 }, hero)
	local heroDot = dot(statusRow, T.sub, 6, 12)
	local heroTitle = UI.label({ Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(20, 0), AutomaticSize = AUTO_Y, TextWrapped = true,
		Font = T.fontBold, TextSize = 16, TextColor3 = T.sub, Text = text("Inspection en cours…", "Inspecting…") }, statusRow)
	local heroSub = label(hero, text("Lecture de l'état de cette session…", "Reading the state of this session…"), 3, T.sub, 12)
	local issuesFrame = column(hero, 4, 6)
	issuesFrame.Visible = false
	local refresh = UI.button({ Size = UDim2.new(1, 0, 0, 32), AutomaticSize = AUTO_Y, TextWrapped = true, LayoutOrder = 5, Text = refreshLabel,
		BackgroundColor3 = T.panel, Stroke = T.stroke }, hero)
	UI.padding(refresh, 6, 10, 10)
	local checkedLabel = label(hero, "", 6, T.sub, 11)
	local restartHint = label(hero, text("Après avoir corrigé un script ou sa configuration dans Studio, relance Play pour charger les changements.",
		"After correcting a script or configuration in Studio, restart Play to load the changes."), 7, T.sub, 12)
	restartHint.Visible = false

	----------------------------------------------------------------------------------------------------------
	-- 2. Tuiles de synthèse (même look que les tuiles de Statistiques) : deux colonnes, hauteur commune = tuile la plus haute

	local tileGrid = UI.new("Frame", { Size = UDim2.new(1, -6, 0, 0), AutomaticSize = AUTO_Y, BackgroundTransparency = 1, LayoutOrder = 2 }, scroll)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, 84)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = tileGrid
	local tileNames = { "Version", "Session", "Extensions", "Storage", "Configuration", "Transport" }
	local tileCaptions = {
		Version = text("VERSION APM", "APM VERSION"), Session = text("SESSION", "SESSION"), Extensions = text("EXTENSIONS", "EXTENSIONS"),
		Storage = text("SAUVEGARDE", "STORAGE"), Configuration = text("CONFIGURATION", "CONFIGURATION"), Transport = text("DISTRIBUTION", "DISTRIBUTION"),
	}
	local tiles = {}
	local function relayoutTiles()
		local tallest = 0
		for _, tile in tiles do tallest = math.max(tallest, tile.Layout.AbsoluteContentSize.Y) end
		grid.CellSize = UDim2.new(0.5, -4, 0, math.max(84, math.ceil(tallest / uiScale()) + 20))
	end
	for index, name in tileNames do
		local card = UI.card(tileGrid, index)
		card.AutomaticSize = Enum.AutomaticSize.None
		local layout = card:FindFirstChildOfClass("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		sectionTitle(card, 1, T.accent, tileCaptions[name])
		tiles[name] = { Layout = layout, Value = label(card, "—", 2, T.sub, 20, T.fontBold, 26), Note = label(card, "", 3, T.sub, 11) }
		layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(relayoutTiles)
	end
	local function setTile(name, value, color, note)
		local tile = tiles[name]
		tile.Value.Text = value
		tile.Value.TextColor3 = color or T.text
		tile.Note.Text = note or ""
		tile.Note.Visible = (note or "") ~= ""
	end

	----------------------------------------------------------------------------------------------------------
	-- 3. À corriger (visible seulement s'il y a des erreurs) puis extensions

	local problemsCard = UI.card(scroll, 3)
	problemsCard.Visible = false
	local problemsTitle = sectionTitle(problemsCard, 1, T.bad, text("À CORRIGER", "NEEDS A FIX"))
	local problemsList = column(problemsCard, 2, 8)

	local extensionsCard = UI.card(scroll, 4)
	sectionTitle(extensionsCard, 1, T.accent, text("EXTENSIONS ET CORRECTIONS", "EXTENSIONS AND FIXES"))
	local extensionsSummary = label(extensionsCard, "", 2, T.sub, 12)
	local extensionsList = column(extensionsCard, 3, 6)

	----------------------------------------------------------------------------------------------------------
	-- 4. Détails techniques repliés : configuration, distribution privée, rapport à copier

	local configSection = collapsible(5, text("CONFIGURATION ACTIVE", "ACTIVE CONFIGURATION"))
	local transportSection = collapsible(6, text("DISTRIBUTION PRIVÉE", "PRIVATE DISTRIBUTION"))
	local reportSection = collapsible(7, text("RAPPORT À COPIER", "REPORT TO COPY"))
	label(reportSection.Body, text("Sélectionne le texte puis Ctrl+C pour le coller dans une demande d'aide ou un ticket.",
		"Select the text then press Ctrl+C to paste it into a help request or ticket."), 1, T.sub, 12)
	local reportBox = UI.input({ Size = UDim2.new(1, 0, 0, 80), AutomaticSize = AUTO_Y, MultiLine = true, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
		TextTruncate = Enum.TextTruncate.None, TextSize = 11, Font = Enum.Font.Code, TextEditable = false, ClearTextOnFocus = false, LayoutOrder = 2 }, reportSection.Body)
	local reportPadding = reportBox:FindFirstChildOfClass("UIPadding")
	if reportPadding then
		reportPadding.PaddingTop, reportPadding.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	end

	----------------------------------------------------------------------------------------------------------
	-- Lignes d'extensions

	local function statusOf(entry)
		if entry.Status == "Error" then return text("À corriger", "Needs a fix"), T.bad end
		if entry.Status == "Disabled" then return text("Désactivée", "Disabled"), T.sub end
		if entry.Status == "Ready" then return text("Métadonnées validées", "Metadata validated"), T.accent end
		return text("Chargée", "Loaded"), T.good
	end

	local function collectEntries(server)
		local entries = {}
		for _, entry in type(server.Entries) == "table" and server.Entries or {} do
			if type(entry) == "table" then table.insert(entries, entry) end
		end
		for index, entry in Core.ExtensionDiagnostics or {} do
			if index > 30 then break end
			if type(entry) == "table" then table.insert(entries, entry) end
		end
		table.sort(entries, function(a, b)
			if (a.Status == "Error") ~= (b.Status == "Error") then return a.Status == "Error" end
			return tostring(a.Kind) .. tostring(a.Id) < tostring(b.Kind) .. tostring(b.Id)
		end)
		return entries
	end

	-- Extension en erreur : ce qui ne va pas, quoi faire, et les détails techniques à la demande
	local function renderProblem(parent, index, entry)
		local content = entryCard(parent, index, T.bad, T.bad)
		label(content, tostring(entry.Kind) .. " / " .. tostring(entry.Id), 1, T.text, 13, T.fontBold, 18)
		local message = Core.Text(entry.Message or "")
		if message ~= "" then label(content, message, 2) end
		local hint = Core.Text(entry.Hint or "")
		if hint ~= "" then label(content, text("Conseil : ", "Tip: ") .. hint, 3, T.accent, 12) end
		local details = {}
		if type(entry.SourcePath) == "string" and entry.SourcePath ~= "" then
			table.insert(details, text("Source : ", "Source: ") .. entry.SourcePath)
		end
		if type(entry.Field) == "string" and entry.Field ~= "" then
			table.insert(details, text("Champ : ", "Field: ") .. entry.Field)
			table.insert(details, text("Reçu : ", "Received: ") .. tostring(entry.Received or ""))
			table.insert(details, text("Attendu : ", "Expected: ") .. Core.Text(entry.Expected or ""))
		end
		if entry.Code then table.insert(details, text("Référence : ", "Reference: ") .. tostring(entry.Code)) end
		if #details > 0 then
			local showText, hideText = text("Voir les détails techniques", "Show technical details"), text("Masquer les détails techniques", "Hide technical details")
			local toggle = linkButton(content, 4, showText)
			local body = column(content, 5, 3)
			body.Visible = false
			for order, line in details do label(body, line, order, T.sub, 12) end
			toggle.Activated:Connect(function()
				body.Visible = not body.Visible
				toggle.Text = body.Visible and hideText or showText
			end)
		end
	end

	-- Extension sans problème : nom, état et éventuel message
	local function renderEntry(parent, index, entry)
		local statusText, color = statusOf(entry)
		local content = entryCard(parent, index, color)
		label(content, tostring(entry.Kind) .. " / " .. tostring(entry.Id), 1, T.text, 13, T.font, 18)
		label(content, statusText, 2, color, 12)
		local message = Core.Text(entry.Message or "")
		if message ~= "" then label(content, message, 3, T.sub, 12) end
	end

	----------------------------------------------------------------------------------------------------------
	-- Rendu complet d'un résultat d'inspection : result = { Data = table|nil, Found = {chemins}, Count = n, Limit = bool }

	local function render(result)
		local serverOk = type(result.Data) == "table"
		local data = serverOk and result.Data or {}
		local coreInfo = type(data.core) == "table" and data.core or {}
		local config = type(data.configuration) == "table" and data.configuration or {}
		local server = type(data.extensions) == "table" and data.extensions or {}
		local found = result.Found or {}
		local entries = collectEntries(server)
		local problems, others = {}, {}
		for _, entry in entries do
			table.insert(entry.Status == "Error" and problems or others, entry)
		end
		local serverErrors, localErrors, loaded = int(server.Errors), #(Core.ExtensionDiagnostics or {}), int(server.Loaded)
		local totalErrors = serverErrors + localErrors
		local unavailable = text("Serveur indisponible", "Server unavailable")
		local objectsNote = text("%d objet(s) APM sur ce client", "%d APM object(s) on this client"):format(#found)

		-- Problèmes repérés, classés du plus grave au plus léger
		local severe, minor = {}, {}
		if not serverOk then
			table.insert(minor, text("Le diagnostic serveur est indisponible. Réessaie avec « Actualiser » ; les erreurs de ce client restent affichées.",
				"Server diagnostics are unavailable. Retry with Refresh; this client's errors are still shown."))
		else
			if data.sessionActive ~= true then table.insert(minor, text("Aucune session APM active pour ce compte.", "No active APM session for this account.")) end
			if data.authorized ~= true then table.insert(minor, text("Ce compte n'a pas accès au panneau.", "This account has no panel access.")) end
			if data.globalAdminRemotes == true then
				table.insert(minor, text("Transport administratif global détecté : les remotes d'administration ne sont pas privés. Vérifie « Distribution privée ».",
					"Global administrative transport detected: admin remotes are not private. Check “Private distribution”."))
			end
			if config.DuplicateConfigurations then
				table.insert(minor, text("Plusieurs configurations détectées : celle indiquée dans « Configuration active » est prioritaire.",
					"Multiple configurations detected: the one shown in “Active configuration” takes priority."))
			end
			if config.MemoryMode and not config.StudioMemory then
				table.insert(minor, text("La sauvegarde persistante est indisponible pour cette session : les changements ne seront pas conservés.",
					"Persistent storage is unavailable for this session: changes will not be kept."))
			end
		end
		if totalErrors > 0 then
			table.insert(severe, text("%d extension(s) ou page(s) à corriger : voir la section « À corriger » ci-dessous.",
				"%d extension(s) or page(s) need a fix: see the “Needs a fix” section below."):format(totalErrors))
		end
		local level = #severe > 0 and "bad" or #minor > 0 and "warn" or "good"
		local color = level == "bad" and T.bad or level == "warn" and T.warn or T.good

		-- Bilan
		heroDot.BackgroundColor3 = color
		heroTitle.TextColor3 = color
		if level == "bad" then
			heroTitle.Text = text("Problème détecté", "Problem detected")
		elseif level == "warn" then
			heroTitle.Text = text("À vérifier", "Needs a look")
		else
			heroTitle.Text = text("Tout est en ordre", "Everything looks good")
			heroSub.Text = text("La session, la configuration et les extensions fonctionnent normalement. Aucune action nécessaire.",
				"The session, configuration and extensions are working normally. Nothing to do.")
		end
		heroSub.Visible = level == "good"
		restartHint.Visible = level ~= "good"
		clear(issuesFrame)
		local row = 0
		for _, message in severe do row += 1 bulletRow(issuesFrame, row, T.bad, message) end
		for _, message in minor do row += 1 bulletRow(issuesFrame, row, T.warn, message) end
		issuesFrame.Visible = row > 0
		checkedLabel.Text = text("Dernière vérification : ", "Last checked: ") .. Core.FormatDate(os.time())

		-- Tuiles
		if serverOk then
			setTile("Version", tostring(coreInfo.Version or "—"), T.text,
				text("Canal %s · API %s", "Channel %s · API %s"):format(tostring(coreInfo.Channel or "—"), tostring(coreInfo.ApiVersion or "—")))
			setTile("Session", data.sessionActive and text("Active", "Active") or text("Inactive", "Inactive"), data.sessionActive and T.good or T.warn,
				text("Accès au panneau : ", "Panel access: ") .. yes(data.authorized))
		else
			setTile("Version", "—", T.sub, unavailable)
			setTile("Session", "—", T.sub, unavailable)
		end
		if totalErrors > 0 then
			setTile("Extensions", text("%d à corriger", "%d to fix"):format(totalErrors), T.bad,
				text("%d erreur(s) serveur · %d sur ce client", "%d server error(s) · %d on this client"):format(serverErrors, localErrors))
		elseif serverOk then
			setTile("Extensions", text("%d chargée(s)", "%d loaded"):format(loaded), T.good, text("Aucune erreur", "No errors"))
		else
			setTile("Extensions", "—", T.sub, unavailable)
		end
		if not serverOk then
			setTile("Storage", "—", T.sub, unavailable)
			setTile("Configuration", "—", T.sub, unavailable)
			setTile("Transport", "—", T.sub, objectsNote)
		else
			if config.MemoryMode then
				setTile("Storage", text("En mémoire", "In memory"), config.StudioMemory and T.accent or T.warn,
					config.StudioMemory and text("Mode test Studio", "Studio test mode") or text("Non persistante", "Not persistent"))
			else
				setTile("Storage", text("Persistante", "Persistent"), T.good, text("Les changements sont conservés", "Changes are kept"))
			end
			if config.DuplicateConfigurations then
				setTile("Configuration", text("Plusieurs fichiers", "Multiple files"), T.warn, text("Prioritaire : ", "Used: ") .. lastSegment(config.SourcePath))
			elseif config.SourcePath then
				setTile("Configuration", text("Fichier actif", "Active file"), T.good, lastSegment(config.SourcePath))
			else
				setTile("Configuration", text("Non indiquée", "Not reported"), T.sub, "")
			end
			setTile("Transport", data.globalAdminRemotes and text("Transport global", "Global transport") or text("Privée", "Private"),
				data.globalAdminRemotes and T.warn or T.good, objectsNote)
		end

		-- À corriger
		clear(problemsList)
		problemsCard.Visible = #problems > 0
		problemsTitle.Text = text("À CORRIGER (%d)", "NEEDS A FIX (%d)"):format(#problems)
		for index, entry in problems do renderProblem(problemsList, index, entry) end

		-- Extensions
		clear(extensionsList)
		if serverOk then
			extensionsSummary.Text = text("%d chargée(s) · %d erreur(s) serveur · %d erreur(s) sur ce client", "%d loaded · %d server error(s) · %d error(s) on this client")
				:format(loaded, serverErrors, localErrors)
		else
			extensionsSummary.Text = text("%d erreur(s) sur ce client", "%d error(s) on this client"):format(localErrors)
		end
		if server.Truncated then
			extensionsSummary.Text ..= "\n" .. text("Liste limitée : consulte aussi la sortie Output de Studio.", "List limited: also check Studio Output.")
		end
		if #others == 0 then
			label(extensionsList, #problems > 0 and text("Aucune autre extension.", "No other extension.")
				or text("Aucune extension enregistrée. Les exemples dans APM_DeveloperTemplates restent inactifs jusqu'à leur copie dans APM_Extensions.",
					"No registered extensions. Examples in APM_DeveloperTemplates stay inactive until copied into APM_Extensions."), 1, T.sub, 12)
		else
			for index, entry in others do renderEntry(extensionsList, index, entry) end
		end

		-- Configuration active
		clear(configSection.Body)
		local configOk = serverOk and not config.DuplicateConfigurations and not (config.MemoryMode and not config.StudioMemory)
		configSection.Summary.TextColor3 = configOk and T.good or T.warn
		if serverOk then
			configSection.Summary.Text = lastSegment(config.SourcePath or "—") .. " · "
				.. (config.MemoryMode and text("en mémoire", "in memory") or text("sauvegarde persistante", "persistent storage"))
			label(configSection.Body, text("Fichier actif : ", "Active file: ") .. tostring(config.SourcePath or "—"), 1, T.text, 12)
			if config.DuplicateConfigurations then
				label(configSection.Body, text("Plusieurs configurations détectées : le fichier indiqué ci-dessus est prioritaire.",
					"Multiple configurations detected: the file shown above takes priority."), 2, T.warn, 12)
			end
			if config.MemoryMode then
				label(configSection.Body, config.StudioMemory
					and text("Mode mémoire demandé pour les tests Studio : les changements restent dans cette session.", "Memory mode requested for Studio tests: changes stay in this session.")
					or text("Mode mémoire : la sauvegarde persistante est indisponible pour cette session.", "Memory mode: persistent storage is unavailable for this session."), 3, T.sub, 12)
			else
				label(configSection.Body, text("Sauvegarde persistante active.", "Persistent storage active."), 3, T.sub, 12)
			end
		else
			configSection.Summary.Text = text("Configuration serveur indisponible.", "Server configuration unavailable.")
			label(configSection.Body, text("Configuration serveur indisponible.", "Server configuration unavailable."), 1, T.sub, 12)
		end

		-- Distribution privée
		clear(transportSection.Body)
		transportSection.Summary.TextColor3 = (serverOk and data.globalAdminRemotes ~= true) and T.good or T.warn
		transportSection.Summary.Text = (serverOk and (data.globalAdminRemotes and text("Transport administratif global détecté", "Global administrative transport detected")
			or text("Transport privé", "Private transport")) or unavailable) .. " · " .. objectsNote
		label(transportSection.Body, text("Ce client : %d objet(s) APM privé(s), %d objets inspectés", "This client: %d private APM object(s), %d inspected objects")
			:format(#found, int(result.Count)) .. (result.Limit and text(" (limite atteinte)", " (limit reached)") or ""), 1, T.text, 12)
		if serverOk then
			label(transportSection.Body, text("Remotes admin globaux : ", "Global admin remotes: ") .. yes(data.globalAdminRemotes), 2,
				data.globalAdminRemotes and T.warn or T.text, 12)
		end
		for index, path in found do
			if index > MAX_OBJECTS_SHOWN then
				label(transportSection.Body, text("… et %d autre(s) (liste complète dans le rapport)", "… and %d more (full list in the report)"):format(#found - MAX_OBJECTS_SHOWN), 100, T.sub, 11)
				break
			end
			label(transportSection.Body, tostring(path), 10 + index, T.sub, 11, Enum.Font.Code)
		end
		label(transportSection.Body, text("Cette inspection décrit ce client maintenant. Pour vérifier une première connexion sans grade, utilise un second client. Une simulation après connexion ne prouve pas l'absence de réplication initiale.",
			"This inspection describes this client now. Use a second client to verify a first join without a rank. Simulation after joining does not prove there was no initial replication."), 200, T.sub, 12)

		-- Rapport à copier
		local lines = { "APM · " .. text("Rapport de diagnostic", "Diagnostics report") .. " · " .. Core.FormatDate(os.time()) }
		if serverOk then
			table.insert(lines, ("APM %s · %s · API %s"):format(tostring(coreInfo.Version or "?"), tostring(coreInfo.Channel or "?"), tostring(coreInfo.ApiVersion or "?")))
			table.insert(lines, text("Session active : ", "Session active: ") .. yes(data.sessionActive) .. " · " .. text("accès au panneau : ", "panel access: ") .. yes(data.authorized))
			table.insert(lines, text("Configuration : ", "Configuration: ") .. tostring(config.SourcePath or "—")
				.. (config.DuplicateConfigurations and (" · " .. text("doublons détectés", "duplicates detected")) or "")
				.. " · " .. (config.MemoryMode and text("mode mémoire", "memory mode") or text("sauvegarde persistante", "persistent storage")))
			table.insert(lines, text("Remotes admin globaux : ", "Global admin remotes: ") .. yes(data.globalAdminRemotes))
		else
			table.insert(lines, text("Diagnostic serveur indisponible.", "Server diagnostics unavailable."))
		end
		table.insert(lines, text("Extensions : %d chargée(s) · %d erreur(s) serveur · %d erreur(s) client", "Extensions: %d loaded · %d server error(s) · %d client error(s)")
			:format(loaded, serverErrors, localErrors))
		for _, entry in entries do
			local statusText = statusOf(entry)
			local line = " - [" .. statusText .. "] " .. tostring(entry.Kind) .. " / " .. tostring(entry.Id)
			local message = Core.Text(entry.Message or "")
			if message ~= "" then line ..= " : " .. message end
			if type(entry.SourcePath) == "string" and entry.SourcePath ~= "" then line ..= " (" .. entry.SourcePath .. ")" end
			if type(entry.Field) == "string" and entry.Field ~= "" then
				line ..= " — " .. entry.Field .. " : " .. tostring(entry.Received or "") .. " → " .. Core.Text(entry.Expected or "")
			end
			if entry.Code then line ..= " #" .. tostring(entry.Code) end
			table.insert(lines, line)
		end
		table.insert(lines, text("Objets APM sur ce client : %d (%d inspectés)", "APM objects on this client: %d (%d inspected)"):format(#found, int(result.Count)))
		for index, path in found do
			if index > MAX_OBJECTS_REPORT then
				table.insert(lines, "   … +" .. (#found - MAX_OBJECTS_REPORT))
				break
			end
			table.insert(lines, "   " .. tostring(path))
		end
		reportBox.Text = table.concat(lines, "\n")
		reportSection.Summary.Text = text("Texte prêt à copier pour une demande d'aide", "Ready-to-copy text for a help request")
	end

	----------------------------------------------------------------------------------------------------------
	-- Inspection : objets APM visibles sur ce client + diagnostic serveur (comportement inchangé)

	local busy = false
	local function inspect()
		if busy then return end
		busy = true
		refresh.Text = text("Inspection…", "Inspecting…")
		task.spawn(function()
			local found, seen, count = {}, {}, 0
			local names = { APM_Client = true, APM_Private = true, APM_Recovery = true, APM_Remotes = true, APM_Gui = true, APM_Launcher = true }
			local roots = { Core.Player:FindFirstChildOfClass("PlayerGui"), Core.Player:FindFirstChild("PlayerScripts"), game:GetService("ReplicatedStorage"), workspace }
			for _, root in roots do
				if root then
					local queue, index = { root }, 1
					while index <= #queue and count < SCAN_LIMIT do
						local node = queue[index]
						index += 1
						count += 1
						if (names[node.Name] or node:GetAttribute("APMPrivate")) and not seen[node] then
							seen[node] = true
							if #found < 100 then table.insert(found, node:GetFullName()) end
						end
						for _, child in node:GetChildren() do
							if #queue < SCAN_LIMIT then table.insert(queue, child) end
						end
						if count % 200 == 0 then task.wait() end
					end
				end
			end
			local ok, data = pcall(function() return Core.R.GetDiagnostics:InvokeServer() end)
			busy = false
			if not alive() then return end
			local rendered, err = pcall(render, { Data = ok and type(data) == "table" and data or nil, Found = found, Count = count, Limit = count >= SCAN_LIMIT })
			if not rendered then warn("[APM] Diagnostics : " .. tostring(err)) end
			refresh.Text = refreshLabel
		end)
	end
	refresh.Activated:Connect(inspect)
	page:GetPropertyChangedSignal("Visible"):Connect(function()
		if page.Visible then inspect() end
	end)
	inspect()
end
return Page
