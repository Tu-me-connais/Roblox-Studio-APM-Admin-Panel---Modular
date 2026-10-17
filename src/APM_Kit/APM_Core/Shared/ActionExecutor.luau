--[[
	ActionExecutor : exécuteur CLIENT des actions distribuées par le serveur (Core/Dispatcher). Un seul exemplaire par client, installé
	automatiquement avec l'APM (démarré par APM_Notices, le client public que TOUS les joueurs reçoivent) : il n'a donc pas besoin que le panneau
	soit ouvert, ni même que le joueur soit admin. Il ne fait rien tant que le serveur ne lui envoie rien : aucune boucle permanente.

	Sécurité :
	  - il n'exécute QUE les actions de ActionCatalog qui ont un contrôleur dans Effects/ (liste fermée, pas de code reçu, jamais de loadstring) ;
	  - chaque paquet est revalidé (forme, version, identifiant, numéro d'ordre, paramètres, expiration) ;
	  - un identifiant déjà vu n'est JAMAIS ré-exécuté (rejeu : même réponse), un numéro d'ordre périmé est refusé ;
	  - une seule instance de contrôleur par action et par client : relancer une action active ne crée jamais de doublon ;
	  - le client ne demande JAMAIS d'action : il ne fait que répondre (Ack), annoncer qu'il est prêt (Ready) ou qu'un effet s'est terminé (Ended).

	Contrôleur d'une action (Effects/<Nom>) : Create(env) -> { Start(params) -> bool, Stop() }. Start doit nettoyer ce qu'il avait créé avant de recommencer.
	Pour les tests : Executor.Create(services) accepte de faux signaux, un faux joueur et une fausse horloge.
]]
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Catalog = require(script.Parent:WaitForChild("ActionCatalog"))

local Executor = {}

local SEEN_LIMIT = 64

local function sameParams(a, b)
	for key, value in a or {} do
		if (b or {})[key] ~= value then return false end
	end
	for key, value in b or {} do
		if (a or {})[key] ~= value then return false end
	end
	return true
end

function Executor.Create(services)
	services = services or {}
	local player = services.Player or Players.LocalPlayer
	local now = services.Now or function() return workspace:GetServerTimeNow() end
	local spawn = services.Spawn or task.spawn
	local report = services.Report or function() end
	local factories = services.Effects or {}
	local env = {
		Player = player,
		Character = services.Character or function() return player.Character end,
		RenderStepped = services.RenderStepped or RunService.RenderStepped,
		Stepped = services.Stepped or RunService.Stepped,
		IsKeyDown = services.IsKeyDown or function(key) return UserInputService:IsKeyDown(key) end,
		TextBoxFocused = services.TextBoxFocused or function() return UserInputService:GetFocusedTextBox() ~= nil end,
		Camera = services.Camera or function() return workspace.CurrentCamera end,
	}

	local api = {}
	local entries = {} -- [action] = { Wanted, Running, Params, Applied, Origin, Character, Controller, Id }
	local lastSeq = {} -- [action] = dernier numéro d'ordre accepté
	local seen, order = {}, {} -- [id] = { Status, Detail } : identifiants déjà traités (rejeu), les 64 derniers
	local generation = 0
	local connections = {}
	local connected, destroyed = false, false
	local changedEvent = Instance.new("BindableEvent")
	-- (action, actif, origine "Server" | "Panel" | ..., raison) : le panneau de l'admin se resynchronise sur cet événement
	api.Changed = changedEvent.Event

	local function entryFor(action)
		local entry = entries[action]
		if not entry then
			entry = { Wanted = false, Running = false }
			entries[action] = entry
		end
		return entry
	end

	-- Démarre le contrôleur sur le personnage courant, sauf s'il y tourne déjà avec les mêmes paramètres. Renvoie (tourne, raison).
	local function ensureRunning(action, entry)
		local character = env.Character()
		if entry.Running and character ~= nil and entry.Character == character and sameParams(entry.Applied, entry.Params) then
			return true
		end
		local ok, started = pcall(function()
			if not entry.Controller then entry.Controller = factories[action].Create(env) end
			return entry.Controller.Start(entry.Params)
		end)
		local was = entry.Running
		if ok and started == true then
			entry.Running, entry.Character, entry.Applied = true, character, entry.Params
			if not was then changedEvent:Fire(action, true, entry.Origin) end
			return true
		end
		entry.Running, entry.Character, entry.Applied = false, nil, nil
		if was then changedEvent:Fire(action, false, entry.Origin, ok and "NoCharacter" or "Error") end
		if not ok then
			warn("[APM] ActionExecutor " .. action .. " : " .. tostring(started))
			return false, "Error"
		end
		return false, "NoCharacter"
	end

	local function stopEntry(action, entry, origin, reason)
		local active = entry.Wanted or entry.Running
		entry.Wanted, entry.Running, entry.Character, entry.Applied = false, false, nil, nil
		if entry.Controller then
			local ok, problem = pcall(entry.Controller.Stop)
			if not ok then warn("[APM] ActionExecutor " .. action .. " : " .. tostring(problem)) end
		end
		if active then changedEvent:Fire(action, false, origin, reason) end
		return active
	end

	local function remember(id, status, detail)
		if seen[id] then return end
		seen[id] = { Status = status, Detail = detail }
		table.insert(order, id)
		if #order > SEEN_LIMIT then seen[table.remove(order, 1)] = nil end
	end
	local function answer(id, status, detail)
		remember(id, status, detail)
		report("Ack", id, status, detail)
	end

	----------------------------------------------------------------------------------------------------------
	-- Instructions du serveur

	function api.Handle(packet)
		if destroyed then return end
		local pid = type(packet) == "table" and Catalog.IsGuid(packet.Id) and packet.Id or nil
		if pid and seen[pid] then
			local cached = seen[pid]
			report("Ack", pid, cached.Status, cached.Detail) -- même réponse, AUCUNE ré-exécution
			return
		end
		local clean, code = Catalog.CleanPacket(packet, now())
		if not clean then
			if pid then answer(pid, code == "Expired" and "Expired" or "Rejected", code) end
			return
		end
		local action = clean.Effect
		if not factories[action] then
			answer(clean.Id, "Rejected", "Unsupported")
			return
		end
		if clean.Seq <= (lastSeq[action] or 0) then
			answer(clean.Id, "Rejected", "Stale") -- une instruction plus récente a déjà été appliquée
			return
		end
		lastSeq[action] = clean.Seq
		local entry = entryFor(action)
		if clean.Op == "Start" then
			entry.Wanted, entry.Params, entry.Origin, entry.Id = true, clean.Params, "Server", clean.Id
			local running, reason = ensureRunning(action, entry)
			if running then
				answer(clean.Id, "Applied")
			elseif reason == "Error" then
				stopEntry(action, entry, "Server", "Error")
				answer(clean.Id, "Failed", "Error")
			else
				answer(clean.Id, "Applied", "Armed") -- accepté ; s'appliquera dès que le personnage est prêt
			end
		else
			local stopped = stopEntry(action, entry, "Server", "Server")
			answer(clean.Id, "Stopped", (not stopped) and "Idle" or nil)
		end
	end

	----------------------------------------------------------------------------------------------------------
	-- Usage local (panneau de l'admin : Tools/Fly, Tools/Noclip) : MAÎME instance de contrôleur, jamais de doublon

	function api.Acquire(action, origin, params)
		if destroyed or not factories[action] or not Catalog.Get(action) then return false end
		local clean = Catalog.CleanParams(action, params, false)
		if not clean then return false end
		local entry = entryFor(action)
		if entry.Wanted and entry.Origin == "Server" then
			return (ensureRunning(action, entry)) -- déjà tenu par le serveur : on ne lui reprend pas la main
		end
		entry.Wanted, entry.Params, entry.Origin = true, clean, origin or "Local"
		local running, reason = ensureRunning(action, entry)
		if not running then stopEntry(action, entry, entry.Origin, reason) end
		return running
	end

	-- L'utilisateur coupe l'action : arrêt complet, quelle que soit l'origine
	function api.Release(action, origin)
		local entry = entries[action]
		if entry then stopEntry(action, entry, origin or "Local", "Local") end
	end

	-- L'interface qui avait demandé l'action disparait (reconstruction, retrait d'accès) : on ne coupe que ce qu'elle tenait elle-même
	function api.Detach(action, origin)
		local entry = entries[action]
		if entry and entry.Wanted and entry.Origin == (origin or "Local") then stopEntry(action, entry, origin or "Local", "Local") end
	end

	-- Nouveau personnage : sans effet si le contrôleur y tourne déjà (pas de doublon)
	function api.Refresh(action)
		local entry = entries[action]
		if entry and entry.Wanted then ensureRunning(action, entry) end
	end

	function api.IsActive(action)
		local entry = entries[action]
		return entry ~= nil and entry.Running == true
	end
	function api.IsWanted(action)
		local entry = entries[action]
		return entry ~= nil and entry.Wanted == true
	end
	function api.Origin(action)
		local entry = entries[action]
		return entry and entry.Wanted and entry.Origin or nil
	end
	function api.Active()
		local list = {}
		for action, entry in entries do
			if entry.Running then table.insert(list, action) end
		end
		table.sort(list)
		return list
	end

	----------------------------------------------------------------------------------------------------------
	-- Cycle de vie

	local function onCharacterRemoving()
		generation += 1
		for action, entry in entries do
			if entry.Running then
				local definition = Catalog.Get(action)
				if definition and definition.Respawn == "Clear" then
					stopEntry(action, entry, entry.Origin, "Respawn")
					report("Ended", action, "Respawn")
				else
					-- l'effet suit le joueur : on libère les connexions de l'ancien personnage, il redémarre sur le nouveau
					entry.Running, entry.Character, entry.Applied = false, nil, nil
					if entry.Controller then pcall(entry.Controller.Stop) end
				end
			end
		end
	end

	local function onCharacterAdded(character)
		generation += 1
		local mine = generation
		for action, entry in entries do
			if entry.Wanted then
				spawn(function()
					local root = character:WaitForChild("HumanoidRootPart", 10)
					local humanoid = character:WaitForChild("Humanoid", 10)
					if destroyed or mine ~= generation or env.Character() ~= character or not root or not humanoid or not entry.Wanted then return end
					ensureRunning(action, entry)
				end)
			end
		end
	end

	-- Branche les signaux (une seule fois) puis annonce au serveur que cet exemplaire est prêt : il renvoie alors ce qu'il attend de ce joueur
	function api.Connect()
		if connected or destroyed then return end
		connected = true
		if services.Dispatch then table.insert(connections, services.Dispatch:Connect(api.Handle)) end
		local removing = services.CharacterRemoving or (player and player.CharacterRemoving)
		local added = services.CharacterAdded or (player and player.CharacterAdded)
		if removing then table.insert(connections, removing:Connect(onCharacterRemoving)) end
		if added then table.insert(connections, added:Connect(onCharacterAdded)) end
		report("Ready", Catalog.Version)
	end

	function api.Destroy()
		if destroyed then return end
		for action, entry in entries do stopEntry(action, entry, "Local", "Local") end
		destroyed = true
		for _, connection in connections do connection:Disconnect() end
		table.clear(connections)
		changedEvent:Destroy()
	end

	return api
end

----------------------------------------------------------------------------------------------------------
-- Exemplaire unique du client réel

local singleton

function Executor.Start()
	if singleton then return singleton end
	if not RunService:IsClient() then return nil end
	local Remotes = require(script.Parent:WaitForChild("Remotes"))
	local factories = {}
	for _, source in script:WaitForChild("Effects"):GetChildren() do
		if source:IsA("ModuleScript") and Catalog.Get(source.Name) then
			local ok, module = pcall(require, source)
			if ok and type(module) == "table" and type(module.Create) == "function" then
				factories[source.Name] = module
			else
				warn("[APM] Contrôleur d'action invalide : " .. source.Name)
			end
		end
	end
	if singleton then return singleton end -- un autre script l'a démarré pendant l'attente des remotes
	local dispatch = Remotes.Get("ActionDispatch", "RemoteEvent")
	local reporter = Remotes.Get("ActionReport", "RemoteEvent")
	if singleton then return singleton end
	singleton = Executor.Create({
		Effects = factories,
		Dispatch = dispatch.OnClientEvent,
		Report = function(...) reporter:FireServer(...) end,
	})
	singleton.Connect()
	return singleton
end

function Executor.Get()
	return singleton
end

return Executor
