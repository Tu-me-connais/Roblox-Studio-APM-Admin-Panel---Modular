--[[
	Lang : traductions de l'APM (client ET serveur).

	Chaque ModuleScript enfant (en, fr, es, pt, de...) renvoie un dictionnaire { ["Clé"] = "Texte" } ; son NOM est le code de langue.
	La langue d'un joueur vient de Player.LocaleId ("fr-fr" -> "fr", "pt-br" -> "pt"), sinon Config.DefaultLanguage, sinon "en".
	Une clé absente d'une langue est prise en anglais : une traduction incomplète ne casse rien.

	Organisation : les traductions fournies sont regroupées PAR ONGLET dans Lang > Tabs (un ModuleScript par onglet, toutes les langues dedans) :
	  return { Keys = { en = { ["Home.Title"] = "..." }, fr = { ... } }, Phrases = { es = { ["English text"] = "..." }, ... } }
	Keys = textes appelés par clé ; Phrases = textes écrits dans le code, indexés par leur texte anglais.
	Les modules Lang > <langue> et Lang > Phrases > <langue> restent lus APRÈS Tabs : ils servent à vos propres textes ou à remplacer un texte fourni.

	Tout texte affiché par l'APM peut être :
	  "Tab.Players"                        une clé                    -> traduite
	  { en = "Hello", fr = "Bonjour" }     un texte multilingue       -> la langue du joueur est choisie ; s'il manque, la
	                                                                    traduction est cherchée dans Phrases/<langue> (clé = texte anglais)
	  Lang.Phrase({ en = "Hello %s", fr = "Bonjour %s" }, nom)  un message multilingue différé { p, a, n }
	  Lang.Msg("Mod.Kick.Done", nom, ...)  un message { k, a, n }     -> clé traduite puis remplie (string.format) ; un argument peut être un message
	  { d = os.time() }                    une date                   -> formatée selon la langue (clé Date.Format)
	  { s = 3600 }                         une durée en secondes      -> "1 h 00 min"
	  "Bonjour"                            un texte simple            -> affiché tel quel
	Le serveur envoie des MESSAGES (pas du texte) : chaque admin les lit dans sa langue, même dans le journal.
]]
local Players = game:GetService("Players")
local LocalizationService = game:GetService("LocalizationService")

local Config = require(script.Parent:WaitForChild("Config"))

local Lang = {}
Lang.Dictionaries = {} -- [code] = { [clé] = texte }
Lang.Phrases = {} -- [code] = { [texte anglais] = traduction } : complète les textes { fr = ..., en = ... } (dossier Phrases)
Lang.Override = nil -- (client) langue choisie à la main pour la session, nil = automatique

local FALLBACK = "en"
-- Préfixes dont une clé manquante affiche simplement la fin (« Rank.Moderator » -> « Moderator »)
local SOFT_PREFIX = { Rank = true, Cat = true, Group = true, Tab = true, Action = true }

local function register(code, dict)
	code = string.lower(code)
	local target = Lang.Dictionaries[code]
	if not target then
		target = {}
		Lang.Dictionaries[code] = target
	end
	for key, text in dict do
		if type(key) == "string" and type(text) == "string" then
			target[key] = text
		end
	end
end

local function registerPhrases(code, book)
	code = string.lower(code)
	local target = Lang.Phrases[code]
	if not target then
		target = {}
		Lang.Phrases[code] = target
	end
	for english, translated in book do
		if type(english) == "string" and type(translated) == "string" then
			target[english] = translated
		end
	end
end

-- Tabs/<Onglet> : toutes les traductions d'un onglet dans un seul module { Keys = { [langue] = { [clé] = texte } }, Phrases = { [langue] = { [texte anglais] = traduction } } }
local tabFolder = script:FindFirstChild("Tabs")
if tabFolder then
	for _, child in tabFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, tab = pcall(require, child)
			if ok and type(tab) == "table" then
				if type(tab.Keys) == "table" then
					for code, dict in tab.Keys do
						if type(code) == "string" and type(dict) == "table" then register(code, dict) end
					end
				end
				if type(tab.Phrases) == "table" then
					for code, book in tab.Phrases do
						if type(code) == "string" and type(book) == "table" then registerPhrases(code, book) end
					end
				end
			else
				warn(("[APM] Traductions de l'onglet « %s » invalides : %s"):format(child.Name, tostring(tab)))
			end
		end
	end
