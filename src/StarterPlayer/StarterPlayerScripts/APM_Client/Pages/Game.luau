--[[
	Game : onglet « Jeu ». Une carte par module serveur de catégorie « Game » (leaderstats, outils, heure, maintenance...).
	Les champs viennent de la déclaration du module (Fields) : ajouter un module Game dans APM_Server > Modules ajoute sa carte ici,
	sans toucher au client. La mise en page est celle de CategoryPage (commune à tous les onglets de catégorie).
]]
local CategoryPage = require(script.Parent.Parent:WaitForChild("CategoryPage"))

local Page = { Id = "Game", Order = 2, Label = "Tab.Game", Handles = { "Game" } }

function Page.Build(Core, page)
	CategoryPage.Build(Core, page, "Game")
end

return Page

