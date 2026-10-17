-- Copie le dossier MonJeu dans APM_Extensions.ClientPages, pas le ModuleScript seul.
-- Les attributs ApiVersion=1 et Permission="MonJeu.Page" sont déjà définis sur ce modèle.
-- Déclare toi-même l'accès dans APM_Extensions.Config.ServerSettings :
-- Settings.PermissionDefaults = { ["MonJeu.Page"] = "Owner" } -- grade choisi explicitement
-- Ne place jamais de secret dans une page client.
local Page = {
	ApiVersion=1, Permission="MonJeu.Page", Id="MonJeuPage", Order=20,
	Label={fr="Mon jeu",en="My game"},
}
function Page.Build(Core, page)
	local UI = Core.UI
	local scroll = UI.scroll({Size=UDim2.fromScale(1,1)},page)
	UI.list(scroll,10)
	local card = UI.card(scroll,1)
	UI.sectionHeader(Core.Text({fr="Page personnalisée",en="Custom page"}),Core.T.accent,card,1)
	UI.label({
		Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y,
		TextWrapped=true, TextSize=13, LayoutOrder=2,
		Text=Core.Text({fr="Ton interface va ici. Les actions doivent passer par les commandes serveur APM.",en="Build your UI here. Actions must use APM server commands."}),
	},card)
	-- Core.Action("MonJeu_Informer", nil, {Message="Bonjour"}) exécute une commande autorisée.
	-- Core.On(signal, callback) nettoie les connexions quand le panneau se reconstruit.
end
return Page
