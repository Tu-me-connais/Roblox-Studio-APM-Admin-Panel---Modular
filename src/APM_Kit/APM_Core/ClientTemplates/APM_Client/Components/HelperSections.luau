--[[
	HelperSections : les sections de la page Sentinel Helper (une fonction par carte). Chaque fonction reçoit le contexte S de la page
	(Core, UI, état serveur S.State, brouillon S.Draft, S.Dirty) et la liste déroulante `scroll`, et renvoie sa carte (ou nil si l'admin n'y a pas droit).
	Le serveur reste seul juge : masquer une carte ici n'est qu'une commodité, chaque demande est revalidée par ConfigureAssistant.
]]
local Sections = {}

local EXTERNAL_PROVIDERS = { { "OpenAI", "OpenAI" }, { "Anthropic", "Anthropic" } }

-- Ligne à interrupteur : le brouillon change, S.Dirty() révèle la barre « Appliquer »
local function switchRow(S, card, order, labelKey, getter, setter, disabled)
	local UI, T = S.UI, S.T
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = order }, card)
	UI.label({ Size = UDim2.new(1, -60, 1, 0), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Text = S.L(labelKey) }, row)
	local toggle = UI.Switch(row, getter(), function(value)
		setter(value)
		S.Dirty()
	end, UDim2.new(1, -46, 0, 2))
	toggle.Frame.Interactable = not disabled
	table.insert(S.Controls, function() toggle.Set(getter()) end)
	return row, toggle
end

-- Curseur avec valeur affichée en direct
local function sliderRow(S, card, order, labelKey, minimum, maximum, getter, setter, format, disabled)
	local UI, T = S.UI, S.T
	local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = order }, card)
	UI.label({ Size = UDim2.new(1, -90, 0, 18), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Text = S.L(labelKey) }, row)
	local value = UI.label({ Size = UDim2.fromOffset(86, 18), Position = UDim2.new(1, -86, 0, 0), TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Right,
		Text = format(getter()) }, row)
	local slider = UI.Slider(row, minimum, maximum, getter(), function(newValue)
		setter(newValue)
		S.Dirty()
	end, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 20))
	slider.Changed = function(newValue) value.Text = format(newValue) end
	slider.Frame.Active = not disabled
	table.insert(S.Controls, function()
		slider.Set(getter())
		value.Text = format(getter())
	end)
	return row
end

local function note(S, card, order, value, color)
	return S.UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 11, TextColor3 = color or S.T.sub,
		LayoutOrder = order, Text = type(value) == "string" and S.L(value) or S.text(value) }, card)
end

local function header(S, card, key, color)
	return S.UI.sectionHeader(S.L(key), color or S.T.accent, card, 1)
end

local function inputBox(S, parent, props)
	props.TextSize = props.TextSize or 12
	return S.UI.input(props, parent)
end

local function textButton(S, parent, props)
	props.TextSize = props.TextSize or 12
	props.BackgroundColor3 = props.BackgroundColor3 or S.T.panel
	props.Stroke = props.Stroke or S.T.stroke
	return S.UI.button(props, parent)
end

----------------------------------------------------------------------------------------------------------
-- 1. Vue d'ensemble

function Sections.Overview(S, scroll, order)
	local card = S.UI.card(scroll, order)
	card.Name = "HelperOverview"
	header(S, card, "Helper.Title")
	note(S, card, 2, "Helper.Intro")
	note(S, card, 3, "Helper.EngineNote", S.T.warn)
	local state = S.State
	local custom = #(state.Config.Custom or {})
	local disabled = 0
	for _ in state.Config.DisabledCommands or {} do disabled += 1 end
	local available = #state.Registry - disabled + custom
	local statusNote = note(S, card, 4, S.Core.Lang.Msg(state.Config.Enabled and "Helper.StatusOn" or "Helper.StatusOff", available, custom), state.Config.Enabled and S.T.good or S.T.bad)
	-- ligne vivante : l'état global vu par le serveur (dernière lecture de Sentinel) prime sur la copie lue à la construction, même si des modifications sont en attente
	table.insert(S.Live, function()
		local api = S.Core.Assistant
		local server = api and api.Server
		local enabled = state.Config.Enabled
		if server and server.Allowed == true then enabled = server.Enabled == true end
		statusNote.Text = S.text(S.Core.Lang.Msg(enabled and "Helper.StatusOn" or "Helper.StatusOff", available, custom))
		statusNote.TextColor3 = enabled and S.T.good or S.T.bad
	end)
	if state.Newer then note(S, card, 5, "Helper.Newer", S.T.bad) end
	if state.Migrated then note(S, card, 6, "Helper.Migrated", S.T.sub) end
	return card
end

----------------------------------------------------------------------------------------------------------
-- 2. Mes préférences (locales : ce compte uniquement)

