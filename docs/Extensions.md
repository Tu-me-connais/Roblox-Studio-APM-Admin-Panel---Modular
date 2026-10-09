# API APM Extensions — version 1

Les exemples de ce dépôt sont facultatifs. Ils ne sont ni dans APM Core, ni activés automatiquement dans Studio. Les fichiers de développeur résident dans le root indépendant `ServerStorage.APM_Extensions`. Les remplacer, les supprimer ou les publier reste le choix du développeur de l'expérience.

```text
ServerStorage
├─ APM_Core                      contenu officiel actualisable
└─ APM_Extensions                contenu développeur préservé
   ├─ Config
   │  ├─ ServerSettings          ModuleScript : réglages privés
   │  └─ SharedConfig            ModuleScript : configuration publique
   ├─ Commands
   │  └─ Examples
   │     └─ ExamplePing          ModuleScript facultatif
   ├─ Adapters
   │  └─ ExampleInventory        ModuleScript facultatif
   ├─ Server
   │  └─ ExampleRoster           ModuleScript facultatif
   └─ ClientPages
      └─ Example                pages client personnalisées
```

Les commandes sont chargées récursivement depuis Commands, avec limite de profondeur et de nombre. Adapters et Server chargent les ModuleScripts **directs** de leur dossier. Un module utilitaire peut être enfant d'un manifeste ou rester dans un dossier propre au jeu ; il n'est pas automatiquement exécuté. Aucun système détecté dans Workspace n'est automatiquement requis par AutoBridge.

## Commandes

Une commande custom déclare au minimum `ApiVersion=1`, `Name`, `Category`, `MinRank` et `Execute`. Mode peut être action, target, toggle ou slider. MinRank doit désigner un grade réellement défini par les réglages de cette expérience. Les noms sont globaux : privilégier un préfixe propre au jeu. Une collision avec une commande officielle est refusée, et ne la remplace jamais.

Le namespace diagnostic `ExtensionId` est le nom du premier dossier sous Commands ; pour une commande directement sous Commands, c'est le nom de son ModuleScript. Name et Category sont limités à 64 caractères ; le namespace à 40. Les caractères lettres/chiffres, `_`, `-` et `.` sont acceptés. Les métadonnées publiques sont validées et bornées avant Init. Fields accepte des tableaux de champs number, choice, text ou string ; Inputs accepte Reason et Minutes.

`Execute(ctx, admin, target, value)` réutilise la validation et la matrice natives. `ctx` reste le contexte historique destiné au code serveur de confiance. `Init(ctx)` et `OnAccessRevoked(ctx, player)` sont facultatifs. Si un Init de commande extension échoue ou renvoie false, la commande est exclue. Une commande qui attend avant d'agir doit appeler `ctx.Authorize(admin, commandName, target)` à nouveau **immédiatement avant la mutation**, et vérifier que ses objets/services existent toujours.

Copier `examples/server/ExamplePing.luau` dans Commands.Examples.ExamplePing fournit une commande de lecture du nombre de joueurs et du temps serveur réel. Elle ne crée aucune statistique. Elle devient une commande de catégorie Examples et utilise les composants existants du panneau.

## Adaptateurs AutoBridge

Un manifeste adapter renvoie `{ApiVersion=1, Id="mon_adaptateur", Adapter={...}}`. Id respecte le contrat AutoBridge : lettres/chiffres, `_` et `-`, au plus 40 caractères. L'adaptateur exige ici une Permission explicite déjà déclarée dans les réglages serveur, un `Probe(ctx)` et un tableau Actions, vide pour un diagnostic sans actions.

Probe renvoie Name, Status, Count et Detail. Status vaut Unsupported, Detected, Compatible, Operational ou Error. Déclarer Compatible/Operational exige que les fonctionnalités annoncées existent réellement. Un dossier, un siège ou un tag n'est pas une preuve de compatibilité avec une économie ou un inventaire.

Chaque action exige Permission, Validate et Execute, et peut déclarer Target et AllowSelf. Validate renvoie une valeur propre, ou nil accompagné d'un motif. Le chemin AutoBridge vérifie accès, fréquence, hiérarchie, compatibilité courante et permissions après les validateurs susceptibles d'attendre. Le code Execute reste responsable d'une dernière vérification après ses propres attentes et juste avant une mutation. Aucun ID ne remplace un adaptateur existant.

`ExampleInventory.luau` inspecte uniquement un éventuel dossier réel `ServerStorage.ExampleInventory`, en bornant son comptage à 500 enfants. Il affiche Detected lorsque le dossier existe et Unsupported sinon. Il ne crée pas de dossier, n'invente pas de service métier et n'effectue aucune mutation. Ajouter `["Examples.Inventory.View"]="Owner"` à PermissionDefaults dans Config.ServerSettings **avant** d'activer ce manifeste ; `ExamplePermissions.luau` contient ce seul fragment, à fusionner avec vos réglages existants.

Les adaptateurs chargés apparaissent dans Home et dans ses détails AutoBridge. Ils ne créent pas d'onglet principal AutoBridge.

