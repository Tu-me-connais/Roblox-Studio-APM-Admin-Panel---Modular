--[[
	Page Funny : studio des situations, en deux étapes.
	  ① Choisir : grille de vignettes (icône + nom, classées par catégorie) à côté de l'aperçu 3D, avec le bouton Lancer
	    juste dessous : on peut lancer en deux clics avec les réglages par défaut.
	  ② Régler : choix en boutons (énergie, durée, portée, cibles...) et réglages propres à l'effet choisi.
	Puis les scènes en cours. L'aperçu 3D est dans Components.FunnyPreview.
	Le serveur revérifie tout (Funny.Scenes) : ce client ne décide de rien.
]]
local Page = { Id = "Funny", Order = 3.5, Label = { fr = "Amusement", en = "Funny" } }

-- Icônes des vignettes (texte simple si un effet ajouté plus tard n'en a pas)
local ICONS = {
	Random = "🎲", Confetti = "🎉", Disco = "💃", Ducks = "🦆", Bubbles = "🧼", Potato = "🥔", Solar = "🪐",
	Snow = "❄️", Hearts = "💖", Fireworks = "🎆", Rainbow = "🌈",
	BigHead = "🎈", Skin = "🎭", BodyParts = "🔀", ReverseGravity = "🚀", UpsideDown = "🙃",
}
local MOVEMENT = { ReverseGravity = true, UpsideDown = true }
local DURATIONS = { 5, 10, 15, 30, 45, 60 }
local GRAVITY_PRESETS = {
	Gentle = { GravityFactor = .2, MaxRise = 18, MaxRiseSpeed = 7 },
	Normal = { GravityFactor = .35, MaxRise = 30, MaxRiseSpeed = 12 },
	Rocket = { GravityFactor = .75, MaxRise = 55, MaxRiseSpeed = 22 },
}

function Page.Visible(Core)
	return Core.HasPermission("Funny.View")
end

function Page.Build(Core, page)
	local Preview = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("FunnyPreview"))
	local DECORS = Preview.DECORS
	local UI, T, R = Core.UI, Core.T, Core.R
	local mine = Core.Session
	local function text(fr, en)
		return Core.Text({ fr = fr, en = en })
	end
	local function alive()
		return Core.Alive(mine) and page.Parent ~= nil
	end
	local function category(id)
		return (id == "Random" or DECORS[id]) and 1 or MOVEMENT[id] and 3 or 2
	end
	local function small(props, parent)
		return UI.label(table.clone({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub,
			LayoutOrder = props.LayoutOrder, Name = props.Name, Text = props.Text or "" }), parent)
	end

	-- Rangée de boutons à choix unique : { Frame, Get, Set, SetOptions(list), Changed = function(id) } ; list = { { id, texte }, ... }
	local function chips(parent, order, label, options, default)
		local frame = UI.new("Frame", { Name = "Chips_" .. tostring(order), Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1, LayoutOrder = order }, parent)
		UI.list(frame, 4)
		local caption = label and UI.label({ Name = "Caption", Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = T.sub, Text = label, LayoutOrder = 1 }, frame)
		local row = UI.new("Frame", { Name = "Options", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 2 }, frame)
		UI.list(row, 6, true)
		local object = { Frame = frame, Caption = caption, Buttons = {} }
		local selected = default
		local signature
		local function paint()
			for id, button in object.Buttons do
				local on = id == selected
				button.BackgroundColor3 = on and T.accent or T.panel
				button.TextColor3 = on and Color3.new(1, 1, 1) or T.text
				button.Font = on and T.fontBold or T.font
			end
		end
		function object.SetOptions(list)
			local keys = {}
			for _, entry in list do table.insert(keys, tostring(entry[1]) .. "=" .. tostring(entry[2])) end
			local nextSignature = table.concat(keys, "|")
			local found = false
			for _, entry in list do
				if entry[1] == selected then found = true end
			end
			if not found and list[1] then selected = list[1][1] end
			if nextSignature == signature then
				paint()
				return
			end
			signature = nextSignature
			for _, button in object.Buttons do button:Destroy() end
			table.clear(object.Buttons)
			local count = math.max(1, #list)
			for index, entry in list do
				local button = UI.button({ Name = tostring(entry[1]), Size = UDim2.new(1 / count, -6 * (count - 1) / count, 1, 0), Text = entry[2], TextSize = 12,
					TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = index, Stroke = T.stroke }, row)
				object.Buttons[entry[1]] = button
				button.Activated:Connect(function()
					if selected == entry[1] then return end
					selected = entry[1]
					paint()
					if object.Changed then object.Changed(selected) end
				end)
			end
			paint()
		end
		function object.Get()
			return selected
		end
		function object.Set(id)
			selected = id
			paint()
		end
		object.SetOptions(options)
		return object
	end
	local function field(label, order, parent)
		local frame = UI.new("Frame", { Name = "Field_" .. order, Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, LayoutOrder = order }, parent)
		UI.label({ Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = T.sub, Text = label }, frame)
		return frame
	end

	local catalog, targetData, partnerData, snapshot = {}, {}, {}, nil
	local selectedScene = "Random"
	local scope, target

	local scroll = UI.scroll({ Name = "FunnyScroll", Size = UDim2.fromScale(1, 1) }, page)
	UI.list(scroll, 10)

	-- ① Choisir : aperçu + lancement à gauche, vignettes à droite ----------------------------------------------
	local studio = UI.card(scroll, 1)
	studio.Name = "SceneStudio"
	UI.sectionHeader(text("FUNNY · LE STUDIO DES SITUATIONS", "FUNNY · SCENE STUDIO"), T.accent, studio, 1)
	small({ LayoutOrder = 2, Text = text("① Choisis un effet : l'aperçu se met à jour. Lance-le tout de suite, ou ajuste-le d'abord dans ②.",
		"① Pick an effect: the preview updates. Start it right away, or fine-tune it first in ②.") }, studio)
	local columns = UI.new("Frame", { Name = "Columns", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 }, studio)
	UI.list(columns, 10, true)
	local left = UI.new("Frame", { Name = "PreviewColumn", Size = UDim2.new(.46, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, columns)
	UI.list(left, 6)
	local right = UI.new("Frame", { Name = "EffectColumn", Size = UDim2.new(.54, -5, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2 }, columns)
	UI.list(right, 6)

	local previewFrame = UI.new("Frame", { Name = "Preview", Size = UDim2.new(1, 0, 0, 210), BackgroundColor3 = T.bg, Corner = 10, ClipsDescendants = true,
		LayoutOrder = 1 }, left)
	local viewport = UI.new("ViewportFrame", { Name = "SceneViewport", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(175, 181, 210), LightColor = Color3.fromRGB(255, 231, 214), LightDirection = Vector3.new(-1, -1, -.5) }, previewFrame)
	local previewBadge = UI.label({ Name = "PreviewBadge", Size = UDim2.new(1, -96, 0, 22), Position = UDim2.fromOffset(10, 6), Font = T.fontBold,
		TextSize = 10, TextColor3 = T.sub, Text = text("APERÇU 3D · MUET", "3D PREVIEW · MUTED"), ZIndex = 2 }, previewFrame)
	local replay = UI.button({ Name = "ReplayPreview", Size = UDim2.fromOffset(76, 22), Position = UDim2.new(1, -84, 0, 6), Text = text("Rejouer", "Replay"),
		TextSize = 10, ZIndex = 2 }, previewFrame)
	local previewTitle = UI.label({ Name = "PreviewTitle", Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -30), TextSize = 14, Font = T.fontBold,
		TextColor3 = T.text, Text = "", ZIndex = 2, TextTruncate = Enum.TextTruncate.AtEnd }, previewFrame)
	local details = small({ Name = "SceneDetails", LayoutOrder = 2 }, left)
	details.TextColor3 = T.text
	local previewHint = small({ Name = "PreviewHint", LayoutOrder = 3 }, left)
	previewHint.TextSize = 11
	local summary = small({ Name = "LaunchSummary", LayoutOrder = 4 }, left)
	local generate = UI.button({ Name = "Generate", Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 5, BackgroundColor3 = T.accent, TextSize = 14,
		TextTruncate = Enum.TextTruncate.AtEnd, Text = text("▶  LANCER · ", "▶  START · ") }, left)
	local randomButton = UI.button({ Name = "Random", Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 6, TextSize = 12,
		Text = "🎲  " .. text("SURPRISE · GÉNÉRER AU HASARD", "SURPRISE · GENERATE RANDOMLY") }, left)
	local status = small({ Name = "Status", LayoutOrder = 7, Text = Core.L("Common.Loading") }, left)
	local tileGroups = UI.new("Frame", { Name = "Tiles", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1 }, right)
	UI.list(tileGroups, 6)

	-- ② Régler : énergie, durée, réglages de l'effet, portée et cibles ------------------------------------------
	local settings = UI.card(scroll, 2)
	settings.Name = "Generator"
	UI.sectionHeader(text("② RÉGLAGES ET CIBLES", "② SETTINGS AND TARGETS"), T.good, settings, 1)
	small({ LayoutOrder = 2, Text = text("Effets temporaires, cibles protégées par leur grade, arrêt disponible à tout moment.",
		"Temporary effects, targets protected by rank, and a stop control whenever you need it.") }, settings)
	local intensity = chips(settings, 3, text("Énergie du décor", "Scene energy"),
		{ { "1", text("Douce", "Mild") }, { "2", text("Animée", "Lively") }, { "3", text("Festival", "Festival") } }, "2")
	intensity.Frame.Name = "IntensityPicker"
	local duration = chips(settings, 4, text("Durée", "Duration"), {}, 15)
	duration.Frame.Name = "DurationPicker"
	-- réglages propres à certains effets
	local scale = chips(settings, 5, text("Taille de la tête · facteur 1,25 à 4", "Head size · factor 1.25–4"),
		{ { 1.5, "×1,5" }, { 2, "×2" }, { 3, "×3" }, { 4, "×4" } }, 2)
	scale.Frame.Name = "ScalePicker"
	local presetRow = field(text("Avatars Roblox connus", "Known Roblox avatars"), 6, settings)
	local preset = UI.picker(presetRow, function()
		return snapshot and snapshot.SkinPresets or {}
		end, "builderman", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 20))
	preset.Frame.Name = "SkinPreset"
	local accountRow = field(text("Pseudo Roblox exact ou UserId", "Exact Roblox username or UserId"), 7, settings)
	local account = UI.input({ Name = "Account", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 20), Text = "builderman",
		PlaceholderText = "Roblox / builderman / mrflimflam" }, accountRow)
	preset.Changed = function(value)
		account.Text = value
	end
	local gravity = chips(settings, 8, text("Force de la gravité inversée", "Reverse gravity strength"),
		{ { "Gentle", text("Douce", "Mild") }, { "Normal", text("Normale", "Normal") }, { "Rocket", text("Fusée", "Rocket") } }, "Normal")
	gravity.Frame.Name = "GravityPreset"
	local partRow = field(text("Partie du corps", "Body part"), 9, settings)
	local bodyPart = UI.picker(partRow, { { "Head", text("Tête et visage", "Head and face") }, { "Face", text("Visage seulement", "Face only") },
		{ "Torso", text("Torse", "Torso") },
		{ "LeftArm", text("Bras gauche", "Left arm") }, { "RightArm", text("Bras droit", "Right arm") }, { "LeftLeg", text("Jambe gauche", "Left leg") },
		{ "RightLeg", text("Jambe droite", "Right leg") } },
		"Head", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 20))
	bodyPart.Frame.Name = "BodyPart"
	local operation = chips(settings, 10, text("Action sur les personnages", "Character operation"),
		{ { "Copy", text("Copier · le partenaire ne change pas", "Copy · partner unchanged") }, { "Swap", text("Échanger · transforme les deux joueurs", "Swap · transforms both players") } }, "Copy")
	operation.Frame.Name = "Operation"
	local partnerMode = chips(settings, 11, text("Partenaire pour la partie du corps", "Body-part partner"),
		{ { "Random", text("Joueur aléatoire", "Random player") }, { "Player", text("Joueur choisi", "Chosen player") } }, "Random")
	partnerMode.Frame.Name = "PartnerMode"
	local partnerRow = field(text("Joueur partenaire", "Partner player"), 12, settings)
	local partner = UI.picker(partnerRow, function()
		local options = {}
		local targetId = scope and scope.Get() == "Player" and target and tonumber(target.Get()) or game.Players.LocalPlayer.UserId
		for _, entry in partnerData do
			if entry.UserId ~= targetId then
				table.insert(options, { tostring(entry.UserId), entry.DisplayName .. " (@" .. entry.Name .. ")" .. (entry.CanSwap and "" or text(" · copie uniquement", " · copy only")) })
			end
		end
		return options
		end, nil, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 20))
	partner.Frame.Name = "PartnerPicker"
	-- portée et cibles
	local reach = chips(settings, 20, text("Portée de la situation", "Scene reach"), { { "Local", text("Local", "Local") } }, "Local")
	reach.Frame.Name = "ReachPicker"
	local reachInfo = small({ Name = "ReachInfo", LayoutOrder = 21 }, settings)
	local networkStatus = small({ Name = "NetworkStatus", LayoutOrder = 22 }, settings)
	scope = chips(settings, 23, text("Cibles", "Targets"), { { "Self", text("Moi uniquement", "Only me") }, { "Player", text("Un joueur précis", "One player") } }, "Self")
	scope.Frame.Name = "ScopePicker"
	local targetRow = field(text("Joueur", "Player"), 24, settings)
	targetRow.Visible = false
	target = UI.picker(targetRow, function()
		local options = {}
		for _, entry in targetData do
			table.insert(options, { tostring(entry.UserId), entry.DisplayName .. " (@" .. entry.Name .. ")" .. (entry.Available and "" or text(" · indisponible", " · unavailable")) })
		end
		return options
		end, nil, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 20))
	target.Frame.Name = "TargetPicker"

	-- Aperçu 3D : le composant lit la sélection via scene.Get() et l'énergie via intensity.Get()
	local tiles = {}
	local scene = {}
	function scene.Get()
		return selectedScene
	end
	local function sceneName(id)
		if id == "Random" then return text("Surprise", "Surprise") end
		for _, entry in catalog do
			if entry.Id == id then return Core.Text(entry.Label) end
		end
		return id
	end
	local syncPreview = Preview.Create(Core, {
		page = page, scroll = scroll, viewport = viewport, previewFrame = previewFrame, previewBadge = previewBadge, previewTitle = previewTitle,
		previewHint = previewHint, replay = replay, scene = scene, intensity = intensity, text = text, alive = alive,
		Catalog = function()
			return catalog
		end,
	})
	intensity.Changed = function()
		syncPreview(true)
	end

	local function scopeOptions()
		local options = { { "Self", text("Moi uniquement", "Only me") }, { "Player", text("Un joueur précis", "One player") } }
		if snapshot and snapshot.CanGroup and selectedScene ~= "BodyParts" then
			table.insert(options, { "Group", text("Groupe · jusqu'à ", "Group · up to ") .. tostring(snapshot.MaxGroupTargets) .. text(" joueurs éligibles", " eligible players") })
		end
		return options
	end
	local function reachOptions()
		local options = { { "Local", text("Local", "Local") } }
		if snapshot and snapshot.CanServer then table.insert(options, { "Server", text("Serveur", "Server") }) end
		if snapshot and snapshot.CanCrossServer then table.insert(options, { "CrossServer", text("Interserveurs", "Cross-server") }) end
		return options
	end
	local function durationOptions()
		local maximum = snapshot and snapshot.MaxDuration or 60
		local options = {}
		for _, seconds in DURATIONS do
			if seconds <= maximum then table.insert(options, { seconds, tostring(seconds) .. " s" }) end
		end
		if maximum > 5 and not table.find(DURATIONS, maximum) and maximum <= 60 then table.insert(options, { maximum, tostring(maximum) .. " s" }) end
		return options
	end
	local function chipLabel(object, id)
		local button = object.Buttons[id]
		return button and button.Text or ""
	end

	local function showFields()
		local id = selectedScene
		local localReach = reach.Get() == "Local"
		scope.SetOptions(scopeOptions())
		scope.Frame.Visible = localReach
		targetRow.Visible = localReach and scope.Get() == "Player"
		reach.Frame.Visible = #reachOptions() > 1
		reachInfo.Visible = reach.Frame.Visible
		reachInfo.Text = reach.Get() == "Server" and text("Serveur · toutes les cibles autorisées", "Server · all permitted targets")
			or reach.Get() == "CrossServer" and text("Interserveurs · serveurs actifs de l'expérience", "Cross-server · active experience servers")
			or text("Local · joueurs choisis ici", "Local · chosen players here")
		local decor = id == "Random" or DECORS[id] == true
		intensity.Frame.Visible = decor
		scale.Frame.Visible = id == "BigHead"
		presetRow.Visible = id == "Skin"
		accountRow.Visible = id == "Skin"
		gravity.Frame.Visible = id == "ReverseGravity"
		if not localReach then partnerMode.Set("Random") end
		partnerMode.Frame.Visible = id == "BodyParts" and localReach
		partnerRow.Visible = id == "BodyParts" and localReach and partnerMode.Get() == "Player"
		partRow.Visible = id == "BodyParts"
		operation.Frame.Visible = id == "BodyParts"
		details.Text = id == "Random" and text("Surprise choisit un décor visuel au hasard ; les transformations se choisissent une par une.",
			"Surprise picks a visual scene at random; transformations are chosen one by one.") or ""
		for _, entry in catalog do
			if entry.Id == id then details.Text = Core.Text(entry.Description) end
		end
		if not localReach then
			details.Text ..= text(" Les grades, les personnages disponibles et la limite de scènes de chaque serveur restent prioritaires. Les parties du corps utilisent des partenaires présents dans chaque serveur.",
				" Ranks, available characters and each server scene limit remain authoritative. Body parts use partners present in each server.")
		end
		-- résumé de ce qui partira avec « Lancer »
		local who = localReach and chipLabel(scope, scope.Get()) or chipLabel(reach, reach.Get())
		if localReach and scope.Get() == "Player" then
			for _, entry in targetData do
				if tostring(entry.UserId) == target.Get() then who = entry.DisplayName end
			end
		end
		local parts = { text("Pour : ", "For: ") .. who, tostring(duration.Get()) .. " s" }
		if decor then table.insert(parts, chipLabel(intensity, intensity.Get())) end
		summary.Text = table.concat(parts, " · ") .. text("   — modifiable dans ②", "   — change it in ②")
		generate.Text = text("▶  LANCER · ", "▶  START · ") .. sceneName(id)
		for tileId, tile in tiles do
			local on = tileId == id
			tile.BackgroundColor3 = on and T.accent:Lerp(T.panel, .45) or T.panel
			local stroke = tile:FindFirstChildOfClass("UIStroke")
			if stroke then
				stroke.Color = on and T.accent or T.stroke
				stroke.Thickness = on and 2 or 1
			end
		end
		syncPreview()
	end
	function scene.Set(id)
		selectedScene = id
		showFields()
	end
	partnerMode.Changed = showFields
	reach.Changed = showFields
	duration.Changed = showFields
	scope.Changed = function()
		targetRow.Visible = reach.Get() == "Local" and scope.Get() == "Player"
		partner.Refresh()
		showFields()
	end
	target.Changed = function()
		partner.Refresh()
		showFields()
	end
	local previousIntensityChanged = intensity.Changed
	intensity.Changed = function(value)
		previousIntensityChanged(value)
		showFields()
	end

	-- Vignettes : une grille par catégorie, la Surprise en premier
	local function buildTiles()
		for _, child in tileGroups:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		table.clear(tiles)
		local headers = { text("DÉCORS · AUTOUR DU PERSONNAGE", "SCENES · AROUND THE CHARACTER"), text("AVATARS · CHANGER D'ALLURE", "AVATARS · CHANGE YOUR LOOK"),
			text("MOUVEMENT · DÉFIER LA PHYSIQUE", "MOVEMENT · BEND THE RULES") }
		local colors = { T.accent, T.good, T.warn }
		local entries = { { Id = "Random" } }
		for _, entry in catalog do table.insert(entries, entry) end
		local order = 0
		for group = 1, 3 do
			local members = {}
			for _, entry in entries do
				if category(entry.Id) == group then table.insert(members, entry) end
			end
			if #members > 0 then
				order += 1
				local header = UI.sectionHeader(headers[group], colors[group], tileGroups, order)
				header.Name = "Group" .. group
				order += 1
				local grid = UI.new("Frame", { Name = "Grid" .. group, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
					LayoutOrder = order }, tileGroups)
				UI.new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -4, 0, 58), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
				for index, entry in members do
					local tile = UI.new("TextButton", { Name = entry.Id, Text = "", BackgroundColor3 = T.panel, Corner = 8, Stroke = T.stroke, LayoutOrder = index }, grid)
					UI.label({ Name = "Icon", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 5), TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center,
						Text = ICONS[entry.Id] or "✦" }, tile)
					UI.label({ Name = "Name", Size = UDim2.new(1, -8, 0, 22), Position = UDim2.new(0, 4, 1, -25), TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center,
						TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd, Font = T.fontBold, Text = sceneName(entry.Id) }, tile)
					tiles[entry.Id] = tile
					tile.Activated:Connect(function()
						scene.Set(entry.Id)
					end)
				end
			end
		end
	end

	-- Scènes en cours ---------------------------------------------------------------------------------------------
	local activeCard = UI.card(scroll, 3)
	activeCard.Name = "ActiveScenes"
	UI.sectionHeader(text("SCÈNES EN COURS", "ACTIVE SCENES"), T.warn, activeCard, 1)
	local stopRow = UI.new("Frame", { Name = "StopButtons", Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 2 }, activeCard)
	UI.list(stopRow, 6, true)
	local stopMine = UI.button({ Name = "StopMine", Size = UDim2.new(1, 0, 1, 0), LayoutOrder = 1, BackgroundColor3 = T.bad, TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd, Text = text("ARRÊTER MES SCÈNES", "STOP MY SCENES") }, stopRow)
	local stopAll = UI.button({ Name = "StopAll", Size = UDim2.new(.5, -3, 1, 0), LayoutOrder = 2, BackgroundColor3 = T.bad, Visible = false, TextSize = 12,
		TextTruncate = Enum.TextTruncate.AtEnd, Text = text("ARRÊTER LES SCÈNES AUTORISÉES", "STOP PERMITTED SCENES") }, stopRow)
	local stopCross = UI.button({ Name = "StopCrossMine", Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3, BackgroundColor3 = T.bad, Visible = false, TextSize = 12,
		Text = text("ARRÊTER MES DIFFUSIONS INTERSERVEURS", "STOP MY CROSS-SERVER BROADCASTS") }, activeCard)
	local activeRows = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4 }, activeCard)
	UI.list(activeRows, 7)
	local refreshButton = UI.button({ Name = "Refresh", Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 5, TextSize = 12, Text = Core.L("Common.Refresh") }, activeCard)
	local function layoutStops()
		stopMine.Size = stopAll.Visible and UDim2.new(.5, -3, 1, 0) or UDim2.new(1, 0, 1, 0)
	end

	local busy, loading = false, false
	local lastRefresh = -math.huge
	local countdowns = {}
	local catalogSignature, activeSignature
	local refresh, stop
	local function setBusy(value)
		busy = value
		local allowed = not value and snapshot and snapshot.Enabled and snapshot.CanUse and Core.HasPermission("Funny.Use")
		if reach.Get() == "Server" then
			allowed = allowed and snapshot.CanServer
		elseif reach.Get() == "CrossServer" then
			allowed = allowed and snapshot.CanCrossServer and snapshot.Network and snapshot.Network.Available
		end
		for _, button in { generate, randomButton } do
			button.Active = allowed == true
			button.AutoButtonColor = allowed == true
			button.BackgroundTransparency = allowed and 0 or .55
		end
	end
	local function clear(frame)
		for _, child in frame:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
	end
	local function render(data)
		if not alive() then return end
		if type(data) ~= "table" or not data.Allowed then
			status.Text = text("Accès refusé ou service indisponible.", "Access denied or service unavailable.")
			snapshot = nil
			setBusy(false)
			return
		end
		snapshot = data
		catalog = data.Catalog or {}
		targetData = data.Targets or {}
		partnerData = data.Partners or {}
		reach.SetOptions(reachOptions())
		duration.SetOptions(durationOptions())
		target.Refresh()
		partner.Refresh()
		preset.Refresh()
		local found = false
		for _, entry in targetData do
			if tostring(entry.UserId) == target.Get() then found = true end
		end
		if not found then target.Set(targetData[1] and tostring(targetData[1].UserId) or nil) end
		local ids = {}
		for _, entry in catalog do table.insert(ids, entry.Id) end
		local signature = table.concat(ids, "|")
		if catalogSignature ~= signature then
			catalogSignature = signature
			if selectedScene ~= "Random" and not table.find(ids, selectedScene) then selectedScene = "Random" end
			buildTiles()
		end
		showFields()
		status.Text = (data.Enabled and text("Prêt · ", "Ready · ") or text("Module désactivé · ", "Module disabled · ")) .. tostring(#data.Active) .. " / " .. tostring(data.MaxActiveScenes)
			.. text(" scènes actives · durée max ", " active scenes · maximum duration ") .. tostring(data.MaxDuration) .. " s"
		local net = data.Network
		networkStatus.Visible = data.CanCrossServer == true
		if net then
			networkStatus.Text = (net.Available and text("Interserveurs connecté · ", "Cross-server connected · ") or (net.Reason and Core.Text(net.Reason) or text("Interserveurs indisponible", "Cross-server unavailable")))
				.. (net.Available and tostring(net.Published) .. text(" messages envoyés, ", " messages sent, ") .. tostring(net.Received) .. text(" reçus ici. Livraison non garantie par Roblox.", " received here. Roblox delivery is not guaranteed.") or "")
				.. (net.LastError and " · " .. net.LastError or "")
		end
		stopCross.Visible = data.CanCrossServer or net and net.MyBroadcasts > 0
		stopAll.Visible = data.CanStopAll and Core.HasPermission("Funny.StopAll")
		layoutStops()
		local activeKeys = {}
		for _, entry in data.Active do
			table.insert(activeKeys, table.concat({ entry.Id, entry.Scenario, entry.Reach or "Local", entry.State or "", tostring(entry.EndsAt), tostring(entry.CanStop),
				entry.Error or "",
				entry.SourceAccount or "", entry.Operation or "", entry.BodyPart or "", tostring(entry.PartnerUserId) }, "|"))
		end
		local nextActiveSignature = table.concat(activeKeys, ";")
		if activeSignature ~= nextActiveSignature then
			activeSignature = nextActiveSignature
			clear(activeRows)
			table.clear(countdowns)
			for i, entry in data.Active do
				local card = UI.card(activeRows, i)
				card.Name = "Scene_" .. entry.Id
				UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, Font = T.fontBold, TextSize = 13, LayoutOrder = 1,
					Text = (ICONS[entry.Scenario] and ICONS[entry.Scenario] .. "  " or "") .. sceneName(entry.Scenario) .. " · @" .. entry.TargetName }, card)
				local reachNames = { Local = text("Local", "Local"), Server = text("Serveur", "Server"), CrossServer = text("Interserveurs", "Cross-server") }
				UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.sub, LayoutOrder = 2,
					Text = (reachNames[entry.Reach] or reachNames.Local) .. text(" · par @", " · by @") .. entry.ActorName .. (DECORS[entry.Scenario] and text(" · intensité ", " · intensity ") .. entry.Intensity or "") }, card)
				local extra = (entry.SourceAccount and text("Avatar : @", "Avatar: @") .. entry.SourceAccount) or (entry.BodyPart and entry.Operation .. " · " .. entry.BodyPart .. " · #" .. tostring(entry.PartnerUserId)) or ""
				local states = { Preparing = text("Préparation de l'avatar…", "Preparing avatar…"), Running = text("En cours", "Running"), Stopping = text("Restauration…", "Restoring…"),
					RestoreFailed = text("Restauration à réessayer", "Retry restoration") }
				UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, TextColor3 = T.warn, LayoutOrder = 2,
					Text = (states[entry.State] or entry.State or "") .. (extra ~= "" and " · " .. extra or "") .. (entry.Error and " · " .. entry.Error or "") }, card)
				local remaining = UI.label({ Size = UDim2.new(1, 0, 0, 22), TextSize = 12, TextColor3 = T.sub, LayoutOrder = 3, Text = "" }, card)
				local track = UI.new("Frame", { Name = "TimeTrack", Size = UDim2.new(1, 0, 0, 4), BackgroundColor3 = T.panel, Corner = 2, LayoutOrder = 4 }, card)
				local fill = UI.new("Frame", { Name = "Remaining", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.accent, Corner = 2 }, track)
				table.insert(countdowns, { Label = remaining, Fill = fill, EndsAt = entry.EndsAt, Duration = entry.Duration })
				if entry.CanStop then
					local button = UI.button({ Name = "Stop", Size = UDim2.new(1, 0, 0, 28), Text = Core.L("Common.Stop"), LayoutOrder = 5, BackgroundColor3 = T.bad, TextSize = 12 }, card)
					button.Text = text("Arrêter cette scène", "Stop this scene")
					button.Activated:Connect(function()
						stop(entry.Id)
					end)
				end
			end
			if #data.Active == 0 then UI.label({ Size = UDim2.new(1, 0, 0, 26), TextSize = 12, TextColor3 = T.sub, Text = text("Aucune scène en cours.", "No active scenes.") }, activeRows) end
		end
		setBusy(busy)
	end
	refresh = function()
		if loading or not alive() then return end
		loading = true
		lastRefresh = os.clock()
		task.spawn(function()
			local ok, data = pcall(function()
				return R.GetFunny:InvokeServer()
			end)
			loading = false
			if not alive() then return end
			if ok then
				render(data)
			else
				snapshot = nil
				status.Text = Core.L("Common.ServerError")
				setBusy(false)
			end
		end)
	end
	local function launch(forceRandom)
		if busy or not snapshot or not snapshot.Enabled or not snapshot.CanUse or not Core.HasPermission("Funny.Use") then return end
		local seconds = tonumber(duration.Get())
		if not seconds or seconds % 1 ~= 0 or seconds < 5 or seconds > snapshot.MaxDuration then
			Core.Toast(text("Choisis une durée entière entre 5 et ", "Choose a whole duration between 5 and ") .. snapshot.MaxDuration .. " s.", false)
			return
		end
		local scenario = forceRandom and "Random" or selectedScene
		local request = { Scenario = scenario, Scope = reach.Get() == "Local" and scope.Get() or "Server", Reach = reach.Get(),
			Duration = seconds, Intensity = tonumber(intensity.Get()) }
		if request.Scope == "Player" then
			request.TargetUserId = tonumber(target.Get())
			if not request.TargetUserId then
				Core.Toast(text("Choisis un joueur disponible.", "Choose an available player."), false)
				return
			end
		end
		if scenario == "BigHead" then
			request.Scale = tonumber(scale.Get())
		elseif scenario == "Skin" then
			request.Account = account.Text
		elseif scenario == "ReverseGravity" then
			for name, value in GRAVITY_PRESETS[gravity.Get()] or GRAVITY_PRESETS.Normal do request[name] = value end
		elseif scenario == "BodyParts" then
			request.PartnerMode = reach.Get() == "Local" and partnerMode.Get() or "Random"
			request.BodyPart = bodyPart.Get()
			request.Operation = operation.Get()
			if request.PartnerMode == "Player" then
				request.PartnerUserId = tonumber(partner.Get())
				if not request.PartnerUserId then
					Core.Toast(text("Choisis un partenaire.", "Choose a partner."), false)
					return
				end
			end
		end
		setBusy(true)
		task.spawn(function()
			local ok, success, reply, result = pcall(function()
				return R.StartFunny:InvokeServer(request)
			end)
			if not alive() then return end
			setBusy(false)
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			if ok and success and result and result.Scenario then
				scene.Set(result.Scenario)
			end
			refresh()
		end)
	end
	stop = function(id)
		if not alive() then return end
		setBusy(true)
		task.spawn(function()
			local ok, success, reply = pcall(function()
				return R.StopFunny:InvokeServer(id)
			end)
			if not alive() then return end
			setBusy(false)
			Core.Toast(ok and reply or Core.L("Common.ServerError"), ok and success == true)
			refresh()
		end)
	end
	UI.Confirmable(generate, function()
		return reach.Get() ~= "Local"
		end, function()
			launch(false)
	end)
	UI.Confirmable(randomButton, function()
		return reach.Get() ~= "Local"
		end, function()
			launch(true)
	end)
	stopCross.Activated:Connect(function()
		stop("CrossMine")
	end)
	stopMine.Activated:Connect(function()
		stop("Mine")
	end)
	UI.Confirmable(stopAll, true, function()
		stop("All")
	end)
	refreshButton.Activated:Connect(refresh)
	Core.On(page:GetPropertyChangedSignal("Visible"), function()
		if page.Visible then refresh() end
	end)
	Core.On(Core.Gui:GetPropertyChangedSignal("Enabled"), function()
		if Core.Alive(mine) and Core.Gui and Core.Gui.Enabled and page.Visible then refresh() end
	end)
	Core.On(Core.AccessChanged.Event, function()
		Core.SetTabVisible("Funny", Core.HasPermission("Funny.View"))
		syncPreview()
		if page.Visible then refresh() end
	end)
	duration.SetOptions(durationOptions())
	buildTiles()
	showFields()
	setBusy(false)
	refresh()
	task.spawn(function()
		while alive() do
			task.wait(1)
			if not alive() then break end
			if page.Visible and Core.Enabled and Core.Gui and Core.Gui.Enabled then
				for _, entry in countdowns do
					if entry.Label.Parent then
						local remaining = math.max(0, entry.EndsAt - workspace:GetServerTimeNow())
						entry.Label.Text = text("Temps restant : ", "Time remaining: ") .. math.ceil(remaining) .. " s"
						entry.Fill.Size = UDim2.fromScale(math.clamp(remaining / math.max(1, entry.Duration or 1), 0, 1), 1)
					end
				end
				if os.clock() - lastRefresh >= 3 then refresh() end
			end
		end
	end)
end

return Page
