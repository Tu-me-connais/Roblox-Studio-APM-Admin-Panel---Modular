# APM | Admin Panel - Modular — V2.10.2

Ce dépôt contient l’export de la version active **APM V2.10.2** du kit Roblox Studio `Workspace.APM_DistributionKits.APM_Kit`, lu par l’accès MCP Studio. La source est ce kit actif ; les points de restauration ne servent pas de source à cet export.

Les scripts et modules, leur hiérarchie, leurs classes, attributs, tags et propriétés de démarrage sont décrits dans `manifest.json`. Les sources sont conservées en UTF-8, avec leurs retours à la ligne. Les valeurs des instances `StringValue`, dont le guide `INSTALLATION`, figurent également dans le manifeste.

## Documentation incluse

Le [dossier des guides](src/APM_Kit/READ%20ME!!!/) contient le sélecteur **« 0 - Langue · Language · Idioma · Língua · Sprache · Язык · 语言 »** et les sept guides : français, anglais, espagnol, portugais, allemand, russe et chinois. Commencer par le sélecteur, puis lire le guide de la langue choisie avant l’installation ou la configuration.

## Installation dans une expérience

La procédure Toolbox documentée dans le kit consiste à insérer `APM_Kit` dans **Workspace** ou **ServerScriptService**, configurer les comptes autorisés, puis lancer Play. `ToolboxBootstrap` reste **activé**, avec `RunContext = Server` : il range le kit dans `ServerStorage` et poursuit le démarrage avec un chargeur privé dans `ServerScriptService`.

`ServerStorage` seul ne lance pas les scripts. `Installer` et `APM_Bootstrap` restent **désactivés** dans le kit ; ils servent à la procédure manuelle alternative décrite dans les guides.

Configurer `APM_Kit.APM_Extensions.Config.ServerSettings` et `SharedConfig`. Si une configuration externe compatible `ServerStorage.APM_Extensions` existe, elle est conservée et prioritaire. Home et Diagnostics indiquent la configuration active. Déclarer explicitement les comptes fixes dans `Settings.Users` du `ServerSettings` actif, avec leur UserId et leur grade ; la configuration distribuée n’accorde aucun grade automatiquement.

## Organisation des sources

```text
src/APM_Kit/
├── APM_Core/                  serveur, modules partagés et modèles clients
├── APM_Extensions/            configurations et extensions
├── APM_DeveloperTemplates/    exemples destinés aux développeurs
├── READ ME!!!/                sélecteur et sept guides
├── ToolboxBootstrap.server.luau
├── Installer.server.luau
└── APM_Bootstrap.server.luau
```

Un script ayant des enfants est représenté par son fichier `.luau` et un dossier du même nom pour ces enfants. Les dossiers vides et les `StringValue` sont préservés dans le manifeste, même lorsqu’ils n’ont pas de fichier source.

## Reconstruction et vérification locale

Avec Python 3.10 ou plus récent, sans dépendance supplémentaire :

```sh
python build.py
python build.py --check
python -m unittest discover -s tests -v
```

La première commande génère `default.project.json`. `--check` vérifie le manifeste, les parents et les chemins uniques, la présence de chaque source, l’absence de fichiers oubliés sous `src`, les empreintes `sourceSha256` lorsqu’elles sont fournies, et la correspondance du projet généré. Elle ne réécrit pas les fichiers.

Le projet Rojo nécessite **Rojo 7.5 ou plus récent**, pour ses règles de classe explicites par script. Il reconstruit le kit dans `Workspace.APM_DistributionKits.APM_Kit`. Les classes des scripts sont fixées par `syncRules` ; les autres instances portent `$className`. Aucun script APM n’est exécuté par le builder.

Les contrôles locaux portent sur l’intégrité de l’export et de sa description. Ils ne constituent pas une validation du fonctionnement en jeu, une importation Studio, une publication d’expérience ou une publication Roblox Package.

## Fidélité et confidentialité

Les empreintes SHA-256 du manifeste portent sur les octets des sources distribuées. La copie distribuée remplace les identifiants de trois exemples commentés de comptes par un identifiant générique et les crédits personnels par « APM contributors ». Ces substitutions sont les seuls écarts intentionnels aux sources Studio ; elles sont détaillées dans [SYNC_REPORT.md](SYNC_REPORT.md). Aucun secret ni donnée personnelle n’est inclus dans l’export.

La lecture et l’export du kit ne modifient pas le projet Studio. La reconstruction Rojo est une opération distincte, à effectuer dans une copie de travail avant tout déploiement.

APM est distribué sous licence MIT ; voir [LICENSE](LICENSE).
