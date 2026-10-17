--[[
	Funny : effets amusants sur les personnages (décors, transformations, physique), lancés depuis l'onglet Funny.
	Toute l'autorité est sur le serveur ; les clients publics n'affichent que les décors.

	Sous-modules :
	  Catalog     catalogue des effets et validation stricte des demandes
	  Scenes      moteur des scènes (droits, réservations, démarrage, arrêt, restauration)
	  Transforms  transformations du personnage avec restauration exacte
	  Network     diffusion entre serveurs (MessagingService)
]]
local Catalog = require(script.Catalog)
local Scenes = require(script.Scenes)

local Funny = {}
Funny.EffectFeature = Catalog.EffectFeature
Funny.Effects = Catalog.Effects
Funny.ValidateRequest = Catalog.ValidateRequest
Funny.Create = Scenes.Create

local function msg(fr, en)
	return { fr = fr, en = en }
end

function Funny.Init(ctx)
	if ctx.Funny and ctx.Funny.Snapshot then return end
	local api = Funny.Create(ctx)
	ctx.Funny = api
	local network = require(script.Network).Create(ctx, api)
	api.Network = network
	ctx.Remotes.GetFunny.OnServerInvoke = function(p)
		if not ctx.Guard.Allow(p, "GetFunny", 10, 10) then return nil end
		local data = api.Snapshot(p)
		if data then data.Network = network.Snapshot(p) end
		return data
	end
	ctx.Remotes.StartFunny.OnServerInvoke = function(p, r)
		if not ctx.Guard.Allow(p, "StartFunny", 3, 10) then return false, msg("Attends avant de relancer.", "Wait before another launch.") end
		if type(r) ~= "table" then return false, msg("Paramètres invalides.", "Invalid parameters.") end
		local clean = table.clone(r)
		local reach = clean.Reach or "Local"
		clean.Reach = nil
		if reach ~= "Local" and reach ~= "Server" and reach ~= "CrossServer" then return false, msg("Portée invalide.", "Invalid reach.") end
		if reach == "Local" and clean.Scope == "Server" then return false, msg("Portée invalide.", "Invalid reach.") end
		if reach ~= "Local" then
			clean.Scope = "Server"
			clean.TargetUserId = nil
		end
		if reach == "CrossServer" then return network.Start(p, clean) end
		return api.Start(p, clean, { Reach = reach })
	end
	ctx.Remotes.StopFunny.OnServerInvoke = function(p, id)
		if not ctx.Guard.Allow(p, "StopFunny", 10, 10) then return false, msg("Attends avant une nouvelle demande.", "Wait before another request.") end
		if id == "CrossMine" then
			if not api.Can(p, "Funny.View") then return false end
			return network.StopMine(p)
		end
		local batches = api.NetworkIds(p, id)
		local success, reply = api.Stop(p, id)
		if success then
			network.StopSelected(p, batches)
			if id == "Mine" then network.StopMine(p) end
		end
		return success, reply
	end
end

return Funny
