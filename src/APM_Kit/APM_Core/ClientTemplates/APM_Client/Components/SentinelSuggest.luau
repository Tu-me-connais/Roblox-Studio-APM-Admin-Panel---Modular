--[[
	SentinelSuggest : moteur d'autocomplétion de Sentinel (CLIENT). Fonctions PURES : aucune Instance, aucune connexion, aucun appel serveur ; ce qui est calculé à chaque frappe
	ne coûte qu'un balayage de quelques centaines de mots en mémoire.

	D'où viennent les suggestions (jamais inventees) :
	  · commandes : Words, envoyé par le SERVEUR (GetAssistant) = les mots tapables (noms, alias, phrases des sept langues, formes d'arrêt) des commandes que CE joueur a le
	    droit de lancer. Une commande interdite ou inexistante n'y figure donc jamais ;
	  · arguments : Slots de chaque commande (même source que la ligne d'usage et le catalogue), joueurs présents (Players), vocabulaire des sélecteurs et des on/off.
	Une suggestion n'est qu'un TEXTE proposé à l'utilisateur : rien n'est exécuté ici, le serveur résout la cible sans ambiguïté (pseudo exact, @identifiant) et revérifie
	tout à l'exécution. Les noms « réservés » (un joueur nommé all, on, me...) sont proposés sous la forme @identifiant pour ne jamais être pris pour un sélecteur.

	Le pliage de comparaison (minuscules, accents latins, cyrillique, pleine largeur) est la copie de Server/Core/Assistant/Unicode.Fold : les clés de Words arrivent déjà pliées,
	il faut plier ce que l'utilisateur tape de la même façon. La parité des deux fonctions est vérifiée par les tests.
]]
local Suggest = {}

Suggest.MAX_ITEMS = 6

----------------------------------------------------------------------------------------------------------
-- Pliage (copie fidèle de Unicode.Fold côté serveur)

local FOLD = {} -- [point de code] = texte de remplacement ("" = supprimé)

local function both(codepoint, replacement)
	FOLD[codepoint] = replacement
end
for codepoint = 0x80, 0x9F do both(codepoint, " ") end
for _, codepoint in { 0xA0, 0x1680, 0x202F, 0x205F, 0x3000, 0x2028, 0x2029 } do both(codepoint, " ") end
for codepoint = 0x2000, 0x200A do both(codepoint, " ") end
for codepoint = 0x200B, 0x200F do both(codepoint, "") end
for codepoint = 0x202A, 0x202E do both(codepoint, "") end
for codepoint = 0x2060, 0x2064 do both(codepoint, "") end
for codepoint = 0xFE00, 0xFE0F do both(codepoint, "") end
for _, codepoint in { 0xAD, 0x34F, 0xFEFF } do both(codepoint, "") end
for _, codepoint in { 0xAB, 0xBB, 0x201C, 0x201D, 0x201E, 0x201F, 0x300C, 0x300D, 0x300E, 0x300F, 0x301D, 0x301E, 0x301F, 0xFF02 } do both(codepoint, '"') end
for _, codepoint in { 0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x2BC } do both(codepoint, "'") end

local function foldRange(sourceStart, sourceEnd, delta)
	for codepoint = sourceStart, sourceEnd do FOLD[codepoint] = utf8.char(codepoint + delta) end
end
foldRange(0xC0, 0xD6, 32)
foldRange(0xD8, 0xDE, 32)
do
	local function accents(sources, targets)
		local index = 0
		for _, codepoint in utf8.codes(sources) do
			index += 1
			FOLD[codepoint] = string.sub(targets, index, index)
		end
	end
	accents("àáâãäåçèéêëìíîïñòóôõöùúûüýÿ", "aaaaaaceeeeiiiinooooouuuuyy")
	accents("ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÑÒÓÔÕÖÙÚÛÜÝ", "aaaaaaceeeeiiiinooooouuuuy")
	FOLD[0xF8], FOLD[0xD8] = "o", "o"
	FOLD[0xE6], FOLD[0xC6] = "ae", "ae"
	FOLD[0xDF], FOLD[0x1E9E] = "ss", "ss"
	FOLD[0xF0], FOLD[0xD0] = "d", "d"
	FOLD[0xFE], FOLD[0xDE] = "th", "th"
	local base = string.split("a a a a a a c c c c c c c c d d d d e e e e e e e e e e g g g g g g g g h h h h i i i i i i i i i i ij ij j j k k k l l l l l l l l l l n n n n n n n n n o o o o o o oe oe r r r r r r s s s s s s s s t t t t t t u u u u u u u u u u u u w w y y y z z z z z z s", " ")
	for index, letters in base do FOLD[0x100 + index - 1] = letters end
end
foldRange(0x410, 0x42F, 32)
foldRange(0x400, 0x40F, 80)
FOLD[0x451] = utf8.char(0x435)
FOLD[0x401] = utf8.char(0x435)
for codepoint = 0xFF01, 0xFF5E do
	if not FOLD[codepoint] then FOLD[codepoint] = string.lower(utf8.char(codepoint - 0xFEE0)) end
end
FOLD[0x2212] = "-"

local NON_ASCII = "[\128-\255]"

function Suggest.Fold(text)
	if type(text) ~= "string" then return "" end
	local folded
	if not string.find(text, NON_ASCII) then
		folded = string.lower(text)
	else
		if not utf8.len(text) then return "" end
		local pieces, count = {}, 0
		for _, codepoint in utf8.codes(string.lower(text)) do
			count += 1
			pieces[count] = FOLD[codepoint] or utf8.char(codepoint)
		end
		folded = table.concat(pieces)
	end
	folded = string.gsub(folded, "%s+", " ")
	folded = string.gsub(folded, "^ ", "")
	folded = string.gsub(folded, " $", "")
	return folded
end
local fold = Suggest.Fold

----------------------------------------------------------------------------------------------------------
-- Index

local function setOf(list)
	local set = {}
	for _, word in type(list) == "table" and list or {} do
		if type(word) == "string" then set[fold(word)] = true end
	end
	return set
end

local function wordsIn(key)
	return select(2, string.gsub(key, " ", " ")) + 1
end

--[[
	Construit l'index à partir de l'état serveur (api.Server). Renvoie { Commands, Phrases = { [clé] = { Command, Negate } }, List = { clés triées }, MaxWords,
	Local = { [mot] = genre }, LocalList, Reserved = { [mot] = true }, Vocabulary = { Me, All, On, Off, Reset (listes) }, AllowAll }.
]]
function Suggest.Build(state)
	state = type(state) == "table" and state or {}
	local commands = type(state.Commands) == "table" and state.Commands or {}
	local index = { Commands = commands, Phrases = {}, List = {}, MaxWords = 1, Local = {}, LocalList = {}, Reserved = {}, AllowAll = state.AllowAll == true }
	for key, slot in type(state.Words) == "table" and state.Words or {} do
		local command = type(slot) == "number" and commands[math.abs(slot)] or nil
		if type(key) == "string" and type(command) == "table" and command.Locked ~= true then
			index.Phrases[key] = { Command = command, Negate = slot < 0 }
			table.insert(index.List, key)
			index.MaxWords = math.max(index.MaxWords, wordsIn(key))
		end
	end
	table.sort(index.List)
	for word, kind in type(state.LocalWords) == "table" and state.LocalWords or {} do
		if type(word) == "string" and type(kind) == "string" then
			index.Local[fold(word)] = kind
			table.insert(index.LocalList, fold(word))
		end
	end
	table.sort(index.LocalList)
	local vocabulary = type(state.Vocabulary) == "table" and state.Vocabulary or {}
	index.Vocabulary = { Me = vocabulary.Me or { "me" }, All = vocabulary.All or { "all" }, On = vocabulary.On or { "on" }, Off = vocabulary.Off or { "off" }, Reset = vocabulary.Reset or { "reset" } }
	index.Me, index.All, index.On, index.Off, index.ResetSet = setOf(index.Vocabulary.Me), setOf(index.Vocabulary.All), setOf(index.Vocabulary.On), setOf(index.Vocabulary.Off), setOf(index.Vocabulary.Reset)
	index.Me["me"], index.All["all"], index.On["on"], index.Off["off"], index.ResetSet["reset"] = true, true, true, true, true
	for _, set in { index.Me, index.All, index.On, index.Off, index.ResetSet, index.Local } do
		for word in set do index.Reserved[word] = true end
	end
	return index
end

----------------------------------------------------------------------------------------------------------
-- Analyse du texte

-- Mots du texte avant le curseur : { Text, From, To, Open } (positions en octets) ; guillemets acceptés (Open = guillemet non refermé)
local function tokenize(before)
	local tokens = {}
	local position, length = 1, #before
	while position <= length do
		local char = string.sub(before, position, position)
		if string.find(char, "%s") then
			position += 1
		else
			local start = position
			if char == '"' or char == "'" then
				local close = string.find(before, char, position + 1, true)
				local finish = close or length
				table.insert(tokens, { Text = string.sub(before, start + 1, finish - (close and 1 or 0)), From = start, To = finish, Open = close == nil, Quoted = true })
				position = finish + 1
			else
				while position <= length and not string.find(string.sub(before, position, position), "%s") do position += 1 end
				table.insert(tokens, { Text = string.sub(before, start, position - 1), From = start, To = position - 1 })
			end
		end
	end
	return tokens
end

-- Ressemble à une durée (chiffres puis éventuellement une unité) : sert seulement à deviner le rôle d'un mot déjà tapé
local function looksLikeDuration(text)
	return string.match(fold(text), "^%d+[%.,]?%d*[%a\128-\255]*$") ~= nil
end

local function startsWith(text, prefix)
	return prefix == "" or string.sub(text, 1, #prefix) == prefix
end

local function item(kind, label, insert, extra)
	local value = { Kind = kind, Label = label, Insert = insert }
	for key, content in extra or {} do value[key] = content end
	return value
end

-- Suggestions de commandes : une par commande (le meilleur mot), les formes d'arrêt après les formes positives
local function commandItems(index, prefix, positiveOnly)
	local best = {}
	for _, key in index.List do
		if startsWith(key, prefix) then
			local entry = index.Phrases[key]
			if not (positiveOnly and entry.Negate) then
				local id = entry.Command.Name .. (entry.Negate and "#" or "")
				local score = (key == prefix and 0 or 1) + (#key - #prefix) / 100
				if key == entry.Command.Name then score -= 0.5 end -- le nom canonique passe avant ses alias
				local current = best[id]
				if not current or score < current.Score then best[id] = { Score = score, Key = key, Command = entry.Command, Negate = entry.Negate } end
			end
		end
	end
	local list = {}
	for _, entry in best do table.insert(list, entry) end
	table.sort(list, function(a, b)
		if a.Negate ~= b.Negate then return not a.Negate end
		if a.Score ~= b.Score then return a.Score < b.Score end
		return a.Key < b.Key
	end)
	local items = {}
	for _, entry in list do
		if #items >= Suggest.MAX_ITEMS then break end
		table.insert(items, item("Command", entry.Key, entry.Key, { Detail = entry.Command.Usage, Command = entry.Command.Name, Negate = entry.Negate, Space = #entry.Command.Slots > 0 }))
	end
	return items
end

local function localItems(index, prefix, limit)
	local items = {}
	if prefix == "" then return items end
	for _, word in index.LocalList do
		if #items >= limit then break end
		if startsWith(word, prefix) then
			table.insert(items, item("Local", word, word, { Detail = index.Local[word], Space = index.Local[word] == "Help" }))
		end
	end
	return items
end

-- Un mot de la liste, au plus un par fonction : le premier qui commence par `prefix` (le canonique d'abord)
local function firstWith(list, prefix, canonical)
	if startsWith(canonical, prefix) then return canonical end
	for _, word in list do
		if startsWith(fold(word), prefix) then return fold(word) end
	end
	return nil
end

local function targetItems(index, slot, partial, options, hasMore)
	local items = {}
	local wanted = fold(partial)
	local function add(value) if #items < Suggest.MAX_ITEMS then table.insert(items, value) end end
	local selfId = options.SelfId
	if slot.Off then
		local word = firstWith(index.Vocabulary.Off, wanted, "off")
		if word then add(item("Selector", word, word, { Detail = "off" })) end
	end
	if slot.Self ~= false then
		local word = firstWith(index.Vocabulary.Me, wanted, "me")
		if word then add(item("Selector", word, word, { Detail = "me", Space = hasMore })) end
	end
	if slot.All and index.AllowAll then
		local word = firstWith(index.Vocabulary.All, wanted, "all")
		if word then add(item("Selector", word, word, { Detail = "all", Space = hasMore })) end
	end
	-- joueurs : pseudo d'abord, puis nom affiché ; « @ » force la recherche par pseudo ou identifiant
	local query = string.gsub(wanted, "^@", "")
	local found = {}
	-- une commande qui n'agit que sur soi (speed sans cible possible) ne propose pas les autres joueurs
	for _, player in (not slot.MeOnly) and options.Players or {} do
		-- soi-même : jamais quand la commande l'interdit ; sans saisie, le sélecteur « me » suffit (le pseudo reste proposé dès qu'on tape ses premières lettres)
		if not (player.UserId == selfId and (slot.Self == false or wanted == "")) then
			local name, display = fold(player.Name), fold(player.DisplayName or player.Name)
			local tier
			if query == "" then tier = 1
			elseif startsWith(name, query) or string.sub(tostring(player.UserId), 1, #query) == query and string.match(query, "^%d+$") then tier = 1
			elseif startsWith(display, query) then tier = 2
			elseif string.find(name, query, 1, true) then tier = 3
			elseif string.find(display, query, 1, true) then tier = 4 end
			if tier then table.insert(found, { Tier = tier, Player = player, Name = name }) end
		end
	end
	table.sort(found, function(a, b)
		if a.Tier ~= b.Tier then return a.Tier < b.Tier end
		return a.Name < b.Name
	end)
	for _, entry in found do
		local player = entry.Player
		-- un pseudo qui est aussi un mot réservé (all, on, me...) ne serait pas compris comme un joueur : on propose @identifiant
		local reserved = index.Reserved[fold(player.Name)] == true
		local insert = reserved and ("@" .. tostring(player.UserId)) or player.Name
		local detail = (player.DisplayName and player.DisplayName ~= player.Name) and player.DisplayName or nil
		add(item("Player", player.Name, insert, { Detail = detail, Self = player.UserId == selfId, UserId = player.UserId, Space = hasMore }))
	end
	return items
end

local function stateItems(index, partial, hasMore)
	local items = {}
	local wanted = fold(partial)
	for _, pair in { { index.Vocabulary.On, "on" }, { index.Vocabulary.Off, "off" } } do
		local word = firstWith(pair[1], wanted, pair[2])
		if word then table.insert(items, item("State", word, word, { Detail = pair[2], Space = false })) end
	end
	return items
end

local function durationItems(slot, partial)
	local items = {}
	local minimum = tonumber(slot.MinMinutes) or 0
	local wanted = fold(partial)
	local units = {}
	if minimum < 1 / 60 + 1e-9 then table.insert(units, "s") end
	for _, unit in { "m", "h", "d" } do table.insert(units, unit) end
	local factor = { s = 1 / 60, m = 1, h = 60, d = 1440 }
	local function allowed(number, unit) return number * factor[unit] >= minimum end
	if wanted == "" then
		for _, example in { { 10, "s" }, { 5, "m" }, { 2, "h" }, { 1, "d" } } do
			if table.find(units, example[2]) and allowed(example[1], example[2]) and #items < Suggest.MAX_ITEMS then
				table.insert(items, item("Duration", example[1] .. example[2], example[1] .. example[2], { Space = true }))
			end
		end
	else
		local digits = string.match(wanted, "^(%d+)$")
		if digits then
			for _, unit in units do
				if allowed(tonumber(digits), unit) then table.insert(items, item("Duration", digits .. unit, digits .. unit, { Space = true })) end
			end
		end
	end
	return items
end

local function choiceItems(slot, partial, hasMore)
	local items = {}
	local wanted = fold(partial)
	for _, id in slot.Options or {} do
		if #items >= Suggest.MAX_ITEMS then break end
		local key = fold(id)
		if startsWith(key, wanted) or startsWith(string.match(key, "[^%.]+$") or key, wanted) then
			table.insert(items, item("Choice", id, id, { Space = hasMore }))
		end
	end
	return items
end

-- Emplacements d'arguments encore à remplir (indices dans command.Slots), selon ce qui est déjà tapé (`given` : mots complets après la commande)
local function openSlots(index, command, given)
	local slots = command.Slots or {}
	local count = #slots
	if count == 0 then return {} end
	local function isState(token) return index.On[fold(token.Text)] ~= nil or index.Off[fold(token.Text)] ~= nil end
	-- Fly, Noclip : cible et état, dans n'importe quel ordre
	if count == 2 and slots[1].Type == "target" and slots[2].Type == "state" then
		local hasState, hasTarget = false, false
		for _, token in given do
			if isState(token) then hasState = true else hasTarget = true end
		end
		local open = {}
		if not hasTarget then table.insert(open, 1) end
		if not hasState then table.insert(open, 2) end
		return open
	end
	-- speed [player|all] <n> : une seule valeur = le nombre ; deux = cible puis nombre
	if command.Kind == "Slider" then
		if #given == 0 then return { 1, 2 } end
		if #given == 1 then
			local word = fold(given[1].Text)
			if tonumber(word) ~= nil or index.ResetSet[word] then return {} end
			return { 2 }
		end
		return {}
	end
	-- cible puis durée / motif (Ban, Mute, Kick, Warn) : la durée se tape avant le motif, le motif prend tout le reste
	if command.Kind == "Target" then
		if #given == 0 then return { 1 } end
		local extras, hasDuration, hasText = {}, false, false
		for position = 2, count do
			if slots[position].Type == "duration" then hasDuration = true end
			if slots[position].Type == "text" then hasText = true end
		end
		if hasDuration or (count == 2 and hasText) then
			local usedDuration, usedText = false, false
			for position = 2, #given do
				if not usedDuration and not usedText and looksLikeDuration(given[position].Text) then usedDuration = true else usedText = true end
			end
			for position = 2, count do
				local slot = slots[position]
				if slot.Type == "duration" and not usedDuration and not usedText then table.insert(extras, position)
				elseif slot.Type == "text" then table.insert(extras, position) end
			end
			return extras
		end
	end
	-- cas général : positionnel (le dernier emplacement de texte reste ouvert)
	local position = #given + 1
	if position <= count then return { position } end
	if slots[count].Type == "text" then return { count } end
	return {}
end

-- Ligne d'aide : { Name, Parts = { { Text, Active } } }
local function hintFor(command, open)
	local active = {}
	for _, position in open do active[position] = true end
	local parts = {}
	for position, slot in command.Slots or {} do table.insert(parts, { Text = slot.Display, Active = active[position] == true }) end
	return { Name = command.Name, Parts = parts }
end

--[[
	Analyse le champ de saisie. text : contenu ; cursor : CursorPosition (nil = fin) ; options : { Players = { { UserId, Name, DisplayName } }, SelfId = UserId }.
	Renvoie { Stage = "none" | "command" | "argument", Items = { { Kind, Label, Insert, Detail?, Space?, Self?, ... } }, Range = { From, To }, Hint = { Name, Parts }? }.
	Appliquer une suggestion : Suggest.Apply(text, result.Range, item).
]]
function Suggest.Analyze(index, text, cursor, options)
	options = options or {}
	text = type(text) == "string" and text or ""
	local position = (type(cursor) == "number" and cursor >= 1 and cursor <= #text + 1) and cursor or #text + 1
	local before = string.sub(text, 1, position - 1)
	local tokens = tokenize(before)
	local result = { Stage = "none", Items = {}, Range = { From = position, To = position - 1 } }
	if #tokens == 0 then return result end
	local last = tokens[#tokens]
	if last.Open then return result end -- guillemet ouvert : texte libre
	local trailing = string.find(before, "%s$") ~= nil
	local complete = trailing and #tokens or #tokens - 1

	-- commande déjà reconnue parmi les mots complets (phrase la plus longue d'abord, comme Catalog.Find côté serveur)
	local matched, used
	for count = math.min(index.MaxWords, complete), 1, -1 do
		local words = table.create(count)
		for position = 1, count do words[position] = fold(tokens[position].Text) end
		local entry = index.Phrases[table.concat(words, " ")]
		if entry then matched, used = entry, count break end
	end

	-- help <commande> : la suite est un nom de commande
	if not matched and complete >= 1 and index.Local[fold(tokens[1].Text)] == "Help" then
		local rest = {}
		for position = 2, #tokens do table.insert(rest, tokens[position].Text) end
		local prefix = fold(table.concat(rest, " ")) .. (trailing and #rest > 0 and " " or "")
		result.Stage = "command"
		result.Items = commandItems(index, prefix, true)
		local from = tokens[2] and tokens[2].From or position
		result.Range = { From = from, To = position - 1 }
		return result
	end

	if not matched then
		local parts = {}
		for position = 1, #tokens do parts[position] = tokens[position].Text end
		local prefix = fold(table.concat(parts, " ")) .. (trailing and " " or "")
		result.Stage = "command"
		result.Items = commandItems(index, prefix, false)
		if #tokens == 1 and not trailing then
			for _, localItem in localItems(index, prefix, math.max(0, Suggest.MAX_ITEMS - #result.Items)) do table.insert(result.Items, localItem) end
		end
		result.Range = { From = tokens[1].From, To = position - 1 }
		return result
	end

	-- arguments de la commande
	local command = matched.Command
	local given, partialToken = {}, nil
	for position = used + 1, #tokens do
		if position == #tokens and not trailing then partialToken = tokens[position] else table.insert(given, tokens[position]) end
	end
	if partialToken and partialToken.Quoted then return result end
	local partial = partialToken and partialToken.Text or ""
	result.Stage = "argument"
	result.Range = partialToken and { From = partialToken.From, To = position - 1 } or { From = position, To = position - 1 }
	local open = openSlots(index, command, given)
	result.Hint = hintFor(command, open)
	local slots = command.Slots or {}
	for _, slotIndex in open do
		local slot = slots[slotIndex]
		-- un autre emplacement attend encore quelque chose après celui-ci ?
		local hasMore = slotIndex < #slots
		local found
		if slot.Type == "target" then found = targetItems(index, slot, partial, options, hasMore)
		elseif slot.Type == "state" then found = stateItems(index, partial, hasMore)
		elseif slot.Type == "duration" then found = durationItems(slot, partial)
		elseif slot.Type == "choice" then found = choiceItems(slot, partial, hasMore)
		elseif slot.Type == "number" and slot.Reset then
			found = {}
			local word = partial ~= "" and firstWith(index.Vocabulary.Reset, fold(partial), "reset") or nil
			if word then table.insert(found, item("Selector", word, word, { Detail = "reset" })) end
		end
		for _, value in found or {} do
			if #result.Items < Suggest.MAX_ITEMS then table.insert(result.Items, value) end
		end
	end
	return result
end

-- Remplace la partie proposée du texte par la suggestion choisie. Renvoie le nouveau texte et la position du curseur (CursorPosition). Rien n'est envoyé.
function Suggest.Apply(text, range, chosen)
	text = type(text) == "string" and text or ""
	local before = string.sub(text, 1, range.From - 1)
	local after = string.sub(text, range.To + 1)
	local insert = chosen.Insert
	local cursor
	if chosen.Space and string.sub(after, 1, 1) ~= " " then
		insert = insert .. " "
		cursor = #before + #insert + 1
	elseif chosen.Space then
		cursor = #before + #insert + 2
	else
		cursor = #before + #insert + 1
	end
	return before .. insert .. after, cursor
end

--[[
	Texte que le catalogue insère dans le champ quand on touche une commande : son nom (ou alias), suivi d'un espace si elle attend des arguments.
	Rien n'est exécuté : l'utilisateur complète puis valide lui-même.
]]
function Suggest.CommandText(command)
	return command.Name .. ((command.Slots and #command.Slots > 0) and " " or "")
end

return Suggest
