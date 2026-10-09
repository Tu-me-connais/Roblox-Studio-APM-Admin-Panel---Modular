# Exemple facultatif de page APM

`ExampleDashboard.luau` utilise les composants et le cycle de vie de l'interface existante. Il ne fait pas partie des sources installées automatiquement du Core. Installez ce ModuleScript dans votre extension, hors `APM_Core`, puis référencez-le dans le manifest serveur de cette extension.

Déclarez la permission `Extensions.Example.View` avec le grade `Owner` par défaut dans `ServerSettings.PermissionDefaults`. Le manifest de la page doit déclarer `Permission = "Extensions.Example.View"` et `ApiVersion = 1`. Le serveur contrôle la permission avant de cloner la page dans la session administrative privée, sous `APM_Client.ExtensionPages/<ExtensionId>`. Il copie ces deux métadonnées comme attributs du ModuleScript. La page retournée doit déclarer les mêmes valeurs.

La page suit l'API existante : `Id`, `Order`, `Label`, `Build(Core, page)`, `Visible(Core)` facultatif, et `Handles` facultatif. Son identifiant ne doit pas remplacer une page officielle ni une catégorie d'une autre extension. `Handles` peut prendre en charge uniquement les catégories composées exclusivement de commandes de cette même extension ; les catégories natives restent gérées par APM. Les pages sont triées par `Order`, puis `Id`.

Utilisez `Core.On` pour les connexions et `Core.Alive(Core.Session)` avec une session capturée pour les opérations différées. Vérifiez la permission avant de mettre à jour un contenu après un appel qui attend une réponse. APM reconstruit la session lors d'une modification des droits. La permission d'une page ne remplace jamais l'autorisation serveur des commandes qu'elle déclenche.

Cet exemple affiche le nom, l'identifiant Roblox et le grade déjà présents dans la session. Il n'ajoute aucun Remote, aucun ScreenGui et aucune donnée fictive.
