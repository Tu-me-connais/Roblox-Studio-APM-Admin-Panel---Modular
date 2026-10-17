--[[
	CommandLocalization : reconnaissance MULTILINGUE des commandes de Sentinel. Fonctions pures, aucun service externe, aucune IA, aucune traduction en ligne.

	PRINCIPE : chaque langue est un ModuleScript enfant (fr, en, es, pt, de, ru, zh) qui ne contient QUE des mots. Toutes les formulations d'une commande
	(« voler », « volar », « fliegen », « voar », « летать », « 飞行 », « fly »...) mènent à UN SEUL identifiant canonique : le nom du module (« Fly »).
	Le reste de Sentinel (cible, validation, permissions, confirmation, Dispatcher) ne voit jamais la langue : il reçoit l'action canonique.
	La langue de saisie est donc totalement indépendante de la langue de l'interface (qui ne sert qu'à AFFICHER les réponses).

	Ajouter une langue (la huitième...) : créer un ModuleScript enfant dont le nom est le code de langue, même forme que fr/en. Rien d'autre à modifier.

	Forme d'un module de langue :
	  Code, Name, Order                       identité
	  Commands = { Fly = { "voler", ... } }    alias de commande (clé = nom du module de l'APM), un à trois mots
	  Off      = { Fly = { "..." } }           alias « arrêt » (unfly...), seulement pour les commandes annulables (UNDOABLE)
	  OffPrefixes, Joiner                      préfixes d'arrêt (« stop », « arrêter de »...) : « préfixe + alias » est généré pour chaque commande annulable ;
	                                           Joiner = "" pour les langues sans espaces (chinois)
	  Selectors = { Me = {...}, All = {...} }  « moi », « tous » (un seul mot)
	  Booleans = { On = {...}, Off = {...} }, Reset, Polite, Units = { Seconds, Minutes, Hours, Days }, Local = { Help, List, Clear }, Choices = { give, take, set, once, keep }

	Règle de collision (déterministe, jamais arbitraire) : une même phrase qui désignerait deux actions différentes, ou une commande et une commande locale
	(aide...), est ÉCARTÉE pour toutes les langues et signalée dans Report().Collisions. Une phrase partagée par deux langues vers la MÊME action
	(« radar », « stats ») n'est pas une collision.
	Ce module ne donne AUCUN droit : il ne fait que comprendre. Le serveur vérifie ensuite grade, matrice, hiérarchie et confirmation, comme pour une commande anglaise.
]]
local Unicode = require(script.Parent.Unicode)
local fold = Unicode.Fold

local Engine = {}
Engine.__index = Engine

Engine.MAX_WORDS = 3 -- mots d'un alias de commande
Engine.MAX_CHARS = 32 -- caractères d'un alias
-- Commandes qui ont une forme « arrêt » (unfly...). Le Catalogue confirme au moment de la construction que le module sait vraiment l'annuler.
Engine.UNDOABLE = { Fly = true, Noclip = true, ESP = true, Spectator = true, Invisible = true, Godmode = true, Freeze = true, Mute = true }
Engine.CHOICES = { give = true, take = true, set = true, once = true, keep = true }
local UNIT_FACTOR = { Seconds = 1 / 60, Minutes = 1, Hours = 60, Days = 1440 } -- facteur en MINUTES

local function countWords(key)
	return select(2, string.gsub(key, " ", " ")) + 1
end

function Engine:_problem(code, text)
	table.insert(self.Problems, string.format("[%s] %s", code, text))
end

-- Mot ou alias -> clé de comparaison + forme à afficher ; nil si invalide. multiword : plusieurs mots permis. quiet : pas de diagnostic.
function Engine:_phrase(code, where, raw, multiword, quiet)
	local function reject(reason)
		if not quiet then self:_problem(code, string.format("%s : %s (%s)", where, reason, tostring(raw))) end
		return nil
	end
	if type(raw) ~= "string" or raw == "" or string.find(raw, "%c") then return reject("texte invalide") end
	local display = Unicode.Sanitize(raw)
	if not display then return reject("UTF-8 invalide") end
	local key = fold(display)
	if key == "" or utf8.len(key) > Engine.MAX_CHARS or string.find(key, '"', 1, true) then return reject("longueur ou guillemet") end
	local words = countWords(key)
	if words > Engine.MAX_WORDS or (words > 1 and not multiword) then return reject("trop de mots") end
	return key, display
