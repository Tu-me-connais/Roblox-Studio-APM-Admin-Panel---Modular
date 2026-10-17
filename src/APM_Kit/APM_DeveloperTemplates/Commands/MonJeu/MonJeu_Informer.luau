-- Copie le dossier MonJeu dans APM_Extensions.Commands. Ce modèle est inactif ici.
-- Le nom de commande est unique dans tout l'APM, même entre plusieurs extensions.
return {
	ApiVersion = 1,
	Name = "MonJeu_Informer",
	Category = "Game",
	Mode = "action",
	MinRank = "Owner", -- Choisis explicitement un Id de Settings.Ranks.
	Label = {fr="Message de test",en="Test message"},
	Description = {fr="Exemple de commande avec un champ texte.",en="Example command with a text field."},
	Fields = {{Name="Message",Type="text",Default="Bonjour",MaxLength=120,Label={fr="Message",en="Message"}}},
	Execute = function(ctx, admin, target, value)
		-- APM valide l'accès, la hiérarchie de cible et les champs avant cet appel.
		ctx.Notify(admin, value.Message, true)
		return true, {fr="Message envoyé.",en="Message sent."}
	end,
	OnAccessRevoked = function(ctx, player)
		-- ctx est le PREMIER argument, player le DEUXIÈME.
		-- Restaure ici les effets temporaires de ce module et déconnecte ses événements.
		-- Cette commande d'exemple ne crée aucun effet persistant.
	end,
}
