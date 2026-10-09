-- AutoBridge: bounded structural discovery. Only adapters explicitly registered by trusted server code execute.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")
local AutoBridge = {}
local ctx, config
local adapters, cache = {}, {}
local scannedAt, scanning, scanCount, truncated = 0, false, 0, false
local DEFAULTS = { Enabled = true, ScanInterval = 30, MaxScanInstances = 1500, MaxEntries = 60, EnableTeamActions = false }
local STATUS = { Detected = true, Compatible = true, Operational = true, Unsupported = true, Error = true }
local MARKERS = { Economy = true, Inventory = true, Progression = true, Vehicle = true, Module = true }
local function disabled()
	return type(ctx.Settings.Modules) == "table" and ctx.Settings.Modules.AutoBridge == false
end

local function message(fr, en)
	return { fr = fr, en = en }
end
local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) ~= math.huge
end
local function copy(source)
	local result = {}
	for key, value in source do result[key] = value end
	return result
end
function AutoBridge.ValidateConfig(patch, base)
	if type(patch) ~= "table" then return nil, "Configuration invalide." end
	local clean = copy(base or DEFAULTS)
	for key, value in patch do
		if key == "Enabled" or key == "EnableTeamActions" then
			if type(value) ~= "boolean" then return nil, "Booléen attendu : " .. key end
			clean[key] = value
		elseif key == "ScanInterval" or key == "MaxScanInstances" or key == "MaxEntries" then
			if not finite(value) then return nil, "Nombre attendu : " .. key end
			local min, max = 5, 600
			if key == "MaxScanInstances" then min, max = 100, 10000 end
			if key == "MaxEntries" then min, max = 5, 100 end
			if value < min or value > max then return nil, "Valeur hors limites : " .. key end
			clean[key] = math.floor(value)
		else return nil, "Paramètre inconnu : " .. tostring(key) end
	end
	return clean
end
local function has(player, permission)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
		and ctx.Ranks.HasPermission(player, "APM.AccessPanel") and ctx.Ranks.HasPermission(player, permission)
end
local function safeString(value, limit)
	return type(value) == "string" and string.sub(value, 1, limit or 240) or ""
end
local function safeReport(id, report)
	report = type(report) == "table" and report or {}
	local result = { Id = id, Name = safeString(report.Name, 60), Status = STATUS[report.Status] and report.Status or "Detected",
		Detail = safeString(report.Detail), Count = finite(report.Count) and math.clamp(math.floor(report.Count), 0, 1000000) or 0, Actions = {} }
	if result.Name == "" then result.Name = id end
	local adapter = adapters[id]
	if adapter then
		for name, action in adapter.Actions do
			table.insert(result.Actions, { Id = name, Label = safeString(action.Label or name, 60), Permission = action.Permission, Target = action.Target == true })
		end
	end
	return result
end

-- API server only. Probe(ctx) -> {Status,Name,Count,Detail}; Actions[id]={Permission,Validate,Execute,Target}.
function AutoBridge.RegisterAdapter(id, adapter)
	if type(id) ~= "string" or not string.match(id, "^[%w_%-]+$") or #id > 40 or type(adapter) ~= "table"
		or type(adapter.Probe) ~= "function" or type(adapter.Actions) ~= "table" then return false, "Invalid adapter contract" end
	if adapters[id] then return false, "Adapter already registered" end
	local registered = { Probe = adapter.Probe, Actions = {}, Permission = adapter.Permission or "AutoBridge.View" }
	if type(registered.Permission) ~= "string" or #registered.Permission > 64 then return false, "Invalid permission" end
	for name, action in adapter.Actions do
		if type(name) ~= "string" or #name > 40 or type(action) ~= "table" or type(action.Permission) ~= "string"
			or #action.Permission > 64 or type(action.Validate) ~= "function" or type(action.Execute) ~= "function" then
			return false, "Each action requires an explicit permission, validator and executor"
		end
		registered.Actions[name] = { Permission = action.Permission, Validate = action.Validate, Execute = action.Execute,
			Target = action.Target == true, AllowSelf = action.AllowSelf == true, Label = action.Label }
	end
	adapters[id] = registered
	scannedAt = 0
	return true
