# APM — Roblox Packages : recherche et architecture proposée

Recherche en lecture seule effectuée le 9 octobre 2026, à partir de la documentation officielle Roblox et des sources locales de l'APM existant. Ce document décrit la préparation à la publication ; il ne certifie pas qu'un asset Package a été créé ou publié.

## Mécanismes vérifiés

Un Package représente une branche d'instances. Choisir soigneusement son propriétaire : son transfert n'est pas pris en charge. Ne pas déplacer ni supprimer son `PackageLink`.

**Get Latest Package** actualise une copie. **Update All** sauvegarde les places sélectionnées, sans les publier, et ignore les copies modifiées. `AutoUpdate` intervient dans Studio ; une modification locale du Package bloque cette actualisation. Les attributs de configuration modifiés à la racine sont préservés lors d'une mise à jour.

**Use & View** permet de consulter/utiliser les versions ; **Edit** autorise aussi leur publication. Révoquer l'accès n'efface pas les copies insérées. **Package Details → Versions** permet la restauration ; **Undo Changes to Package** abandonne les modifications non publiées. Les configurations se réinitialisent séparément. Modifier un Package imbriqué modifie aussi son parent. [Documentation officielle des Packages](https://create.roblox.com/docs/projects/assets/packages).

`PackageLink` est créé par Studio, pas par `Instance.new()` ou un script de jeu. Ses propriétés ne constituent pas une API runtime de mise à jour : `AutoUpdate` possède une sécurité Roblox, et `VersionNumber` une sécurité non accessible. `PackageId` est en lecture seule. La référence décrit aussi une recherche périodique des nouvelles versions quand la place est ouverte ; il faut comprendre cette précision dans le contexte Studio. [Référence officielle PackageLink](https://create.roblox.com/docs/reference/engine/classes/PackageLink).

Une publication de place ne remplace pas immédiatement les serveurs existants. Ceux-ci gardent leur ancienne version jusqu'à leur arrêt, ou jusqu'au redémarrage des serveurs obsolètes via Creator Dashboard. [Publier des mises à jour de jeu](https://create.roblox.com/docs/projects/update-games).

La propriété `Script.Source` relève de la capacité `PluginOrOpenCloud`. APM ne doit donc pas promettre l'édition du code source d'une expérience publiée par un script de jeu ordinaire. [Référence officielle Script](https://create.roblox.com/docs/reference/engine/classes/Script).

## Conséquences pour l'APM existant

L'actuel `APM_Installer.luau` clone en mode Edit le serveur, le partagé, les modèles clients privés et les notifications. Il refuse une nouvelle installation si ces copies existent. Convertir seulement le kit source en Package laisserait donc des copies actives indépendantes figées sur leur ancienne version. Il faut changer le chemin de démarrage, pas seulement renommer deux dossiers.

Les composants existants restent réutilisables : `APMService` orchestre les services, `Sessions` distribue le client privé aux comptes autorisés, `Shell` découvre les pages, les commandes administratives viennent de `Modules`, et AutoBridge possède déjà un registre d'adaptateurs. Home et le composant `AutoBridgePanel` restent dans le Core officiel. Les mécanismes métier et leurs validations ne demandent pas de reconstruction.

Les réglages actuels `APM_Server.Settings` comprennent les grades, les utilisateurs, le groupe, les clés de sauvegarde et les valeurs par défaut. `APM_Shared.Config` contient les préférences publiques d'interface. Ces valeurs propriétaires doivent être extraites hors de la branche actualisable, en conservant leur comportement et leurs noms de sauvegarde. `SuiteSettings_v2` est une sauvegarde additive déjà implémentée ; elle ne justifie pas de réécrire les données v1.

## Séparation proposée

Cette organisation est une proposition d'ingénierie, pas une contrainte Roblox sur les noms :

```text
ServerStorage
├── APM_Core                  Model officiel, seul candidat Package
│   ├── Runtime               démarrage officiel et API versionnée
│   ├── Server                services, commandes et sécurité officiels
│   ├── Shared                modèles des composants publics partagés
│   └── ClientTemplates       interface privée officielle, Home/AutoBridge
├── APM_Extensions            branche propriétaire hors Package
│   ├── Config                réglages serveur et interface
│   ├── Commands              commandes personnalisées
│   ├── AutoBridgeAdapters    intégrations personnalisées
│   └── ClientPages           pages et composants personnalisés
└── APM_RestorePoints          sauvegardes indépendantes

ServerScriptService
└── APM_Bootstrap              amorçage externe minimal
```

`APM_Core` reste dans `ServerStorage`, où son code serveur et ses modèles privés ne sont pas répliqués. Un script d'amorçage dans `ServerScriptService` peut requérir ses ModuleScripts ; les Scripts placés dans `ServerStorage` ne s'exécutent pas spontanément. [Organisation officielle du modèle de données](https://create.roblox.com/docs/projects/data-model).

Le bootstrap doit désigner un seul Core, vérifier son contrat de démarrage, puis appeler sa méthode officielle de lancement. La stratégie retenue consiste à requérir directement les services officiels depuis ce Core privé. Cela évite les anciennes copies permanentes dans `ServerScriptService`. Les éléments partagés nécessaires aux clients sont clonés uniquement au runtime depuis cette version du Core, avec une identification explicite des copies gérées, un refus des collisions inconnues et une protection contre un second démarrage. Ces clones utilisent du code déjà présent dans la place publiée ; ils ne téléchargent pas une nouvelle version et n'éditent pas `Source`.

Le Core instancie les éléments partagés publics, et `Sessions` continue de distribuer directement son modèle client administratif privé. Les extensions serveur restent côté serveur. Seules les pages clientes et les configurations publiques explicitement sélectionnées sont copiées dans les sessions autorisées. Une extension cliente n'est jamais une autorisation : les opérations sont encore vérifiées sur le serveur.

Une mise à jour doit lire les extensions sans modifier leur arbre. Les identifiants officiels restent réservés ; une collision de page, commande, adaptateur ou permission doit être signalée et rejetée. La compatibilité de chaque extension doit être vérifiée avant son chargement. Une erreur d'extension doit apparaître dans les diagnostics sans faire démarrer une copie supplémentaire du Core.

Les sauvegardes de données restent dans les DataStores de l'expérience, hors de l'asset Package. Le plugin Sentinel Audit appartient à la distribution Studio indépendante : son cycle d'installation et ses permissions de plugin sont distincts de Sentinel Guard runtime.

## Versions, canaux et retours arrière

Conserver trois numéros distincts : version produit APM (par exemple SemVer), version du contrat d'extension, version du schéma de données. Les exposer dans un manifeste officiel accessible au runtime. Ne pas tenter de déduire la version produit en lisant `PackageLink.VersionNumber`.

Pour obtenir des canaux contrôlés, la proposition est de publier **deux assets distincts**, Stable et Experimental, avec des identités documentées. Ce choix évite de supposer l'existence d'un mécanisme Roblox de canaux sémantiques que la documentation consultée ne décrit pas. L'amorçage vérifie le canal et la compatibilité attendus ; il ne recherche pas un asset sur Internet au lancement.

Préférer `AutoUpdate=false` pour les expériences de production afin que le développeur examine le changement et lance les tests avant publication. L'actualisation automatique peut être choisie sur une place de validation. Le Package simplifie l'acquisition du Core ; les tests, migrations et décisions de déploiement restent ceux du développeur de l'expérience.

Un retour arrière du code ne revient pas automatiquement sur les données. Si une nouvelle version a modifié leur format, l'ancienne peut devenir incompatible. Toute migration doit être additive ou explicitement réversible, versionnée et idempotente ; une version inconnue doit bloquer les écritures concernées. Il faut conserver une copie indépendante du Core, des réglages et des extensions avant la migration. La restauration d'une ancienne place ne publie pas automatiquement cette restauration. [Historique officiel des versions de place](https://create.roblox.com/docs/projects/version-history).

## Procédure de publication à préparer

1. Vérifier la sauvegarde originale et créer un nouveau point de restauration hors du Core.
2. Installer la séparation réelle, migrer les personnalisations existantes et vérifier le fonctionnement des extensions.
3. Exporter un modèle Core et une distribution d'installation séparée. Un fichier `.rbxmx` reste un modèle local tant qu'il n'a pas été converti et publié dans Studio.
4. Dans Studio, sélectionner uniquement la racine `APM_Core`, puis **Convert to Package** ; choisir le propriétaire officiel et les droits de distribution.
5. Enregistrer l'asset ID réel après publication. Publier les versions suivantes sur cet asset, avec une description et le manifeste APM correspondant.
6. Sur une place de validation, récupérer la version, vérifier les extensions, permissions, sessions privées, Home, AutoBridge, Sentinel et sauvegardes.
7. Publier ensuite les places souhaitées. Décider séparément de laisser s'épuiser les serveurs existants ou de redémarrer les serveurs obsolètes.

Ces étapes n'ont pas été exécutées par cette recherche. La conversion réelle en Package et la publication exigent l'interaction Studio et le compte propriétaire approprié ; un export préparé ne doit pas être annoncé comme un asset actualisable déjà publié.

## GitHub, forks et licence — décision distincte

Un dépôt public est consultable et peut être forké sur GitHub, mais il faut une licence pour accorder les droits généraux de modification, utilisation et redistribution du logiciel. La licence **MIT a été choisie par l'utilisateur après cette recherche** ; son texte accompagne la distribution. La comparaison ci-dessous conserve les éléments ayant éclairé cette décision. [Documentation officielle GitHub](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).

| Option | Conséquence concrète |
| --- | --- |
| MIT | Permet les modifications, redistributions, sous-licences et ventes ; exige de conserver la notice de copyright et la notice de licence dans les copies concernées. Les versions dérivées peuvent être propriétaires. |
| GPLv3 | Permet également de vendre des copies. Lorsqu'un travail dérivé couvert est distribué, ses libertés et les obligations de licence/source doivent être conservées. Une simple interaction réseau sans transfert de copie n'est pas, à elle seule, une distribution au sens de la GPLv3. |

Ces points viennent des textes des licences : [MIT, texte approuvé par l'OSI](https://opensource.org/license/mit) et [GPLv3, texte approuvé par l'OSI](https://opensource.org/license/gpl-3.0). Une séparation technique en Core et Extensions ne détermine pas, à elle seule, les obligations de licence d'un ensemble distribué.

La gratuité des versions officielles est l'engagement de distribution d'APM. **MIT et GPLv3 n'interdisent pas la revente par des tiers.** La licence MIT choisie permet donc la vente de versions dérivées. Ajouter une interdiction générale des usages commerciaux ne correspond pas à la définition OSI de l'open source. [Définition officielle de l'open source](https://opensource.org/osd).
