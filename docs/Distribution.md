# Distribution, installation et mises à jour d'APM

Cette documentation accompagne la version expérimentale **`2.1.0-preview.1`**. Elle prépare les exports locaux et une publication future. Elle ne fournit aucun asset ID Roblox inventé et ne prétend pas qu'une publication de Package ou de dépôt GitHub a eu lieu.

## Installation depuis le bundle local

Le modèle de distribution `.rbxmx` contient un `APM_Distribution` privé : `APM_Core`, `APM_Extensions`, le modèle de Script `APM_Bootstrap` désactivé et l'installer désactivé.

1. Arrêter les essais Play et ouvrir l'expérience dans Studio **en mode Edit**.
2. Conserver une sauvegarde indépendante de l'expérience et des sources. Pour une installation existante, conserver aussi l'APM original et ses points de restauration.
3. Importer le modèle local, puis placer `APM_Distribution` dans `ServerStorage` avant tout test.
4. Lire le Core, le bootstrap, les configurations et l'installer. L'installer désactivé ne s'exécute pas automatiquement.
5. Exécuter le code de l'installer depuis la barre de commande Studio en mode Edit. Il installe les éléments aux emplacements ci-dessous et refuse les collisions avec une installation déjà présente.
6. Adapter `APM_Extensions.Config.ServerSettings` et `SharedConfig` à l'expérience. Ne placer aucune information secrète dans `SharedConfig`, car sa destination est publique.
7. Pour essayer cette version, définir explicitement l'attribut booléen `AllowExperimental=true` sur `ServerScriptService.APM_Bootstrap`. Cette autorisation ne transforme pas la version en version stable.
8. Vérifier l'installation en Studio, puis effectuer les vérifications propres à l'expérience avant de publier.

Une installation APM antérieure déjà distribuée dans plusieurs services n'est pas une installation vierge. L'installer refuse d'écraser ces objets. Il faut une migration spécifique : sauvegarder, identifier les réglages et ajouts personnalisés, déplacer ceux-ci dans les extensions, puis retirer uniquement les anciennes copies officielles identifiées. La migration de la Baseplate de développement est traitée séparément par le rapport de validation de la livraison.

## Emplacements et responsabilités

| Emplacement | Rôle et personnalisation |
| --- | --- |
| `ServerStorage.APM_Core.Server` | Services et commandes officiels ; requis directement depuis le Core. |
| `ServerStorage.APM_Core.Shared` | Sources officielles des composants publics partagés ; copies générées uniquement au runtime. |
| `ServerStorage.APM_Core.ClientTemplates` | Modèles officiels de l'interface privée, utilisés directement par les sessions. |
| `ServerStorage.APM_Core.Bootstrap` | Logique de démarrage officielle versionnée. |
| `ServerStorage.APM_Core.Release` | Version produit, canal et contrats de compatibilité. |
| `ServerScriptService.APM_Bootstrap` | Script externe minimal qui choisit et vérifie un Core avant son démarrage. |
| `ServerStorage.APM_Extensions.Config.ServerSettings` | Grades, comptes, groupe, sauvegardes et options serveur propres à l'expérience. |
| `ServerStorage.APM_Extensions.Config.SharedConfig` | Langue, thème et réglages publics d'interface propres à l'expérience. |
| `ServerStorage.APM_Extensions.Commands` | Commandes personnalisées. |
| `ServerStorage.APM_Extensions.Adapters` | Adaptateurs AutoBridge personnalisés. |
| `ServerStorage.APM_Extensions.Server` | Modules d'intégration serveur propres à l'expérience. |
| `ServerStorage.APM_Extensions.ClientPages` | Pages personnalisées distribuées dans les sessions clientes autorisées. |
| `ServerStorage.APM_RestorePoints` | Copies indépendantes utilisées pour le retour arrière en Edit. |

Le Core n'écrit pas dans les sources des extensions lors de sa mise à jour. Les extensions restent hors de sa branche. Les noms et contrats officiels ne doivent pas être remplacés par une extension portant le même identifiant. Un code client personnalisé doit appeler une opération autorisée côté serveur ; afficher un bouton ne confère aucun droit.

Les DataStores appartiennent à l'expérience, pas au Package. Préserver leurs noms existants évite de repartir avec des données vierges. Une évolution du code ne réécrit pas arbitrairement les données d'une ancienne version. Les sauvegardes et migrations de schéma nécessitent une validation distincte.