end

function Engine:_claim(group, key, value, code)
	local bucket = self.Claims[group]
	if not bucket then
		bucket = {}
		self.Claims[group] = bucket
	end
	local slot = bucket[key]
	if not slot then
		slot = { Values = {}, Languages = {} }
		bucket[key] = slot
	end
	slot.Values[value] = true
	slot.Languages[code] = true
end

function Engine:_loadLanguage(child)
	local code = string.lower(child.Name)
	local loaded, definition = pcall(require, child)
	if not loaded or type(definition) ~= "table" then
		self:_problem(code, "module de langue illisible : " .. tostring(definition))
		return
	end
	if not string.match(code, "^[a-z][a-z%-]?[a-z%-]?[a-z%-]?[a-z%-]?[a-z%-]?[a-z%-]?[a-z%-]?$") or self.Languages[code] then
		self:_problem(code, "code de langue invalide ou en double")
		return
	end
	if definition.Code ~= nil and string.lower(tostring(definition.Code)) ~= code then
		self:_problem(code, "Code différent du nom du module")
		return
	end
	local language = { Code = code, Name = type(definition.Name) == "string" and definition.Name or code, Order = tonumber(definition.Order) or 100,
		Explicit = 0, Generated = 0, OffPrefixes = {} }
	self.Languages[code] = language

	local function commands(list, negate)
		if list == nil then return end
		if type(list) ~= "table" then self:_problem(code, "Commands / Off doit être une table") return end
		for moduleName, aliases in list do
			if type(moduleName) ~= "string" or type(aliases) ~= "table" then
				self:_problem(code, "entrée de commande invalide")
			elseif negate and not Engine.UNDOABLE[moduleName] then
				self:_problem(code, moduleName .. " n'a pas de forme d'arrêt")
			else
				for _, raw in aliases do
					local key, display = self:_phrase(code, moduleName, raw, true)
					if key then
						table.insert(self.Records, { Key = key, Display = display, Module = moduleName, Negate = negate, Language = code, Source = "Dictionary" })
						language.Explicit += 1
					end
				end
			end
		end
	end
	commands(definition.Commands, false)
	commands(definition.Off, true)

	-- formes d'arrêt générées : « préfixe + alias » pour chaque commande annulable (ignoré au-delà de trois mots)
	if type(definition.OffPrefixes) == "table" and type(definition.Commands) == "table" then
		local joiner = type(definition.Joiner) == "string" and definition.Joiner or " "
		for _, prefix in definition.OffPrefixes do
			if self:_phrase(code, "OffPrefixes", prefix, true) then table.insert(language.OffPrefixes, Unicode.Sanitize(prefix)) end
		end
		for moduleName in Engine.UNDOABLE do
			local aliases = definition.Commands[moduleName]
			if type(aliases) == "table" then
				for _, positive in aliases do
					for _, prefix in language.OffPrefixes do
						local key, display = self:_phrase(code, moduleName, prefix .. joiner .. tostring(positive), true, true)
						if key then
							table.insert(self.Records, { Key = key, Display = display, Module = moduleName, Negate = true, Language = code, Source = "Generated" })
							language.Generated += 1
						end
					end
				end
			end
		end
	end

	-- vocabulaire des arguments
	local function words(group, value, list)
		if list == nil then return end
		if type(list) ~= "table" then self:_problem(code, group .. " doit être une table") return end
		for _, raw in list do
			local key = self:_phrase(code, group .. "/" .. value, raw, false)
			if key then self:_claim(group, key, value, code) end
		end
	end
	local selectors, booleans = definition.Selectors, definition.Booleans
	if type(selectors) == "table" then
		words("Arg", "Me", selectors.Me)
		words("Arg", "All", selectors.All)
	end
	if type(booleans) == "table" then
		words("Arg", "True", booleans.On)
		words("Arg", "False", booleans.Off)
	end
	words("Arg", "Reset", definition.Reset)
	words("Polite", "Polite", definition.Polite)
	if type(definition.Units) == "table" then
		for unit in UNIT_FACTOR do words("Unit", unit, definition.Units[unit]) end
	end
	if type(definition.Local) == "table" then
		for _, kind in { "Help", "List", "Clear" } do words("Local", kind, definition.Local[kind]) end
	end
	if type(definition.Choices) == "table" then
		for choice in Engine.CHOICES do words("Choice", choice, definition.Choices[choice]) end
	end
