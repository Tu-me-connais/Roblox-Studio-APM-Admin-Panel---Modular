-- Funny.Catalog : catalogue des effets et validation stricte d'une demande venue du client (aucune clé inconnue acceptée).
local Catalog = {}

local CATALOG = {
	{ Id = "Confetti", Label = { fr = "Pluie de confettis", en = "Confetti shower" },
		Description = { fr = "Confettis pastel qui virevoltent et rubans de soie en spirale, avec des fondus doux.", en = "Fluttering pastel confetti and spiraling silk ribbons with soft fades." } },
	{ Id = "Disco", Label = { fr = "Disco de poche", en = "Pocket disco" },
		Description = { fr = "Boule à miroirs, halos croisés et faisceaux pastel sur le sol, accompagnés de Raining Tacos.", en = "A mirror ball, crossing halos and pastel floor beams accompanied by Raining Tacos." } },
	{ Id = "Ducks", Label = { fr = "Conseil des canards", en = "Duck council" },
		Description = { fr = "Un cortège de petits canards qui se dandinent autour du personnage, sur des ondulations turquoise.", en = "Little rubber ducks waddle around the character over turquoise ripples." } },
	{ Id = "Bubbles", Label = { fr = "Bureau des bulles", en = "Bubble department" },
		Description = { fr = "Des bulles irisées montent doucement, avec un contour lumineux et des reflets nacrés.", en = "Iridescent bubbles gently rise with luminous rims and pearly highlights." } },
	{ Id = "Potato", Label = { fr = "Sa majesté la patate", en = "Your potato majesty" },
		Description = { fr = "Une patate souriante en cape violette, couronne dorée et bijoux, entourée d'étoiles.", en = "A smiling potato in a purple cape, golden crown and jewels, surrounded by stars." } },
	{ Id = "Solar", Label = { fr = "Centre de l'univers", en = "Center of the universe" },
		Description = { fr = "Un soleil miniature, des planètes aux orbites inclinées, des anneaux et de la poussière d'étoiles.", en = "A tiny sun, planets on tilted orbits, rings and stardust." } },
	{ Id = "Snow", Label = { fr = "Petite tempête de neige", en = "Little snowstorm" },
		Description = { fr = "Un nuage douillet au-dessus de la tête et des flocons qui tombent en tourbillonnant.", en = "A cozy cloud above the head and snowflakes swirling down." } },
	{ Id = "Hearts", Label = { fr = "Coup de foudre", en = "Love at first sight" },
		Description = { fr = "Des cœurs lumineux montent en spirale autour du personnage, avec un grand cœur qui bat au-dessus.", en = "Glowing hearts spiral up around the character, with a big beating heart above." } },
	{ Id = "Fireworks", Label = { fr = "Feu d'artifice de poche", en = "Pocket fireworks" },
		Description = { fr = "De petites fusées montent autour du personnage et éclatent en gerbes colorées.", en = "Little rockets rise around the character and burst into colorful sprays." } },
	{ Id = "Rainbow", Label = { fr = "Arc-en-ciel perso", en = "Personal rainbow" },
		Description = { fr = "Un arc-en-ciel qui tourne lentement au-dessus du personnage, posé sur deux petits nuages.", en = "A rainbow slowly turning above the character, resting on two little clouds." } },
	{ Id = "BigHead", Permission = "Funny.Transform", Label = { fr = "Grande tête", en = "Big head" },
		Description = { fr = "Agrandit progressivement la tête avec un facteur réglable. R15 et R6.", en = "Smoothly grows the head with an adjustable factor. R15 and R6." } },
	{ Id = "Skin", Permission = "Funny.Transform", Label = { fr = "Skin d'un compte Roblox", en = "Roblox account skin" },
		Description = { fr = "Prend temporairement l'avatar réel du compte choisi, puis restaure l'apparence.", en = "Temporarily uses the chosen account's real avatar, then restores the appearance." } },
	{ Id = "ReverseGravity", Permission = "Funny.Physics", Label = { fr = "Gravité inversée", en = "Reverse gravity" },
		Description = { fr = "Le personnage s'envole avec une gravité personnelle (hauteur et vitesse limitées) et reste dirigeable ; il est reposé au sol à la fin.", en = "The character floats up with personal reversed gravity (bounded height and speed) and can still steer; it is set back on the ground at the end." } },
	{ Id = "UpsideDown", Permission = "Funny.Physics", Label = { fr = "Personnage à l'envers", en = "Upside-down character" },
		Description = { fr = "Retourne le personnage tête en bas : il continue de marcher, sauter et tourner (sur la tête !), puis se remet à l'endroit.", en = "Flips the character head over heels: it keeps walking, jumping and turning (on its head!), then turns back upright." } },
	{ Id = "BodyParts", Permission = "Funny.Transform", Label = { fr = "Copier ou échanger une partie du corps", en = "Copy or swap a body part" },
		Description = { fr = "Tête, visage, torse, bras ou jambes avec un joueur choisi ou aléatoire. Un échange transforme les deux joueurs.", en = "Head, face, torso, arms or legs from a chosen or random player. A swap transforms both players." } },
}
local BY_ID = {}
for _, entry in CATALOG do
	BY_ID[entry.Id] = entry