## Intégrations serveur et API limitée

Un manifeste de Server renvoie `{ApiVersion=1, Id="mon_integration", Init=function(api) ... end}`. Les manifests adapter et intégration partagent leurs IDs : une collision est refusée. L'API fournie ne livre ni remotes administratifs ni méthodes d'écriture des grades.

| Méthode | Contrat |
| --- | --- |
| `RegisterCommand(command)` | Charge une commande par le chemin validé. Disponible pendant l'initialisation seulement ; ensuite RegistrationClosed. |
| `RegisterOptions(localName, provider)` | Renvoie la clé `Id.localName`. Le provider renvoie une liste `{id, texte}` à partir des données réelles. localName est limité à 20 caractères. |
| `AddProfileProvider(provider)` | Contrat historique `provider(userId, livePlayer)` ; livePlayer vaut nil hors ligne. Renvoie des lignes Label/Value. |
| `RegisterAdapter(localName, adapter)` | Registre AutoBridge sous `Id_localName`, limité à 40 caractères ; permissions déclarées exigées. |
| `HasPermission(player, name)` | Accès au panneau et permission actuels. Une permission inconnue est refusée. |
| `CanTarget(admin, target)` | Hiérarchie native APM. |
| `Authorize(admin, commandName, target)` | Joueurs présents, accès au panneau, permission de commande et hiérarchie. |
| `Notify(player, message, success)` | Notification privée via le transport APM existant. |
| `Log(actor, action, target, detail, level)` | Journal Extensions ; l'action est préfixée par Id. |

**Les lignes de profil et listes de choix du contrat existant sont consultables par tous les administrateurs du panneau.** Y placer seulement des données adaptées à ce public. Pour des données économiques ou privées restreintes, utiliser une commande ou un adaptateur avec une permission explicite et une validation serveur ; ne pas considérer la visibilité d'un onglet comme une autorisation.

`ExampleRoster.luau` propose les vraies équipes présentes, ajoute au profil l'équipe et l'âge réel du compte, puis enregistre une commande Owner qui compte les membres actuels de l'équipe choisie. L'absence ou la suppression d'une équipe est signalée. Il ne crée pas d'équipe, de monnaie ni de statistique.

L'API est un contrat d'intégration, **pas un sandbox**. Une extension est du code serveur local de confiance et peut délibérément appeler les services Roblox. Init n'est pas une transaction : le code du développeur peut avoir eu des effets ou enregistré des hooks avant de signaler un échec. Éviter les effets permanents dans Init et assurer soi-même le nettoyage des connexions/tâches propres au jeu. Les hooks enregistrés sont relus au prochain démarrage du serveur ; modifier les sources en Edit ne remplace pas le code des serveurs publiés en cours.

## Permissions, erreurs et mises à jour

Les permissions supplémentaires sont déclarées dans ServerSettings.PermissionDefaults avant l'initialisation de la matrice. Les permissions de commande utilisent Name et MinRank. Le refus d'une permission est autoritaire côté serveur ; les vues client n'en sont que la présentation.

Le chargement rejette les versions API inconnues, contrats invalides, collisions, données publiques non sérialisables et erreurs de require/Init. Les diagnostics retournent uniquement type, ID, statut et code générique. Les messages complets restent dans la console serveur. Le relevé d'extensions est transmis au propriétaire réel ou aux détenteurs de APM.Simulate, dans les diagnostics détaillés et Home.Diagnostics.

Mettre à jour seulement APM_Core préserve le root APM_Extensions et les données sauvegardées. Tester d'abord la version officielle avec vos extensions, car une mise à jour de code peut modifier un contrat ou un comportement. Le numéro de Package Roblox, la version produit et ApiVersion sont distincts. Une erreur API doit être corrigée dans l'extension ou résolue par un Core compatible ; elle ne doit pas être contournée en copiant du code custom dans le Package.

Les configurations fusionnent les maps et remplacent les listes Ranks, ClientTools, ToolSources et PlayerGroups. Une valeur `nil` absente d'une table n'efface pas un défaut. Pour retirer un champ, ajouter `RemoveKeys={"StudioRank","CreatorRank"}` (ou le nom voulu) au niveau concerné du module de configuration. Cette règle permet notamment de tester une première connexion sans aucun grade, sans modifier les défauts officiels.

Les pages sont rangées sous `ClientPages/<ExtensionId>` et portent les attributs `ApiVersion=1` et `Permission="ma.permission"`. Elles renvoient aussi ces mêmes valeurs dans leur table, avec Id et Build. Une permission doit être déclarée dans ServerSettings.PermissionDefaults. La découverte est bornée à 200 pages et huit niveaux de dossiers ; les erreurs de manifest apparaissent dans les diagnostics. Le serveur renouvelle la session lorsque la liste des pages autorisées change. Le Shell revalide la permission et réserve les identifiants officiels ; les pages personnalisées ont un Order d'au moins 1 pour conserver Home comme accueil initial.
