--[[
	SharedConfig : TES réglages PARTAGÉS de l'APM, lus par le serveur ET par chaque client (rien de secret ici).

	Ce fichier ne contient que ce que tu personnalises. Les valeurs officielles (langue, touches, titre, thème, groupes de
	boutons) sont documentées dans APM_Core > Shared > Config ; copie une ligne ici pour la remplacer.
	Le thème se fusionne couleur par couleur : Config.Theme = { accent = Color3.fromRGB(230, 90, 90) } ne change que l'accent.
]]
local Config = {}

-- EXEMPLES COURANTS (retire le « -- » pour activer) --------------------------------------------------------
-- Config.ForceLanguage = "fr"                        -- même langue pour tout le monde (nil = langue du compte Roblox)
-- Config.DefaultLanguage = "en"                      -- langue de secours
-- Config.OpenKey = Enum.KeyCode.F2                   -- touche qui ouvre le panneau
-- Config.Title = "APM"                               -- titre de la fenêtre
-- Config.Theme = { accent = Color3.fromRGB(88, 128, 232) }

return Config
