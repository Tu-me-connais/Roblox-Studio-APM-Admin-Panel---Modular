# APM Core et Extensions — validation du 9 octobre 2026

## Résultat installé via MCP

L'expérience confirmée `118486791701544` utilise maintenant `ServerStorage.APM_Core`, `ServerStorage.APM_Extensions` et `ServerScriptService.APM_Bootstrap`. Il s'agit de **2.1.0-preview.1**, canal **experimental**, licence **MIT**. Aucun Package Roblox, dépôt GitHub ou changement de place n'a été publié. Studio est laissé en mode Edit.

Le Core contient 75 sources : services officiels requis directement depuis le modèle privé, navigation et composants clients, Home avec AutoBridge, 21 commandes natives, grades et permissions, sessions, Sentinel Guard, API d'extensions, versions et contrôle des migrations. La configuration de l'expérience est dans les deux ModuleScripts externes Config.ServerSettings et Config.SharedConfig. Leurs valeurs actuelles ont été conservées.

Les dossiers Commands, Adapters, Server et ClientPages sont à l'extérieur du Core. Les commandes réutilisent la validation, la hiérarchie, les permissions, le transport privé et le journal existants. Les pages sont copiées uniquement dans les sessions autorisées ; une modification de leurs permissions renouvelle la session. Les adaptateurs sont explicitement enregistrés et restent visibles dans Home, sans onglet AutoBridge indépendant. Les exemples sont livrés hors Core et ne sont pas activés dans la Baseplate finale.

Le bootstrap conserve un contrat externe minimal. Il charge le Core courant, génère les composants partagés depuis cette version et distribue les notices publiques. Il refuse les collisions avec une installation ancienne, les contrats inconnus et une version expérimentale sans opt-in. Il ne télécharge aucun code et n'écrit pas Source au runtime.

## Audit et sauvegardes avant modification

Avant la nouvelle structure, les 72 sources du kit réel ont été comparées aux sources locales, puis les 70 sources actives aux mêmes références : aucune différence. Un démarrage Play a confirmé dix onglets, Home par défaut, AutoBridge et Sentinel, les sessions privées et 21 commandes chargées. Le fonctionnement ne repose donc pas seulement sur la présence d'une interface.

La sauvegarde `ServerStorage.APM_RestorePoints.APM_Original_20261009` est conservée. Un point indépendant `APM_BeforeCoreExtensions_20261009` a été créé avant les changements ; il contient les branches du kit et de l'installation active (142 sources dans le premier instantané). Les anciennes instances ont ensuite été conservées sous RetiredInstances dans ce même point, avec leurs emplacements et états Disabled précédents. Elles ne constituent plus une installation active.

Le plugin Sentinel Audit existe comme sources locales et modèle exporté séparé. L'inventaire des interfaces de plugins Studio ne l'a pas montré comme plugin installé ; cette installation n'est donc pas certifiée. Sentinel Guard runtime a été démarré et interrogé.

## Essais exécutés

