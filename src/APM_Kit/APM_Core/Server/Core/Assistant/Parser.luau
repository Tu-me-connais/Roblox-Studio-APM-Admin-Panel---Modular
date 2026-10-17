--[[
	Parser : analyse LOCALE des commandes de Sentinel (aucune IA, aucun service externe). Fonctions pures, testables sans joueur réel :
	  texte -> mots (guillemets acceptés) · mots -> cible (me, all, pseudo, identifiant, nom partiel NON ambigu) · nombres, durées,
	  booléens · suggestions d'orthographe. Rien ici ne donne un droit : ce module ne fait que comprendre, le serveur vérifie ensuite.

	Multilingue : le vocabulaire (sélecteurs « moi / tous », « on / off », unités de durée, politesse...) vient de CommandLocalization, qui réunit les
	sept langues de l'APM ; il est valable quelle que soit la langue de l'interface. Les mots historiques (anglais, français) sont toujours reconnus,
	même si le dictionnaire ne se chargeait pas. La comparaison passe par Unicode.Fold : majuscules (latin, cyrillique), accents latins et formes
	pleine largeur sont indifférents. Les pseudos ne sont jamais modifiés : seule la CLÉ de comparaison est pliée.
]]
local Unicode = require(script.Parent.Unicode)

local loaded, Lexicon = pcall(function()
	return require(script.Parent.CommandLocalization)
end)
if not loaded then
	warn("[APM] Sentinel : dictionnaires multilingues indisponibles, seuls l'anglais et le français historiques sont compris (" .. tostring(Lexicon) .. ")")
	Lexicon = nil
end

local Parser = {}
Parser.Lexicon = Lexicon

Parser.MAX_LENGTH = 200 -- caractères d'une commande
Parser.MAX_TOKENS = 24

-- minuscules, sans accents latins, cyrillique et pleine largeur pliés, espaces réduits : sert à comparer, jamais à afficher
function Parser.Normalize(text)
	if type(text) ~= "string" then return "" end
	return Unicode.Fold(text)
end

