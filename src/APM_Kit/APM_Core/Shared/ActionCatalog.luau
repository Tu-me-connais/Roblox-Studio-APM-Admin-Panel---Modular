--[[
	ActionCatalog : liste FERMÉE des actions distribuées par le serveur aux clients (Dispatcher -> ActionExecutor).
	Le serveur et le client lisent la MÊME déclaration : une action absente d'ici n'existe pas, ni à l'envoi ni à la réception.
	Aucun code ne voyage jamais : un paquet ne contient qu'un nom d'action de cette liste, des paramètres typés et bornés, un identifiant
	unique, un numéro d'ordre et une date d'expiration.

	Classes d'une commande de l'APM :
	  Server        s'exécute entièrement sur le serveur (Kick, Freeze, Mute, Speed...)
	  ClientSelf    effet local d'observation ou d'interface de l'admin, jamais distribué (ESP, Spectator)
	  ClientTarget  s'exécute sur le client de la CIBLE, décidé et suivi par le serveur (Fly)
	  Hybrid        client de la cible + soutien serveur (Noclip : le serveur coupe aussi les collisions pour les autres joueurs)

	Ajouter une action distribuée : (1) la déclarer ici, (2) écrire son contrôleur dans ActionExecutor/Effects/<Nom>,
	(3) facultatif : un soutien serveur dans Core/Dispatcher/Hooks. Voir le « READ ME!!! ».
]]
local Catalog = {}

Catalog.Version = 1
Catalog.TTL = 20 -- secondes de validité d'une instruction (horloge serveur partagée)
Catalog.MaxSeq = 2 ^ 31

-- Déclarations. Params : { [nom] = { Type = "number", Min, Max, Default } } ; Respawn : Persist (l'effet suit le joueur) ou Clear (coupé au décès)
local EFFECTS = {
	Fly = {
		Kind = "ClientTarget", Respawn = "Persist", Order = 20,
		Params = { Speed = { Type = "number", Min = 8, Max = 200, Default = 70 } },
	},
	Noclip = {
		Kind = "Hybrid", Respawn = "Persist", Order = 21,
		Params = {},
	},
}

-- Réponses autorisées d'un client (statut, détail) et raisons de fin d'effet : listes fermées, rien de libre ne remonte au serveur
Catalog.Statuses = { Applied = true, Stopped = true, Rejected = true, Expired = true, Failed = true }
Catalog.Details = { Armed = true, Idle = true, NoCharacter = true, Stale = true, Unsupported = true, Params = true, Shape = true, Version = true, Error = true, Expired = true }
Catalog.EndReasons = { Respawn = true, Panel = true, Error = true, Local = true }
Catalog.Ops = { Start = true, Stop = true }

function Catalog.Get(name)
	if type(name) ~= "string" then return nil end
	return EFFECTS[name]
end

function Catalog.Names()
	local list = {}
	for name in EFFECTS do table.insert(list, name) end
	table.sort(list, function(a, b) return EFFECTS[a].Order < EFFECTS[b].Order end)
	return list
end

function Catalog.Kind(name)
	local definition = Catalog.Get(name)
	return definition and definition.Kind or nil
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
Catalog.Finite = finite

function Catalog.IsGuid(value)
	return type(value) == "string" and #value == 36 and string.match(value, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

--[[
	Paramètres d'une action -> table propre, ou nil + code. strict = true (client) : toute valeur hors bornes, tout champ inconnu, tout type
	inattendu est REFUSÉ. strict = false (serveur, panneau local) : les nombres sont ramenés dans les bornes, les champs inconnus refusés.
]]
function Catalog.CleanParams(name, params, strict)
	local definition = Catalog.Get(name)
	if not definition then return nil, "Unsupported" end
	if params ~= nil and type(params) ~= "table" then return nil, "Params" end
	local source = params or {}
	for key in source do
		if type(key) ~= "string" or definition.Params[key] == nil then return nil, "Params" end
	end
	local clean = {}
	for key, schema in definition.Params do
		local value = source[key]
		if value == nil then
			clean[key] = schema.Default
		elseif schema.Type == "number" then
			if not finite(value) then return nil, "Params" end
			if strict and (value < schema.Min or value > schema.Max) then return nil, "Params" end
			clean[key] = math.clamp(value, schema.Min, schema.Max)
		elseif schema.Type == "boolean" then
			if type(value) ~= "boolean" then return nil, "Params" end
			clean[key] = value
		else
			return nil, "Params"
		end
	end
	return clean
end

local PACKET_KEYS = { V = true, Id = true, Seq = true, Op = true, Effect = true, Params = true, Expires = true }

--[[
	Paquet reçu par un client -> paquet propre, ou nil + code (Shape | Version | Unsupported | Params | Expired).
	now : heure serveur courante ; sans elle, l'expiration n'est pas vérifiée.
]]
function Catalog.CleanPacket(packet, now)
	if type(packet) ~= "table" then return nil, "Shape" end
	for key in packet do
		if type(key) ~= "string" or not PACKET_KEYS[key] then return nil, "Shape" end
	end
	if packet.V ~= Catalog.Version then return nil, "Version" end
	if not Catalog.IsGuid(packet.Id) then return nil, "Shape" end
	if not finite(packet.Seq) or packet.Seq < 1 or packet.Seq > Catalog.MaxSeq or packet.Seq % 1 ~= 0 then return nil, "Shape" end
	if type(packet.Op) ~= "string" or not Catalog.Ops[packet.Op] then return nil, "Shape" end
	if not Catalog.Get(packet.Effect) then return nil, "Unsupported" end
	if not finite(packet.Expires) then return nil, "Shape" end
	local params
	if packet.Op == "Start" then
		local reason
		params, reason = Catalog.CleanParams(packet.Effect, packet.Params, true)
		if not params then return nil, reason end
	elseif packet.Params ~= nil then
		return nil, "Params"
	end
	if now ~= nil then
		if not finite(now) then return nil, "Shape" end
		if packet.Expires < now then return nil, "Expired" end
		if packet.Expires > now + Catalog.TTL * 2 then return nil, "Shape" end
	end
	return { V = packet.V, Id = packet.Id, Seq = packet.Seq, Op = packet.Op, Effect = packet.Effect, Params = params, Expires = packet.Expires }
end

return Catalog
