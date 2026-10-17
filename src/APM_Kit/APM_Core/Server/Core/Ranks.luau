--[[
	Ranks : grades de l'APM, matrice d'accès « module x grade », sauvegarde et synchronisation entre serveurs.

	Grade d'un compte = le PLUS HAUT de ses sources :
	  Settings.Users (fixe) · créateur du jeu (Settings.CreatorRank) · grade donné dans le panneau (ou Settings.DefaultUsers)
	  · rang dans Settings.Group · Settings.StudioRank (Studio seulement)
	L'attribution prioritaire du propriétaire réel (OwnerAuthority_v2) peut remplacer les sources d'un autre compte.
	Un admin n'agit que sur un grade strictement inférieur au sien ; le SuperRank n'est ciblable par personne.

	Matrice d'accès : chaque module a des valeurs par défaut (d'après son MinRank) ; ce que l'onglet Paramètres change est
	enregistré (clé "Access") et l'emporte. Tous les grades, SuperRank compris, suivent les valeurs par défaut et les choix enregistrés.
	Interrupteur « Actif » : une fonctionnalité coupée (Access["$Disabled"]) est refusée à TOUS les grades, Dev compris.
	APM.AccessPanel et APM.ManagePermissions ne se coupent jamais (personne ne reste enfermé hors du panneau).
	Sans DataStore EN STUDIO : mode mémoire (tout marche, rien n'est enregistré). En jeu publié, une lecture ratée refuse par prudence.

	Le code est réparti dans les sous-modules de Ranks (Storage, Assignments, Access, Identity, Authority,
	Simulation, Resolution, Sync) ; ils partagent un état privé S et complètent cette même table Ranks.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Settings = require(script.Parent.Parent:WaitForChild("Settings"))
local Lang = require(ReplicatedStorage:WaitForChild("APM_Shared"):WaitForChild("Lang"))
local Msg = Lang.Msg

local IS_STUDIO = RunService:IsStudio()

local Ranks = {}
-- État privé partagé par les sous-modules (jamais exposé hors de Ranks)
local S = {
	Settings = Settings,
	Msg = Msg,
	IS_STUDIO = IS_STUDIO,
	simulations = {}, -- session-only; never written to a DataStore
	simulationGeneration = 0,
	ownerOverrides = {},
	ownerRevision = -1,
	OWNER_KEY = "OwnerAuthority_v2",
}
Ranks.OwnerAuthorityReady = false
Ranks.PermissionNames = {}

----------------------------------------------------------------------------------------------------------
-- Définition des grades (Settings.Ranks)

Ranks.List, Ranks.ById = {}, {}
for _, def in Settings.Ranks or {} do
	if type(def) == "table" and type(def.Id) == "string" and def.Id ~= "" and def.Id ~= "None" and type(def.Level) == "number" and def.Level > 0 and def.Level < math.huge
		and not Ranks.ById[def.Id] then
		local entry = {
			Id = def.Id,
			Level = def.Level,
			Color = typeof(def.Color) == "Color3" and def.Color or Color3.fromRGB(150, 157, 172),
			Fixed = def.Fixed == true,
			Name = type(def.Name) == "string" and def.Name or nil,
		}
		Ranks.ById[def.Id] = entry
		table.insert(Ranks.List, entry)
	end
end
table.sort(Ranks.List, function(a, b)
	return a.Level > b.Level
end)
assert(#Ranks.List > 0, "[APM] Settings.Ranks ne contient aucun grade valide.")

local function rankOrNil(id)
	if type(id) == "string" and Ranks.ById[id] then
		return id
	end
	return nil
end

Ranks.Super = rankOrNil(Settings.SuperRank) or Ranks.List[1].Id
Ranks.Manager = rankOrNil(Settings.ManagerRank) or Ranks.Super
Ranks.Announcer = rankOrNil(Settings.AnnounceRank) or Ranks.List[#Ranks.List].Id
local CREATOR_RANK = rankOrNil(Settings.CreatorRank)
local STUDIO_RANK = rankOrNil(Settings.StudioRank)

-- Permissions dédiées ajoutées après coup : par défaut, exactement l'ancien comportement (grade minimum ou tous les grades).
-- Settings.PermissionDefaults peut les remplacer comme les autres.
local BUILTIN_PERMISSIONS = {
	["APM.Announce"] = Ranks.Announcer, -- annonce à tout le serveur (ancien Settings.AnnounceRank)
	["APM.AnnounceStyle"] = Ranks.Manager, -- réglages des annonces (disposition, couleurs, textes) : Owner par défaut
	["APM.ServerLock"] = Ranks.Manager, -- verrouillage du serveur (ancien Settings.ManagerRank)
	["APM.ViewLogs"] = true, -- onglet Logs
}

function Ranks.Level(rankId)
	local rank = type(rankId) == "string" and Ranks.ById[rankId] or nil
	return rank and rank.Level or 0
end

-- Grade qu'on peut donner / retirer depuis le panneau
function Ranks.IsAssignable(rankId)
	local rank = type(rankId) == "string" and Ranks.ById[rankId] or nil
	return rank ~= nil and not rank.Fixed and rankId ~= Ranks.Super
end

-- Liste envoyée au client (badges, colonnes de la matrice, choix de grade)
function Ranks.Public()
	local list = {}
	for _, rank in Ranks.List do
		table.insert(list, { Id = rank.Id, Level = rank.Level, Color = rank.Color, Fixed = not Ranks.IsAssignable(rank.Id), Name = rank.Name })
	end
	return list
end

-- UserId valide (les comptes de test négatifs de Studio, Player1 = -1..., ne sont acceptés qu'en Studio)
function Ranks.ValidUserId(userId)
	if type(userId) ~= "number" or userId ~= userId or math.abs(userId) >= 2 ^ 53 or userId % 1 ~= 0 then
		return false
	end
	return userId > 0 or (userId < 0 and IS_STUDIO)
end

S.rankOrNil = rankOrNil
S.CREATOR_RANK, S.STUDIO_RANK, S.BUILTIN_PERMISSIONS = CREATOR_RANK, STUDIO_RANK, BUILTIN_PERMISSIONS

for _, part in { "Storage", "Assignments", "Access", "Identity", "Authority", "Simulation", "Resolution", "Sync" } do
	require(script:WaitForChild(part))(Ranks, S)
end

return Ranks
