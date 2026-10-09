# APM — audit de l'architecture avant séparation Core / Extensions

Audit en lecture seule des sources exportées dans `work/apm-next`, le 9 octobre 2026. Cet audit ne remplace pas la vérification de l'état réel du DataModel par MCP : il décrit le code disponible sur disque avant les nouvelles modifications structurelles. Les résultats des tests Studio précédents sont distingués de cette lecture de code.

## Architecture et démarrage existants

L'inventaire réel contient **72 fichiers Luau**. Le fichier `manifest.json` présent dans ce dossier reste l'ancien manifeste de 59 sources, avec chemins sous Workspace et tailles historiques ; il ne décrit pas le kit courant.

L'installation actuelle répartit quatre ensembles officiels : `ServerScriptService.APM_Server`, `ReplicatedStorage.APM_Shared`, `ServerStorage.APM_ClientTemplates` et le LocalScript public `StarterPlayer.StarterPlayerScripts.APM_Notices`. Le kit source reste privé sous `ServerStorage.APM_Kit`.

`APM_Installer` refuse le mode Play, vérifie le schéma du kit et les collisions, prépare des clones des quatre composants, puis les insère en Edit avec points d'historique. Il n'existe pas de gestion des mises à jour dans cet installateur : une installation déjà présente est refusée. Le commentaire d'`APM_Boot` et son message d'erreur parlent encore de l'ancien placement Workspace et d'installation automatique ; ils doivent être corrigés.

Le serveur démarre par `APM_Boot`, ne démarre pas sous un objet portant l'attribut `APM_Kit` et réclame une instance serveur unique via `Remotes.Claim("Server")`. `APMService.Init` crée un contexte et initialise grades, configuration, préférences, journal, annuaire, contrôles, matrice et profils. Il charge ensuite les commandes natives, puis Simulation, AutoBridge et Sentinel, branche les endpoints et lance les sessions privées. Un second `Init` est ignoré.

L'API publique existante expose notamment `WaitForReady`, `IsAdmin`, `GetRank`, `HasRankAtLeast`, `Notify`, `Log`, `RegisterOptions` et `AddProfileProvider`. Les services propres au jeu peuvent être injectés via `Init(deps)` puis consultés dans `ctx.Game`. Modifier directement `APM_Boot` pour les injecter mêle aujourd'hui personnalisation et code officiel.

## Fonctionnalités réutilisables

Le dossier serveur `Modules` contient 21 commandes : Ban, Bring, Freeze, GiveTool, Godmode, Heal, Invisible, JumpPower, Kick, Kill, Leaderstats, Mute, Respawn, Return, Shutdown, Speed, Teleport, TimeOfDay, ToSpawn, Unban et Warn. Son scan accepte les ModuleScripts et les sous-dossiers. Chaque module doit renvoyer une table avec `Execute` ; `Init` et `OnAccessRevoked` sont facultatifs. Les noms dupliqués sont rejetés, le classement est déterminé par Order puis Name.

Les commandes profitent du chemin de validation existant : accès au panneau, matrice de permission, hiérarchie des cibles, validation des champs, fréquence, confirmation côté UI lorsque déclarée, notification et journal. Les extensions doivent réutiliser ce chemin. Lorsqu'une commande personnalisée attend avant une mutation, elle doit également réutiliser `ctx.Authorize` juste avant la mutation ; le Core ne peut pas intercepter le code arbitraire interne à `Execute`.

`Shell` découvre les enfants ModuleScript directs de `APM_Client.Pages`, appelle leur fonction `Build`, et génère des onglets à partir des catégories de commandes sans page dédiée. `Visible` détermine l'affichage, mais ne constitue pas une autorisation serveur. `Profile` est une page secondaire. L'interface officielle est construite à partir de `UI`, `Core`, `Shell`, `CategoryPage`, des pages et des outils client, sans nouvelle fenêtre spécifique AutoBridge.

Home est le premier onglet et remplace les préférences historiques vers AutoBridge. Le endpoint privé `GetHomeSnapshot` construit les chiffres à partir du serveur réel, d'AutoBridge, de Sentinel et des diagnostics de la session. Ses sections facultatives sont filtrées par permission, puis refiltrées après les appels susceptibles d'attendre. Le composant `AutoBridgePanel` contient les interactions avancées dans Home. Les compteurs dénombrent des rapports par état, sans additionner des unités comme outils, équipes et statistiques.