function Sections.Preferences(S, scroll, order)
	local UI, T, Core = S.UI, S.T, S.Core
	local card = UI.card(scroll, order)
	card.Name = "HelperPreferences"
	header(S, card, "Helper.Local.Title", T.good)
	note(S, card, 2, "Helper.Local.Intro")
	local status = note(S, card, 20, "")
	local function saved(ok)
		S.Say(status, ok and "Helper.Local.Saved" or "Helper.Local.NotSaved", ok)
	end
	local function personal(name, default)
		local prefs = Core.PersonalPreferences or {}
		local value = prefs[name]
		return value == nil and default or value
	end
	local function save(patch)
		Core.PersonalPreferences = Core.PersonalPreferences or {}
		for key, value in patch do Core.PersonalPreferences[key] = value end
		task.spawn(function()
			local ok, accepted = pcall(function() return Core.R.SetPreferences:InvokeServer(patch) end)
			saved(ok and accepted == true)
		end)
	end
	-- ces réglages s'appliquent tout de suite (pas de barre « Appliquer »)
	local row1 = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 3 }, card)
	UI.label({ Size = UDim2.new(1, -60, 1, 0), TextSize = 12, Text = S.L("Helper.Local.Show") }, row1)
	local show = UI.Switch(row1, personal("AssistantEnabled", true), function(value)
		if Core.Assistant then Core.Assistant.SetEnabled(value, saved) else save({ AssistantEnabled = value }) end
	end, UDim2.new(1, -46, 0, 2))
	-- état du commutateur lu à la source unique (Core.Assistant.State) : il suit l'Accueil et les changements globaux sans boucle (Switch.Set ne rappelle pas le callback)
	local showStatus = note(S, card, 4, "")
	local function paintShow()
		local api = Core.Assistant
		if not api then return end
		local state = api.State()
		show.Set(state.Personal)
		show.Frame.Interactable = state.GlobalEnabled
		if not state.Allowed then
			showStatus.Text = ""
		else
			showStatus.Text = S.L((not state.GlobalEnabled) and "Sentinel.Home.GloballyOff" or (state.Personal and "Sentinel.Home.On" or "Sentinel.Home.Off"))
		end
	end
	table.insert(S.Live, paintShow)
	paintShow()
	local row2 = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 5 }, card)
	UI.label({ Size = UDim2.new(1, -60, 1, 0), TextSize = 12, Text = S.L("Helper.Local.Wave") }, row2)
	UI.Switch(row2, personal("AssistantWave", true), function(value) save({ AssistantWave = value }) end, UDim2.new(1, -46, 0, 2))
	local sizeRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, LayoutOrder = 6 }, card)
	UI.label({ Size = UDim2.new(1, -90, 0, 18), TextSize = 12, Text = S.L("Helper.Local.Size") }, sizeRow)
	local sizeValue = UI.label({ Size = UDim2.fromOffset(86, 18), Position = UDim2.new(1, -86, 0, 0), TextSize = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Right,
		Text = string.format("%d %%", math.floor(personal("AssistantScale", 1) * 100 + .5)) }, sizeRow)
	local size = UI.Slider(sizeRow, 60, 150, math.floor(personal("AssistantScale", 1) * 100 + .5), function(value)
		save({ AssistantScale = value / 100 })
		if Core.Assistant and Core.Assistant.Relayout then Core.Assistant.Relayout() end
	end, UDim2.new(1, 0, 0, 24), UDim2.fromOffset(0, 20))
	size.Changed = function(value) sizeValue.Text = string.format("%d %%", value) end
	local reset = textButton(S, card, { Name = "ResetSentinelLayout", Size = UDim2.new(1, 0, 0, 30), Text = S.L("Helper.Local.Reset"), LayoutOrder = 7 })
	reset.Activated:Connect(function()
		if Core.Assistant and Core.Assistant.ResetLayout then Core.Assistant.ResetLayout() end
		S.Say(status, "Helper.Local.ResetDone", true)
	end)
	return card
end

----------------------------------------------------------------------------------------------------------
-- 3. Réglages administratifs (tout le serveur) — permission Assistant.Configure