| Scénario | Résultat observé |
| --- | --- |
| Compilation | Toutes les sources runtime, installation, exemples et tests compilent avec loadstring en Edit ; les 75 sources du Core installé sont comparées aux fichiers livrés. |
| Pages personnalisées, tests isolés | 42 assertions : contrôle avant require, API, collisions, Handles, tri, permissions retirées pendant découverte et arrêt de session. |
| Registre serveur, tests isolés | 74 assertions : contrats, limites, tri, API, permissions déclarées, erreurs isolées, diagnostics sans messages privés, collisions et conservation d'un chargement réussi face à son doublon rejeté. |
| Validateurs Sentinel/AutoBridge | 27 assertions : bornes, données non finies, observation, faux positifs et refus des appels anonymes. |
| Configuration | Fusion des maps, remplacement des listes et retrait explicite avec RemoveKeys vérifiés. |
| Démarrage normal | Dix onglets officiels, Home visible par défaut, zéro extension activée, zéro erreur d'extension, zéro alerte Sentinel, un panneau privé et notices publiques. |
| Commandes natives par RPC | Heal remet effectivement la santé de 50 à 100 ; TimeOfDay applique 9 h ; deux actions apparaissent dans le journal. Effets limités au test Play. |
| Extension de commande | ExamplePing exécutée via le remote privé ; le journal contient les vrais joueurs, capacité et temps serveur. |
| Intégration serveur | ExampleRoster enregistre options/profil et une deuxième commande : 23 commandes pendant le test, 21 après nettoyage. |
| Page personnalisée | ExampleDashboard est copiée et rendue dans le panneau existant. La configuration publique temporaire du titre est bien appliquée. |
| Adaptateur personnalisé | ExampleInventory lit un dossier réel et compte un Tool réel ; aucun service métier ni statut Operational n'est inventé. |
| Contrats refusés | Collision avec Heal, API 2 inconnue et require levant une erreur : trois erreurs génériques visibles, APM continue à fonctionner et Heal reste natif. |
| Retrait/restauration de permission | Session renouvelée ; source de page et onglet retirés ; commande refusée et journalisée. Le retour au contexte réel restitue la page. |
| Première connexion sans grade | StudioRank et CreatorRank retirés uniquement pour ce test : notices publiques présentes, aucun APM_Client, APM_Private, APM_Remotes ni panneau dans les surfaces clientes inspectées. Configuration originale restaurée ensuite. |
| Respawn | Panneau, session privée, notices et support public restent présents une seule fois. |
| Mise à jour locale réelle en Edit | Core de validation remplacé ; au Play suivant, la version preview.2-validation est effectivement servie. Extensions conservées et aucune duplication d'interface/session. |
| Retour arrière réel en Edit | Restauration du Core preview.1 en conservant les extensions ; scripts des modèles clients activés correctement, interface et notices fonctionnelles. |
| Installateur isolé | Destinations de services simulées avec de vrais arbres clonés Studio : installation, état des points d'entrée, refus des doublons, opt-in expérimental, API future et schéma de données futur vérifiés. Cet essai n'est pas un import XML. |
| Analyse AutoBridge | Un Tool actif est compté ; un Tool et un tag sous les points de restauration sont exclus. Analyse de test non tronquée. |
| Sentinel runtime | Test synthétique normal marqué Test, sans déplacement ni sanction ; zéro alerte dans le dernier démarrage nettoyé. |
| Revue visuelle | Home conserve les cartes et le style existants ; aucune nouvelle interface administrative principale. |

Les 143 assertions des trois suites isolées sont distinctes des essais d'intégration et de déploiement. Les services mockés ne prouvent pas un comportement de DataStore ou de Package publié.

Le premier essai de simulation avait utilisé un argument RPC incorrect ; il a été refusé et le scénario a ensuite réussi avec la signature existante. Le test du rollback a révélé un défaut dans le nouvel outil de sauvegarde : les descendants LocalScript étaient désactivés dans la sauvegarde. L'outil a été corrigé pour préserver les modèles privés exactement ; la mise à jour et le retour arrière ont été rejoués avec succès. Les instantanés de validation affectés sont conservés, marqués comme non restaurables par RestoreCore.

## Données et mises à jour

APM_Data_v1 et APM_Sync_v1 sont conservés, ainsi que les clés historiques, SuiteSettings_v2 et Preferences_v2. Aucun changement de format de données n'est requis par cette migration de structure. Les essais ont utilisé StudioMemory=true ; aucune écriture dans les sauvegardes publiées n'a été demandée. Le nouveau contrôle de migrations refuse les changements de schéma non pris en charge. Il ne prétend pas restaurer des DataStores avec un rollback de code.

Le Core installé est un modèle **préparé pour conversion en Package**, sans PackageLink ni asset ID fabriqué. Les Packages s'actualisent dans Studio ; la publication des places et le renouvellement des serveurs restent des décisions séparées. Voir [Distribution](Distribution.md) et les [mécanismes officiels Roblox](https://create.roblox.com/docs/projects/assets/packages).

## Livraison et limites pratiques

Les modèles Core et Distribution, l'archive GitHub et le manifeste sont générés par build.py. La relecture XML contrôle classes, états Disabled, attributs, sources, licence embarquée et absence de faux PackageLink. L'archive contrôle les empreintes SHA-256 et CRC ; des entrées identiques produisent des artifacts identiques.

L'import moteur des fichiers .rbxmx livrés, la création/publication de vrais Packages et le cycle d'actualisation d'un Package lié restent à exécuter dans Studio. Les tests fonctionnels décrits ont utilisé les instances installées directement par MCP. Le CLI officiel Rojo téléchargé et vérifié a été bloqué par le contrôle d'application Windows ; sa compilation n'a pas été exécutée et cette politique n'a pas été contournée. Le projet Rojo a été vérifié structurellement contre ses sources officielles.

Les sauvegardes publiées, plusieurs serveurs et MessagingService, les tests matériels mobile/manette et les intégrations métier des expériences destinataires nécessitent leurs propres essais. Le code d'une extension reste du code développeur de confiance ; l'API n'est pas un sandbox et son Init n'est pas une transaction.

La version reste expérimentale jusqu'à ces vérifications de distribution. Les artifacts APM 2.0 et les sources originales précédemment livrés sont conservés séparément.