end

local function internalSource(node)
	-- Restore points and the official code Package are inactive administration sources, not game systems.
	for _,name in {"APM_Core","APM_RestorePoints"} do
		local root=ServerStorage:FindFirstChild(name)
		if root and (node==root or node:IsDescendantOf(root)) then return true end
	end
	return false
end
local function structuralScan()
	local counts = { Tools = 0, VehicleSeats = 0 }
	local markers = {}
	local queue, cursor, visited = {}, 1, {}
	local roots = { workspace }
	for _, source in ctx.Settings.ToolSources or {} do
		if typeof(source) == "Instance" then table.insert(roots, source) end
	end
	for _, root in roots do
		if not visited[root] and not internalSource(root) then visited[root] = true; table.insert(queue, root) end
	end
	local limit, processed = config.MaxScanInstances, 0
	while cursor <= #queue and processed < limit do
		local node = queue[cursor]
		queue[cursor] = false
		cursor += 1
		processed += 1
		if node:IsA("Tool") then counts.Tools += 1 end
		if node:IsA("VehicleSeat") then counts.VehicleSeats += 1 end
		local marker = node:GetAttribute("AutoBridgeSystem")
		if type(marker) == "string" and MARKERS[marker] then markers[marker] = (markers[marker] or 0) + 1 end
		for _, child in node:GetChildren() do
			if #queue >= limit then break end
			if not visited[child] and not internalSource(child) then visited[child] = true; table.insert(queue, child) end
		end
		if processed % 100 == 0 then task.wait() end
	end
	for kind in MARKERS do
		local tagged = CollectionService:GetTagged("AutoBridge." .. kind)
		local active=0 for _,node in tagged do if not internalSource(node) then active+=1 end end
		if active > 0 then markers[kind] = math.max(markers[kind] or 0, active) end
	end
	scanCount = processed
	truncated = processed >= limit or #queue >= limit
	return counts, markers
end

function AutoBridge.Discover(force)
	if not ctx or not config.Enabled then cache = {}; return cache end
	if scanning or (not force and scannedAt > 0 and os.clock() - scannedAt < config.ScanInterval) then return cache end
	scanning = true
	local ok, results = pcall(function()
		local counts, markers = structuralScan()
		local result = {}
		local statCount = 0
		for index, player in Players:GetPlayers() do
			if index > 120 then break end
			local leaderstats = player:FindFirstChild("leaderstats")
			for _, stat in leaderstats and leaderstats:GetChildren() or {} do
				if stat:IsA("IntValue") or stat:IsA("NumberValue") then statCount += 1 end
			end
		end
		local teamCount = #Teams:GetTeams()
		table.insert(result, safeReport("leaderstats", { Name = "Leaderstats", Status = statCount > 0 and "Operational" or "Unsupported", Count = statCount,
			Detail = statCount > 0 and "Statistiques numériques accessibles. Modifications via le module Leaderstats existant ; aucune économie personnalisée supposée." or "Aucune statistique numérique présente actuellement." }))
		table.insert(result, safeReport("teams", { Name = "Teams", Status = teamCount > 0 and "Operational" or "Unsupported", Count = teamCount,
			Detail = config.EnableTeamActions and "Diagnostic et changement d'équipe validé disponibles." or "Diagnostic disponible. Changement d'équipe désactivé par défaut." }))
		table.insert(result, safeReport("tools", { Name = "Tools", Status = counts.Tools > 0 and "Operational" or "Unsupported", Count = counts.Tools,
			Detail = "Comptage structurel borné. Distribution via GiveTool et ses sources configurées ; aucun script découvert n'est exécuté." }))
		table.insert(result, safeReport("vehicles", { Name = "Véhicules / VehicleSeat", Status = counts.VehicleSeats > 0 and "Detected" or "Unsupported", Count = counts.VehicleSeats,
			Detail = "La présence d'un siège ne prouve pas la compatibilité du contrôleur. Adaptateur explicite requis pour agir." }))
		for kind, count in markers do
			table.insert(result, safeReport("marker_" .. kind, { Name = kind, Count = count, Status = "Unsupported",
				Detail = "Marqueur explicite détecté (tag AutoBridge." .. kind .. " ou attribut AutoBridgeSystem). Adaptateur serveur requis ; aucun require automatique." }))
		end
		for id, adapter in adapters do
			if id ~= "teams" then
				local probeOk, report = pcall(adapter.Probe, ctx)
				table.insert(result, safeReport(id, probeOk and report or { Status = "Error", Detail = "Erreur d'intégration : " .. safeString(tostring(report), 150) }))
			end
		end
		table.sort(result, function(a, b) return a.Id < b.Id end)
		while #result > config.MaxEntries do table.remove(result) end
		return result
	end)
	scanning = false
	scannedAt = os.clock()
	if ok then cache = results else cache = { safeReport("scan", { Status = "Error", Detail = "Analyse structurelle interrompue : " .. safeString(tostring(results), 150) }) } end
	return cache
