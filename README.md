# APM | Admin Panel - Modular

APM est un panneau d'administration Roblox modulaire. La distribution officielle est gratuite. Cette évolution prolonge l'APM existant : Home conserve AutoBridge, les commandes natives, les grades et permissions, les sessions privées et Sentinel Guard.

Cette distribution prépare la séparation entre le Core officiel actualisable et les extensions propres à une expérience. Elle est livrée comme **version expérimentale `2.1.0-preview.1`**. Aucun Roblox Package ni dépôt GitHub n'est publié par la préparation locale de ces fichiers.

## Version et contrats

| Champ du manifeste `APM_Core.Release` | Valeur |
| --- | --- |
| `Version` | `2.1.0-preview.1` |
| `Channel` | `experimental` |
| `CoreApiVersion` | `1` |
| `ExtensionApiVersion` | `1` |
| `ExtensionsSchema` | `1` |
| `DataSchemaVersion` | `2` |
| `BootstrapApiVersion` | `1` |
| `InstallationSchema` | `3` |

Le bootstrap refuse un contrat futur qu'il ne prend pas en charge. Le canal expérimental exige l'attribut booléen `AllowExperimental=true` sur `ServerScriptService.APM_Bootstrap`. Les numéros APM sont indépendants du numéro de révision d'un asset Roblox Package.

## Architecture installée

```text
ServerStorage
├── APM_Core                   candidat au Package officiel
│   ├── Server                 services, sécurité et commandes officiels
│   ├── Shared                 composants partagés publics
│   ├── ClientTemplates        interface administrative privée
│   ├── Bootstrap              démarrage officiel
│   └── Release                manifeste de version
├── APM_Extensions             hors Package, appartient au développeur
│   ├── Config
│   │   ├── ServerSettings
│   │   └── SharedConfig
│   ├── Commands
│   ├── Adapters
│   ├── Server
│   └── ClientPages
└── APM_RestorePoints           sauvegardes indépendantes

ServerScriptService
└── APM_Bootstrap               amorçage externe minimal
```

Personnaliser les configurations et les extensions dans `APM_Extensions`. Les scripts officiels du Core ne sont plus l'emplacement des adaptations d'une expérience. Le bootstrap requiert les services depuis le Core privé ; les éléments partagés sont générés au runtime depuis cette même version. Les modèles clients administratifs sont distribués par le système de sessions aux utilisateurs autorisés.

Home reste l'accueil central : systèmes AutoBridge détectés, états d'intégration, informations serveur, Sentinel et diagnostics. Les réglages avancés d'AutoBridge restent dans Home, avec les permissions serveur existantes. Les valeurs affichées proviennent des systèmes et du serveur.

## Installation et mises à jour

Lire [Distribution, installation et mises à jour](docs/Distribution.md) avant l'installation.

Le modèle `.rbxmx` contient un bundle privé `APM_Distribution` avec le Core, les extensions initiales, un bootstrap désactivé et un installer désactivé. Placer le bundle dans `ServerStorage`, examiner le code, puis exécuter l'installer **en mode Edit**. L'installer refuse les collisions : une ancienne installation nécessite une migration contrôlée, pas une nouvelle copie par-dessus.

`default.project.json` fournit la description Rojo générée pour reconstruire la structure depuis les sources. Un import Rojo ou `.rbxmx` ne crée pas à lui seul un `PackageLink` Roblox. La conversion en Package et sa publication sont des opérations Studio distinctes.

Les exemples d'extensions sont des ressources à lire et à adapter. Ils ne sont pas installés automatiquement dans l'expérience.

## Vérification

Les résultats de validation accompagnant la livraison indiquent les essais réellement effectués. Avant un déploiement dans une autre expérience, vérifier ses extensions, permissions, sessions privées, sauvegardes et intégrations. Un essai en Studio ne remplace pas un essai de sauvegarde et de déploiement dans une expérience publiée.

Les mises à jour de Package se récupèrent dans Studio. Elles ne modifient pas instantanément les serveurs existants : il faut tester et publier les places, puis choisir le renouvellement des serveurs.

## Sources et licence

Les sources sont préparées pour un dépôt GitHub public et pour la création de versions dérivées. APM est distribué sous la **licence MIT**, reproduite dans [LICENSE](LICENSE). Aucun dépôt GitHub n'a été publié par cette préparation locale.

Les modèles `.rbxmx` contiennent aussi le texte MIT complet dans `APM_Core.LICENSE` (`StringValue`). Le Core et le bundle portent l'attribut `APMLicense="MIT"`.

MIT permet les forks, modifications, redistributions et usages commerciaux, y compris la vente de copies, avec conservation des notices nécessaires. La distribution officielle gratuite n'interdit donc pas la vente de versions dérivées. Voir les conditions dans [Distribution](docs/Distribution.md#sources-github-et-licence) et la provenance dans [NOTICE.md](NOTICE.md).

Le plugin **Sentinel Audit** constitue une distribution Studio indépendante. Il complète l'audit de développement ; **Sentinel Guard** appartient au Core runtime.