function Sections.General(S, scroll, order)
	local state = S.State
	if not state.Can.Configure then return nil end
	local UI, T = S.UI, S.T
	local card = UI.card(scroll, order)
	card.Name = "HelperGeneral"
	header(S, card, "Helper.General.Title", T.warn)
	note(S, card, 2, "Helper.General.Intro")
	local draft = S.Draft
	switchRow(S, card, 3, "Helper.General.Enabled", function() return draft.Enabled end, function(value) draft.Enabled = value end)
	switchRow(S, card, 4, "Helper.General.Confirm", function() return draft.ConfirmDangerous end, function(value) draft.ConfirmDangerous = value end)
	switchRow(S, card, 5, "Helper.General.AllowAll", function() return draft.AllowAll end, function(value) draft.AllowAll = value end)
	switchRow(S, card, 6, "Helper.General.Deployed", function() return draft.DefaultDeployed end, function(value) draft.DefaultDeployed = value end)
	switchRow(S, card, 7, "Helper.General.Wave", function() return draft.WaveEnabled end, function(value) draft.WaveEnabled = value end)

	-- style des réponses : deux choix
	local styleRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 8 }, card)
	UI.label({ Size = UDim2.new(.4, 0, 1, 0), TextSize = 12, Text = S.L("Helper.General.Style") }, styleRow)
	local styleButtons = {}
	for index, choice in { "Short", "Detailed" } do
		local button = textButton(S, styleRow, { Name = "Style" .. choice, Size = UDim2.new(.3, -4, 1, 0), Position = UDim2.new(.4 + (index - 1) * .3, index == 1 and 0 or 4, 0, 0),
			Text = S.L("Helper.General.Style" .. choice) })
		styleButtons[choice] = button
		button.Activated:Connect(function()
			draft.ReplyStyle = choice
			for name, other in styleButtons do other.BackgroundColor3 = name == draft.ReplyStyle and T.accent or T.panel end
			S.Dirty()
		end)
	end
	local function paintStyle() for name, other in styleButtons do other.BackgroundColor3 = name == draft.ReplyStyle and T.accent or T.panel end end
	paintStyle()
	table.insert(S.Controls, paintStyle)

	local function plain(value) return tostring(value) end
	sliderRow(S, card, 9, "Helper.General.MaxAll", 1, 100, function() return draft.MaxAllTargets end, function(value) draft.MaxAllTargets = value end, plain)
	sliderRow(S, card, 10, "Helper.General.Rate", 2, 30, function() return draft.RatePerWindow end, function(value) draft.RatePerWindow = value end, plain)
	sliderRow(S, card, 11, "Helper.General.History", 10, 100, function() return draft.MaxHistory end, function(value) draft.MaxHistory = value end, plain)
	sliderRow(S, card, 12, "Helper.General.WaveInterval", 10, 120, function() return draft.WaveInterval end, function(value) draft.WaveInterval = value end,
		function(value) return string.format("%d s", value) end)
	sliderRow(S, card, 13, "Helper.General.Speed", 50, 200, function() return math.floor(draft.AnimationSpeed * 100 + .5) end, function(value) draft.AnimationSpeed = value / 100 end,
		function(value) return string.format("%d %%", value) end)

	-- commandes du registre : lesquelles Sentinel accepte-t-il ? (le panneau, lui, ne change pas)
	UI.sectionHeader(S.L("Helper.General.Commands"), T.accent, card, 14)
	note(S, card, 15, "Helper.General.CommandsNote")
	local list = UI.new("Frame", { Name = "CommandSwitches", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 16 }, card)
	UI.list(list, 4)
	for index, entry in state.Registry do
		local row = UI.new("Frame", { Name = "Command_" .. entry.Name, Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = index }, list)
		UI.label({ Size = UDim2.new(1, -60, 1, 0), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Text = entry.Usage }, row)
		local toggle = UI.Switch(row, not draft.DisabledCommands[entry.Name], function(value)
			draft.DisabledCommands[entry.Name] = (not value) or nil
			S.Dirty()
		end, UDim2.new(1, -46, 0, 1))
		table.insert(S.Controls, function() toggle.Set(not draft.DisabledCommands[entry.Name]) end)
	end

	-- alias globaux
	UI.sectionHeader(S.L("Helper.General.Aliases"), T.accent, card, 17)
	note(S, card, 18, "Helper.General.AliasesNote")
	local aliasList = UI.new("Frame", { Name = "AliasList", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 19 }, card)
	UI.list(aliasList, 4)
	local function renderAliases()
		for _, child in aliasList:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
		local names = {}
		for alias in draft.Aliases do table.insert(names, alias) end
		table.sort(names)
		for index, alias in names do
			local row = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = index }, aliasList)
			UI.label({ Size = UDim2.new(1, -40, 1, 0), TextSize = 12, Text = alias .. "  =  " .. draft.Aliases[alias] }, row)
			local remove = textButton(S, row, { Name = "RemoveAlias", Size = UDim2.fromOffset(30, 24), Position = UDim2.new(1, -30, 0, 1), Text = "×" })
			remove.Activated:Connect(function()
				draft.Aliases[alias] = nil
				renderAliases()
				S.Dirty()
			end)
		end
	end
	renderAliases()
	table.insert(S.Controls, renderAliases)
	local addRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 20 }, card)
	local aliasBox = inputBox(S, addRow, { Name = "NewAlias", Size = UDim2.new(.3, -4, 1, 0), PlaceholderText = S.L("Helper.General.AliasName") })
	local options = {}
	for _, entry in state.Registry do table.insert(options, { entry.Name, entry.Name }) end
	for _, custom in state.Config.Custom or {} do table.insert(options, { custom.Name, custom.Name }) end
	local picker = UI.picker(addRow, options, options[1] and options[1][1], UDim2.new(.4, -4, 1, 0), UDim2.new(.3, 0, 0, 0))
	local add = textButton(S, addRow, { Name = "AddAlias", Size = UDim2.new(.3, 0, 1, 0), Position = UDim2.new(.7, 0, 0, 0), Text = S.L("Helper.General.AddAlias") })
	add.Activated:Connect(function()
		local alias = string.lower(aliasBox.Text)
		local target = picker.Get()
		if not string.match(alias, "^[a-z][a-z0-9_]+$") or #alias > 24 or not target then
			S.Core.Toast(S.L("Helper.General.AliasInvalid"), false)
			return
		end
		draft.Aliases[alias] = target
		aliasBox.Text = ""
		renderAliases()
		S.Dirty()
	end)
	return card
