-- Optional: APM_Extensions.Server.ExampleRoster. All data below is ordinary public player/team information.
local Players=game:GetService("Players")
local Teams=game:GetService("Teams")
return {
	ApiVersion=1,
	Id="example_roster",
	Init=function(api)
		local optionsKey,problem=api.RegisterOptions("teams",function()
			local list={}
			for _,team in Teams:GetTeams() do table.insert(list,{team.Name,team.Name}) end
			table.sort(list,function(a,b) return a[1]<b[1] end)
			return list
		end)
		assert(optionsKey,problem)
		assert(api.AddProfileProvider(function(_,player)
			if not player then return {} end
			return {{Label={fr="Équipe actuelle",en="Current team"},Value=player.Team and player.Team.Name or {fr="Aucune",en="None"}},
				{Label={fr="Âge réel du compte (jours)",en="Account age (days)"},Value=player.AccountAge}}
		end))
		local registered,why=api.RegisterCommand({
			ApiVersion=1,Name="ExampleTeamMembers",Category="Examples",Mode="action",MinRank="Owner",Order=110,
			Label={fr="Compter les membres d'une équipe",en="Count team members"},
			Fields={{Name="Team",Label={fr="Équipe",en="Team"},Type="choice",Options=optionsKey}},
			Execute=function(ctx,admin,_,value)
				if not api.Authorize(admin,"ExampleTeamMembers") then return false,{fr="Accès refusé.",en="Access denied."} end
				local team=Teams:FindFirstChild(value.Team)
				if not team or not team:IsA("Team") then return false,{fr="Équipe supprimée ou inconnue.",en="Team removed or unknown."} end
				local count=0
				for _,player in Players:GetPlayers() do if player.Team==team then count+=1 end end
				return true,{fr=string.format("%s : %d joueur(s) actuellement.",team.Name,count),en=string.format("%s: %d current player(s).",team.Name,count)}
			end,
		})
		assert(registered,why)
	end,
}
