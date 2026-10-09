--[[
	Settings : RÉGLAGES SERVEUR de l'APM. Seul le serveur lit ce module (les clients ne le voient jamais).

	>>> À faire en premier : mettre ton UserId dans Settings.Users (ex. [123456789] = "Dev"). <<<
	Ton UserId est dans l'adresse de ton profil : roblox.com/users/<UserId>/profile
]]
local ServerStorage = game:GetService("ServerStorage")

local Settings = {}

-- GRADES ------------------------------------------------------------------------------------------------
-- Du plus haut au plus bas.
--   Id     identifiant enregistré (ne plus le changer une fois le jeu en ligne)
--   Level  puissance : plus grand = plus haut ; un admin n'agit que sur un Level strictement inférieur au sien
--   Color  couleur du badge
--   Fixed  true : grade donné SEULEMENT ici (Users / CreatorRank), jamais depuis le panneau
--   Name   (facultatif) nom affiché si aucune traduction "Rank.<Id>" n'existe dans APM_Shared > Lang
Settings.Ranks = {
	{ Id = "Dev", Level = 5, Color = Color3.fromRGB(255, 80, 160), Fixed = true },
	{ Id = "Owner", Level = 4, Color = Color3.fromRGB(220, 170, 70), Fixed = true },
	{ Id = "CoOwner", Level = 3, Color = Color3.fromRGB(200, 150, 50) },
	{ Id = "Staff", Level = 2, Color = Color3.fromRGB(88, 128, 232) },
	{ Id = "StaffTest", Level = 1, Color = Color3.fromRGB(120, 128, 145) },
}

Settings.SuperRank = "Dev" -- accès à tout, toujours ; personne ne peut le cibler
Settings.ManagerRank = "Owner" -- minimum pour l'onglet Paramètres (grades, matrice d'accès, verrouillage du serveur)
Settings.AnnounceRank = "Staff" -- minimum pour envoyer une annonce à tout le serveur
Settings.CreatorRank = "Owner" -- donné au créateur du jeu (ou au propriétaire du groupe pour un jeu de groupe) ; nil = aucun

-- COMPTES ------------------------------------------------------------------------------------------------
-- Grade FIXE par UserId (prioritaire, ne se change pas depuis le panneau)
Settings.Users = {
	--[1069201574] = "Dev",
}

-- Grades de DÉPART (modifiables ou retirables ensuite depuis le panneau, onglet Paramètres)
Settings.DefaultUsers = {
	-- [1069201574] = "Staff",
}

-- Grades d'un GROUPE Roblox (Id = 0 : désactivé). Ranks : [rang minimum dans le groupe, 1 à 255] = grade.
Settings.Group = {
	Id = 0,
	Ranks = {
		-- [255] = "Owner",
		-- [200] = "CoOwner",
		-- [100] = "Staff",
	},
}
-- Le grade d'un compte est le PLUS HAUT de ses sources : Users, créateur, panneau / DefaultUsers, groupe, Studio.

-- STUDIO -----------------------------------------------------------------------------------------------
-- Grade donné en Studio au joueur de test (ton compte en « Lancer », ou Player1 en « Serveur local ») :
-- l'APM marche tout de suite, sans rien configurer. Sans effet dans le jeu publié. nil = désactivé.
Settings.StudioRank = "Owner"

-- SAUVEGARDE ------------------------------------------------------------------------------------------------
-- Un seul DataStore pour tout l'APM (grades, matrice d'accès, bans, avertissements, journal, annuaire).
-- Changer le nom repart de zéro. Sans accès aux DataStores en Studio, l'APM passe en MODE MÉMOIRE (rien n'est enregistré).
Settings.DataStoreName = "APM_Data_v1"
Settings.MessagingTopic = "APM_Sync_v1" -- synchronisation des droits entre serveurs (MessagingService)

-- LIMITES -----------------------------------------------------------------------------------------------------
Settings.MaxLogs = 300 -- entrées gardées dans le journal (onglet Logs)
Settings.MaxRoster = 20000 -- comptes gardés dans l'annuaire (onglet Joueurs > Global)
Settings.MaxWarnings = 25 -- avertissements gardés par joueur

-- MODULE « Donner un outil » (GiveTool) : dossiers où chercher les Tool (descendants compris)
Settings.ToolSources = { ServerStorage }

-- Suite 2.0 : valeurs sûres, configuration serveur centralisée.
Settings.StudioMemory = true -- tests sans écriture dans les sauvegardes du jeu publié
Settings.PermissionDefaults = {
 ["APM.AccessPanel"]="StaffTest", ["APM.ManagePermissions"]="Owner", ["APM.Simulate"]="Owner",
 ["Sentinel.View"]="Staff", ["Sentinel.Configure"]="Owner", ["Sentinel.Test"]="Owner",
 ["AutoBridge.View"]="Staff", ["AutoBridge.Configure"]="Owner",
}
Settings.Modules = {Simulation=true, AutoBridge=true, Sentinel=true}
Settings.ClientTools = {"Fly", "Noclip", "ESP", "Spectator"}
Settings.DisabledCommands = {}
Settings.AutoBridge = {Enabled=true, ScanInterval=30, MaxScanInstances=1500, MaxEntries=60, EnableTeamActions=false}
Settings.Sentinel = {Enabled=true, Mode="Observation", Interval=1, CorrectPosition=false, AllowKick=false}
-- Official defaults stay in Core; developer values live outside the Package.
local extensions = ServerStorage:WaitForChild("APM_Extensions", 10)
assert(extensions and extensions:GetAttribute("APMExtensionsSchema") == 1, "[APM] Extensions configuration incompatible")
local config = extensions:FindFirstChild("Config")
local custom = config and config:FindFirstChild("ServerSettings")
assert(custom and custom:IsA("ModuleScript"), "[APM] External ServerSettings missing")
local override = require(custom)
assert(type(override)=="table", "[APM] ServerSettings must return a table")
local merged = require(game:GetService("ReplicatedStorage"):WaitForChild("APM_Shared").Configuration).Merge(Settings, override)
-- These compatibility identifiers are immutable data contracts, independent of product versions.
assert(type(merged.DataStoreName)=="string" and merged.DataStoreName~="", "[APM] Invalid DataStoreName")
assert(type(merged.PermissionDefaults)=="table" and type(merged.Ranks)=="table", "[APM] Invalid settings")
return merged