end

-- Dictionnaires par langue (facultatifs : vos propres clés, ou remplacement d'un texte fourni)
for _, child in script:GetChildren() do
	if child:IsA("ModuleScript") then
		local ok, dict = pcall(require, child)
		if ok and type(dict) == "table" then
			register(child.Name, dict)
		else
			warn(("[APM] Langue « %s » invalide : %s"):format(child.Name, tostring(dict)))
		end
	end
end

-- Phrases/<code> : traductions des textes écrits directement dans le code ({ fr = ..., en = ... }), indexées par le texte anglais
local phraseFolder = script:FindFirstChild("Phrases")
if phraseFolder then
	for _, child in phraseFolder:GetChildren() do
		if child:IsA("ModuleScript") then
			local ok, book = pcall(require, child)
			if ok and type(book) == "table" then
				local code = string.lower(child.Name)
				registerPhrases(code, book)
			else
				warn(("[APM] Phrases « %s » invalides : %s"):format(child.Name, tostring(book)))
			end
		end
	end
end

local function defaultCode()
	local code = type(Config.DefaultLanguage) == "string" and string.lower(Config.DefaultLanguage) or FALLBACK
	return Lang.Dictionaries[code] and code or FALLBACK
end

-- Ajoute / remplace des textes : Lang.Add("fr", { ["Ma.Cle"] = "Texte" })
function Lang.Add(code, dict)
	if type(code) == "string" and type(dict) == "table" then
		register(code, dict)
	end
end

-- Plusieurs langues d'un coup : Lang.AddAll({ en = { ... }, fr = { ... } }) (champ Strings d'un module)
function Lang.AddAll(strings)
	if type(strings) ~= "table" then
		return
	end
	for code, dict in strings do
		Lang.Add(code, dict)
	end
end

function Lang.Has(key)
	if type(key) ~= "string" then
		return false
	end
	for _, dict in Lang.Dictionaries do
		if dict[key] ~= nil then
			return true
		end
	end
	return false
end

-- Codes disponibles, triés : { "de", "en", "es", "fr", "pt", "ru", "zh" }
function Lang.Codes()
	local list = {}
	for code in Lang.Dictionaries do
		table.insert(list, code)
	end
	table.sort(list)
	return list
end

-- "fr-fr" / "FR" / "pt_BR" -> code disponible
function Lang.Normalize(localeId)
	local forced = type(Config.ForceLanguage) == "string" and string.lower(Config.ForceLanguage) or nil
	if forced and Lang.Dictionaries[forced] then
		return forced
	end
	if type(localeId) ~= "string" or localeId == "" then
		return defaultCode()
	end
	local lower = string.gsub(string.lower(localeId), "_", "-")
	if Lang.Dictionaries[lower] then
		return lower
	end
	local base = string.match(lower, "^(%a+)")
	if base and Lang.Dictionaries[base] then
		return base
	end
	return defaultCode()
end

-- (serveur) langue d'un joueur, d'après son compte Roblox
function Lang.ForPlayer(player)
	local ok, locale = pcall(function()
		return player.LocaleId
	end)
	return Lang.Normalize(ok and locale or nil)
end

-- (client) langue du joueur local : choix manuel de la session, sinon langue de son compte Roblox
function Lang.Local()
	if Lang.Override and Lang.Dictionaries[Lang.Override] then
		return Lang.Override
	end
	local locale
	local player = Players.LocalPlayer
	if player then
		pcall(function()
			locale = player.LocaleId
		end)
	end
	if not locale or locale == "" then
		pcall(function()
			locale = LocalizationService.RobloxLocaleId
		end)
	end
	return Lang.Normalize(locale)
end

local function lookup(lang, key)
	local dict = Lang.Dictionaries[lang]
	local text = dict and dict[key]
	if text == nil then
		local fallback = Lang.Dictionaries[defaultCode()]
		text = fallback and fallback[key]
	end
	if text == nil then
		local english = Lang.Dictionaries[FALLBACK]
		text = english and english[key]
	end
	return text