end

----------------------------------------------------------------------------------------------------------
-- 4. Commandes personnalisées — permission Assistant.Commands (données, jamais du code)

function Sections.Custom(S, scroll, order)
	local state = S.State
	if not state.Can.Commands then return nil end
	local UI, T, Core = S.UI, S.T, S.Core
	local R = Core.R
	local card = UI.card(scroll, order)
	card.Name = "HelperCustom"
	header(S, card, "Helper.Custom.Title", T.good)
	note(S, card, 2, "Helper.Custom.Intro")
	local status = note(S, card, 40, "")
	local list = UI.new("Frame", { Name = "CustomList", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 }, card)
	UI.list(list, 4)

	local editor = UI.new("Frame", { Name = "CustomEditor", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 5, Visible = false }, card)
	UI.list(editor, 6)
	local original = nil
	local function field(order, placeholder, name)
		return inputBox(S, editor, { Name = name, Size = UDim2.new(1, 0, 0, 30), PlaceholderText = S.L(placeholder), LayoutOrder = order })
	end
	local nameBox = field(1, "Helper.Custom.Name", "CustomName")
	local descBox = field(2, "Helper.Custom.Description", "CustomDescription")
	local aliasesBox = field(3, "Helper.Custom.Aliases", "CustomAliases")

	-- arguments (3 au plus)
	local argumentRows = {}
	local TYPE_OPTIONS = { { "target", S.L("Helper.Custom.TypeTarget") }, { "number", S.L("Helper.Custom.TypeNumber") }, { "text", S.L("Helper.Custom.TypeText") }, { "boolean", S.L("Helper.Custom.TypeBoolean") } }
	for index = 1, state.Limits.MaxArgs do
		local row = UI.new("Frame", { Name = "Argument" .. index, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 3 + index }, editor)
		local argName = inputBox(S, row, { Name = "ArgumentName", Size = UDim2.new(.36, -4, 1, 0), PlaceholderText = S.L("Helper.Custom.ArgumentName") .. " " .. index })
		local argType = UI.picker(row, TYPE_OPTIONS, "text", UDim2.new(.36, -4, 1, 0), UDim2.new(.36, 0, 0, 0))
		local required = textButton(S, row, { Name = "ArgumentRequired", Size = UDim2.new(.28, 0, 1, 0), Position = UDim2.new(.72, 0, 0, 0), Text = S.L("Helper.Custom.Optional") })
		local isRequired = false
		required.Activated:Connect(function()
			isRequired = not isRequired
			required.Text = S.L(isRequired and "Helper.Custom.Required" or "Helper.Custom.Optional")
			required.BackgroundColor3 = isRequired and T.accent or T.panel
		end)
		argumentRows[index] = { Name = argName, Type = argType, Required = function() return isRequired end, SetRequired = function(value)
			isRequired = value
			required.Text = S.L(isRequired and "Helper.Custom.Required" or "Helper.Custom.Optional")
			required.BackgroundColor3 = isRequired and T.accent or T.panel
		end }
	end

	local permissions = {}
	for _, name in state.Permissions do table.insert(permissions, { name, name }) end
	UI.label({ Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextColor3 = T.sub, Text = S.L("Helper.Custom.Permission"), LayoutOrder = 8 }, editor)
	local permissionPicker = UI.picker(editor, permissions, "Assistant.Use", UDim2.new(1, 0, 0, 30), nil)
	permissionPicker.Frame.LayoutOrder = 9

	UI.label({ Size = UDim2.new(1, 0, 0, 16), TextSize = 11, TextColor3 = T.sub, Text = S.L("Helper.Custom.Action"), LayoutOrder = 10 }, editor)
	local ACTIONS = { { "Reply", S.L("Helper.Custom.ActionReply") }, { "Teleport", S.L("Helper.Custom.ActionTeleport") }, { "Run", S.L("Helper.Custom.ActionRun") } }
	local actionPicker = UI.picker(editor, ACTIONS, "Reply", UDim2.new(1, 0, 0, 30), nil)
	actionPicker.Frame.LayoutOrder = 11

	local replyFrame = UI.new("Frame", { Name = "ReplyFields", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 12 }, editor)
	UI.list(replyFrame, 6)
	local replyBox = inputBox(S, replyFrame, { Name = "ReplyText", Size = UDim2.new(1, 0, 0, 30), PlaceholderText = S.L("Helper.Custom.ReplyText") })

	local teleportFrame = UI.new("Frame", { Name = "TeleportFields", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 13, Visible = false }, editor)
	UI.list(teleportFrame, 6)
	local whoPicker = UI.picker(teleportFrame, { { "Self", S.L("Helper.Custom.WhoSelf") }, { "Target", S.L("Helper.Custom.WhoTarget") } }, "Self", UDim2.new(1, 0, 0, 30), nil)
	local coordinates = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1 }, teleportFrame)
	local axes = {}
	for index, axis in { "X", "Y", "Z" } do
		axes[axis] = inputBox(S, coordinates, { Name = "Point" .. axis, Size = UDim2.new(.22, -4, 1, 0), Position = UDim2.new((index - 1) * .22, (index - 1) * 2, 0, 0), PlaceholderText = axis, Text = "0" })
	end
	local here = textButton(S, coordinates, { Name = "UseMyPosition", Size = UDim2.new(.34, 0, 1, 0), Position = UDim2.new(.66, 4, 0, 0), Text = S.L("Helper.Custom.MyPosition") })
	here.Activated:Connect(function()
		local character = Core.Player.Character
		if not character then return end
		local position = character:GetPivot().Position
		axes.X.Text, axes.Y.Text, axes.Z.Text = string.format("%.1f", position.X), string.format("%.1f", position.Y), string.format("%.1f", position.Z)
	end)

	local runFrame = UI.new("Frame", { Name = "RunFields", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 14, Visible = false }, editor)
	UI.list(runFrame, 6)
	note(S, runFrame, 0, "Helper.Custom.RunNote")
	local stepBoxes = {}
	for index = 1, state.Limits.MaxSteps do
		stepBoxes[index] = inputBox(S, runFrame, { Name = "Step" .. index, Size = UDim2.new(1, 0, 0, 30), PlaceholderText = S.L("Helper.Custom.Step") .. " " .. index, LayoutOrder = index })
	end

	local function showAction(kind)
		replyFrame.Visible, teleportFrame.Visible, runFrame.Visible = kind == "Reply", kind == "Teleport", kind == "Run"
	end
	actionPicker.Changed = showAction

	local buttons = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, LayoutOrder = 20 }, editor)
	local save = textButton(S, buttons, { Name = "SaveCustom", Size = UDim2.new(.5, -4, 1, 0), BackgroundColor3 = T.good, Text = S.L("Helper.Custom.Save") })
	local cancel = textButton(S, buttons, { Name = "CancelCustom", Size = UDim2.new(.5, -4, 1, 0), Position = UDim2.new(.5, 4, 0, 0), Text = S.L("Helper.Cancel") })

	local function split(textValue)
		local items = {}
		for item in string.gmatch(textValue, "[^,%s]+") do table.insert(items, item) end
		return items
	end

	local function fill(definition)
		original = definition and definition.Name or nil
		nameBox.Text, descBox.Text = definition and definition.Name or "", definition and definition.Description or ""
		aliasesBox.Text = definition and table.concat(definition.Aliases or {}, ", ") or ""
		for index, row in argumentRows do
			local arg = definition and definition.Args and definition.Args[index]
			row.Name.Text = arg and arg.Name or ""
			row.Type.Set(arg and arg.Type or "text")
			row.SetRequired(arg and arg.Required == true or false)
		end
		permissionPicker.Set(definition and definition.Permission or "Assistant.Use")
		local action = definition and definition.Action or { Type = "Reply", Text = "" }
		actionPicker.Set(action.Type)
		showAction(action.Type)
		replyBox.Text = action.Text or ""
		whoPicker.Set(action.Who or "Self")
		axes.X.Text, axes.Y.Text, axes.Z.Text = tostring(action.X or 0), tostring(action.Y or 0), tostring(action.Z or 0)
		for index, box in stepBoxes do box.Text = action.Steps and action.Steps[index] and action.Steps[index].Command or "" end
	end

	local function collect()
		local definition = { Name = string.lower(nameBox.Text), Description = descBox.Text, Aliases = split(string.lower(aliasesBox.Text)), Args = {}, Permission = permissionPicker.Get() }
		for _, row in argumentRows do
			if row.Name.Text ~= "" then table.insert(definition.Args, { Name = row.Name.Text, Type = row.Type.Get(), Required = row.Required() }) end
		end
		local kind = actionPicker.Get()
		if kind == "Reply" then
			definition.Action = { Type = "Reply", Text = replyBox.Text }
		elseif kind == "Teleport" then
			definition.Action = { Type = "Teleport", Who = whoPicker.Get(), X = tonumber(axes.X.Text), Y = tonumber(axes.Y.Text), Z = tonumber(axes.Z.Text) }
		else
			local steps = {}
			for _, box in stepBoxes do if box.Text ~= "" then table.insert(steps, { Command = box.Text }) end end
			definition.Action = { Type = "Run", Steps = steps }
		end
		return definition
	end

	save.Activated:Connect(function()
		save.Interactable = false
		S.Say(status, "Common.Loading")
		local definition = collect()
		task.spawn(function()
			local ok, first, second = pcall(function() return R.ConfigureAssistant:InvokeServer("SaveCustom", definition, original) end)
			if not S.alive() then return end
			save.Interactable = true
			if ok and first == true then
				Core.Toast(second, true)
				S.Reload()
			else
				S.Say(status, ok and (second or first) or "Helper.Unavailable", false)
			end
		end)
	end)
	cancel.Activated:Connect(function()
		editor.Visible = false
		original = nil
	end)

	-- liste existante
	for index, definition in state.Config.Custom or {} do
		local row = UI.new("Frame", { Name = "Custom_" .. definition.Name, Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = index }, list)
		UI.label({ Size = UDim2.new(1, -150, 1, 0), TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd, Text = definition.Name .. (definition.Description ~= "" and ("  —  " .. definition.Description) or "") }, row)
		local edit = textButton(S, row, { Name = "EditCustom", Size = UDim2.fromOffset(72, 26), Position = UDim2.new(1, -148, 0, 2), Text = S.L("Helper.Custom.Edit") })
		local delete = textButton(S, row, { Name = "DeleteCustom", Size = UDim2.fromOffset(72, 26), Position = UDim2.new(1, -72, 0, 2), BackgroundColor3 = Color3.fromRGB(58, 44, 48), Text = S.L("Helper.Custom.Delete") })
		edit.Activated:Connect(function()
			fill(definition)
			editor.Visible = true
		end)
		UI.Confirmable(delete, true, function()
			task.spawn(function()
				local ok, first, second = pcall(function() return R.ConfigureAssistant:InvokeServer("DeleteCustom", definition.Name) end)
				if not S.alive() then return end
				if ok and first == true then Core.Toast(second, true) S.Reload() else S.Say(status, ok and (second or first) or "Helper.Unavailable", false) end
			end)
		end)
	end
	local addButton = textButton(S, card, { Name = "NewCustom", Size = UDim2.new(1, 0, 0, 30), Text = S.L("Helper.Custom.New"), LayoutOrder = 4 })
	addButton.Activated:Connect(function()
		fill(nil)
		editor.Visible = true
	end)
	fill(nil)
	return card
