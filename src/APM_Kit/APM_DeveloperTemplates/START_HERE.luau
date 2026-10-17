--[[
APM_DeveloperTemplates : exemples INACTIFS, hors du chargeur APM_Extensions.
Copie uniquement l'exemple voulu dans son dossier équivalent sous APM_Extensions.
Ne déplace pas ce dossier entier dans APM_Core.

1. Commande : Commands/MonJeu/MonJeu_Informer -> APM_Extensions.Commands/MonJeu
2. Page : ClientPages/MonJeu/MonJeuPage -> APM_Extensions.ClientPages/MonJeu
   Garde les attributs du ModuleScript et déclare MonJeu.Page dans ServerSettings.
3. Intégration : Server/MonJeuIntegration -> APM_Extensions.Server
4. AutoBridge : Adapters/MonJeuStatus -> APM_Extensions.Adapters
   Déclare MonJeu.Status dans ServerSettings.

Aucune permission n'est ajoutée automatiquement. Choisis les grades dans ta configuration.
Utilise des Id de namespace et de commande uniques. Relance Play après une modification.
Diagnostics affiche le chemin source, le champ invalide et la correction attendue.
Le README fournit le guide complet et les autres langues.
]]
return {}
