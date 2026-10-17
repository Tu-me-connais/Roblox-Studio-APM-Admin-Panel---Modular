--[[
	Settings : VALEURS PAR DÉFAUT officielles des réglages serveur de l'APM (référence documentée).
	Seul le serveur lit ce module (les clients ne le voient jamais).

	Ne modifie pas ce fichier : il fait partie du Core et est remplacé à chaque mise à jour.
	Tes réglages vont dans APM_Extensions > Config > ServerSettings (copie-y la ligne à changer) ; ils sont fusionnés
	par-dessus ces valeurs à la fin de ce module.
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

Settings.SuperRank = "Dev" -- grade le plus haut, non ciblable ; accès selon la matrice de permissions
Settings.ManagerRank = "Owner" -- minimum pour l'onglet Paramètres ; valeur par défaut de la permission APM.ServerLock
Settings.AnnounceRank = "Staff" -- valeur par défaut de la permission APM.Announce (annonce à tout le serveur)
-- Toutes les fonctionnalités se règlent ensuite dans le panneau : Paramètres > Fonctionnalités et accès, par catégorie.
Settings.CreatorRank = nil -- aucun grade automatique ; option volontaire dans ServerSettings externe

-- COMPTES ------------------------------------------------------------------------------------------------
-- Grade FIXE par UserId (prioritaire, ne se change pas depuis le panneau)
Settings.Users = {
	-- [123456789] = "Dev", -- compte choisi explicitement par le développeur
	-- [123456789] = "Owner",
}

-- Grades de DÉPART (modifiables ou retirables ensuite depuis le panneau, onglet Paramètres)
Settings.DefaultUsers = {
	-- [123456789] = "Staff",
}

-- Grades d'un GROUPE Roblox (Id = 0 : désactivé). Ranks : [rang minimum dans le groupe, 1 à 255] = grade.
Settings.Group = {
	Id = 0,
	Ranks = {
		-- [123456789] = "Owner",
		-- [200] = "CoOwner",
		-- [100] = "Staff",
	},
}
-- Le grade d'un compte est le PLUS HAUT de ses sources : Users, créateur, panneau / DefaultUsers, groupe, Studio.

-- STUDIO -----------------------------------------------------------------------------------------------
-- Grade donné en Studio au joueur de test (ton compte en « Lancer », ou Player1 en « Serveur local ») :
-- Désactivé par défaut : les tests utilisent les grades réellement configurés. Sans effet dans le jeu publié.
Settings.StudioRank = nil

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
 ["Funny.View"]="Staff", ["Funny.Use"]="Staff", ["Funny.Group"]="Owner", ["Funny.StopAll"]="Owner",
 ["Funny.Transform"]="Staff", ["Funny.Physics"]="Owner",
 ["Funny.Server"]="Owner", ["Funny.CrossServer"]="Owner",
 -- Sentinel (assistant flottant) et Sentinel Helper : à ne pas confondre avec les permissions « Sentinel.* » de Sentinel Guard
 ["Assistant.Use"]="StaffTest", ["Assistant.Configure"]="Owner", ["Assistant.Commands"]="Owner", ["Assistant.External"]="Owner",
}
Settings.Modules = {Simulation=true, AutoBridge=true, Sentinel=true, Funny=true, Assistant=true, Dispatcher=true}
Settings.Funny = {Enabled=true, MaxDuration=60, MaxActiveScenes=16, MaxGroupTargets=8, CrossServerEnabled=true, MessagingTopic="APM_Funny_v1"}
Settings.ClientTools = {"Fly", "Noclip", "ESP", "Spectator"}
Settings.DisabledCommands = {}
Settings.AutoBridge = {Enabled=true, ScanInterval=30, MaxScanInstances=1500, MaxEntries=60, EnableTeamActions=false}
Settings.Sentinel = {Enabled=true, Mode="Observation", Interval=1, CorrectPosition=false, AllowKick=false}
-- Sentinel (assistant de commandes flottant, 2.10.2). Valeurs de départ ; Sentinel Helper les ajuste ensuite (enregistrées par SuiteConfig).
-- Moteur de commandes LOCAL, à règles : il n'a besoin d'aucune IA ni connexion Internet.
-- External : IA externe FACULTATIVE, désactivée tant que rien n'est configuré ICI (ServerSettings, jamais visible des clients) :
--   Hosts = { "api.exemple.com" }  hôtes HTTPS autorisés (liste vide = aucune requête HTTP, jamais) ; SecretName = nom d'un Secret Roblox
--   (HttpService:GetSecret) ou ApiKey = "..." (moins sûr). Le serveur n'envoie à l'IA que le texte saisi et la liste des commandes.
Settings.Assistant = {
	Enabled = true,
	MaxHistory = 40, ReplyStyle = "Short", ConfirmDangerous = true,
	AllowAll = true, MaxAllTargets = 25, RatePerWindow = 8,
	DefaultDeployed = true, WaveEnabled = true, WaveInterval = 30, AnimationSpeed = 1,
	External = { Enabled = false, Hosts = {}, SecretName = nil, ApiKey = nil, Provider = "OpenAI", Endpoint = nil, Model = nil, TimeoutSeconds = 8, MaxPerMinute = 6 },
}
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
-- Runtime provenance is derived by the bootstrap, never from a client.
merged._APMConfiguration = {
 SourcePath = extensions:GetAttribute("APMConfigurationSourcePath") or custom:GetFullName(),
 DuplicateConfigurations = extensions:GetAttribute("APMDuplicateConfigurations") == true,
 AlternateSourcePath = extensions:GetAttribute("APMAlternateConfigurationPath"),
 StudioMemory = merged.StudioMemory == true,
}
return merged
