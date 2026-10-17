--[[
	Noclip (outil du panneau) : interrupteur de la fenêtre de l'admin pour SON propre personnage. Le contrôleur n'est plus ici :
	il vit dans APM_Shared > ActionExecutor > Effects > Noclip et sert aussi quand le serveur applique Noclip à un joueur (Sentinel, panneau Joueurs).
	Un seul contrôleur par client, donc jamais de doublon entre le panneau et le serveur. Modèle d'un outil client : Name, Order, Set(actif), Refresh()
	+ facultatifs Init(core), State() (l'effet tourne-t-il déjà ?), Detach() (l'interface disparait : ne coupe que ce que le panneau tenait).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Executor = require(ReplicatedStorage:WaitForChild("APM_Shared"):WaitForChild("ActionExecutor"))

local M = {}
M.Name, M.Order = "Noclip", 21

local Core

-- Le serveur peut démarrer / arrêter l'effet sur CET appareil : l'interrupteur du panneau suit
function M.Init(core)
	Core = core
	local engine = Executor.Start()
	if not engine then return end
	engine.Changed:Connect(function(action, on, origin)
		if action ~= M.Name or origin == "Panel" or not Core or not Core.Enabled then return end
		Core.ToolState[M.Name] = on and true or nil
		if Core.AccessChanged then pcall(function() Core.AccessChanged:Fire() end) end
	end)
end

function M.Set(on)
	local engine = Executor.Start()
	if not engine then return false end
	if on then
		return engine.Acquire(M.Name, "Panel")
	end
	engine.Release(M.Name, "Panel")
end

function M.State()
	local engine = Executor.Get()
	return engine ~= nil and engine.IsActive(M.Name)
end

-- Nouveau personnage : sans effet si le contrôleur y tourne déjà
function M.Refresh()
	local engine = Executor.Get()
	if engine then engine.Refresh(M.Name) end
end

-- Reconstruction ou retrait d'accès du panneau : on ne coupe que l'effet que le panneau avait lancé lui-même (renvoie vrai s'il l'a coupé)
function M.Detach()
	local engine = Executor.Get()
	if engine and engine.Origin(M.Name) == "Panel" then
		engine.Detach(M.Name, "Panel")
		return true
	end
	return false
end

return M
