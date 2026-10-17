--[[
	ServerSettings : TES réglages serveur de l'APM. Seul le serveur lit ce module (les clients ne le voient jamais).

	Ce fichier ne contient que ce que tu personnalises. Tout le reste prend les valeurs officielles, documentées
	ligne par ligne dans APM_Core > Server > Settings (ne modifie pas ce fichier-là : il est remplacé à chaque mise à jour).
	Pour changer une autre valeur, copie sa ligne ici : elle remplace la valeur par défaut.
	  - une table (ex. Settings.Funny = { MaxDuration = 30 }) ne remplace que les clés écrites ;
	  - une liste (Ranks, ClientTools, ToolSources) est remplacée en entier ;
	  - Settings.RemoveKeys = { "Clé" } supprime une valeur par défaut.

	>>> À faire en premier : mettre ton UserId dans Settings.Users (ex. [123456789] = "Dev"). <<<
	Ton UserId est dans l'adresse de ton profil : roblox.com/users/<UserId>/profile
]]
local Settings = {}
-- Aucun grade accordé automatiquement aux joueurs de test de Studio.
Settings.RemoveKeys = { "StudioRank", "CreatorRank" }

-- COMPTES ------------------------------------------------------------------------------------------------
-- Grade FIXE par UserId (prioritaire, ne se change pas depuis le panneau)
Settings.Users = {
	-- Ajouter ici les comptes fixes propres à l'expérience installée.
}

-- Grades de DÉPART (modifiables ou retirables ensuite depuis le panneau, onglet Paramètres)
Settings.DefaultUsers = {
	-- [123456789] = "Staff",
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

-- EXEMPLES COURANTS (retire le « -- » pour activer) --------------------------------------------------------
-- Settings.StudioRank = "Owner"                      -- donner volontairement un grade de test en Studio
-- Retirer StudioRank de RemoveKeys pour activer cet exemple.
-- Settings.CreatorRank = "Owner"                    -- option volontaire pour le propriétaire réel du jeu
-- Retirer CreatorRank de RemoveKeys pour activer cet exemple.
-- Settings.Modules = { Funny = false }               -- couper un module optionnel (Simulation, AutoBridge, Sentinel, Funny)
-- Settings.DisabledCommands = { Kill = true }        -- retirer une commande
-- Settings.Funny = { MaxDuration = 30 }              -- limites des effets Funny
-- Settings.Sentinel = { Mode = "Balanced" }          -- réglages de départ de Sentinel Guard (modifiables ensuite dans l'onglet Sentinel Guard)
--[[ Toutes les options de Sentinel Guard (valeur par défaut entre parenthèses) :
	Enabled (true)             surveillance générale             Mode ("Observation" | "Balanced" | "Strict")
	DetectSpeed (true)         vitesse                           SpeedLimitEnabled (false) + SpeedLimit (50 studs/s) : plafond précis
	DetectTeleport (true)      téléportation                    TeleportDistance (140 studs), TeleportConfirm (1)
	DetectFly (false)          vol                               FlySeconds (4)
	DetectNoclip (false)       personnage coincé dans un mur
	DetectHumanoid (true)      WalkSpeed / saut du personnage    JumpLimitEnabled (false) + JumpHeightLimit (30 studs)
	DetectAbuse (true)         requêtes refusées répétées      EnforceLimits (false) : remet vitesse / saut au plafond
	ExemptAdmins (true)  NotifyAdmins (true)  CorrectPosition (false)  AllowKick (false : ici seulement, jamais depuis le panneau)
	Avancé : Interval, MaxHorizontalSpeed, SpeedTolerance, LatencyAllowance, SpawnGrace, PhysicsGrace, RequiredSamples,
	          AlertCooldown, MaxAlerts, SuspectMemory
	LagFilter (true) : un déplacement en retard (lag) n'est pas une téléportation
	SafeZones : zones où rien n'est signalé, ex. SafeZones = { { Name = "Lobby", X = 0, Y = 5, Z = 0, Radius = 60 } } (40 max)
	Historique permanent (DataStore de l'APM, clés Sentinel_P_<userId>, Sentinel_Index, Sentinel_Audit) :
	          PersistHistory (true), RetentionDays (30, de 1 à 365)
	Exemple : Settings.Sentinel = { Mode = "Balanced", SpeedLimitEnabled = true, SpeedLimit = 40, DetectFly = true }
	Dans tes scripts serveur (ctx.Sentinel) : NotifyServerTeleport(player) AVANT de déplacer un joueur, pour que ce déplacement soit
	reconnu comme venant du serveur ; Alerted:Connect(function(alerte) ... end) pour réagir toi-même à une alerte.
]]

return Settings
