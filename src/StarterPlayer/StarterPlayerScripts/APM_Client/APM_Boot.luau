--[[
	APM_Boot : démarre le panneau côté client (APM_Client > Core).
	Pour un joueur sans grade, rien n'est créé ; si un grade lui est donné en cours de partie, le panneau apparaît tout seul.
	Si le client est arrivé deux fois (installation automatique + StarterPlayerScripts), seul le premier démarre.
]]
local Core = require(script.Parent:WaitForChild("Core"))
Core.Start()