end

----------------------------------------------------------------------------------------------------------
-- 5. IA externe (facultative) — lecture avec Assistant.Configure, modification avec Assistant.External

function Sections.External(S, scroll, order)
	local state = S.State
	if not (state.Can.Configure or state.Can.External) then return nil end
	local UI, T, Core = S.UI, S.T, S.Core
	local card = UI.card(scroll, order)
	card.Name = "HelperExternal"
	header(S, card, "Helper.External.Title", T.sub)
	note(S, card, 2, "Helper.External.Intro")
	local status = state.ExternalStatus
	local checks = status and status.Checks or {}
	local items = { { "Enabled", "Helper.External.CheckEnabled" }, { "Hosts", "Helper.External.CheckHosts" }, { "Endpoint", "Helper.External.CheckEndpoint" },
		{ "Key", "Helper.External.CheckKey" }, { "Http", "Helper.External.CheckHttp" }, { "Model", "Helper.External.CheckModel" } }
	for index, item in items do
		local ok = checks[item[1]] == true
		UI.label({ Name = "Check" .. item[1], Size = UDim2.new(1, 0, 0, 18), TextSize = 12, TextColor3 = ok and T.good or T.sub, LayoutOrder = 2 + index, Text = (ok and "[OK]  " or "[  ]  ") .. S.L(item[2]) }, card)
	end
	note(S, card, 10, status and status.Available and "Helper.External.Ready" or "Helper.External.NotReady", status and status.Available and T.good or T.warn)
	note(S, card, 11, "Helper.External.Setup")
	if not state.Can.External then return card end
	local draft = S.Draft
	local external = draft.External
	switchRow(S, card, 12, "Helper.External.Enable", function() return draft.External.Enabled end, function(value) draft.External.Enabled = value end)
	local providerRow = UI.new("Frame", { Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 13 }, card)
	UI.label({ Size = UDim2.new(.4, 0, 1, 0), TextSize = 12, Text = S.L("Helper.External.Provider") }, providerRow)
	local provider = UI.picker(providerRow, EXTERNAL_PROVIDERS, external.Provider, UDim2.new(.6, 0, 1, 0), UDim2.new(.4, 0, 0, 0))
	provider.Changed = function(id) draft.External.Provider = id S.Dirty() end
	table.insert(S.Controls, function() provider.Set(draft.External.Provider) end)
	local model = inputBox(S, card, { Name = "ExternalModel", Size = UDim2.new(1, 0, 0, 30), PlaceholderText = S.L("Helper.External.Model"), Text = external.Model or "", LayoutOrder = 14 })
	model.FocusLost:Connect(function() draft.External.Model = model.Text S.Dirty() end)
	local endpoint = inputBox(S, card, { Name = "ExternalEndpoint", Size = UDim2.new(1, 0, 0, 30), PlaceholderText = S.L("Helper.External.Endpoint"), Text = external.Endpoint or "", LayoutOrder = 15 })
	endpoint.FocusLost:Connect(function() draft.External.Endpoint = endpoint.Text S.Dirty() end)
	table.insert(S.Controls, function() model.Text, endpoint.Text = draft.External.Model or "", draft.External.Endpoint or "" end)
	sliderRow(S, card, 16, "Helper.External.Timeout", 3, 20, function() return draft.External.TimeoutSeconds end, function(value) draft.External.TimeoutSeconds = value end,
		function(value) return string.format("%d s", value) end)
	sliderRow(S, card, 17, "Helper.External.PerMinute", 1, 30, function() return draft.External.MaxPerMinute end, function(value) draft.External.MaxPerMinute = value end, tostring)
	local result = note(S, card, 19, "")
	local test = textButton(S, card, { Name = "TestExternal", Size = UDim2.new(1, 0, 0, 30), Text = S.L("Helper.External.Test"), LayoutOrder = 18 })
	test.Activated:Connect(function()
		test.Interactable = false
		S.Say(result, "Common.Loading")
		task.spawn(function()
			local ok, first, second = pcall(function() return Core.R.ConfigureAssistant:InvokeServer("TestExternal") end)
			if not S.alive() then return end
			test.Interactable = true
			S.Say(result, ok and (second or first) or "Helper.Unavailable", ok and first == true)
		end)
	end)
	return card