L'audit et les tests précédents d'Accueil ont validé un démarrage réel, des fixtures réelles en Play, une erreur d'adaptateur, l'affichage d'alertes de test, les restrictions de lecture/configuration et le retrait d'une permission pendant une attente. Voir `Accueil-APM-Validation.md`. Cette étape ne transforme pas l'existence d'une interface en preuve de fonctionnement d'intégrations économiques inconnues.

## AutoBridge et Sentinel

`AutoBridge.RegisterAdapter(id, adapter)` est une API serveur explicite existante. Un adaptateur déclare `Probe(ctx)`, `Actions` et éventuellement sa permission de consultation. Chaque action déclare une permission, `Validate`, `Execute` et, au besoin, une cible. Les collisions sont refusées. La découverte structurelle est bornée ; aucun script découvert n'est automatiquement exécuté. Les rapports filtrent les permissions des adaptateurs et des actions. Les actions vérifient la compatibilité courante et revalident permissions et hiérarchie après les validateurs susceptibles d'attendre.

Les diagnostics natifs concernent leaderstats, équipes, outils et VehicleSeat, ainsi que des marqueurs explicites. Un siège ou un tag ne prouve pas une compatibilité avec le service métier du jeu. Les intégrations économiques, inventaires, véhicules et quêtes doivent passer par un adaptateur explicitement écrit pour les services réels du jeu.

Sentinel Guard est le service runtime serveur `Core.Sentinel`. Il échantillonne les mouvements, produit des alertes heuristiques et tient ses états en mémoire. Il supporte Observation, Balanced et Strict, des exceptions de durée limitée (`Exempt`, `NotifyServerTeleport`), des tests synthétiques identifiés et la configuration persistée. Observation est le défaut. Correction de position et kick restent désactivés par défaut ; un kick nécessite également l'autorisation serveur explicite `Settings.Sentinel.AllowKick`. Les mécanismes de déplacement propres au jeu doivent déclarer leurs exceptions côté serveur.

Le plugin **Sentinel Audit** existe sous forme de sources autonomes et de `.rbxmx` dans `work/sentinel-audit` et `outputs`. Il lit les sources Studio et ne dépend pas du runtime APM. Son scanner est lexical et heuristique. L'artefact fourni ne prouve pas que le plugin est installé localement ; les documents précédents déclarent son installation et son widget comme essais manuels à effectuer. Son installateur facultatif APM connaît le contrat historique à quatre composants ; il faudra le faire évoluer ou documenter son incompatibilité avec un nouveau contrat.

## Grades, permissions et transport

`Settings` définit les grades Dev, Owner, CoOwner, Staff et StaffTest, leurs niveaux, les comptes fixes et initiaux, le groupe, le propriétaire de l'expérience et le grade Studio. Le grade effectif est le maximum des sources, avec une attribution prioritaire du propriétaire réel stockée séparément. Le grade simulé reste borné par le contexte réel et expire après cinq minutes. La hiérarchie protège les grades supérieurs ou égaux et le propriétaire réel.

Les permissions nommées passent par la même matrice persistée `Access`. `HasRealPermission` exige un joueur présent, des données de sécurité chargées et une déclaration de permission dans `Ranks.Defaults`. Une permission custom non déclarée est donc refusée. Les permissions dédiées sont configurables même pour le SuperRank ; les anciennes commandes conservent son comportement historique.

`Sessions` clone les sources du panneau privé et les remotes administratifs seulement dans le PlayerGui des joueurs autorisés. Le serveur vérifie identité de l'appelant, session active, accès courant, fréquence et structure du payload. La révocation invalide la session immédiatement, appelle les nettoyages, supprime l'interface et retire le transport après les appels en cours. Une session réduite existe seulement pour restaurer une simulation. Seules Announcement, Warned et Muted sont publiques.

Les listes d'endpoints sont actuellement fixes dans `APM_Shared.Remotes`. Une extension ne peut pas créer implicitement un nouvel endpoint en assignant une propriété du contexte. Le chemin des commandes et `AutoBridgeAction` suffit pour beaucoup d'intégrations. Un éventuel nouvel appel générique doit passer par un registre serveur explicite, avec permission, validation, fréquence et revalidation après attente, plutôt que par des remotes publics arbitraires.

## Persistance et migrations

