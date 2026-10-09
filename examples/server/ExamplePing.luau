-- Optional: APM_Extensions.Commands.Examples.ExamplePing. Never installed automatically.
local Players=game:GetService("Players")
return {
	ApiVersion=1,
	Name="ExamplePing",
	Category="Examples",
	Mode="action",
	MinRank="Owner",
	Order=100,
	Label={fr="État réel du serveur",en="Live server status"},
	Description={fr="Consulte les joueurs présents et le temps de fonctionnement.",en="Read current players and server uptime."},
	Strings={fr={["Mod.ExamplePing.Done"]="%d / %d joueurs ; serveur actif depuis %d s."},
		en={["Mod.ExamplePing.Done"]="%d / %d players; server running for %d s."}},
	Execute=function(ctx,admin)
		if not ctx.Authorize(admin,"ExamplePing") then return false,{fr="Accès refusé.",en="Access denied."} end
		return true,ctx.Msg("Mod.ExamplePing.Done",#Players:GetPlayers(),Players.MaxPlayers,math.floor(workspace.DistributedGameTime))
	end,
}