end

----------------------------------------------------------------------------------------------------------
-- 5 bis. Langues des commandes : les alias officiels des sept langues (lecture seule ; les dictionnaires sont des ModuleScripts du Core)

function Sections.Languages(S, scroll, order)
	local state = S.State
	if type(state.Languages) ~= "table" or type(state.Aliases) ~= "table" or #state.Languages == 0 then return nil end
	local UI, T, Core = S.UI, S.T, S.Core
	local card = UI.card(scroll, order)
	card.Name = "HelperLanguages"
	header(S, card, "Helper.Lang.Title", T.accent)
	note(S, card, 2, "Helper.Lang.Intro")
	note(S, card, 3, "Helper.Lang.TargetRule", T.warn)
	local localization = state.Localization or {}
	local collisions, problems = tonumber(localization.Collisions) or 0, tonumber(localization.Problems) or 0
	note(S, card, 4, Core.Lang.Msg("Helper.Lang.Health", collisions, problems), (collisions + problems) > 0 and T.warn or T.good)
	local options = {}
	for _, language in state.Languages do table.insert(options, { language.Code, language.Name }) end
	local row = UI.new("Frame", { Name = "LanguagePickRow", Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, LayoutOrder = 5 }, card)
	UI.label({ Size = UDim2.new(.3, 0, 1, 0), TextSize = 12, Text = S.L("Helper.Lang.Pick") }, row)
	local prefixes = note(S, card, 6, "")
	local list = UI.new("Frame", { Name = "LanguageAliases", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 7 }, card)
	UI.list(list, 3)
	local function render(code)
		for _, child in list:GetChildren() do
			if child:IsA("GuiObject") then child:Destroy() end
		end
		for index, entry in state.Aliases[code] or {} do
			local words = table.concat(entry.On, ", ")
			if #entry.Off > 0 then words = words .. "    " .. S.L("Helper.Lang.Off") .. " " .. table.concat(entry.Off, ", ") end
			UI.label({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, TextSize = 12, LayoutOrder = index,
				TextXAlignment = Enum.TextXAlignment.Left, Text = entry.Module .. "  =  " .. words }, list)
		end
		local stops = state.OffPrefixes and state.OffPrefixes[code] or {}
		prefixes.Text = #stops > 0 and S.text(Core.Lang.Msg("Helper.Lang.Prefixes", table.concat(stops, ", "))) or ""
	end
	local picker = UI.picker(row, options, options[1][1], UDim2.new(.7, 0, 1, 0), UDim2.new(.3, 0, 0, 0))
	picker.Changed = render
	render(options[1][1])
	return card