-- Texte valide pour une commande ? Renvoie la version nettoyée (espaces typographiques -> espace, caractères invisibles et de contrôle retirés,
-- guillemets typographiques -> ") ou nil + code. Longueur en CARACTÈRES, pas en octets.
function Parser.Clean(text)
	if type(text) ~= "string" then return nil, "Invalid" end
	if #text > Parser.MAX_LENGTH * 4 or not utf8.len(text) then return nil, "Invalid" end
	text = Unicode.Sanitize(text)
	if not text then return nil, "Invalid" end
	if utf8.len(text) > Parser.MAX_LENGTH then return nil, "TooLong" end
	text = string.gsub(text, "[%c]", " ")
	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")
	if text == "" then return nil, "Empty" end
	return text
end

-- Mots d'une commande ; "guillemets doubles" ou 'simples' regroupent un texte contenant des espaces
function Parser.Tokenize(text)
	local tokens, position, length = {}, 1, #text
	while position <= length do
		local char = string.sub(text, position, position)
		if string.find(char, "%s") then
			position += 1
		else
			if char == '"' or char == "'" then
				local close = string.find(text, char, position + 1, true)
				if not close then return nil, "Quote" end
				table.insert(tokens, string.sub(text, position + 1, close - 1))
				position = close + 1
			else
				local finish = position
				while finish <= length and not string.find(string.sub(text, finish, finish), "%s") do finish += 1 end
				table.insert(tokens, string.sub(text, position, finish - 1))
				position = finish
			end
			if #tokens > Parser.MAX_TOKENS then return nil, "TooMany" end
		end
	end
	return tokens
end

-- Politesse sans effet (« please freeze bob », « stp freeze bob », « por favor volar ») : ignorée en tête de commande
local POLITE = { please = true, pls = true, plz = true, stp = true, svp = true, sil = true, te = true, plait = true }
local function isPolite(word)
	return POLITE[word] == true or (Lexicon ~= nil and Lexicon:IsPolite(word))
end
function Parser.StripPoliteness(tokens)
	local start = 1
	while start < #tokens do
		local word = string.gsub(Parser.Normalize(tokens[start]), "'", "")
		if isPolite(word) then start += 1 else break end
	end
	if start == 1 then return tokens end
	return table.move(tokens, start, #tokens, 1, {})
end

-- Distance d'édition (bornée) entre deux mots, par CARACTÈRES : suggestions d'orthographe
local function symbols(text)
	local list = {}
	if Unicode.IsAscii(text) then
		for index = 1, #text do list[index] = string.byte(text, index) end
	else
		local ok = pcall(function()
			for _, codepoint in utf8.codes(text) do table.insert(list, codepoint) end
		end)
		if not ok then return nil end
	end
	return list
end

function Parser.Distance(a, b, limit)
	limit = limit or 3
	if #a > 96 or #b > 96 then return limit + 1 end
	local first, second = symbols(a), symbols(b)
	if not first or not second then return limit + 1 end
	local la, lb = #first, #second
	if math.abs(la - lb) > limit then return limit + 1 end
	local previous, current = {}, {}
	for j = 0, lb do previous[j] = j end
	for i = 1, la do
		current[0] = i
		local best = current[0]
		for j = 1, lb do
			local cost = first[i] == second[j] and 0 or 1
			current[j] = math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
			best = math.min(best, current[j])
		end
		if best > limit then return limit + 1 end
		previous, current = current, previous
	end
	return previous[lb]
end

-- Noms proches de `word` (préfixe ou faute de frappe), les plus proches d'abord
function Parser.Suggest(word, names, maximum)
	word = Parser.Normalize(word)
	if word == "" then return {} end
	local length = utf8.len(word) or #word
	local limit = length <= 4 and 1 or 2
	local found = {}
	for _, name in names do
		local distance = Parser.Distance(word, name, limit)
		if distance <= limit then
			table.insert(found, { Name = name, Score = distance })
		elseif length >= 2 and string.sub(name, 1, #word) == word then
			table.insert(found, { Name = name, Score = 1.5 })
		end
	end
	table.sort(found, function(a, b)
		if a.Score ~= b.Score then return a.Score < b.Score end
		return a.Name < b.Name
	end)
	local result = {}
	for index = 1, math.min(#found, maximum or 3) do result[index] = found[index].Name end
	return result
end

-- Nombre simple (pas d'hexadécimal ni d'exposant) ; nil sinon. Chiffres pleine largeur acceptés ; virgule décimale acceptée avec 1 ou 2 décimales
-- (« 1,5 » = 1.5) ; « 1,000 » est refusé : ambigu entre séparateur de milliers et décimale, on ne devine pas.
function Parser.Number(token)
	if type(token) ~= "string" or #token > 64 then return nil end
	token = Unicode.Fold(token)
	if #token > 16 then return nil end
	local whole, fraction = string.match(token, "^(%-?%d+),(%d%d?)$")
	if whole then token = whole .. "." .. fraction end
	if not (string.match(token, "^%-?%d+%.?%d*$") or string.match(token, "^%-?%.%d+$")) then return nil end
	local value = tonumber(token)
	if value == nil or value ~= value or math.abs(value) == math.huge then return nil end
	return value
end

-- Durée en minutes : 5, 5m, 90min, 2h, 1d (j = jours), 30s (secondes : 0,5 minute), 5分钟, 2小时, 3 Tage... ; nil sinon
-- Le serveur ne fait que COMPRENDRE la durée ; chaque commande refuse ensuite celle qu'elle ne sait pas honorer (Catalog : MinMinutes).
local LEGACY_UNITS = { s = 1 / 60, sec = 1 / 60, secs = 1 / 60, m = 1, min = 1, mn = 1, h = 60, d = 1440, j = 1440 }
function Parser.Duration(token)
	if type(token) ~= "string" or #token > 64 then return nil end
	local key = Unicode.Fold(token)
	-- virgule décimale (1,5m, 0,5) d'abord : sinon « 0,5 » serait lu comme le nombre 0 suivi d'une unité inconnue ; « 1,500 » reste refusé (milliers ou décimale : on ne devine pas)
	local number, unit
	local whole, fraction, rest = string.match(key, "^(%d+),(%d%d?)(%D*)$")
	if whole then
		number, unit = whole .. "." .. fraction, rest
	else
		number, unit = string.match(key, "^(%d+%.?%d*)(.-)$")
	end
	if not number then return nil end
	number = tonumber(number)
	if not number then return nil end
	local factor = unit == "" and 1 or LEGACY_UNITS[unit] or (Lexicon ~= nil and Lexicon:Unit(unit)) or nil
	if not factor then return nil end
	return number * factor
end

-- Une expression qui COMMENCE comme une durée (chiffres puis lettres : 1w, 5x, 2nd) sans être lisible par Duration : Sentinel ne la prend jamais pour un motif
-- (une durée perdue dans le motif d'un bannissement le rendrait définitif). Les nombres seuls (5, 0,5) sont des durées valides, donc exclus ici.
function Parser.LooksLikeDuration(token)
	if type(token) ~= "string" or #token > 64 then return false end
	local key = Unicode.Fold(token)
	if Parser.Duration(token) ~= nil then return false end
	return string.match(key, "^%d+[%.,]?%d*[%a\128-\255]+$") ~= nil
end

local TRUE_WORDS = { on = true, ["true"] = true, ["1"] = true, yes = true, oui = true, enable = true, enabled = true, activer = true, active = true }
local FALSE_WORDS = { off = true, ["false"] = true, ["0"] = true, no = true, non = true, disable = true, disabled = true, desactiver = true, desactive = true }
-- true / false / nil, dans les sept langues (on, off, oui, non, sí, nao, ja, nein, да, нет, 开, 关...)
function Parser.Boolean(token)
	local word = Parser.Normalize(token)
	if TRUE_WORDS[word] then return true end
	if FALSE_WORDS[word] then return false end
	if Lexicon ~= nil then return Lexicon:Boolean(word) end
	return nil
end

-- Mots de réinitialisation (speed reset, vitesse défaut, 速度 重置...)
local RESET_WORDS = { reset = true, default = true, defaut = true }
function Parser.IsReset(token)
	local word = Parser.Normalize(token)
	return RESET_WORDS[word] == true or (Lexicon ~= nil and Lexicon:IsReset(word))
end

-- Sélecteurs : « moi » et « tous » dans les sept langues. Les tables ci-dessous sont l'ancien socle (EN/FR) ; ME_WORDS[mot] / ALL_WORDS[mot]
-- consultent aussi le dictionnaire, pour que l'ancien code (Parser.ME_WORDS[Parser.Normalize(x)]) comprenne toutes les langues.
local BASE_ME = { me = true, moi = true, self = true, ["@me"] = true, je = true }
local BASE_ALL = { all = true, everyone = true, everybody = true, tous = true, tout = true, ["*"] = true, ["@all"] = true }
function Parser.IsMe(word)
	return BASE_ME[word] == true or (Lexicon ~= nil and Lexicon:IsMe(word))
end
function Parser.IsAll(word)
	return BASE_ALL[word] == true or (Lexicon ~= nil and Lexicon:IsAll(word))
end
local ME_WORDS = setmetatable({}, { __index = function(_, word) return Parser.IsMe(word) or nil end })
local ALL_WORDS = setmetatable({}, { __index = function(_, word) return Parser.IsAll(word) or nil end })
Parser.ME_WORDS, Parser.ALL_WORDS = ME_WORDS, ALL_WORDS

-- Commande locale de l'interface (aide, liste, effacer) : "Help" | "List" | "Clear" | nil, dans les sept langues
local BASE_LOCAL = { help = "Help", aide = "Help", list = "List", commands = "List", commandes = "List", clear = "Clear", cls = "Clear", effacer = "Clear" }
function Parser.LocalCommand(word)
	return BASE_LOCAL[word] or (Lexicon ~= nil and Lexicon:LocalCommand(word)) or nil
end

-- Mot de choix localisé (give / take / set / once / keep) -> identifiant canonique, ou nil
function Parser.Choice(word)
	return Lexicon ~= nil and Lexicon:Choice(word) or nil
end

-- Joueurs dont le pseudo ou le nom affiché est EXACTEMENT ce mot (comparaison pliée) : sert à repérer un mot réservé (sélecteur, on/off...) qui
-- serait aussi le nom d'un joueur. Dans ce cas Sentinel ne devine jamais : il demande de préciser (@identifiant).
function Parser.Clashes(word, players)
	local found = {}
	if word == "" then return found end
	for _, candidate in players do
		if Parser.Normalize(candidate.Name) == word or Parser.Normalize(candidate.DisplayName or candidate.Name) == word then
			table.insert(found, candidate)
		end
	end
	return found
end

--[[
	Résout une cible parmi `players` : { { UserId, Name, DisplayName }, ... }.
	Ordre : me / all (dans toutes les langues) · identifiant exact · pseudo exact · nom affiché exact · début de pseudo · début de nom affiché · fragment.
	Premier niveau qui trouve quelqu'un : un seul joueur = cible ; plusieurs = AMBIGU (on demande de préciser, on ne tire jamais au hasard).
	Mot réservé = pseudo d'un joueur présent (un joueur nommé « all », « Yo », « Ich »...) : AMBIGU aussi, jamais le sélecteur par défaut.
	Pour viser ce joueur : @identifiant (ou @pseudo pour un mot qui n'est pas @me / @all). Pour viser le sélecteur : un synonyme (all, @all, @me...).
	Renvoie { Kind = "Me" | "All" | "Single" | "Ambiguous" | "None", Player = joueur, Matches = { pseudos (5 au plus) }, Count = n }
]]
function Parser.ResolveTarget(query, players)
	local raw = type(query) == "string" and query or ""
	local word = Parser.Normalize(raw)
	if word == "" or (utf8.len(word) or #word) > 60 then return { Kind = "None", Matches = {}, Count = 0 } end
	local selector = Parser.IsMe(word) and "Me" or (Parser.IsAll(word) and "All" or nil)
	if selector then
		local clashes = Parser.Clashes(word, players)
		if #clashes == 0 then return { Kind = selector } end
		table.sort(clashes, function(a, b) return a.Name < b.Name end)
		local matches = {}
		for index = 1, math.min(#clashes, 4) do matches[index] = string.format("%s (@%d)", clashes[index].Name, clashes[index].UserId) end
		table.insert(matches, selector == "Me" and "@me" or "@all")
		return { Kind = "Ambiguous", Matches = matches, Count = #clashes + 1, Reserved = selector }
	end
	local idText = string.match(word, "^@?(%d+)$")
	if idText and #idText >= 3 and #idText <= 16 then
		local id = tonumber(idText)
		for _, candidate in players do
			if candidate.UserId == id then return { Kind = "Single", Player = candidate, Matches = { candidate.Name }, Count = 1 } end
		end
	end
	word = string.gsub(word, "^@", "")
	local names, displays = {}, {}
	for index, candidate in players do
		names[index] = Parser.Normalize(candidate.Name)
		displays[index] = Parser.Normalize(candidate.DisplayName or candidate.Name)
	end
	local tiers = {
		function(index) return names[index] == word end,
		function(index) return displays[index] == word end,
		function(index) return string.sub(names[index], 1, #word) == word end,
		function(index) return string.sub(displays[index], 1, #word) == word end,
		function(index) return string.find(names[index], word, 1, true) ~= nil end,
		function(index) return string.find(displays[index], word, 1, true) ~= nil end,
	}
	for _, test in tiers do
		local found = {}
		for index in players do
			if test(index) then table.insert(found, players[index]) end
		end
		if #found == 1 then
			return { Kind = "Single", Player = found[1], Matches = { found[1].Name }, Count = 1 }
		elseif #found > 1 then
			table.sort(found, function(a, b) return a.Name < b.Name end)
			local matches = {}
			for index = 1, math.min(#found, 5) do matches[index] = found[index].Name end
			return { Kind = "Ambiguous", Matches = matches, Count = #found }
		end
	end
	return { Kind = "None", Matches = {}, Count = 0 }
end

return Parser