Le DataStore conserve son nom historique `APM_Data_v1` par défaut. Les clés existantes sont `Ranks`, `Access`, `Bans`, `Journal`, `Roster`, `Warn_<userId>`, puis les clés additives `OwnerAuthority_v2`, `SuiteSettings_v2` et `Preferences_v2_<userId>`. Les opérations sensibles utilisent `UpdateAsync`, des révisions pour les droits et des autorisations revérifiées dans le callback. Grades et accès sont synchronisés entre serveurs via MessagingService et relectures périodiques. Les bans sont relus périodiquement. Le verrou de serveur, la simulation, les états des outils client et les échantillons/alertes Sentinel sont locaux au serveur.

`SuiteConfig` n'enregistre que les sections AutoBridge et Sentinel avec schéma 2. Il refuse un schéma inconnu et applique une configuration seulement après confirmation de sauvegarde. Les préférences sont sauvegardées périodiquement et au départ/fermeture. Le mode mémoire Studio est explicitement activé par `Settings.StudioMemory=true`, sans écritures dans les sauvegardes publiées. Une panne de données dans un serveur publié n'est pas transformée en mode mémoire permissif.

Il n'existe pas encore de version sémantique Core centralisée, de registre formel de migrations ni de procédure générale de rollback. Les schémas v2 sont déjà additifs et doivent rester lisibles sans réécrire destructivement les tables v1. Une migration de code et un rollback de code ne sont pas équivalents à restaurer les données sauvegardées.

## Séparation minimale recommandée

Le contenu officiel actuel doit être conservé et enveloppé dans un seul root Core versionné. Les chemins internes du serveur restent aussi stables que possible ; les emplacements publics nécessaires et les clones de sessions doivent être matérialisés à partir de ce root avec un identifiant/version communs. La nouvelle source de vérité doit être explicite afin qu'une mise à jour ne laisse pas tourner une copie installée obsolète à côté du Package.

Un root indépendant `APM_Extensions` appartient au développeur : Settings serveur, Config publique, commandes, pages client, adaptateurs et services d'intégration. Il ne doit être ni un enfant du Package Core ni une destination remplacée par l'installateur de mises à jour. Les données persistées restent externes aux sources du Package.

Les hooks nécessaires sont peu nombreux :

1. Fusionner des defaults officiels avec les réglages développeur avant le chargement de Ranks. Valider les champs structurants et ne jamais repartir silencieusement sur des autorisations plus larges si un module de configuration custom échoue.
2. Charger d'abord les commandes officielles, puis les commandes déclarées dans les extensions avant `InitModuleAccess` et `Sessions.Init`. Refuser les collisions et garder une provenance dans les diagnostics.
3. Charger les adaptateurs serveur explicitement déclarés après `AutoBridge.Init` et avant Ready. Les présenter avec les rapports Home existants.
4. Copier uniquement les pages/composants client autorisés dans les sessions privées, puis étendre la découverte du Shell. Exiger un Id, une permission déclarée et un Build ; rejeter les Id réservés/collisions avant tout require client.
5. Garder la configuration partagée cohérente avec `Lang`, qui requiert lui aussi `APM_Shared.Config`. Un override uniquement dans Core client ne suffit pas pour ForceLanguage et DefaultLanguage.
6. Exposer une API d'extension versionnée autour des hooks existants, avec un contexte limité et une procédure de nettoyage. Documenter qu'un module serveur local de développeur reste du code de confiance pouvant volontairement accéder aux services Roblox.

Doivent rester hors Package : extensions et configurations du développeur, sauvegardes de restauration, DataStores, intégrations de l'expérience, artefacts d'audit, plugin Studio et ses réglages locaux. Les pages, commandes et réglages officiels peuvent être inclus dans le Package avec leurs defaults ; leur personnalisation doit passer par les extensions.

## Contrôles à effectuer pendant la modification

Conserver la sauvegarde originale et la sauvegarde avant Home, puis créer une troisième restauration indépendante avant la séparation. Vérifier par MCP les sources actives et les liens de Package existants avant de les remplacer. Ne pas considérer le manifeste historique comme une preuve de synchronisation.

Les essais pertinents sont : démarrage unique, Home inchangé, commande extension avec permissions/hiérarchie, page extension sans seconde GUI, adaptateur extension réel visible dans Home, configuration custom conservée après remplacement du Core, collision refusée, erreur d'extension diagnostiquée, révocation pendant attente et rollback du code sans modification des clés historiques. La publication et le comportement des Packages demandent leurs propres contrôles Studio ; aucune lecture locale ne prouve la propagation à des serveurs déjà en cours d'exécution.