end

local function listOf(set)
	local list = {}
	for value in set do table.insert(list, value) end
	table.sort(list)
	return list
end

-- Résout les collisions et construit le vocabulaire utilisable
function Engine:_finalize()
	local lexicon = self.Lexicon
	-- 1. vocabulaire d'arguments : un mot, une seule fonction. Sinon écarté partout.
	for group, bucket in self.Claims do
		for key, slot in bucket do
			local values = listOf(slot.Values)
			if #values > 1 then
				table.insert(self.Collisions, { Kind = group, Key = key, With = values, Languages = listOf(slot.Languages), Resolution = "Excluded" })
			elseif group == "Arg" then
				lexicon[values[1] == "True" and "True" or values[1] == "False" and "False" or values[1]][key] = slot.Languages
			elseif group == "Unit" then
				lexicon.Units[key] = UNIT_FACTOR[values[1]]
			elseif group == "Local" then
				lexicon.Local[key] = values[1]
			elseif group == "Choice" then
				lexicon.Choices[key] = values[1]
			else
				lexicon.Polite[key] = true
			end
		end
	end
	-- 2. phrases de commande : une phrase = une action (module + sens). Plusieurs actions, ou une commande locale / formule de politesse : écartée.
	local groups = {}
	for _, record in self.Records do
		local slot = groups[record.Key]
		if not slot then
			slot = { Actions = {}, Languages = {} }
			groups[record.Key] = slot
		end
		slot.Actions[record.Module .. (record.Negate and "#off" or "")] = true
		slot.Languages[record.Language] = true
	end
	for key, slot in groups do
		local actions = listOf(slot.Actions)
		local reason
		if #actions > 1 then
			reason = "Alias"
		elseif lexicon.Local[key] then
			reason, actions = "LocalCommand", { actions[1], "Local:" .. lexicon.Local[key] }
		elseif lexicon.Polite[key] then
			reason, actions = "Polite", { actions[1], "Polite" }
		end
		if reason then
			self.Blocked[key] = true
			table.insert(self.Collisions, { Kind = reason, Key = key, With = actions, Languages = listOf(slot.Languages), Resolution = "Excluded" })
		end
	end
	table.sort(self.Collisions, function(a, b)
		if a.Kind ~= b.Kind then return a.Kind < b.Kind end
		return a.Key < b.Key
	end)
end

function Engine.new(container)
	local self = setmetatable({}, Engine)
	self.Languages, self.Problems, self.Collisions = {}, {}, {}
	self.Lexicon = { Me = {}, All = {}, True = {}, False = {}, Reset = {}, Polite = {}, Units = {}, Local = {}, Choices = {} }
	self.Records, self.Blocked, self.Claims = {}, {}, {}
	local children = {}
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") then table.insert(children, child) end
	end
	table.sort(children, function(a, b) return a.Name < b.Name end)
	for _, child in children do self:_loadLanguage(child) end
	self:_finalize()
	return self
end

----------------------------------------------------------------------------------------------------------
-- Vocabulaire des arguments (clés déjà pliées par Unicode.Fold)

function Engine:Normalize(text) return fold(text) end
function Engine:IsMe(key) return self.Lexicon.Me[key] ~= nil end
function Engine:IsAll(key) return self.Lexicon.All[key] ~= nil end
function Engine:IsReset(key) return self.Lexicon.Reset[key] ~= nil end
function Engine:IsPolite(key) return self.Lexicon.Polite[key] == true end
function Engine:Unit(key) return self.Lexicon.Units[key] end -- facteur en minutes
function Engine:LocalCommand(key) return self.Lexicon.Local[key] end -- "Help" | "List" | "Clear"
function Engine:Choice(key) return self.Lexicon.Choices[key] end -- identifiant de choix canonique
-- true / false / nil
function Engine:Boolean(key)
	if self.Lexicon.True[key] then return true end
	if self.Lexicon.False[key] then return false end
	return nil
