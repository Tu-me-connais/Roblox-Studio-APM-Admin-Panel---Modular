--[==[

	APM | Admin Panel - Modular — GUIDE COMPLET (FRANÇAIS)
	Version 2.10.2 (stable) · Licence MIT · Gratuit · Créé par APM contributors
	=====================================================================================================

	L'APM est un panneau d'administration pour aider les développeurs à gérer leur expérience : modération,
	grades, sécurité, statistiques et effets amusants. Tout est revérifié par le serveur et rien n'est envoyé
	aux joueurs qui n'y ont pas accès.

	SOMMAIRE
		1. Installation
		2. Langues du panneau
		3. Configuration
		4. Systèmes
		5. Modules
		6. Extensions (pour les développeurs)
		7. Mises à jour et aide


	=====================================================================================================
	1. INSTALLATION
	=====================================================================================================

	1) Insère APM_Kit depuis la Toolbox (Workspace ou ServerScriptService conviennent).
	   Ne le mets pas seul dans ServerStorage : les scripts n'y démarrent pas.
	2) Laisse le script ToolboxBootstrap activé (RunContext : Server). Au lancement, il range automatiquement le kit
	   dans ServerStorage et démarre un chargeur privé dans ServerScriptService.
	   Les scripts Installer et APM_Bootstrap restent désactivés : ils servent seulement à une installation manuelle.
	3) Donne-toi un grade dans le fichier ServerSettings actif (voir section 3), puis ajoute ton UserId :
			Settings.Users = { [123456789] = "Owner" }
	   Ton UserId est dans l'adresse de ton profil : roblox.com/users/<UserId>/profile
	   Aucun compte ne reçoit de grade par défaut. Remplace 123456789 par ton propre UserId dans ce fichier actif.
	4) Lance Play. Clique sur le petit bouton « APM » en haut de l'écran ou appuie sur F2 pour ouvrir le panneau.
	   Z recentre la fenêtre. Dans l'Accueil, tu peux masquer le bouton et choisir une autre touche.
	5) Sauvegardes : le jeu publié utilise les DataStores. En Studio, le mode mémoire est activé par défaut
	   (Settings.StudioMemory = true) : les changements restent dans cette session. Pour tester les DataStores en Studio,
	   mets Settings.StudioMemory = false dans le ServerSettings actif ET active « Enable Studio Access to API Services »
	   dans Paramètres du jeu > Sécurité. Ces tests peuvent écrire dans les vraies sauvegardes.

	Bon à savoir
	• Le bouton APM vérifie 16 emplacements autour de l'écran pour ne pas cacher tes interfaces ; si tout est occupé,
	  il se place en bas à gauche par-dessus.
	• Quand le panneau est ouvert, il passe automatiquement devant toutes les interfaces du jeu.
	• Aucun code n'est téléchargé, aucun script n'est modifié pendant le jeu, rien n'est publié automatiquement.


	=====================================================================================================
	2. LANGUES DU PANNEAU
	=====================================================================================================

	7 langues : français (fr), English (en), español (es), português (pt), Deutsch (de), русский (ru), 中文 (zh).
	• Par défaut, chaque admin voit le panneau dans la langue de son compte Roblox.
	• Le bouton de langue en haut du panneau (ex. « FR v ») permet d'en choisir une autre ; le choix est mémorisé.
	• Les joueurs voient les annonces, avertissements et messages de mute dans leur propre langue.
	• Dans SharedConfig :
			Config.ForceLanguage = "fr"     -- même langue pour tout le monde (nil = langue du compte)
			Config.DefaultLanguage = "en"   -- langue de secours
	• Traductions : APM_Core > Shared > Lang > Tabs (un module par onglet, toutes les langues dedans). Les modules Lang > <langue> et Lang > Phrases restent disponibles pour vos propres textes.


	=====================================================================================================
	3. CONFIGURATION
	=====================================================================================================

	Modifie uniquement APM_Extensions > Config dans le dossier actif. Si ServerStorage.APM_Extensions existe déjà,
	il est prioritaire sur APM_Kit.APM_Extensions ; sinon, commence dans le dossier du kit. L'Accueil et les Diagnostics
	affichent le SourcePath actif et signalent les configurations en double : modifie d'abord le fichier indiqué.
	Ne modifie pas APM_Core : il est remplacé à chaque mise à jour.
	Les valeurs par défaut, commentées ligne par ligne, sont dans APM_Core > Server > Settings et APM_Core > Shared > Config.
	Pour changer une valeur, copie sa ligne dans ton fichier : elle remplace la valeur par défaut.
	• une table (ex. Settings.Funny = { MaxDuration = 30 }) ne remplace que les clés écrites ;
	• une liste (Ranks, ClientTools, ToolSources) est remplacée en entier ;
	• Settings.RemoveKeys = { "Clé" } supprime une valeur par défaut.

	ServerSettings (lu seulement par le serveur)
		Ranks               grades, du plus haut au plus bas (Id, Level, Color, Fixed, Name)
		SuperRank           "Dev" : accès configurables, personne ne peut le cibler
		ManagerRank         "Owner" : minimum pour l'onglet Paramètres
		AnnounceRank        "Staff" : peut faire une annonce à tout le serveur
		CreatorRank         nil par défaut : aucun grade automatique. Option "Owner" à activer explicitement pour le propriétaire de cette expérience (ou de son groupe), jamais pour l’auteur de l’APM.
		                    Pour activer cette option, enlève aussi "CreatorRank" de Settings.RemoveKeys, puis définis Settings.CreatorRank = "Owner".
		Users               grades FIXES par UserId (prioritaires, non modifiables depuis le panneau)
		DefaultUsers        grades de départ (modifiables ensuite dans le panneau)
		Group               { Id = groupe, Ranks = { [rang minimum dans le groupe] = "Grade" } }
		StudioRank          grade de test Studio facultatif (nil par défaut : aucun grade automatique) ; sans effet en ligne
		DataStoreName       "APM_Data_v1" : un seul DataStore pour tout l'APM (le changer repart de zéro)
		MessagingTopic      synchronisation des droits et des bans entre serveurs
		MaxLogs / MaxRoster / MaxWarnings   300 / 20000 / 25
		ToolSources         dossiers où chercher les Tool pour « Donner un outil » (ServerStorage par défaut)
		PermissionDefaults  grade minimum par défaut de chaque permission nommée (APM.*, Sentinel.*, Funny.*...)
		Modules             couper un système optionnel : { Simulation, AutoBridge, Sentinel, Funny, Assistant }
		Funny               { MaxDuration = 60, MaxActiveScenes = 16, MaxGroupTargets = 8, CrossServerEnabled = true }
		ClientTools         outils du joueur admin : { "Fly", "Noclip", "ESP", "Spectator" }
		DisabledCommands    retirer une commande : { Kill = true }
		AutoBridge          { Enabled, ScanInterval = 30, MaxScanInstances = 1500, EnableTeamActions = false }
		Sentinel            { Enabled, Mode = "Observation", Interval = 1, CorrectPosition = false, AllowKick = false }
		Assistant           { Enabled, MaxHistory = 40, ReplyStyle = "Short", ConfirmDangerous, AllowAll, MaxAllTargets = 25, RatePerWindow = 8, DefaultDeployed, WaveEnabled, WaveInterval = 30, AnimationSpeed, External = { Enabled = false, Hosts = {}, SecretName, ApiKey, Model } }  -- Sentinel 2.10.2

	SharedConfig (lu par le serveur ET les clients : rien de secret)
		ForceLanguage, DefaultLanguage, OpenKey (F2), RecenterKey (Z), Title, Theme (couleur par couleur),
		LauncherButton, MobileButton, LanguageButton


	=====================================================================================================
	4. SYSTÈMES
	=====================================================================================================

	GRADES
	• Par défaut : Dev (5) > Owner (4) > CoOwner (3) > Staff (2) > StaffTest (1).
	• Un admin n'agit que sur un grade STRICTEMENT inférieur au sien ; Dev ne peut jamais être ciblé.
	• Le grade d'un compte est le PLUS HAUT de ses sources : Users, créateur, panneau / DefaultUsers, groupe, Studio.
	• Les grades « Fixed » ne se donnent que dans la configuration, jamais depuis le panneau.
	• La liste des grades indique leur source et le grade qui restera après retrait d'une attribution du panneau.
	  Ce retrait ne révoque pas les accès fixes ou de groupe ; le propriétaire réel dispose d'une action séparée « Révoquer l'accès ».

	FONCTIONNALITÉS ET ACCÈS (onglet Paramètres)
	• Tout l'APM, par catégorie. La colonne « Actif » allume ou coupe une fonctionnalité pour tout le jeu ; les colonnes
	  de grades choisissent qui peut l'utiliser. Une ligne de catégorie coche tout d'un coup.
	• Dev suit le MinRank par défaut et les choix d'accès enregistrés pour son grade, comme les autres grades.
	• Orange = mélange ; grisé = hors de ta portée. L'accès au panneau et aux Paramètres n'est jamais retiré en masse.
	• Les changements sont enregistrés et synchronisés sur tous les serveurs (MessagingService).

	SÉCURITÉ (onglet Sécurité)
	• Les droits permanents, commandes et outils se règlent ensemble dans Paramètres > Fonctionnalités et accès,
	  avec une recherche. Sécurité ouvre ce même éditeur.
	• Teste un grade inférieur pendant cinq minutes. Choisis les permissions du test avec les cases à cocher ;
	  le JSON reste une option avancée. Seuls les droits réellement possédés sont sélectionnables. Reviens au grade réel
	  avec le bouton ou /apm-restore ; si le panneau disparaît, utilise le bouton de récupération dédié.
	• Simulation de grade : teste le panneau comme un grade inférieur pendant 5 minutes ; /apm-restore dans le chat
	  rend immédiatement ton vrai grade.
	• Modèle de sécurité : chaque admin reçoit ses propres remotes privés ; le serveur revérifie grade, accès,
	  hiérarchie, valeurs et anti-spam à chaque demande. Un joueur sans grade ne reçoit ni le panneau, ni le bouton,
	  ni aucun remote d'admin : seulement l'affichage public des annonces, avertissements et mutes.

	SAUVEGARDES
	• Un seul DataStore (APM_Data_v1) : grades, matrice d'accès, bans, avertissements, journal et annuaire des joueurs.
	• Écritures limitées pour économiser le budget : l'annuaire est enregistré par lots (environ toutes les 5 minutes),
	  les préférences seulement quand elles changent.
	• Sans DataStore (Studio sans accès API) : mode mémoire, rien n'est enregistré.

	ACCUEIL
	• État du serveur, performances (selon tes droits), joueurs connectés avec recherche et fiches détaillées,
	  résumés AutoBridge, Sentinel et diagnostics. Actualisation toutes les 15 s quand l'Accueil est visible.
	• Ouverture du panneau : afficher / masquer le bouton discret, changer la touche.

	STATISTIQUES (onglet Statistiques)
	• Graphiques : utilisation du panneau, joueurs, rendement du serveur (cycle, mémoire, réseau) et DataStores
	  les plus sollicités. Un point toutes les 15 s, gardé en mémoire sur le serveur (aucune écriture).
	• Pour suivre les DataStores de TON jeu (script serveur) :
			local ServerStorage = game:GetService("ServerStorage")
			local core = ServerStorage:WaitForChild("APM_Core", 10)
			local server = core and core:WaitForChild("Server", 10)
			local service = server and server:WaitForChild("APMService", 10)
			assert(service and service:IsA("ModuleScript"), "APMService indisponible.")
			local APM = require(service)
			APM.WaitForReady()
			local DataStoreService = game:GetService("DataStoreService")
			local store = APM.TrackDataStore(DataStoreService:GetDataStore("PlayerData"), "PlayerData")
			-- puis utilise store comme d'habitude (GetAsync, SetAsync, UpdateAsync...)

	JOURNAL (onglet Logs)  • Chaque action d'admin est inscrite (300 entrées), avec filtres par catégorie et gravité.
	BANNISSEMENTS          • Ban d'un joueur connecté ou d'un compte hors ligne (pseudo exact ou UserId), durée ou
	                         permanent, appliqué sur tous les serveurs ; débannissement dans l'onglet Bannissements.
	VERROU DU SERVEUR      • Empêche les joueurs sans grade de rejoindre ce serveur ; la maintenance l'utilise.

	SENTINEL GUARD (anti-triche)
	• Observe côté serveur les vitesses et téléportations anormales, avec tolérances (latence, apparition, siège,
	  physique). Modes : Observation (défaut), Équilibré, Strict.
	• Par défaut il ne fait que SIGNALER aux admins. Correction de position : option. Expulsion automatique :
	  seulement si Settings.Sentinel.AllowKick = true. Diagnostic synthétique pour tester sans vrai joueur.
	• « Origine des réglages » montre les valeurs effectives, celles du script et les choix sauvegardés ou limités à la session Studio.
	  « Revenir aux valeurs du script » supprime les choix enregistrés, y compris les zones sûres ajoutées dans le panneau,
	  et réapplique immédiatement le script ; ses zones sûres sont conservées.

	AUTOBRIDGE (intégrations)
	• Détecte ce que ton jeu utilise déjà : leaderstats, équipes, outils, sièges de véhicule.
	• N'exécute jamais de code inconnu. Changement d'équipe désactivé par défaut (EnableTeamActions).
	• Dans Accueil > Intégrations et réglages, consulte chaque valeur effective et son origine.
	  « Revenir aux valeurs du script » supprime les choix enregistrés et réapplique immédiatement les valeurs du script.

	FUNNY (effets amusants, onglet Funny)
	• ① Choisis un effet dans la grille (aperçu 3D à côté), puis ▶ LANCER ; ② règle énergie, durée, portée et cibles.
	• Décors : confettis, disco, canards, bulles, patate royale, système solaire, neige, cœurs, feu d'artifice, arc-en-ciel.
	• Transformations : grande tête, skin d'un compte Roblox, copier/échanger une partie du corps, gravité inversée,
	  personnage à l'envers (le joueur garde le contrôle de ses mouvements).
	• Portées : Local, Serveur, Interserveurs. Tout est temporaire, les cibles sont protégées par leur grade,
	  l'apparence est restaurée à la fin et un bouton d'arrêt est toujours disponible.

	DIAGNOSTICS : L'Accueil et les Diagnostics montrent la configuration active et les doublons. Les diagnostics des extensions
	indiquent le SourcePath, le champ invalide, la valeur reçue, la valeur attendue et la correction à effectuer.


	SENTINEL (assistant de commandes flottant) et SENTINEL HELPER — nouveau en 2.10.2
	(à ne pas confondre avec Sentinel Guard, l'anti-triche ci-dessus)
	• Sentinel est une petite fenêtre déplaçable, indépendante du panneau : elle reste à l'écran quand l'APM est fermé.
	  Tapez une commande (fly, freeze bob, bring bob, speed bob 50, unfly me, kick bob spam...). C'est un moteur LOCAL à règles,
	  pas une IA générative : aucune connexion Internet n'est nécessaire. help liste les commandes utilisables,
	  help <commande> donne le détail, clear vide l'historique.
	• Les commandes sont celles de l'APM : chaque module et outil client du registre (Joueurs, Modération, Jeu, Bans, vos extensions).
	  Cibles : me, all, un pseudo exact, un UserId ou un nom partiel qui ne désigne qu'UN joueur (plusieurs correspondances :
	  Sentinel demande de préciser). Alias : tp, vitesse, geler... (français et anglais).
	• Sécurité : le client n'envoie que du texte. Le serveur vérifie identité, grade, permissions, hiérarchie (les grades protégés
	  le restent), bornes des arguments et fréquence (8 commandes / 10 s par défaut) avec le même code que les boutons du panneau.
	  Les commandes sensibles (kick, ban, shutdown) demandent une confirmation. Aucun code n'est jamais évalué. « all » est refusé pour kick / ban.
	• fly / noclip / esp / spectate ne concernent que VOUS (outils client) : le serveur autorise, votre appareil applique et Sentinel
	  confirme seulement après coup. speed / jump acceptent un joueur et all : speed bob 50, speed all 20.
	• Fenêtre : déplacez l'en-tête ou la poignée de gauche ; deux flèches indépendantes replient la zone de discussion (flèche du haut)
	  et la zone de saisie (flèche latérale) ; les deux repliées : il ne reste qu'une flèche, non déplaçable, qui restaure tout.
	  Position et repli sont enregistrés par compte. L'onde de nuances des flèches passe toutes les 30 s (réglable, désactivable).
	• Accueil : l'interrupteur Sentinel l'active ou le désactive pour votre compte (l'APM peut rester fermé).
	• Onglet Sentinel Helper (groupe Développement) : mes préférences (locales) / réglages du serveur (tout le monde) / commandes
	  personnalisées / IA externe facultative / test du moteur / stockage. Permissions : Assistant.Use (StaffTest), Assistant.Configure,
	  Assistant.Commands, Assistant.External (Owner). Réglages enregistrés dans le DataStore de l'APM (SuiteSettings_v2, section
	  SentinelAssistant) ; le mode mémoire de Studio ne les garde que pour la session.
	• Les commandes personnalisées sont des DONNÉES (nom, arguments, permission, une action autorisée : répondre un texte, se
	  téléporter vers un point, lancer jusqu'à 5 commandes existantes). Jamais du code Lua. Chaque étape s'exécute avec les droits de celui qui tape.
	• IA externe (facultative, désactivée par défaut) : exige Settings.Assistant.External dans ServerSettings (Hosts = { "api.exemple.com" },
	  SecretName ou ApiKey) et les requêtes HTTP activées. La clé n'atteint jamais les clients ni le DataStore. L'IA ne voit que le texte tapé
	  et les noms de commandes ; elle propose une commande que VOUS confirmez et que le serveur valide comme toute autre.
	• ServerSettings : Settings.Assistant = { Enabled, MaxHistory, ReplyStyle, ConfirmDangerous, AllowAll, MaxAllTargets, RatePerWindow,
	  DefaultDeployed, WaveEnabled, WaveInterval, AnimationSpeed, External = {...} } ; Settings.Modules.Assistant = false le coupe.

	LANGUES DES COMMANDES DE SENTINEL (7 langues) — reconnaissance multilingue
	• Sentinel comprend en même temps le français, l'anglais, l'espagnol, le portugais, l'allemand, le russe et le chinois. La langue de
	  saisie est INDÉPENDANTE de la langue du panneau : interface en français, commande en russe puis en chinois, sans rien changer.
	  Toutes les formulations mènent à UNE action canonique (le nom du module : Fly, Freeze, Kick...) ; permissions, protections,
	  confirmations et journal sont exactement ceux de la commande anglaise. Une traduction n'accorde jamais rien de plus.
	• Exemples (toutes = Fly) : fly · voler · volar · voar · fliegen · летать · 飞行 (飛行). Formes d'arrêt : unfly · arrêter de voler ·
	  dejar de volar · parar de voar · stopp fliegen · перестать летать · 停止飞行. On peut mélanger : « voler all », « fly tous ».
	  Majuscules, accents et lettres / espaces pleine largeur sont indifférents (é = e, ß = ss, ё = е, Ｆｌｙ = fly). Le chinois simplifié
	  et traditionnel sont listés un par un. Aucune devinette : une commande inconnue reste inconnue (suggestions seulement).
	• Cible, trois formes identiques dans toutes les langues :
	    – sans cible : la commande qui accepte une cible vous vise VOUS (fly, unfly, noclip, speed 50...) ;
	    – un pseudo : fly Bob (jamais traduit ni modifié ; un début de pseudo unique est accepté, l'ambiguïté est refusée) ;
	    – all (tous, todos, alle, все, 所有人...) : tous les joueurs autorisés, TOUJOURS après une confirmation qui nomme l'action
	      canonique, le sens (arrêt) et le nombre de joueurs. Une cible absente n'est JAMAIS « all ».
	  « me » : me, moi, yo, eu, ich, я, 我... Les commandes qui exigent une cible (kick, freeze, bring...) la gardent obligatoire ;
	  spectate garde son sens (observer un joueur, en local) ; esp reste local.
	• Confirmations : tout « all » demande désormais confirmation (même avec ConfirmDangerous = false). Elle est liée à l'action CANONIQUE,
	  à son sens et aux joueurs réellement résolus : autre commande, autre sens, autre liste de joueurs ou jeton expiré (20 s) = on redemande.
	• Un mot réservé qui est aussi le pseudo d'un joueur présent (un joueur nommé All, Ich, On...) n'est jamais deviné : Sentinel demande
	  de préciser avec @identifiant (ou @pseudo ; @me et @all restent les sélecteurs).
	• Les réponses suivent la langue des réglages de l'APM, pas la langue tapée.
	• Commandes personnalisées : leurs noms restent ASCII ; un nom ou alias déjà pris par une formulation officielle de N'IMPORTE QUELLE langue
	  est refusé (la formulation officielle l'emporte ; conflits listés dans Sentinel Helper > Stockage). Une étape « fly all » demande toujours confirmation.
	• Sentinel Helper > « Langues des commandes » : formulations officielles par langue (lecture seule) ; le Test du moteur affiche la langue reconnue,
	  l'action canonique, le sens, la cible et la confirmation éventuelle.
	• Développeurs : les formulations sont dans Server > Core > Assistant > CommandLocalization (un ModuleScript par langue : Commands, Off, OffPrefixes,
	  Selectors, Booleans, Units, Local, Choices). Ajouter une 8e langue = ajouter un ModuleScript enfant nommé d'après son code (même forme que fr / en),
	  sans rien modifier d'autre. Une formulation qui désignerait deux actions est écartée et signalée (Report().Collisions) ; une formulation partagée
	  par deux langues pour la MÊME action est normale.
	• Limites : commandes structurées seulement (aucune compréhension de phrases libres) ; en chinois, un espace sépare la commande et ses arguments ;
	  un mot qui est sélecteur ou on / off dans une langue est réservé dans toutes ; décimales « 1,5 » acceptées, « 1,000 » refusé (ambigu).

	=====================================================================================================
	5. MODULES
	=====================================================================================================

	Chaque module peut être coupé ou réservé à certains grades dans Paramètres > Fonctionnalités et accès.

	ONGLET JOUEURS (choisis un joueur, puis l'action)
		Expulser (Kick) · Bannir (Ban) · Avertir (Warn) · Rendre muet (Mute) · Geler (Freeze) · Tuer (Kill)
		Soigner (Heal) · Réapparaître (Respawn) · Amener à toi (Bring) · Aller à lui (Teleport)
		Renvoyer (Return) · Au spawn (ToSpawn)
		Motif et durée (en minutes, vide = définitif) pour Kick, Ban, Warn, Mute et Freeze.
		Vue « Global » : annuaire de tous les comptes déjà venus, même hors ligne.

	ONGLET MODÉRATION (sur toi-même)
		Godmode (santé infinie) · Invisible · Vitesse · Saut
		Outils : Fly (voler), Noclip (traverser les murs), ESP (voir les joueurs à travers les murs), Spectator (observer)
		Annonce à tout le serveur.

	ONGLET JEU
		Donner un outil (GiveTool) · Leaderstats (modifier une valeur) · Heure du jeu (TimeOfDay)
		Maintenance du serveur (Shutdown) : verrouille, annonce et expulse les joueurs sans grade après le délai.

	ONGLET BANNISSEMENTS
		Liste des bans, débannir (Unban), bannir un compte par pseudo exact ou UserId.


	=====================================================================================================
	6. EXTENSIONS (POUR LES DÉVELOPPEURS)
	=====================================================================================================

	Ajoute tes extensions au dossier APM_Extensions actif. APM_DeveloperTemplates est inactif : commence par START_HERE
	et copie uniquement les exemples utiles dans les dossiers actifs correspondants.
	• Commands.MonJeu.MonJeu_Informer : copie le dossier MonJeu dans Commands.
	• ClientPages.MonJeu.MonJeuPage : copie le dossier MonJeu dans ClientPages.
	• Server.MonJeuIntegration et Adapters.MonJeuStatus : copie chaque ModuleScript dans son dossier correspondant.
	Choisis un nom de commande et un namespace uniques. Aucune permission n'est ajoutée automatiquement : déclare
	MonJeu.Page / MonJeu.Status dans Settings.PermissionDefaults du ServerSettings actif, avec le grade minimum choisi.
	Relance Play après une modification de source ou de configuration.

	A) Une commande : un ModuleScript dans APM_Extensions > Commands
		return {
			ApiVersion = 1,
			Name = "Confettis",              -- identifiant unique (lettres, chiffres, _ - .)
			Category = "Players",            -- Players, Moderation, Game... ou ta propre catégorie
			Mode = "target",                 -- "action" | "target" (un joueur) | "toggle" | "slider"
			MinRank = "Staff",               -- grade minimum par défaut
			Label = { fr = "Confettis", en = "Confetti" },
			Description = { fr = "Lance des confettis.", en = "Throws confetti." },
			-- facultatif : Group, Order, Color, Confirm, AllowSelf, Min / Max / Default (slider),
			--             Fields = { { Name = "Montant", Type = "number", Min = 1, Max = 100 } },
			--             Inputs = { "Reason", "Minutes" }, Init = function(ctx) end, OnAccessRevoked = function(ctx, player) end
			Execute = function(ctx, admin, target, value)
				-- le serveur a déjà vérifié le grade, l'accès, la hiérarchie et les valeurs
				return true, "Confettis lancés !"   -- (succès, message affiché à l'admin)
			end,
		}
		Types de champs : "number", "choice" (Options), "text", "string". Chaque exécution est inscrite au journal.

	B) Une intégration serveur : un ModuleScript dans APM_Extensions > Server
		return { ApiVersion = 1, Id = "MonJeu", Init = function(api)
			-- api.RegisterCommand(commande), api.RegisterOptions(nom, fournisseur), api.AddProfileProvider(fn),
			-- api.RegisterAdapter(nom, adaptateur), api.HasPermission(joueur, permission), api.CanTarget(admin, cible),
			-- api.Authorize(admin, commande, cible), api.Notify(joueur, message, succès), api.Log(acteur, action, cible, détail)
		end }
	Enregistre les commandes directement dans Init(api), avant toute tâche différée, et vérifie les résultats.
	N'appelle pas APM.WaitForReady() dans Init : l'APM attend déjà que cette initialisation soit terminée.

	C) Un adaptateur AutoBridge : APM_Extensions > Adapters  →  { ApiVersion = 1, Id = "...", Adapter = { Permission, Probe, Actions } }
	D) Une page du panneau : APM_Extensions > ClientPages > MonJeu > MonJeuPage (ModuleScript dans son dossier de namespace).
	   Garde les attributs du ModuleScript ApiVersion = 1 et Permission = "MonJeu.Page". Déclare explicitement
	   Settings.PermissionDefaults = { ["MonJeu.Page"] = "Owner" } dans le ServerSettings actif ; choisis ton grade minimum.
	   Retourne une table avec ApiVersion = 1, la même Permission, un Id valide et unique = "MonJeuPage", et Build(Core, page).
	   Label et Order sont facultatifs, comme Visible(Core). Handles ne peut lister que les catégories de ce namespace.
	   Les Id utilisent lettres, chiffres, _, . ou - et ne doivent pas reprendre un Id de l’APM.
	   Le modèle fonctionnel est APM_DeveloperTemplates.ClientPages.MonJeu.MonJeuPage. La page n'est envoyée qu'aux admins
	   autorisés. Aucun secret dans le code client. Utilise Core.On(signal, callback) pour les connexions et
	   Core.Action(command, target, value) pour les commandes serveur autorisées.

	E) Depuis tes autres scripts serveur :
		local ServerStorage = game:GetService("ServerStorage")
		local core = ServerStorage:WaitForChild("APM_Core", 10)
		local server = core and core:WaitForChild("Server", 10)
		local service = server and server:WaitForChild("APMService", 10)
		assert(service and service:IsA("ModuleScript"), "APMService indisponible.")
		local APM = require(service)
		APM.WaitForReady()
		APM.IsAdmin(joueur)  APM.GetRank(joueur)  APM.HasRankAtLeast(joueur, "Staff")
		APM.Notify(joueur, texte, succès)  APM.Log(acteur, action, cible, détail, catégorie, "info"|"warning"|"danger")
		APM.AddProfileProvider(fn)  APM.RegisterOptions(nom, fn)  APM.TrackDataStore(store, "Nom")

	L'état des extensions (chargées / erreurs) s'affiche dans l'onglet Diagnostics.


	=====================================================================================================
	7. MISES À JOUR ET AIDE
	=====================================================================================================

	• Mettre à jour : remplace APM_Kit par la nouvelle version. Garde ton dossier APM_Extensions : une configuration
	  externe ServerStorage.APM_Extensions compatible est conservée et prioritaire. Ne modifie jamais APM_Core.
	• Le panneau ne s'ouvre pas ? Vérifie ton grade (Settings.Users), que ToolboxBootstrap est activé et que le kit
	  n'est pas seul dans ServerStorage. La sortie (Output) affiche « [APM] Serveur prêt » quand tout va bien.
	• Bloqué dans une simulation de grade ? Tape /apm-restore dans le chat.
	• « Mode mémoire » affiché ? Normal en Studio : rien n'est enregistré pendant tes tests.


	JOURNAL DES CHANGEMENTS 2.10.2
	• NOUVEAU : Sentinel, assistant de commandes flottant (déplaçable, deux flèches de repli indépendantes, mode ultra-compact).
	• NOUVEAU : onglet Sentinel Helper (préférences, réglages serveur, commandes personnalisées, IA externe facultative, test du moteur).
	• NOUVEAU : interrupteur Sentinel dans l'accueil ; préférences par compte (position, repli, taille, animation).
	• NOUVEAU : permissions Assistant.Use / Configure / Commands / External ; catégorie « Sentinel (assistant) » dans Fonctionnalités et accès.
	• NOUVEAU : speed et jump acceptent une cible (speed bob 50) ; freeze et mute exposent leur état (jamais de bascule par erreur).
	• CHANGEMENT : APMService.perform est le cœur d'exécution commun des boutons du panneau et de Sentinel (mêmes contrôles, même journal).
	• CHANGEMENT : Preferences accepte 4 champs personnels (AssistantEnabled, AssistantLayout, AssistantWave, AssistantScale) ; SuiteConfig accepte la section SentinelAssistant.
	• NOUVEAU : actions distribuées (Dispatcher + ActionExecutor) : Fly et Noclip s'appliquent aussi aux autres joueurs (« fly bob », « fly all », « unfly bob », « noclip bob »), validés par le serveur, exécutés sur l'appareil de la cible et confirmés par lui.
	• NOUVEAU : chaque action distribuée est contrôlée par le serveur (grade, droit sur l'outil, hiérarchie : « all » ne contourne jamais une protection), porte un identifiant unique avec expiration et se termine par un bilan chiffré (affectés, protégés, échecs, non confirmés). La réponse d'un client est une confirmation, jamais une preuve absolue : le serveur vérifie ce qu'il peut (Fly : état du Humanoid ; Noclip : collisions).
	• NOUVEAU : onglet Joueurs, carte « Pouvoirs sur le joueur » (bascule sur le joueur choisi, boutons « tous » avec confirmation) ; « spectate bob » observe un joueur ; « esp bob » est refusé volontairement (l'ESP est une vue locale, jamais donnée à un autre joueur).
	• CHANGEMENT : Fly et Noclip partagent UN seul contrôleur (APM_Shared > ActionExecutor > Effects) entre l'interrupteur du panneau et le serveur : aucun doublon. Nouveaux remotes : ActionDispatch / ActionReport (publics, réponses seulement), DispatchAction (panneau admin).
	• CHANGEMENT : « all » sur une commande serveur donne un bilan « Freeze : 8 affecté(s), 2 protégé(s), 0 échec(s), 1 ignoré(s) ».
	• Développeurs : ajouter une action distribuée = la déclarer dans ActionCatalog + un contrôleur dans ActionExecutor/Effects (+ Dispatcher/Hooks facultatif) ; Settings.Modules.Dispatcher = false la désactive. Rien n'est enregistré : les effets cessent quand le joueur part.
	• Aucune migration de données : DataSchemaVersion reste 2 ; configurations et sauvegardes existantes intactes.
	• NEW : Sentinel multilingue : commandes en français, anglais, espagnol, portugais, allemand, russe et chinois en même temps, indépendamment de la langue de l'interface ; une seule action canonique, mêmes permissions, protections et confirmations.
	• NEW : cible implicite : « fly », « unfly », « noclip » agissent sur vous ; « fly Bob » vise un joueur ; « fly all » (et ses traductions) demande toujours confirmation.
	• CHANGE : toute cible « all » est confirmée (kill, freeze, mute, heal, respawn, bring, speed, jump, fly, noclip), même avec ConfirmDangerous = false ; la confirmation est liée à l'action canonique et aux joueurs résolus.
	• CHANGE : un mot réservé qui est aussi un pseudo présent (All, Ich, On...) est ambigu : utiliser @identifiant.
	• NEW : carte « Langues des commandes » dans Sentinel Helper, Test du moteur enrichi ; normalisation Unicode (cyrillique, chinois, pleine largeur, accents) ; longueur en caractères (200), pas en octets.
	• Développeurs : CommandLocalization (un ModuleScript par langue) ; une 8e langue = un ModuleScript de plus.

	• NOUVEAU : « help » ouvre un catalogue interactif : TOUTES les commandes du registre en grille de 3 colonnes. Une commande que vous n'avez pas le droit de lancer porte un cadenas (calculé par le serveur ; il ne donne aucun droit). Toucher une commande la PRÉPARE seulement dans le champ de saisie (jamais exécutée).
	• NOUVEAU : autocomplétion : commandes et alias (7 langues), joueurs (pseudo, nom affiché, @UserId), sélecteurs, on/off et durées valables pour la commande ; flèches pour parcourir, Tab pour compléter, Entrée envoie (ou complète une suggestion choisie aux flèches), Échap ferme. Seules les commandes enregistrées et permises sont proposées ; calcul local, aucune requête à chaque frappe.
	• NOUVEAU : durées : 10s · 5m · 2h · 1d (et leurs traductions). Une durée qu'une commande ne sait pas honorer est refusée avec un message : ban travaille en minutes entières (30s et 0,5 sont refusés au lieu de devenir un bannissement définitif) ; un format inconnu (1w) n'est jamais avalé dans le motif.
	• CORRECTION : l'Accueil et Sentinel Helper lisent le même état : éteindre Sentinel depuis l'Accueil s'affiche aussitôt dans Sentinel Helper (et inversement) ; fermer l'APM ne le change jamais.
	• CHANGEMENT : la flèche de la zone de saisie suit la position de la fenêtre (moitié gauche : repli vers la gauche ; moitié droite : vers la droite) ; les flèches ont une discrète pastille sombre pour rester visibles sur fond clair.

	Licence MIT · Gratuit · Créé par APM contributors

]==]
return {}