end

----------------------------------------------------------------------------------------------------------
-- 6. Test du moteur : comment Sentinel comprend-il ce texte ? (aucune exécution)

function Sections.Test(S, scroll, order)
	local UI, T, Core = S.UI, S.T, S.Core
	local card = UI.card(scroll, order)
	card.Name = "HelperTest"
	header(S, card, "Helper.Test.Title", T.accent)
	note(S, card, 2, "Helper.Test.Intro")
	local box = inputBox(S, card, { Name = "ExplainInput", Size = UDim2.new(1, 0, 0, 30), PlaceholderText = S.L("Helper.Test.Placeholder"), LayoutOrder = 3 })
	local result = note(S, card, 5, "")
	local run = textButton(S, card, { Name = "ExplainRun", Size = UDim2.new(1, 0, 0, 30), Text = S.L("Helper.Test.Run"), LayoutOrder = 4 })
	run.Activated:Connect(function()
		local sample = box.Text
		task.spawn(function()
			local ok, first, second = pcall(function() return Core.R.ConfigureAssistant:InvokeServer("Explain", sample) end)
			if not S.alive() then return end
			if not ok or first ~= true or type(second) ~= "table" then S.Say(result, "Helper.Unavailable", false) return end
			if second.Kind == "Unknown" then
				local hints = second.Suggestions and #second.Suggestions > 0 and table.concat(second.Suggestions, ", ") or "—"
				S.Say(result, Core.Lang.Msg("Helper.Test.Unknown", hints), false)
			elseif second.Kind == "Invalid" then
				S.Say(result, "Helper.Test.Invalid", false)
			elseif second.Kind == "Local" then
				S.Say(result, Core.Lang.Msg("Helper.Test.Local", second.Command), true)
			else
				-- reconnu : commande, langue de la formulation, action canonique, sens, cible (et confirmation) ; rien n'est execute
				local lines = { S.text(Core.Lang.Msg("Helper.Test.Known", second.Command, second.Usage or "")) }
				if type(second.Languages) == "table" and #second.Languages > 0 then
					table.insert(lines, S.text(Core.Lang.Msg("Helper.Test.Language", table.concat(second.Languages, ", "))))
				end
				if second.Module then
					table.insert(lines, S.text(Core.Lang.Msg("Helper.Test.Action", second.Module, S.L(second.Off and "Helper.Test.Off" or "Helper.Test.On"))))
				end
				local target = second.Target
				if target then
					local key = target.Kind == "All" and "Helper.Test.Target.All" or (target.Kind == "Self" and (target.Implicit and "Helper.Test.Target.Self" or "Helper.Test.Target.SelfExplicit") or "Helper.Test.Target.One")
					table.insert(lines, S.L(key))
				else
					table.insert(lines, S.L("Helper.Test.Target.None"))
				end
				if second.NeedsConfirm then table.insert(lines, S.L("Helper.Test.NeedsConfirm")) end
				if second.Problem then table.insert(lines, S.L("Helper.Test.Refused")) end
				S.Say(result, table.concat(lines, "\n"), second.Problem == nil)
			end
		end)
	end)
	return card