end

function AutoBridge.GetState(player)
	if player and not has(player, "AutoBridge.View") then return { Allowed = false } end
	local discovered = AutoBridge.Discover(false)
	if player and not has(player, "AutoBridge.View") then return { Allowed = false } end
	local systems = {}
	for _, entry in discovered do
		local adapter = adapters[entry.Id]
		if not player or not adapter or has(player, adapter.Permission) then
			local safe = safeReport(entry.Id, entry)
			local actions = {}
			for _, action in safe.Actions do
				if (not player or has(player, action.Permission)) and (entry.Id ~= "teams" or config.EnableTeamActions) then table.insert(actions, action) end
			end
			safe.Actions = actions
			table.insert(systems, safe)
		end
	end
	local options = {}
	for index, team in Teams:GetTeams() do
		if index > 60 then break end
		table.insert(options, { team.Name, team.Name })
	end
	return { Allowed = true, Enabled = config.Enabled, Disabled = disabled(), Config = copy(config), Systems = systems, Teams = options,
		Scanning = scanning, ScannedAt = scannedAt, ScannedInstances = scanCount, Truncated = truncated, SchemaVersion = 2 }
end

function AutoBridge.Configure(player, patch)
	if not has(player, "AutoBridge.Configure") then return false, message("Accès refusé.", "Access denied.") end
	if not ctx.Guard.Allow(player, "ConfigureAutoBridge", 3, 10) then return false, message("Patiente avant de modifier les réglages.", "Wait before changing settings.") end
	local clean, err = AutoBridge.ValidateConfig(patch, config)
	if not clean then return false, err end
	if disabled() and clean.Enabled then return false, "AutoBridge désactivé dans Settings.Modules côté serveur." end
	if ctx.SuiteConfig then
		local saved, problem = ctx.SuiteConfig.Save("AutoBridge", clean, function()
			return has(player, "AutoBridge.Configure") and (not disabled() or not clean.Enabled)
		end)
		if not saved then return false, problem or message("Sauvegarde non confirmée.", "Save not confirmed.") end
	end
	if not has(player, "AutoBridge.Configure") or (disabled() and clean.Enabled) then return false, "Autorisations modifiées : configuration annulée." end
	config = clean
	scannedAt = 0
	ctx.Log(player.Name, "ConfigureAutoBridge", nil, "Configuration AutoBridge mise à jour", "AutoBridge", "info")
	return true, message("Réglages AutoBridge appliqués.", "AutoBridge settings applied.")
end