end
local BODY_PARTS = { Head = true, Face = true, Torso = true, LeftArm = true, RightArm = true, LeftLeg = true, RightLeg = true }
Catalog.List, Catalog.ById, Catalog.BodyParts = CATALOG, BY_ID, BODY_PARTS

-- Chaque effet est une fonctionnalité « Funny.Effect.<Id> » que l'onglet Paramètres peut couper pour tout le jeu.
function Catalog.EffectFeature(id)
	return "Funny.Effect." .. tostring(id)
end

function Catalog.Effects()
	local list = {}
	for index, entry in CATALOG do
		table.insert(list, { Id = entry.Id, Order = index, Label = entry.Label, Description = entry.Description, Permission = entry.Permission })
	end
	return list
end

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function userId(n)
	return finite(n) and n ~= 0 and n % 1 == 0 and math.abs(n) < 2 ^ 53
end

-- Renvoie une copie propre de la demande, ou nil si un champ est inconnu, absent ou hors limites
function Catalog.ValidateRequest(request, maximum)
	if type(request) ~= "table" then return nil end
	local keys = { Scenario = true, Scope = true, TargetUserId = true, Duration = true, Intensity = true }
	local scenario = type(request.Scenario) == "string" and request.Scenario or ""
	if not BY_ID[scenario] and scenario ~= "Random" then return nil end
	if scenario == "BigHead" then
		keys.Scale = true
	elseif scenario == "Skin" then
		keys.Account = true
	elseif scenario == "ReverseGravity" then
		keys.GravityFactor = true
		keys.MaxRise = true
		keys.MaxRiseSpeed = true
	elseif scenario == "BodyParts" then
		keys.PartnerMode = true
		keys.PartnerUserId = true
		keys.BodyPart = true
		keys.Operation = true
	end
	for key in request do
		if not keys[key] then return nil end
	end
	if request.Scope ~= "Self" and request.Scope ~= "Player" and request.Scope ~= "Group" and request.Scope ~= "Server" then return nil end
	if request.Scope == "Player" then
		if not userId(request.TargetUserId) then return nil end
	elseif request.TargetUserId ~= nil then
		return nil
	end
	if not finite(request.Duration) or request.Duration % 1 ~= 0 or request.Duration < 5 or request.Duration > (maximum or 60) then return nil end
	if not finite(request.Intensity) or request.Intensity % 1 ~= 0 or request.Intensity < 1 or request.Intensity > 3 then return nil end
	local clean = table.clone(request)
	if scenario == "BigHead" then
		clean.Scale = request.Scale or 2
		if not finite(clean.Scale) or clean.Scale < 1.25 or clean.Scale > 4 then return nil end
	elseif scenario == "Skin" then
		if type(request.Account) ~= "string" then return nil end
		clean.Account = request.Account:match("^%s*(.-)%s*$")
		if #clean.Account < 1 or #clean.Account > 20 or not clean.Account:match("^[%w_]+$") then return nil end
		local id = tonumber(clean.Account)
		if id and (not userId(id) or id < 1) then return nil end
	elseif scenario == "ReverseGravity" then
		clean.GravityFactor = request.GravityFactor or .35
		clean.MaxRise = request.MaxRise or 30
		clean.MaxRiseSpeed = request.MaxRiseSpeed or 12
		for name, bounds in { GravityFactor = { .1, 1 }, MaxRise = { 5, 60 }, MaxRiseSpeed = { 3, 25 } } do
			if not finite(clean[name]) or clean[name] < bounds[1] or clean[name] > bounds[2] then return nil end
		end
	elseif scenario == "BodyParts" then
		if request.Scope == "Group" or (request.Scope == "Server" and request.PartnerMode ~= "Random") or not BODY_PARTS[request.BodyPart]
			or (request.Operation ~= "Copy" and request.Operation ~= "Swap") then
			return nil
		end
		if request.PartnerMode == "Player" then
			if not userId(request.PartnerUserId) then return nil end
		elseif request.PartnerMode ~= "Random" or request.PartnerUserId ~= nil then
			return nil
		end
	end
	return clean
end

return Catalog
