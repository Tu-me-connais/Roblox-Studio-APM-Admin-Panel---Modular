--[[
	Config : réglages PARTAGÉS de l'APM, lus par le serveur ET par chaque client.
	Rien de secret ici (les clients peuvent le lire) : grades, UserIds et sauvegarde sont dans
	ServerScriptService > APM_Server > Settings.
]]
local Config = {}

-- LANGUE ----------------------------------------------------------------------------------------------
-- L'APM s'affiche automatiquement dans la langue du compte Roblox de chaque joueur (Player.LocaleId : "fr-fr" -> "fr").
-- Langues fournies : les ModuleScripts de APM_Shared > Lang (en, fr, es, pt, de). Le READ ME explique comment en ajouter une.
Config.DefaultLanguage = "en" -- langue de secours quand celle du joueur n'est pas traduite
Config.ForceLanguage = nil -- ex. "fr" : même langue pour tout le monde (nil = automatique, recommandé)
Config.LanguageButton = true -- bouton de langue dans l'en-tête du panneau (choix manuel, valable pour la session)

-- OUVERTURE DU PANNEAU ------------------------------------------------------------------------------------
Config.OpenKey = Enum.KeyCode.F2 -- ouvre / ferme le panneau
Config.RecenterKey = Enum.KeyCode.Z -- recentre la fenêtre quand elle est ouverte
Config.MobileButton = true -- bouton « APM » à l'écran sur téléphone / tablette (pas de clavier)

-- INTERFACE -------------------------------------------------------------------------------------------------
Config.Title = "APM"
Config.Theme = {
	bg = Color3.fromRGB(24, 26, 32),
	panel = Color3.fromRGB(32, 35, 43),
	panel2 = Color3.fromRGB(40, 44, 54),
	stroke = Color3.fromRGB(58, 63, 76),
	accent = Color3.fromRGB(88, 128, 232),
	text = Color3.fromRGB(238, 240, 246),
	sub = Color3.fromRGB(150, 157, 172),
	good = Color3.fromRGB(80, 175, 110),
	bad = Color3.fromRGB(205, 75, 75),
	warn = Color3.fromRGB(224, 168, 62),
	font = Enum.Font.GothamMedium,
	fontBold = Enum.Font.GothamBold,
}

-- Groupes de boutons de l'onglet Joueurs (champ Group des modules) : ordre et couleur.
-- Un groupe absent de cette liste est ajouté à la fin, avec la couleur d'accent. Titre affiché : traduction "Group.<Id>".
Config.PlayerGroups = {
	{ Id = "Sanctions", Color = Color3.fromRGB(205, 95, 95) },
	{ Id = "Assistance", Color = Color3.fromRGB(80, 175, 110) },
	{ Id = "Movement", Color = Color3.fromRGB(88, 128, 232) },
}

-- Developer-owned configuration is cloned by the bootstrap from outside Core.
local custom = script.Parent:FindFirstChild("CustomConfig")
assert(custom and custom:IsA("ModuleScript"), "[APM] CustomConfig missing; use the external bootstrap")
local override = require(custom)
assert(type(override) == "table", "[APM] SharedConfig must return a table")
return require(script.Parent.Configuration).Merge(Config, override)