end

----------------------------------------------------------------------------------------------------------
-- 7. Stockage et diagnostic

function Sections.Storage(S, scroll, order)
	local state = S.State
	local UI, T, Core = S.UI, S.T, S.Core
	local card = UI.card(scroll, order)
	card.Name = "HelperStorage"
	header(S, card, "Helper.Storage.Title", T.sub)
	local storage = state.Storage
	local mode = storage and storage.Storage or "Memory"
	note(S, card, 2, Core.Lang.Msg("Helper.Storage.Mode", S.L("Helper.Storage." .. mode)))
	if mode == "Memory" then note(S, card, 3, "Helper.Storage.MemoryNote", T.warn) end
	note(S, card, 4, Core.Lang.Msg("Helper.Storage.Overrides", storage and storage.OverrideCount or 0))
	if #(state.Config.Issues or {}) > 0 then
		local lines = {}
		for _, issue in state.Config.Issues do table.insert(lines, tostring(issue.Name) .. " (" .. tostring(issue.Code) .. ")") end
		note(S, card, 5, Core.Lang.Msg("Helper.Storage.Issues", table.concat(lines, ", ")), T.bad)
	end
	if #(state.Conflicts or {}) > 0 then
		local lines = {}
		for _, conflict in state.Conflicts do table.insert(lines, conflict.Name .. " / " .. tostring(conflict.With)) end
		note(S, card, 6, Core.Lang.Msg("Helper.Storage.Conflicts", table.concat(lines, ", ")), T.warn)
	end
	if state.Can.Configure and state.Can.Commands then
		local reset = textButton(S, card, { Name = "ResetAssistantSettings", Size = UDim2.new(1, 0, 0, 30), Text = S.L("Helper.Storage.Reset"), BackgroundColor3 = Color3.fromRGB(58, 44, 48), LayoutOrder = 7 })
		UI.Confirmable(reset, true, function()
			task.spawn(function()
				local ok, first, second = pcall(function() return Core.R.ConfigureAssistant:InvokeServer("Reset") end)
				if not S.alive() then return end
				Core.Toast(ok and (second or first) or S.L("Helper.Unavailable"), ok and first == true)
				if ok and first == true then S.Reload() end
			end)
		end)
	end
	return card
end

return Sections
