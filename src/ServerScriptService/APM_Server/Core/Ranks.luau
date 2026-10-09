--[[
	Ranks : grades de l'APM, matrice d'accès « module x grade », sauvegarde et synchronisation entre serveurs.

	Grade d'un compte = le PLUS HAUT de ses sources :
	  Settings.Users (fixe) · créateur du jeu (Settings.CreatorRank) · grade donné dans le panneau (ou Settings.DefaultUsers)
	  · rang dans Settings.Group · Settings.StudioRank (Studio seulement)
	L'attribution prioritaire du propriétaire réel (OwnerAuthority_v2) peut remplacer les sources d'un autre compte.
	Un admin n'agit que sur un grade strictement inférieur au sien ; le SuperRank n'est ciblable par personne.

	Matrice d'accès : chaque module a des valeurs par défaut (d'après son MinRank) ; ce que l'onglet Paramètres change est
	enregistré (clé "Access") et l'emporte. Le SuperRank conserve les commandes héritées ; les permissions dédiées restent configurables.
	Sans DataStore EN STUDIO : mode mémoire (tout marche, rien n'est enregistré). En jeu publié, une lecture ratée refuse par prudence.
]]
local DataStoreService = game:GetService("DataStoreService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local GroupService = game:GetService("GroupService")

local Settings = require(script.Parent.Parent:WaitForChild("Settings"))
local Lang = require(ReplicatedStorage:WaitForChild("APM_Shared"):WaitForChild("Lang"))
local Msg = Lang.Msg

local IS_STUDIO = RunService:IsStudio()

local Ranks = {}
local simulations = {} -- session-only; never written to a DataStore
local simulationGeneration = 0
local ownerOverrides = {}
local ownerRevision = -1
local OWNER_KEY = "OwnerAuthority_v2"
Ranks.OwnerAuthorityReady = false
Ranks.PermissionNames = {}
local reconcileSimulations

----------------------------------------------------------------------------------------------------------
-- Définition des grades (Settings.Ranks)

Ranks.List, Ranks.ById = {}, {}
for _, def in Settings.Ranks or {} do
	if type(def) == "table" and type(def.Id) == "string" and def.Id ~= "" and def.Id ~= "None" and type(def.Level) == "number" and def.Level > 0
		and not Ranks.ById[def.Id] then
		local entry = {
			Id = def.Id,
			Level = def.Level,
			Color = typeof(def.Color) == "Color3" and def.Color or Color3.fromRGB(150, 157, 172),
			Fixed = def.Fixed == true,
			Name = type(def.Name) == "string" and def.Name or nil,
		}
		Ranks.ById[def.Id] = entry
		table.insert(Ranks.List, entry)
	end
end
table.sort(Ranks.List, function(a, b)
	return a.Level > b.Level
end)
assert(#Ranks.List > 0, "[APM] Settings.Ranks ne contient aucun grade valide.")

local function rankOrNil(id)
	if type(id) == "string" and Ranks.ById[id] then
		return id
	end
	return nil
end

Ranks.Super = rankOrNil(Settings.SuperRank) or Ranks.List[1].Id
Ranks.Manager = rankOrNil(Settings.ManagerRank) or Ranks.Super
Ranks.Announcer = rankOrNil(Settings.AnnounceRank) or Ranks.List[#Ranks.List].Id
local CREATOR_RANK = rankOrNil(Settings.CreatorRank)
local STUDIO_RANK = rankOrNil(Settings.StudioRank)

function Ranks.Level(rankId)
	local rank = type(rankId) == "string" and Ranks.ById[rankId] or nil
	return rank and rank.Level or 0
end

-- Grade qu'on peut donner / retirer depuis le panneau
function Ranks.IsAssignable(rankId)
	local rank = type(rankId) == "string" and Ranks.ById[rankId] or nil
	return rank ~= nil and not rank.Fixed and rankId ~= Ranks.Super
end

-- Liste envoyée au client (badges, colonnes de la matrice, choix de grade)
function Ranks.Public()
	local list = {}
	for _, rank in Ranks.List do
		table.insert(list, { Id = rank.Id, Level = rank.Level, Color = rank.Color, Fixed = not Ranks.IsAssignable(rank.Id), Name = rank.Name })
	end
	return list
end

-- UserId valide (les comptes de test négatifs de Studio, Player1 = -1..., ne sont acceptés qu'en Studio)
function Ranks.ValidUserId(userId)
	if type(userId) ~= "number" or userId ~= userId or math.abs(userId) >= 2 ^ 53 or userId % 1 ~= 0 then
		return false
	end
	return userId > 0 or (userId < 0 and IS_STUDIO)
end

----------------------------------------------------------------------------------------------------------
-- Sauvegarde (DataStore de l'APM, partagé avec le journal, les bans, les avertissements et l'annuaire)

local store
Ranks.Memory = false

local function enterMemory(reason)
	if Ranks.Memory then
		return
	end
	Ranks.Memory = true
	store = nil
	if reason == "Settings.StudioMemory" then
		print("[APM] Tests Studio isolés : mode mémoire demandé, aucune écriture dans les sauvegardes publiées.")
	else
		warn(("[APM] DataStore inaccessible (%s) : MODE MÉMOIRE, rien n'est enregistré. En Studio : Paramètres du jeu > Sécurité > "
			.. "Activer l'accès de Studio aux services API."):format(tostring(reason)))
	end
end

do
	if IS_STUDIO and Settings.StudioMemory == true then
		enterMemory("Settings.StudioMemory")
	else
		local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, Settings.DataStoreName or "APM_Data_v1")
		if ok then
			store = result
		elseif IS_STUDIO then
			enterMemory(result)
		else
			warn("[APM] DataStore unavailable: privileged access remains closed. " .. tostring(result))
		end
	end
end

-- Le DataStore de l'APM (nil en mode mémoire)
function Ranks.GetStore()
	return store
end

-- Lit une clé : valeur, ok (ok = false : lecture impossible, on reste prudent)
local function load(key)
	if not store then
		return nil, Ranks.Memory
	end
	local attempts = IS_STUDIO and 1 or 3
	local lastError
	for attempt = 1, attempts do
		local ok, value = pcall(store.GetAsync, store, key)
		if ok then
			return value, true
		end
		lastError = value
		if attempt < attempts then
			task.wait(attempt)
		end
	end
	if IS_STUDIO then
		enterMemory(lastError)
		return nil, true
	end
	warn(("[APM] Lecture impossible (%s) : %s"):format(key, tostring(lastError)))
	return nil, false
end

local TOPIC = Settings.MessagingTopic or "APM_Sync_v1"
local function publish()
	if reconcileSimulations then
		reconcileSimulations()
	end
	if Ranks.OnChanged then
		-- Rights and private sessions are invalidated before the mutation returns.
		local ok, err = pcall(Ranks.OnChanged)
		if not ok then
			warn("[APM] Rights refresh failed: " .. tostring(err))
		end
	end
	if store then
		task.spawn(function()
			pcall(MessagingService.PublishAsync, MessagingService, TOPIC, game.JobId)
		end)
	end
end

----------------------------------------------------------------------------------------------------------
-- Grades donnés dans le panneau (clé "Ranks")

Ranks.Dynamic = {} -- [userId] = Id du grade, ou "None" (retiré alors qu'il était dans Settings.DefaultUsers)
Ranks.SecurityReady = false
local rankRevision = -1

local function readRankMap(data)
	local map = {}
	for key, rank in data do
		local userId = tonumber(key)
		if userId and Ranks.ValidUserId(userId) and (rank == "None" or Ranks.IsAssignable(rank)) then
			map[userId] = rank
		end
	end
	return map
end

function Ranks.LoadRanks()
	local data, ok = load("Ranks")
	if not ok then
		Ranks.SecurityReady = false
		return false
	end
	Ranks.SecurityReady = true
	if type(data) ~= "table" then
		if data ~= nil then Ranks.SecurityReady = false; return false end
		Ranks.Dynamic = {}
		rankRevision = 0
		return true
	end
	local revision = tonumber(data._Revision) or 0
	if revision < rankRevision then
		return true
	end
	rankRevision = revision
	Ranks.Dynamic = readRankMap(data)
	return true
end

-- Donne (rankId) ou retire (nil) un grade enregistré. Renvoie ok, message.
function Ranks.SetRank(userId, rankId, validate)
	if typeof(validate) == "Instance" and validate:IsA("Player") then
		local actor = validate
		validate = function()
			return actor.Parent == Players and Ranks.IsAdmin(actor) and Ranks.HasPermission(actor, "APM.ManagePermissions")
				and actor.UserId ~= userId and not Ranks.IsFixed(userId)
				and (Ranks.IsSuper(actor) or (Ranks.Level(Ranks.GetRealRankByUserId(userId)) < Ranks.GetLevel(actor)
					and (not rankId or Ranks.Level(rankId) < Ranks.GetLevel(actor))))
		end
	elseif validate ~= nil and type(validate) ~= "function" then
		return false, Msg("Srv.InvalidParams")
	end
	if not Ranks.ValidUserId(userId) or (validate and not validate()) then
		return false, Msg("Srv.AccessChanged")
	end
	if rankId ~= nil and not Ranks.IsAssignable(rankId) then
		return false, Msg("Srv.UnknownRank")
	end
	local value = rankId
	if value == nil and Settings.DefaultUsers and Settings.DefaultUsers[userId] then
		value = "None" -- sinon le grade de départ reviendrait
	end
	if not store and not Ranks.Memory then
		return false, Msg("Srv.RankSaveFailed")
	end
	if not store then
		Ranks.Dynamic[userId] = value
		Ranks.SecurityReady = true
		publish()
		return true
	end
	local cancelled = false
	local ok, result = pcall(store.UpdateAsync, store, "Ranks", function(old)
		if validate and not validate() then
			cancelled = true
			return nil
		end
		local map = type(old) == "table" and old or {}
		map[tostring(userId)] = value
		map._Revision = (tonumber(map._Revision) or 0) + 1
		return map
	end)
	if not ok or cancelled or type(result) ~= "table" then
		return false, Msg("Srv.RankSaveFailed")
	end
	local revision = tonumber(result._Revision) or 0
	if revision >= rankRevision then
		rankRevision = revision
		Ranks.Dynamic = readRankMap(result)
	end
	Ranks.SecurityReady = true
	publish()
	return true
end

----------------------------------------------------------------------------------------------------------
-- Matrice d'accès (clé "Access") : valeurs enregistrées par-dessus les valeurs par défaut des modules

Ranks.Access = {} -- [module] = { [Id du grade] = true / false } (choix faits dans le panneau)
Ranks.Defaults = {} -- [module] = { [Id du grade] = true / false } (d'après le MinRank du module)
Ranks.AccessReady = false
local accessRevision = -1

function Ranks.LoadAccess()
	local data, ok = load("Access")
	if not ok then
		Ranks.AccessReady = false
		return false
	end
	Ranks.AccessReady = true
	if type(data) ~= "table" then
		if data ~= nil then Ranks.AccessReady = false; return false end
		Ranks.Access = {}
		accessRevision = 0
		return true
	end
	local revision = tonumber(data._Revision) or 0
	if revision < accessRevision then
		return true
	end
	accessRevision = revision
	data._Revision = nil
	Ranks.Access = data
	return true
end

-- Déclare des modules dans la matrice : list = { module, ... } (MinRank lu) ou { "Nom", ... } ; allowAll : tous les grades par défaut
function Ranks.InitModuleAccess(list, allowAll)
	for _, info in list do
		local name = type(info) == "table" and info.Name or info
		if type(name) == "string" and name ~= "" then
			local minimum = type(info) == "table" and Ranks.Level(info.MinRank) or 0
			local entry = Ranks.Defaults[name] or {}
			Ranks.Defaults[name] = entry
			for _, rank in Ranks.List do
				if rank.Id ~= Ranks.Super and entry[rank.Id] == nil then
					entry[rank.Id] = allowAll == true or rank.Level >= minimum
				end
			end
		end
	end
	-- Named permissions share the existing Access key and revision protocol.
	for name, config in Settings.PermissionDefaults or {} do
		if type(name) == "string" and #name <= 64 then
			Ranks.PermissionNames[name] = true
			local minimum = type(config) == "table" and config.MinRank or config
			local entry = Ranks.Defaults[name] or {}
			Ranks.Defaults[name] = entry
			for _, rank in Ranks.List do
				entry[rank.Id] = minimum == true or (type(minimum) == "string" and Ranks.ById[minimum] ~= nil and rank.Level >= Ranks.Level(minimum))
			end
		end
	end
end

-- Ce grade a-t-il accès à ce module ? (choix enregistré, sinon valeur par défaut ; module inconnu : non)
function Ranks.Allowed(name, rankId)
	if rankId == Ranks.Super and not Ranks.PermissionNames[name] then
		return true
	end
	local stored = Ranks.Access[name]
	if type(stored) == "table" and type(stored[rankId]) == "boolean" then
		return stored[rankId]
	end
	local default = Ranks.Defaults[name]
	return default ~= nil and default[rankId] == true
end

-- Matrice complète pour le client : { [module] = { [grade] = bool } }
function Ranks.GetModuleAccess()
	local view = {}
	for name in Ranks.Defaults do
		local entry = {}
		for _, rank in Ranks.List do
			entry[rank.Id] = Ranks.Allowed(name, rank.Id)
		end
		view[name] = entry
	end
	return view
end

function Ranks.SetModuleAccess(name, rankId, allowed, validate)
	if typeof(validate) == "Instance" and validate:IsA("Player") then
		local actor = validate
		validate = function() return Ranks.CanManagePermissionColumn(actor, name, rankId) end
	elseif validate ~= nil and type(validate) ~= "function" then
		return false, Msg("Srv.InvalidParams")
	end
	if type(name) ~= "string" or not Ranks.Defaults[name] or not Ranks.ById[rankId] or (rankId == Ranks.Super and not Ranks.PermissionNames[name]) or type(allowed) ~= "boolean" then
		return false, Msg("Srv.InvalidParams")
	end
	if validate and not validate() then
		return false, Msg("Srv.AccessChanged")
	end
	if not store and not Ranks.Memory then
		return false, Msg("Srv.AccessSaveFailed")
	end
	if not store then
		Ranks.Access[name] = type(Ranks.Access[name]) == "table" and Ranks.Access[name] or {}
		Ranks.Access[name][rankId] = allowed
		Ranks.AccessReady = true
		publish()
		return true, Msg("Srv.AccessSaved")
	end
	local cancelled = false
	local ok, result = pcall(store.UpdateAsync, store, "Access", function(old)
		if validate and not validate() then
			cancelled = true
			return nil
		end
		local map = type(old) == "table" and old or {}
		map[name] = type(map[name]) == "table" and map[name] or {}
		map[name][rankId] = allowed
		map._Revision = (tonumber(map._Revision) or 0) + 1
		return map
	end)
	if not ok or cancelled or type(result) ~= "table" then
		return false, Msg("Srv.AccessSaveFailed")
	end
	local revision = tonumber(result._Revision) or 0
	if revision >= accessRevision then
		accessRevision = revision
		result._Revision = nil
		Ranks.Access = result
	end
	Ranks.AccessReady = true
	publish()
	return true, Msg("Srv.AccessSaved")
end

----------------------------------------------------------------------------------------------------------
-- Grade d'un compte

local groupRanks = {} -- [userId] = grade venant de Settings.Group (calculé à la connexion)
local groupOwners = {} -- [userId] = true : propriétaire du groupe qui possède le jeu
local resolved = {} -- [userId] = true : sources asynchrones (groupes) déjà lues
local offlineResolvedAt = {}
local creatorGroupOwnerId, creatorOwnerAt = nil, -math.huge
local creatorOwnerReading = false
local resolving = {} -- keyed by Player identity, not UserId, so reconnects cannot share a pending lookup
local function simulationEnabled()
	return type(Settings.Modules) ~= "table" or Settings.Modules.Simulation ~= false
end

local function readCreatorGroupOwner(force)
	if game.CreatorType ~= Enum.CreatorType.Group or game.CreatorId == 0 then return true end
	if creatorOwnerReading then
		local deadline = os.clock() + 10
		while creatorOwnerReading and os.clock() < deadline do task.wait(0.1) end
		return not creatorOwnerReading and creatorGroupOwnerId ~= nil
	end
	-- Keep successful reads cached; a failed lookup must be retryable at the next sync tick.
	local cacheSeconds = creatorGroupOwnerId and 60 or 10
	if not force and os.clock() - creatorOwnerAt < cacheSeconds then return creatorGroupOwnerId ~= nil end
	creatorOwnerReading = true
	local ok, data = pcall(GroupService.GetGroupInfoAsync, GroupService, game.CreatorId)
	creatorOwnerReading = false
	creatorOwnerAt = os.clock()
	if not ok or type(data) ~= "table" or type(data.Owner) ~= "table" or not Ranks.ValidUserId(data.Owner.Id) then
		creatorGroupOwnerId = nil
		return false
	end
	creatorGroupOwnerId = data.Owner.Id
	return true
end

local function readGroupRank(userId, groupId, player)
	local ok, data = pcall(function() return GroupService:GetRolesInGroupAsync(userId, groupId) end)
	if ok and type(data) == "table" and type(data.IsMember) == "boolean" then
		if not data.IsMember then return 0, true end
		if type(data.Roles) ~= "table" then return nil, false end
		local maximum = 0
		for _, role in data.Roles do
			if type(role) ~= "table" or type(role.Rank) ~= "number" then return nil, false end
			maximum = math.max(maximum, role.Rank)
		end
		return maximum, true
	end
	-- Compatibility with runtimes that only implement the legacy API.
	if player then
		local legacyOK, value = pcall(player.GetRankInGroup, player, groupId)
		if legacyOK and type(value) == "number" then return value, true end
	end
	return nil, false
end

local function mapGroupRank(value)
	local best, bestRank = -1, nil
	for minimum, rankId in (Settings.Group and Settings.Group.Ranks) or {} do
		if type(minimum) == "number" and rankOrNil(rankId) and value >= minimum and minimum > best then
			best, bestRank = minimum, rankId
		end
	end
	return bestRank
end

local function isCreator(userId)
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId ~= 0 and userId == game.CreatorId
	end
	return creatorGroupOwnerId ~= nil and userId == creatorGroupOwnerId
end

function Ranks.IsExperienceOwner(player)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players and isCreator(player.UserId)
end

function Ranks.LoadOwnerAuthority()
	local data, ok = load(OWNER_KEY)
	if not ok then
		Ranks.OwnerAuthorityReady = false
		return false
	end
	-- Unknown newer schemas are not silently overwritten by this version.
	if data ~= nil and (type(data) ~= "table" or data.SchemaVersion ~= 2 or type(data.Users) ~= "table") then
		Ranks.OwnerAuthorityReady = false
		warn("[APM] Unsupported OwnerAuthority_v2 schema; access remains closed.")
		return false
	end
	Ranks.OwnerAuthorityReady = true
	local revision = data and tonumber(data._Revision) or 0
	if revision < ownerRevision then
		return true
	end
	ownerRevision = revision
	local safe = {}
	for key, value in data and data.Users or {} do
		local userId = tonumber(key)
		if Ranks.ValidUserId(userId) and (value == "None" or rankOrNil(value)) then
			safe[userId] = value
		end
	end
	ownerOverrides = safe
	return true
end

function Ranks.SetOwnerAccessOverride(owner, userId, rankId)
	if not Ranks.IsExperienceOwner(owner) or simulations[owner.UserId] then
		return false, "Seul le propriétaire réel de l'expérience, hors simulation, peut modifier ces accès."
	end
	if not Ranks.ValidUserId(userId) or isCreator(userId) then
		return false, "Compte invalide ou propriétaire protégé."
	end
	if rankId ~= "None" and rankId ~= "Inherit" and not rankOrNil(rankId) then
		return false, Msg("Srv.UnknownRank")
	end
	if not Ranks.OwnerAuthorityReady or (not store and not Ranks.Memory) then
		return false, Msg("Srv.RankSaveFailed")
	end
	local value = rankId ~= "Inherit" and rankId or nil
	if not store then
		ownerOverrides[userId] = value
		ownerRevision += 1
		publish()
		return true, "Accès propriétaire enregistré."
	end
	local cancelled = false
	local ok, result = pcall(store.UpdateAsync, store, OWNER_KEY, function(old)
		if not Ranks.IsExperienceOwner(owner) or simulations[owner.UserId] or isCreator(userId) then
			cancelled = true
			return nil
		end
		if old ~= nil and (type(old) ~= "table" or old.SchemaVersion ~= 2 or type(old.Users) ~= "table") then
			cancelled = true
			return nil
		end
		local data = old or { SchemaVersion = 2, _Revision = 0, Users = {} }
		data.Users[tostring(userId)] = value
		data._Revision = (tonumber(data._Revision) or 0) + 1
		return data
	end)
	if not ok or cancelled or type(result) ~= "table" then
		return false, Msg("Srv.RankSaveFailed")
	end
	local revision = tonumber(result._Revision) or 0
	if revision >= ownerRevision then
		ownerRevision = revision
		local safe = {}
		for key, rank in result.Users do
			local id = tonumber(key)
			if Ranks.ValidUserId(id) and (rank == "None" or rankOrNil(rank)) then
				safe[id] = rank
			end
		end
		ownerOverrides = safe
	end
	publish()
	return true, "Accès propriétaire enregistré."
end

function Ranks.GetOwnerAccessOverride(userId)
	return ownerOverrides[userId] or "Inherit"
end

function Ranks.GetOwnerAccessOverrides()
	return table.clone(ownerOverrides)
end

local function higher(a, b)
	if not a then
		return b
	end
	if not b then
		return a
	end
	return Ranks.Level(a) >= Ranks.Level(b) and a or b
end

-- Grade fixé dans Settings (Users ou créateur) : non modifiable depuis le panneau
function Ranks.IsFixed(userId)
	return rankOrNil(Settings.Users and Settings.Users[userId]) ~= nil or (CREATOR_RANK ~= nil and isCreator(userId))
end

function Ranks.GetRealRankByUserId(userId)
	userId = tonumber(userId)
	if not Ranks.ValidUserId(userId) or not Ranks.SecurityReady or not Ranks.OwnerAuthorityReady then
		return nil
	end
	if not isCreator(userId) and ownerOverrides[userId] then
		return ownerOverrides[userId] ~= "None" and ownerOverrides[userId] or nil
	end
	local fixed = rankOrNil(Settings.Users and Settings.Users[userId])
	local rank = fixed
	if CREATOR_RANK and isCreator(userId) then
		rank = higher(rank, CREATOR_RANK)
	end
	if Ranks.SecurityReady then
		local dynamic = Ranks.Dynamic[userId]
		if dynamic and dynamic ~= "None" then
			rank = higher(rank, rankOrNil(dynamic))
		elseif dynamic == nil then
			rank = higher(rank, rankOrNil(Settings.DefaultUsers and Settings.DefaultUsers[userId]))
		end
	end
	rank = higher(rank, groupRanks[userId])
	if STUDIO_RANK and IS_STUDIO and Players:GetPlayerByUserId(userId) ~= nil and (userId > 0 or userId == -1) then
		rank = higher(rank, STUDIO_RANK)
	end
	return rank
end

function Ranks.GetRankByUserId(userId)
	userId = tonumber(userId)
	local real = Ranks.GetRealRankByUserId(userId)
	local simulation = userId and simulations[userId]
	if simulation then
		if simulation.expires <= os.clock() then
			Ranks.ClearSimulation(userId)
			return real
		end
		return simulation.rank
	end
	return real
end

function Ranks.GetRealRank(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	return Ranks.GetRealRankByUserId(player.UserId)
end

function Ranks.GetRealLevel(player)
	return Ranks.Level(Ranks.GetRealRank(player))
end

function Ranks.GetRank(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return nil
	end
	return Ranks.GetRankByUserId(player.UserId)
end

function Ranks.GetLevel(player)
	return Ranks.Level(Ranks.GetRank(player))
end

function Ranks.IsAdmin(player)
	return Ranks.HasPermission(player, "APM.AccessPanel")
end

function Ranks.IsSuper(player)
	return Ranks.GetRank(player) == Ranks.Super
end

function Ranks.HasRankAtLeast(player, rankId)
	local level = Ranks.GetLevel(player)
	return level > 0 and level >= Ranks.Level(rankId)
end

-- L'admin peut-il agir sur ce compte ? (grade strictement supérieur ; sur soi-même : SuperRank seulement)
function Ranks.CanTargetUserId(admin, userId)
	if not Ranks.IsAdmin(admin) then
		return false
	end
	if admin.UserId == userId then
		return Ranks.IsSuper(admin)
	end
	local live = Players:GetPlayerByUserId(userId)
	if live and not resolved[userId] then return false end
	local groupId = type(Settings.Group) == "table" and tonumber(Settings.Group.Id) or 0
	if not live and ((groupId and groupId > 0) or game.CreatorType == Enum.CreatorType.Group)
		and (not offlineResolvedAt[userId] or os.clock() - offlineResolvedAt[userId] > 60) then return false end
	if isCreator(userId) then return false end
	local targetRank = Ranks.GetRealRankByUserId(userId)
	if targetRank == Ranks.Super then
		return false
	end
	return Ranks.GetLevel(admin) > Ranks.Level(targetRank)
end

function Ranks.CanTarget(admin, target)
	if typeof(target) ~= "Instance" or not target:IsA("Player") then
		return false
	end
	return Ranks.CanTargetUserId(admin, target.UserId)
end

-- Ce joueur peut-il utiliser ce module ?
function Ranks.CanUse(player, name)
	return Ranks.IsAdmin(player) and Ranks.HasPermission(player, name)
end

function Ranks.HasRealPermission(player, name)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
		or type(name) ~= "string" or not Ranks.AccessReady or not Ranks.SecurityReady or not Ranks.OwnerAuthorityReady then
		return false
	end
	if name == "APM.Simulate" and not simulationEnabled() then return false end
	local rank = Ranks.GetRealRank(player)
	return rank ~= nil and Ranks.Defaults[name] ~= nil and Ranks.Allowed(name, rank)
end

function Ranks.HasPermission(player, name)
	if not Ranks.HasRealPermission(player, name) then
		return false
	end
	local simulation = simulations[player.UserId]
	if not simulation then
		return true
	end
	if simulation.expires <= os.clock() then
		Ranks.ClearSimulation(player)
		return Ranks.HasRealPermission(player, name)
	end
	if not simulation.rank then
		return false
	end
	if simulation.permissions then
		return simulation.permissions[name] == true
	end
	return Ranks.Allowed(name, simulation.rank)
end

function Ranks.GetPermissions(player, real)
	local result = {}
	for name in Ranks.Defaults do
		result[name] = real and Ranks.HasRealPermission(player, name) or (not real and Ranks.HasPermission(player, name))
	end
	return result
end

function Ranks.CanManagePermissionColumn(actor, name, rankId)
	if actor.Parent ~= Players or not Ranks.IsAdmin(actor) or not Ranks.HasPermission(actor, "APM.ManagePermissions") then return false end
	local owner = Ranks.IsExperienceOwner(actor) and not simulations[actor.UserId]
	if (name == "APM.AccessPanel" or name == "APM.ManagePermissions") and not owner then
		if rankId == Settings.CreatorRank then return false end
		for _, player in Players:GetPlayers() do
			if Ranks.IsExperienceOwner(player) and Ranks.GetRealRank(player) == rankId then return false end
		end
	end
	return owner or Ranks.IsSuper(actor) or Ranks.Level(rankId) < Ranks.GetLevel(actor)
end

function Ranks.GetSimulation(player)
	local simulation = simulations[player.UserId]
	if simulation and (simulation.expires <= os.clock() or not Ranks.HasRealPermission(player, "APM.Simulate")) then
		Ranks.ClearSimulation(player)
		simulation = nil
	end
	return {
		enabled = simulationEnabled(),
		active = simulation ~= nil,
		rank = simulation and simulation.rank or nil,
		realRank = Ranks.GetRealRank(player),
		permissions = Ranks.GetPermissions(player, false),
		realPermissions = Ranks.GetPermissions(player, true),
		custom = simulation ~= nil and simulation.permissions ~= nil,
		remaining = simulation and math.max(0, math.ceil(simulation.expires - os.clock())) or 0,
		actualOwner = Ranks.IsExperienceOwner(player),
	}
end

function Ranks.SetSimulation(player, rankId, permissions)
	if not simulationEnabled() then return false, "Simulation désactivée dans Settings.Modules côté serveur." end
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players
		or not Ranks.HasRealPermission(player, "APM.Simulate") or not Ranks.HasPermission(player, "APM.Simulate") then
		return false, "Permission de simulation refusée."
	end
	if rankId == "None" or rankId == "" then
		rankId = nil
	end
	if rankId ~= nil and (not rankOrNil(rankId) or Ranks.Level(rankId) > Ranks.GetRealLevel(player)) then
		return false, "La simulation ne peut pas dépasser votre grade réel."
	end
	local clean
	if permissions ~= nil then
		if type(permissions) ~= "table" or rankId == nil then
			return false, "Une configuration personnalisée exige un grade autorisé."
		end
		clean = {}
		local count = 0
		for name, allowed in permissions do
			count += 1
			if count > 200 or type(name) ~= "string" or #name > 64 or not Ranks.Defaults[name] or type(allowed) ~= "boolean" then
				return false, "Configuration de permissions invalide."
			end
			if allowed and not Ranks.HasRealPermission(player, name) then
				return false, "La simulation ne peut pas accorder un droit absent de votre contexte réel."
			end
			clean[name] = allowed
		end
	end
	simulationGeneration += 1
	local generation = simulationGeneration
	local previous = simulations[player.UserId]
	if previous and previous.timer then task.cancel(previous.timer) end
	simulations[player.UserId] = { rank = rankId, permissions = clean, expires = os.clock() + 300, generation = generation }
	-- Register expiry before session removal; expired callbacks cannot clear newer tests.
	simulations[player.UserId].timer = task.delay(300, function()
		local current = simulations[player.UserId]
		if current and current.generation == generation then
			current.timer = nil
			Ranks.ClearSimulation(player)
		end
	end)
	publish()
	return true, "Simulation activée pour cinq minutes. /apm-restore restaure le contexte réel."
end

function Ranks.ClearSimulation(playerOrId)
	local userId = typeof(playerOrId) == "Instance" and playerOrId.UserId or playerOrId
	if simulations[userId] then
		if simulations[userId].timer then task.cancel(simulations[userId].timer) end
		simulations[userId] = nil
		publish()
	end
	return true, "Contexte réel restauré."
end

reconcileSimulations = function()
	for userId, simulation in simulations do
		local player = Players:GetPlayerByUserId(userId)
		local valid = player and simulation.expires > os.clock() and Ranks.HasRealPermission(player, "APM.Simulate")
			and Ranks.HasRealPermission(player, "APM.AccessPanel") and Ranks.Level(simulation.rank) <= Ranks.GetRealLevel(player)
		if valid and simulation.permissions then
			for name, allowed in simulation.permissions do
				if allowed and not Ranks.HasRealPermission(player, name) then
					valid = false
					break
				end
			end
		end
		if not valid then
			if simulation.timer then task.cancel(simulation.timer) end
			simulations[userId] = nil
		end
	end
end

-- Attend que les sources asynchrones (groupes) du joueur soient lues
function Ranks.WaitResolved(player, timeout)
	local deadline = os.clock() + (timeout or 10)
	while player.Parent and not resolved[player.UserId] and os.clock() < deadline do
		task.wait(0.1)
	end
	return player.Parent == Players and resolved[player.UserId] == true and Ranks.SecurityReady and Ranks.AccessReady and Ranks.OwnerAuthorityReady
end

local function resolve(player)
	if resolving[player] or player.Parent ~= Players then return end
	resolving[player] = true
	local userId = player.UserId
	local ok, problem = pcall(function()
		local group = Settings.Group
		local groupId = type(group) == "table" and tonumber(group.Id) or 0
		local sourcesOK, groupRank = true, nil
		if groupId and groupId > 0 and type(group.Ranks) == "table" then
			local value, rankOK = readGroupRank(userId, groupId, player)
			sourcesOK = rankOK
			if rankOK then groupRank = mapGroupRank(value) end
		end
		local owner = false
		if game.CreatorType == Enum.CreatorType.Group and game.CreatorId ~= 0 then
			local ownerOK = readCreatorGroupOwner(false)
			sourcesOK = sourcesOK and ownerOK
			owner = ownerOK and userId == creatorGroupOwnerId
		end
		-- Network calls can finish after a departure or reconnect. Only this Player may consume their result.
		if player.Parent ~= Players or Players:GetPlayerByUserId(userId) ~= player then return end
		if sourcesOK then
			groupRanks[userId], groupOwners[userId], resolved[userId] = groupRank, owner or nil, true
			publish()
		else
			resolved[userId] = nil
		end
	end)
	resolving[player] = nil
	if not ok then warn("[APM] Group resolution failed; retry scheduled: " .. tostring(problem)) end
end

local function retryUnresolvedPlayers()
	for _, player in Players:GetPlayers() do
		if not resolved[player.UserId] and not resolving[player] then task.spawn(resolve, player) end
	end
end

function Ranks.ResolveOfflineRank(userId)
	if not Ranks.ValidUserId(userId) or not Ranks.SecurityReady or not Ranks.OwnerAuthorityReady then return nil, false end
	local live = Players:GetPlayerByUserId(userId)
	if live then
		if not Ranks.WaitResolved(live, 8) then return nil, false end
		return Ranks.GetRank(live), true
	end
	local groupId = type(Settings.Group) == "table" and tonumber(Settings.Group.Id) or 0
	if (groupId and groupId > 0) or game.CreatorType == Enum.CreatorType.Group then
		if offlineResolvedAt[userId] and os.clock() - offlineResolvedAt[userId] < 60 then
			return Ranks.GetRealRankByUserId(userId), true
		end
		if userId <= 0 then return nil, false end
		if groupId and groupId > 0 then
			local value, ok = readGroupRank(userId, groupId, nil)
			if not ok then return nil, false end
			groupRanks[userId] = mapGroupRank(value)
		end
		if not readCreatorGroupOwner(false) then return nil, false end
		offlineResolvedAt[userId] = os.clock()
	end
	return Ranks.GetRealRankByUserId(userId), true
end

----------------------------------------------------------------------------------------------------------
-- Démarrage et synchronisation

local started = false
function Ranks.Init()
	if started then
		return
	end
	started = true
	Ranks.LoadRanks()
	Ranks.LoadAccess()
	Ranks.LoadOwnerAuthority()
	Ranks.InitModuleAccess({})
	Players.PlayerAdded:Connect(resolve)
	for _, player in Players:GetPlayers() do
		task.spawn(resolve, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		local userId = player.UserId
		groupRanks[userId], groupOwners[userId], resolved[userId] = nil, nil, nil
		resolving[player] = nil
		offlineResolvedAt[userId] = nil
		if simulations[userId] and simulations[userId].timer then task.cancel(simulations[userId].timer) end
		simulations[userId] = nil
	end)
end

-- Relit grades et matrice quand un autre serveur les change (MessagingService), et toutes les 25-35 s au cas où
local syncing = false
function Ranks.StartSync()
	if syncing then
		return
	end
	syncing = true
	local function refresh()
		local ranksBefore, accessBefore, ownerBefore = rankRevision, accessRevision, ownerRevision
		local wasReady = Ranks.SecurityReady and Ranks.AccessReady and Ranks.OwnerAuthorityReady
		Ranks.LoadRanks()
		Ranks.LoadAccess()
		Ranks.LoadOwnerAuthority()
		local ownerBeforeId = creatorGroupOwnerId
		readCreatorGroupOwner(false)
		local isReady = Ranks.SecurityReady and Ranks.AccessReady and Ranks.OwnerAuthorityReady
		if ranksBefore ~= rankRevision or accessBefore ~= accessRevision or ownerBefore ~= ownerRevision or wasReady ~= isReady or ownerBeforeId ~= creatorGroupOwnerId then
			if reconcileSimulations then reconcileSimulations() end
			if Ranks.OnChanged then Ranks.OnChanged() end
		end
	end
	if store then
		task.spawn(function()
			pcall(function()
				MessagingService:SubscribeAsync(TOPIC, function(message)
					if message.Data ~= game.JobId then
						task.spawn(refresh)
					end
				end)
			end)
		end)
	end
	task.spawn(function()
		while true do
			task.wait(25 + math.random() * 10)
			if store then
				refresh()
			end
			retryUnresolvedPlayers()
		end
	end)
end

return Ranks