function AutoBridge.Execute(player, adapterId, actionId, target, args)
	if not has(player, "AutoBridge.View") or not config.Enabled then return false, message("AutoBridge indisponible ou accès refusé.", "AutoBridge unavailable or access denied.") end
	if not ctx.Guard.Allow(player, "AutoBridgeAction", 8, 10) then return false, "Trop de requêtes." end
	if type(adapterId) ~= "string" or #adapterId > 40 or type(actionId) ~= "string" or #actionId > 40 then return false, "Action invalide." end
	local adapter = adapters[adapterId]
	local action = adapter and adapter.Actions[actionId]
	if not action or not has(player, adapter.Permission) or not has(player, action.Permission) then return false, "Action refusée." end
	if adapterId == "teams" and not config.EnableTeamActions then return false, "Les changements d'équipe sont désactivés." end
	if action.Target then
		if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players then return false, "Cible invalide." end
		if target == player then
			if not action.AllowSelf then return false, "Action sur soi refusée." end
		elseif not ctx.Ranks.CanTarget(player, target) then return false, "Grade de la cible protégé." end
	else target = nil end
	local probeOk, report = pcall(adapter.Probe, ctx)
	if not probeOk or type(report) ~= "table" or (report.Status ~= "Compatible" and report.Status ~= "Operational") then return false, "Intégration actuellement incompatible." end
	local validateOk, clean, problem = pcall(action.Validate, ctx, player, target, args)
	if not validateOk or clean == nil then return false, problem or "Paramètres invalides." end
	-- Validators may yield. Recheck current permissions and hierarchy before the mutation.
	if not config.Enabled or not has(player, action.Permission) or not has(player, adapter.Permission) or not has(player, "AutoBridge.View")
		or (target and (target.Parent ~= Players or (target ~= player and not ctx.Ranks.CanTarget(player, target))))
		or (adapterId == "teams" and not config.EnableTeamActions) then return false, "Autorisations modifiées : action annulée." end
	local ok, success, reply = pcall(action.Execute, ctx, player, target, clean)
	if not ok then success, reply = false, "Erreur de l'adaptateur : action interrompue." end
	ctx.Log(player.Name, "AutoBridge." .. adapterId .. "." .. actionId, target and target.Name or nil, reply or "OK", "AutoBridge", success == false and "warning" or "info")
	return success == true, reply
end

function AutoBridge.Init(context)
	if ctx then return AutoBridge end
	ctx = context
	config = copy(DEFAULTS)
	local initial = type(ctx.Settings.AutoBridge) == "table" and ctx.Settings.AutoBridge or {}
	config = AutoBridge.ValidateConfig(initial, config) or config
	if ctx.SuiteConfig then config = AutoBridge.ValidateConfig(ctx.SuiteConfig.Snapshot("AutoBridge") or {}, config) or config end
	if disabled() then config.Enabled = false end
	AutoBridge.RegisterAdapter("teams", { Probe = function()
		return { Status = #Teams:GetTeams() > 0 and "Operational" or "Unsupported" }
	end, Actions = { SetTeam = { Permission = "AutoBridge.Configure", Target = true, AllowSelf = true, Label = "Changer l'équipe",
		Validate = function(_, _, _, args)
			if type(args) ~= "table" or type(args.Team) ~= "string" or #args.Team > 100 then return nil, "Équipe invalide." end
			for _, team in Teams:GetTeams() do if team.Name == args.Team then return { Team = team } end end
			return nil, "Équipe introuvable."
		end,
		Execute = function(_, _, target, clean)
			if clean.Team.Parent ~= Teams then return false, "Équipe supprimée." end
			target.Team = clean.Team
			target.Neutral = false
			return true, "Équipe modifiée : " .. target.Name
		end } } })
	ctx.Remotes.GetAutoBridge.OnServerInvoke = function(player)
		if not has(player, "AutoBridge.View") or not ctx.Guard.Allow(player, "GetAutoBridge", 10, 10) then return { Allowed = false } end
		return AutoBridge.GetState(player)
	end
	ctx.Remotes.RefreshAutoBridge.OnServerInvoke = function(player)
		if not has(player, "AutoBridge.View") or not ctx.Guard.Allow(player, "RefreshAutoBridge", 2, 15) then return false, "Actualisation limitée." end
		AutoBridge.Discover(true)
		return true, AutoBridge.GetState(player)
	end
	ctx.Remotes.ConfigureAutoBridge.OnServerInvoke = AutoBridge.Configure
	ctx.Remotes.AutoBridgeAction.OnServerInvoke = AutoBridge.Execute
	return AutoBridge
end
return AutoBridge