end
-- Mot réservé (sélecteur, booléen, réinitialisation, commande locale) : "Me" | "All" | "True" | "False" | "Reset" | "Local" | nil
function Engine:Reserved(key)
	for _, name in { "Me", "All", "True", "False", "Reset" } do
		if self.Lexicon[name][key] then return name end
	end
	if self.Lexicon.Local[key] then return "Local" end
	return nil
end

----------------------------------------------------------------------------------------------------------
-- Index des phrases de commande pour un catalogue donné

--[[
	modules : { [nom de module] = { Undoable = bool } } = commandes réellement présentes (une commande désactivée dans Sentinel n'a aucune phrase).
	Renvoie { Phrases = { [clé] = { Module, Negate, Languages = { [code] = true }, Display = { [code] = texte }, Generated = bool } }, MaxWords = n }
]]
function Engine:Compile(modules)
	local index, maxWords = {}, 1
	for _, record in self.Records do
		local info = modules[record.Module]
		if info and not self.Blocked[record.Key] and (not record.Negate or info.Undoable) then
			local slot = index[record.Key]
			if not slot then
				slot = { Module = record.Module, Negate = record.Negate, Languages = {}, Display = {}, Generated = true }
				index[record.Key] = slot
			end
			slot.Languages[record.Language] = true
			if record.Source == "Dictionary" then slot.Generated = false end
			if slot.Display[record.Language] == nil or record.Source == "Dictionary" then slot.Display[record.Language] = record.Display end
			maxWords = math.max(maxWords, countWords(record.Key))
		end
	end
	return { Phrases = index, MaxWords = maxWords }
end

-- Langues dans l'ordre d'affichage : { { Code, Name, Order } }
function Engine:LanguageList()
	local list = {}
	for _, language in self.Languages do table.insert(list, { Code = language.Code, Name = language.Name, Order = language.Order }) end
	table.sort(list, function(a, b)
		if a.Order ~= b.Order then return a.Order < b.Order end
		return a.Code < b.Code
	end)
	return list
end

--[[
	Alias visibles par langue, pour Sentinel Helper : { [code] = { { Module, On = { ... }, Off = { ... } } } }, à partir d'un index Compile.
	Les formes d'arrêt générées (préfixe + alias) ne sont pas répétées : la liste des préfixes est donnée à part (OffPrefixes).
]]
function Engine:Describe(compiled)
	local result = {}
	for key, slot in compiled.Phrases do
		for code, display in slot.Display do
			if not (slot.Generated and slot.Negate) then
				result[code] = result[code] or {}
				local byModule = result[code]
				byModule[slot.Module] = byModule[slot.Module] or { Module = slot.Module, On = {}, Off = {} }
				table.insert(slot.Negate and byModule[slot.Module].Off or byModule[slot.Module].On, display)
			end
		end
	end
	local output = {}
	for code, byModule in result do
		local list = {}
		for _, entry in byModule do
			table.sort(entry.On)
			table.sort(entry.Off)
			table.insert(list, entry)
		end
		table.sort(list, function(a, b) return a.Module < b.Module end)
		output[code] = list
	end
	return output
end

function Engine:OffPrefixes(code)
	local language = self.Languages[code]
	return language and table.clone(language.OffPrefixes) or {}
end

-- Bilan de contrôle : langues, nombres d'alias, collisions, diagnostics de chargement
function Engine:Report()
	local languages = {}
	for _, entry in self:LanguageList() do
		local language = self.Languages[entry.Code]
		local keys, commands = {}, {}
		for _, record in self.Records do
			if record.Language == entry.Code and not self.Blocked[record.Key] then
				keys[record.Key] = true
				commands[record.Module] = true
			end
		end
		local phrases, commandCount = 0, 0
		for _ in keys do phrases += 1 end
		for _ in commands do commandCount += 1 end
		table.insert(languages, { Code = entry.Code, Name = entry.Name, Phrases = phrases, Explicit = language.Explicit, Generated = language.Generated, Commands = commandCount })
	end
	local blocked = 0
	for _ in self.Blocked do blocked += 1 end
	return { Languages = languages, Collisions = self.Collisions, Problems = self.Problems, Blocked = blocked }
end

local Localization = Engine.new(script)
Localization.New = Engine.new -- Engine.new(conteneur) : autre jeu de langues (tests, huitième langue d'essai)
Localization.Class = Engine
return Localization
