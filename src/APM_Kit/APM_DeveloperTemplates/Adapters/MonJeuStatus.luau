-- Copie ce ModuleScript dans APM_Extensions.Adapters. AutoBridge doit être activé.
-- Déclare explicitement dans ServerSettings :
-- Settings.PermissionDefaults = { ["MonJeu.Status"] = "Owner" } -- grade choisi par le dev
-- Ce modèle est une intégration en lecture seule : il ne modifie pas le jeu.
return {
	ApiVersion=1, Id="MonJeuStatus",
	Adapter={
		Permission="MonJeu.Status",
		Probe=function(ctx)
			return {
				Name="MonJeu", DisplayName={fr="Mon jeu",en="My game"}, Status="Operational", Count=#game:GetService("Players"):GetPlayers(),
				Detail={fr="Intégration serveur de démonstration.",en="Example server integration."},
			}
		end,
		Actions={ -- lecture seule tant que cette table reste vide.
			-- Pour ajouter une action, déclare MonJeu.Action et adapte ce bloc :
			-- MonAction = {
			--   Permission="MonJeu.Action", Target=true, AllowSelf=false,
			--   Label={fr="Mon action",en="My action"},
			--   Validate=function(ctx,admin,target,args)
			--     -- Valide et copie uniquement les valeurs attendues. nil,error refuse.
			--     return {}, nil
			--   end,
			--   Execute=function(ctx,admin,target,clean)
			--     -- Appelle ton système serveur ici après les vérifications APM.
			--     return true, {fr="Action terminée.",en="Action completed."}
			--   end,
			-- },
		},
	},
}