## Reconstruction depuis les sources

Les fichiers Luau et le `default.project.json` généré décrivent la structure exportable avec Rojo. Vérifier la destination de synchronisation avant d'utiliser ce projet sur une expérience existante : une reconstruction complète du modèle n'est pas une mise à jour ciblée du Core.

`build.py` requiert Python 3.10 ou plus et `lxml`. Depuis une copie du dépôt, `python build.py --output dist` régénère les modèles, le manifeste et l'archive. Les empreintes et horodatages ZIP sont déterministes pour des entrées identiques. Le manifeste référence chaque fichier de l'archive, sauf sa propre empreinte pour éviter une autoréférence.

Le projet généré requiert Rojo 7.5 ou plus pour les règles explicites de classe des points d'entrée clients. Il conserve `APM_Bootstrap.Disabled=true` : après reconstruction dans une expérience de test et examen de la configuration, activer le Script pour essayer cette version. Une reconstruction Rojo ne démarre donc pas automatiquement APM. [Historique officiel Rojo](https://github.com/rojo-rbx/rojo/blob/master/CHANGELOG.md).

Deux distributions ont des responsabilités différentes :

- Le bundle `.rbxmx` simplifie l'installation initiale locale.
- Les sources et la description Rojo permettent l'examen du code, les modifications et la reconstruction par les développeurs.

Les exemples sont volontairement fournis hors de l'installation active. Copier uniquement les exemples adaptés à l'expérience dans les emplacements d'extension prévus, puis les vérifier.

## Création du Roblox Package officiel

La conversion et la publication restent des opérations manuelles Studio. Seule la racine `ServerStorage.APM_Core` doit devenir le Package. Les extensions, le bootstrap externe et les points de restauration restent à l'extérieur.

1. Choisir le compte ou groupe propriétaire officiel.
2. Sélectionner `APM_Core` dans Explorer, puis **Convert to Package**.
3. Compléter la fiche, publier et conserver le `PackageLink` créé par Studio.
4. Enregistrer l'asset ID réel dans les métadonnées de distribution et la documentation publique.
5. Pour les versions suivantes, publier les changements sur le même asset officiel avec un manifeste APM et une description cohérents.

La proposition de distribution utilise des assets distincts **Stable** et **Experimental**. Aucun de leurs IDs n'est encore fourni. Cette séparation empêche une place utilisant le canal stable de recevoir une préversion parce que le même asset a été republié.

Un modèle local n'est pas un Package lié. Un script runtime ne peut pas fabriquer `PackageLink`. [Référence officielle PackageLink](https://create.roblox.com/docs/reference/engine/classes/PackageLink).

## Mise à jour par Studio

Sur une installation liée, récupérer le nouveau Core avec **Get Latest Package**. Les extensions restent hors du Package. `AutoUpdate` agit dans Studio et les copies modifiées sont exclues ; **Update All** sauvegarde les places sélectionnées sans les publier. Les attributs de configuration personnalisés à la racine bénéficient du mécanisme de préservation Roblox, mais les configurations complètes d'APM restent externes. [Documentation officielle des Packages](https://create.roblox.com/docs/projects/assets/packages).

Pour une expérience de production, conserver l'actualisation automatique désactivée permet d'examiner le changement avant le déploiement. Une place de validation peut utiliser `AutoUpdate`. Dans les deux cas, lire le changelog, sauvegarder, vérifier les contrats d'extension et de bootstrap, puis tester.

Le manifeste fourni indique API Core et d'extension `1`, schéma d'extension `1`, schéma de données `2`, contrat bootstrap `1` et schéma d'installation `3`. Le bootstrap refuse les contrats futurs non pris en charge. Une mise à jour changeant son contrat requiert une mise à jour explicite du petit Script externe ; ce changement ne doit pas être masqué comme une simple mise à jour du Core.

## Mise à jour manuelle depuis un nouveau bundle

La procédure `UpdateCore.luau` accompagne la distribution pour le remplacement local du Core **en mode Edit**. Lire le script livré avant de l'exécuter. Sa cible est le Core officiel ; les extensions et leur configuration doivent rester intactes. Un point de restauration indépendant précède le remplacement.

Importer le nouveau bundle dans `ServerStorage`, arrêter Play, comparer les manifests et exécuter la procédure de mise à jour livrée. Ne relancer ni l'installer d'une installation vierge ni une synchronisation complète Rojo pour écraser une installation existante. Si la procédure refuse une collision ou un contrat incompatible, traiter la migration identifiée au lieu de dupliquer le Core.

