--[[
	Unicode : normalisation des textes tapés dans Sentinel pour les sept langues de l'APM (fr, en, es, pt, de, ru, zh). Fonctions pures.

	Luau ne met en minuscules que l'ASCII (string.lower) et n'a ni NFC ni NFKC : on travaille donc par points de code, avec des tables fermées.
	  Sanitize   nettoie un texte À CONSERVER (motif d'une sanction...) : espaces typographiques -> espace, caractères invisibles supprimés,
	             guillemets typographiques (« » “ ” „ 「 」...) -> ", apostrophes typographiques -> '. Casse et accents sont gardés.
	  Fold       clé de COMPARAISON : Sanitize + minuscules (latin, cyrillique, formes pleine largeur) + accents latins retirés + ß -> ss + ё -> е
	             + chiffres et lettres pleine largeur (ＦＬＹ ５０) -> ASCII. Ne sert qu'à comparer : un pseudo n'est jamais modifié.
	  Truncate   coupe à N CARACTÈRES (jamais au milieu d'un caractère UTF-8 : un texte coupé en octets ferait échouer JSON et DataStore).
	Les variantes chinoises (simplifié / traditionnel) ne sont PAS fusionnées : elles sont listées une à une dans les dictionnaires.
]]
local Unicode = {}

local SANITIZE, FOLD = {}, {} -- [point de code] = texte de remplacement ("" = supprimé)

local function both(codepoint, replacement)
	SANITIZE[codepoint], FOLD[codepoint] = replacement, replacement
end

-- espaces : contrôles C1, NBSP, espaces d'imprimerie, espace idéographique (saisie chinoise) -> espace
for codepoint = 0x80, 0x9F do both(codepoint, " ") end
for _, codepoint in { 0xA0, 0x1680, 0x202F, 0x205F, 0x3000, 0x2028, 0x2029 } do both(codepoint, " ") end
for codepoint = 0x2000, 0x200A do both(codepoint, " ") end
-- caractères invisibles (largeur nulle, sens d'écriture, césure facultative, BOM, sélecteurs de variante) -> supprimés
for codepoint = 0x200B, 0x200F do both(codepoint, "") end
for codepoint = 0x202A, 0x202E do both(codepoint, "") end
for codepoint = 0x2060, 0x2064 do both(codepoint, "") end
for codepoint = 0xFE00, 0xFE0F do both(codepoint, "") end
for _, codepoint in { 0xAD, 0x34F, 0xFEFF } do both(codepoint, "") end
-- guillemets doubles (français, allemand, anglais typographique, chinois, pleine largeur) -> "
for _, codepoint in { 0xAB, 0xBB, 0x201C, 0x201D, 0x201E, 0x201F, 0x300C, 0x300D, 0x300E, 0x300F, 0x301D, 0x301E, 0x301F, 0xFF02 } do both(codepoint, '"') end
-- apostrophes et guillemets simples typographiques -> '
for _, codepoint in { 0x2018, 0x2019, 0x201A, 0x201B, 0x2032, 0x2BC } do both(codepoint, "'") end

----------------------------------------------------------------------------------------------------------
-- Pliage de comparaison (en plus de ce qui précède)

local function foldRange(sourceStart, sourceEnd, delta)
	for codepoint = sourceStart, sourceEnd do FOLD[codepoint] = utf8.char(codepoint + delta) end
end

-- latin-1 : majuscules -> minuscules (sauf × U+D7), puis accents retirés
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
	FOLD[0xF8], FOLD[0xD8] = "o", "o" -- ø Ø
	FOLD[0xE6], FOLD[0xC6] = "ae", "ae" -- æ Æ
	FOLD[0xDF], FOLD[0x1E9E] = "ss", "ss" -- ß ẞ
	FOLD[0xF0], FOLD[0xD0] = "d", "d" -- ð Ð
	FOLD[0xFE], FOLD[0xDE] = "th", "th" -- þ Þ
	-- latin étendu A (U+0100-017F) : lettre de base, dans l'ordre des points de code
	local base = string.split("a a a a a a c c c c c c c c d d d d e e e e e e e e e e g g g g g g g g h h h h i i i i i i i i i i ij ij j j k k k l l l l l l l l l l n n n n n n n n n o o o o o o oe oe r r r r r r s s s s s s s s t t t t t t u u u u u u u u u u u u w w y y y z z z z z z s", " ")
	for index, letters in base do FOLD[0x100 + index - 1] = letters end
end

-- cyrillique : majuscules -> minuscules (А-Я, Ѐ-Џ), puis ё -> е (on tape très souvent е pour ё)
foldRange(0x410, 0x42F, 32)
foldRange(0x400, 0x40F, 80)
FOLD[0x451] = utf8.char(0x435)
FOLD[0x401] = utf8.char(0x435)

-- formes pleine largeur (saisie chinoise / japonaise) : ！-～ -> ASCII ; le signe moins mathématique -> -
for codepoint = 0xFF01, 0xFF5E do
	if not FOLD[codepoint] then FOLD[codepoint] = string.lower(utf8.char(codepoint - 0xFEE0)) end
end
FOLD[0x2212] = "-"

----------------------------------------------------------------------------------------------------------

local NON_ASCII = "[\128-\255]"

local function convert(text, map)
	local pieces, count = {}, 0
	for _, codepoint in utf8.codes(text) do
		count += 1
		pieces[count] = map[codepoint] or utf8.char(codepoint)
	end
	return table.concat(pieces)
end

-- texte à conserver : voir l'en-tête. Texte invalide (UTF-8) -> nil
function Unicode.Sanitize(text)
	if type(text) ~= "string" then return nil end
	if not string.find(text, NON_ASCII) then return text end
	if not utf8.len(text) then return nil end
	return convert(text, SANITIZE)
end

-- clé de comparaison : minuscules, sans accents latins, espaces réduits et rognés. Texte invalide ou non textuel -> ""
function Unicode.Fold(text)
	if type(text) ~= "string" then return "" end
	local folded
	if not string.find(text, NON_ASCII) then
		folded = string.lower(text)
	else
		if not utf8.len(text) then return "" end
		folded = convert(string.lower(text), FOLD)
	end
	folded = string.gsub(folded, "%s+", " ")
	folded = string.gsub(folded, "^ ", "")
	folded = string.gsub(folded, " $", "")
	return folded
end

-- Coupe à `limit` caractères (pas octets). Texte invalide : coupé avant le premier octet invalide.
function Unicode.Truncate(text, limit)
	if type(text) ~= "string" then return "" end
	local length, bad = utf8.len(text)
	if not length then
		text = string.sub(text, 1, bad - 1)
		length = utf8.len(text) or 0
	end
	if length <= limit then return text end
	return string.sub(text, 1, utf8.offset(text, limit + 1) - 1)
end

-- Le texte contient-il autre chose que de l'ASCII ?
function Unicode.IsAscii(text)
	return type(text) == "string" and not string.find(text, NON_ASCII)
end

return Unicode