end

-- Un message traduisible : Lang.Msg("Mod.Kick.Done", "Bob", "") -> { k = "Mod.Kick.Done", a = { "Bob", "" }, n = 2 }
-- (il passe par les remotes et le DataStore, et sera traduit chez celui qui le lit)
function Lang.Msg(key, ...)
	return { k = key, a = { ... }, n = select("#", ...) }
end

-- Texte multilingue avec arguments, traduit seulement chez celui qui le lit.
-- Le modèle reste intact pour la recherche exacte dans Phrases ; aucun texte libre n'est deviné.
function Lang.Phrase(template, ...)
	return { p = template, a = { ... }, n = select("#", ...) }
end

local function formatDuration(lang, seconds)
	seconds = math.max(0, math.floor(tonumber(seconds) or 0))
	local hours, minutes = seconds // 3600, (seconds % 3600) // 60
	if hours >= 24 then
		return Lang.Get(lang, "Time.DayHour", hours // 24, hours % 24)
	elseif hours > 0 then
		return Lang.Get(lang, "Time.HourMin", hours, minutes)
	end
	return Lang.Get(lang, "Time.Min", minutes)
end

local function formatText(lang, text, count, args)
	if count == 0 then
		return text
	end
	for index = 1, count do
		local value = args[index]
		if type(value) == "table" or type(value) == "string" then
			args[index] = Lang.Text(lang, value)
		elseif value == nil then
			args[index] = ""
		end
	end
	local ok, result = pcall(string.format, text, table.unpack(args, 1, count))
	return ok and result or text
end

-- Traduit le modèle AVANT de remplir ses arguments (contrairement à des textes déjà formatés).
function Lang.Format(lang, template, ...)
	return formatText(lang, Lang.Text(lang, template), select("#", ...), { ... })
end

-- Texte d'une clé dans une langue, rempli avec les arguments (qui peuvent être des clés ou des messages)
function Lang.Get(lang, key, ...)
	local text = lookup(lang, key)
	if text == nil then
		local prefix, rest = string.match(tostring(key), "^(%a+)%.(.+)$")
		if prefix and SOFT_PREFIX[prefix] then
			return rest
		end
		return tostring(key)
	end
	return formatText(lang, text, select("#", ...), { ... })
end

-- Résout n'importe quelle valeur affichable (voir l'en-tête)
function Lang.Text(lang, value)
	local kind = type(value)
	if kind == "string" then
		if string.find(value, ".", 1, true) and not string.find(value, " ", 1, true) then
			local text = lookup(lang, value)
			if text then
				return text
			end
			local prefix, rest = string.match(value, "^(%a+)%.([%w_%-]+)$")
			if prefix and SOFT_PREFIX[prefix] then
				return rest
			end
		end
		return value
	elseif kind == "table" then
		if type(value.p) == "string" or type(value.p) == "table" then
			local args = type(value.a) == "table" and value.a or {}
			return Lang.Format(lang, value.p, table.unpack(args, 1, tonumber(value.n) or #args))
		elseif type(value.k) == "string" then
			local args = type(value.a) == "table" and value.a or {}
			return Lang.Get(lang, value.k, table.unpack(args, 1, tonumber(value.n) or #args))
		elseif type(value.d) == "number" then
			if value.d <= 0 then
				return "-"
			end
			return os.date(lookup(lang, "Date.Format") or "%Y-%m-%d %H:%M", value.d)
		elseif type(value.s) == "number" then
			return formatDuration(lang, value.s)
		end
		local picked = value[lang]
		if picked == nil and type(value.en) == "string" then
			local book = Lang.Phrases[lang]
			picked = book and book[value.en]
		end
		if picked == nil then
			picked = value[defaultCode()] or value[FALLBACK]
		end
		if picked == nil then
			local _, first = next(value)
			picked = first
		end
		return picked ~= nil and tostring(picked) or ""
	elseif value == nil then
		return ""
	end
	return tostring(value)
end

return Lang