Cette mise à jour manuelle remplace du code dans la place ouverte dans Studio. Elle ne télécharge aucun code au démarrage des serveurs et ne modifie aucun serveur déjà publié.

## Publication de la place et serveurs existants

Après validation, publier chaque place concernée dans Roblox. Les serveurs existants continuent avec leur ancienne version jusqu'à leur arrêt ou leur redémarrage. Dans Creator Dashboard, la gestion des serveurs permet de redémarrer seulement les serveurs obsolètes. [Documentation officielle du renouvellement des serveurs](https://create.roblox.com/docs/projects/update-games).

Une version du Package, une version sauvegardée d'une place et une version de place publiée sont trois choses distinctes. Le runtime d'APM utilise les sources présentes dans sa place. Il ne modifie pas `Script.Source` pour s'actualiser. [Référence officielle Script](https://create.roblox.com/docs/reference/engine/classes/Script).

## Retour arrière

En mode Edit, arrêter Play, choisir le point de restauration approprié dans `ServerStorage.APM_RestorePoints`, vérifier sa version et restaurer uniquement le Core prévu. Conserver les extensions et réglages actuels, sauf si une migration spécifique exige aussi leur restauration.

Pour un Package lié, Studio expose également l'historique de ses versions. Une ancienne version du code ne restaure pas les DataStores. Le schéma de données doit être lisible par cette version avant la remise en service. Après un retour arrière, recommencer les vérifications, puis publier la place et gérer les serveurs obsolètes si nécessaire.

L'historique d'une place permet aussi de récupérer une ancienne version, mais sa restauration ne la publie pas automatiquement. [Historique officiel des versions](https://create.roblox.com/docs/projects/version-history).

## Validation avant diffusion

Le rapport joint à la livraison distingue les essais déjà réalisés des essais encore nécessaires sur une expérience cible. Les vérifications de déploiement doivent couvrir les permissions réelles, la réplication privée, la sauvegarde publiée, les collisions, les extensions, les versions incompatibles et la conservation des personnalisations après remplacement du Core. Les essais de Baseplate et du mode mémoire Studio ne prouvent pas une sauvegarde publiée réussie.

Le plugin **Sentinel Audit** se distribue et s'installe séparément comme outil Studio. Il ne remplace pas **Sentinel Guard**, le service runtime du Core.

## Sources GitHub et licence

La distribution officielle d'APM reste gratuite. Le dépôt public est préparé pour exposer le code, les instructions d'installation, les contrats d'extension et les changements de version. Ne publier ni données d'utilisateurs, ni secrets, ni configurations privées d'une expérience dans le dépôt public.

La licence **MIT** a été choisie pour APM. Le fichier `LICENSE` à la racine contient son texte et doit accompagner les distributions. Un dépôt public GitHub peut être consulté et forké ; sa licence définit les droits généraux de réutilisation, modification et redistribution. [Documentation officielle GitHub sur les licences](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository).

Le modèle Core autonome et le bundle `.rbxmx` embarquent aussi le texte complet dans le `StringValue` `APM_Core.LICENSE`. L'attribut `APMLicense="MIT"` identifie la licence sur leurs racines ; cet attribut seul ne remplace pas le texte complet. Le builder vérifie sa fidélité après relecture XML.

MIT autorise modification, redistribution, sous-licence, réutilisation commerciale et vente, avec conservation des notices de copyright et de licence nécessaires. Un fork peut devenir propriétaire. La gratuité des versions officielles est l'engagement de distribution d'APM ; elle n'ajoute pas d'interdiction de vente aux droits accordés par MIT. [Texte MIT approuvé par l'OSI](https://opensource.org/license/mit).

Les extensions ajoutées par un développeur peuvent contenir du code tiers soumis à d'autres licences. Conserver leurs notices et vérifier les droits de redistribution de ces ajouts. `NOTICE.md` documente la provenance de cette distribution et distingue l'architecture officielle, les exemples facultatifs et le plugin Studio indépendant.

Pour maintenir des publications identifiables, utiliser des tags GitHub correspondant au manifeste APM, publier un changelog et indiquer l'asset Package officiel de chaque canal lorsque celui-ci existe. Les forks doivent annoncer leur identité et leurs modifications sans se présenter comme la version officielle. Aucun tag, dépôt ou asset officiel n'a été créé par cette préparation locale.
