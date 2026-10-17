-- Copie ce ModuleScript dans APM_Extensions.Server ; aucun accès n'est ajouté par ce modèle.
-- Init(api) s'exécute au démarrage. Enregistre les commandes ici, avant task.spawn/task.defer.
-- Ne fais pas APM.WaitForReady() dans Init(api) : l'APM attend déjà la fin de cet appel.
return {
	ApiVersion=1, Id="MonJeuIntegration",
	Init=function(api)
		local key, problem = api.RegisterOptions("Zones",function()
			return {{"Lobby",{fr="Accueil",en="Lobby"}},{"Arena",{fr="Arène",en="Arena"}}}
		end)
		assert(key,problem) -- key = "MonJeuIntegration.Zones" pour Fields[i].Options.
		local registered, issue = api.AddProfileProvider(function(userId, player)
			-- Ces lignes sont visibles par les administrateurs : aucune donnée secrète ici.
			return {{Label={fr="Zone",en="Zone"},Value=player and player:GetAttribute("Zone") or "—"}}
		end)
		assert(registered,issue)
		-- api.RegisterCommand(commande) -> success, code ; vérifie toujours son résultat.
		-- api.RegisterAdapter(nom, adaptateur) -> success, code.
		-- api.HasPermission(player,permission), api.CanTarget(admin,target),
		-- api.Notify(player,message,success), api.Log(actor,action,target,detail,level).
		return true
	end,
}
