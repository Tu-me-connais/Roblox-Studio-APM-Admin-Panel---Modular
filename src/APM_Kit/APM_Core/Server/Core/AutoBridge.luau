-- AutoBridge: bounded structural discovery. Only adapters explicitly registered by trusted server code execute.
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local CollectionService = game:GetService("CollectionService")
local SourceScope = require(script.Parent.SourceScope)
local AutoBridge = {}
local ctx, config, scriptConfig
local adapters, cache = {}, {}
local scannedAt, scanning, scanCount, truncated = 0, false, 0, false
local DEFAULTS = { Enabled = true, ScanInterval = 30, MaxScanInstances = 1500, MaxEntries = 60, EnableTeamActions = false }
local STATUS = { Detected = true, Compatible = true, Operational = true, Unsupported = true, Error = true }
local MARKERS = { Economy = true, Inventory = true, Progression = true, Vehicle = true, Module = true }
local function disabled()
	return type(ctx.Settings.Modules) == "table" and ctx.Settings.Modules.AutoBridge == false
end

local function message(fr, en, ...)
	if select("#", ...) > 0 then return { p = { fr = fr, en = en }, a = { ... }, n = select("#", ...) } end
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
	if type(patch) ~= "table" then return nil, message("Configuration invalide.", "Invalid configuration.") end
	local clean = copy(base or DEFAULTS)
	for key, value in patch do
		if key == "Enabled" or key == "EnableTeamActions" then
			if type(value) ~= "boolean" then return nil, message("Booléen attendu : %s", "Boolean expected: %s", key) end
			clean[key] = value
		elseif key == "ScanInterval" or key == "MaxScanInstances" or key == "MaxEntries" then
			if not finite(value) then return nil, message("Nombre attendu : %s", "Number expected: %s", key) end
			local min, max = 5, 600
			if key == "MaxScanInstances" then min, max = 100, 10000 end
			if key == "MaxEntries" then min, max = 5, 100 end
			if value < min or value > max then return nil, message("Valeur hors limites : %s", "Value out of range: %s", key) end
			clean[key] = math.floor(value)
		else
			return nil, message("Paramètre inconnu : %s", "Unknown setting: %s", tostring(key))
		end
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
-- Texte affichable d'un rapport : chaîne (adaptateurs du jeu) ou message { fr, en } (rapports intégrés)
local function safeText(value, limit)
	if type(value) == "table" then
		if type(value.p) == "table" then
			local template, args = {}, {}
			for _, code in {"fr","en","es","pt","de","ru","zh"} do if type(value.p[code]) == "string" then template[code] = safeString(value.p[code], limit) end end
			local source = type(value.a) == "table" and value.a or {}
			local count = math.min(#source, 8)
			for index = 1, count do local item=source[index]; args[index] = type(item) == "number" and finite(item) and item or safeString(tostring(item), limit) end
			return {p=template,a=args,n=count}
		end
		local texts = {}
		for _, code in {"fr","en","es","pt","de","ru","zh"} do if type(value[code]) == "string" then texts[code] = safeString(value[code], limit) end end
		return texts
	end
	return safeString(value, limit)
end
local function safeReport(id, report)
	report = type(report) == "table" and report or {}
	local result = { Id = id, Name = safeString(report.Name, 60), Status = STATUS[report.Status] and report.Status or "Detected",
		DisplayName = safeText(report.DisplayName or report.Name, 60), Detail = safeText(report.Detail), Count = finite(report.Count) and math.clamp(math.floor(report.Count), 0, 1000000) or 0, Actions = {} }
	if result.Name == "" then result.Name = id end
	local adapter = adapters[id]
	if adapter then
		for name, action in adapter.Actions do
			table.insert(result.Actions, { Id = name, Label = safeText(action.Label or name, 60), Permission = action.Permission, Target = action.Target == true })
		end
	end
	return result
end

-- API server only. Probe(ctx) -> {Status,Name,Count,Detail}; Actions[id]={Permission,Validate,Execute,Target}.
function AutoBridge.RegisterAdapter(id, adapter)
	local function identifier(value, limit)
		return type(value) == "string" and #value > 0 and #value <= limit
			and string.match(value, "^[%w_%.%-]+$") ~= nil
	end
	local function permission(value)
		return type(value) == "string" and #value > 0 and #value <= 64 and utf8.len(value) ~= nil
	end
	if not identifier(id, 40) or type(adapter) ~= "table"
			or type(adapter.Probe) ~= "function" or type(adapter.Actions) ~= "table" then return false, "Invalid adapter contract" end
	if adapters[id] then return false, "Adapter already registered" end
	local required = adapter.Permission
	if required == nil then required = "AutoBridge.View" end
	if not permission(required) then return false, "Invalid permission" end
	local registered = { Probe = adapter.Probe, Actions = {}, Permission = required }
	local count = 0
	for name, action in adapter.Actions do
		count += 1
		if count > 40 then return false, "Too many adapter actions" end
		if not identifier(name, 40) or type(action) ~= "table" or not permission(action.Permission)
				or type(action.Validate) ~= "function" or type(action.Execute) ~= "function" then
			return false, "Each action requires an explicit permission, validator and executor"
		end
		registered.Actions[name] = { Permission = action.Permission, Validate = action.Validate, Execute = action.Execute,
			Target = action.Target == true, AllowSelf = action.AllowSelf == true, Label = action.Label }
	end
	adapters[id] = registered
	scannedAt = 0
	return true
end

local internalSource = SourceScope.IsInactive
local function structuralScan()
	local counts = { Tools = 0, VehicleSeats = 0 }
	local markers = {}
	local queue, cursor, visited = {}, 1, {}
	local roots = { workspace }
	for _, source in ctx.Settings.ToolSources or {} do
		if typeof(source) == "Instance" then table.insert(roots, source) end
	end
	for _, root in roots do
		if not visited[root] and not internalSource(root) then
			visited[root] = true
			table.insert(queue, root)
		end
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
			if not visited[child] and not internalSource(child) then
				visited[child] = true
				table.insert(queue, child)
			end
		end
		if processed % 100 == 0 then task.wait() end
	end
	for kind in MARKERS do
		local tagged = CollectionService:GetTagged("AutoBridge." .. kind)
		local active = 0
		for _, node in tagged do if not internalSource(node) then active += 1 end end
		if active > 0 then markers[kind] = math.max(markers[kind] or 0, active) end
	end
	scanCount = processed
	truncated = processed >= limit or #queue >= limit
	return counts, markers
end

function AutoBridge.Discover(force)
	if not ctx or not config.Enabled then
		cache = {}
		return cache
	end
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
		table.insert(result, safeReport("leaderstats", { Name = "Leaderstats", DisplayName = message("Statistiques des joueurs","Player statistics"), Status = statCount > 0 and "Operational" or "Unsupported", Count = statCount,
			Detail = statCount > 0 and message("Statistiques numériques accessibles. Modifications via le module Leaderstats existant ; aucune économie personnalisée supposée.",
				"Numeric statistics available. Changes go through the existing Leaderstats module; no custom economy is assumed.")
				or message("Aucune statistique numérique présente actuellement.", "No numeric statistics present right now.") }))
		table.insert(result, safeReport("teams", { Name = "Teams", DisplayName = message("Équipes","Teams"), Status = teamCount > 0 and "Operational" or "Unsupported", Count = teamCount,
			Detail = config.EnableTeamActions and message("Diagnostic et changement d'équipe validé disponibles.", "Diagnostics and validated team changes available.")
				or message("Diagnostic disponible. Changement d'équipe désactivé par défaut.", "Diagnostics available. Team changes disabled by default.") }))
		table.insert(result, safeReport("tools", { Name = "Tools", DisplayName = message("Outils","Tools"), Status = counts.Tools > 0 and "Operational" or "Unsupported", Count = counts.Tools,
			Detail = message("Comptage structurel borné. Distribution via GiveTool et ses sources configurées ; aucun script découvert n'est exécuté.",
				"Bounded structural count. Distribution through GiveTool and its configured sources; no discovered script is executed.") }))
		table.insert(result, safeReport("vehicles", { Name = "VehicleSeat", DisplayName = message("Sièges de véhicules","Vehicle seats"), Status = counts.VehicleSeats > 0 and "Detected" or "Unsupported",
			Count = counts.VehicleSeats,
			Detail = message("La présence d'un siège ne prouve pas la compatibilité du contrôleur. Adaptateur explicite requis pour agir.",
				"A seat does not prove controller compatibility. An explicit adapter is required to act.") }))
		for kind, count in markers do
			table.insert(result, safeReport("marker_" .. kind, { Name = kind, Count = count, Status = "Unsupported",
				Detail = message("Marqueur explicite détecté (tag AutoBridge.%s ou attribut AutoBridgeSystem). Adaptateur serveur requis ; aucun require automatique.", "Explicit marker detected (tag AutoBridge.%s or AutoBridgeSystem attribute). Server adapter required; no automatic require.", kind) }))
		end
		for id, adapter in adapters do
			if id ~= "teams" then
				local probeOk, report = pcall(adapter.Probe, ctx)
				table.insert(result, safeReport(id, probeOk and report or { Status = "Error", Detail = message("Erreur d'intégration : %s", "Integration error: %s", safeString(tostring(report), 150)) }))
			end
		end
		table.sort(result, function(a, b)
			return a.Id < b.Id
		end)
		while #result > config.MaxEntries do table.remove(result) end
		return result
	end)
	scanning = false
	scannedAt = os.clock()
	if ok then cache = results else cache = { safeReport("scan", { Status = "Error", Detail = message("Analyse structurelle interrompue : %s", "Structural scan interrupted: %s", safeString(tostring(results), 150)) }) } end
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
		ConfigSource = ctx.SuiteConfig and ctx.SuiteConfig.Provenance("AutoBridge", scriptConfig, config) or nil,
		Scanning = scanning, ScannedAt = scannedAt, ScannedInstances = scanCount, Truncated = truncated, SchemaVersion = 2 }
end

function AutoBridge.Configure(player, patch)
	if not has(player, "AutoBridge.Configure") then return false, message("Accès refusé.", "Access denied.") end
	if not ctx.Guard.Allow(player, "ConfigureAutoBridge", 3, 10) then return false, message("Patiente avant de modifier les réglages.", "Wait before changing settings.") end
	local reset = type(patch) == "table" and patch.ResetToScript == true
	if type(patch) == "table" and patch.ResetToScript ~= nil then
		if not reset then return false, message("Demande de réinitialisation invalide.", "Invalid reset request.") end
		for key in patch do if key ~= "ResetToScript" then return false, message("La réinitialisation doit être envoyée seule.", "Reset must be requested on its own.") end end
	end
	local clean, err = AutoBridge.ValidateConfig(reset and {} or patch, reset and scriptConfig or config)
	if not clean then return false, err end
	if reset and disabled() then clean.Enabled = false end
	if disabled() and clean.Enabled then return false, message("AutoBridge désactivé dans Settings.Modules côté serveur.", "AutoBridge disabled in server-side Settings.Modules.") end
	local reply = message("Appliqué pour cette session.", "Applied for this session.")
	if ctx.SuiteConfig then
		local authorize = function()
			return has(player, "AutoBridge.Configure") and (not disabled() or not clean.Enabled)
		end
		local saved, problem
		if reset then saved, problem = ctx.SuiteConfig.Reset("AutoBridge", authorize)
		else saved, problem = ctx.SuiteConfig.Save("AutoBridge", clean, authorize) end
		if not saved then return false, problem or message("Sauvegarde non confirmée.", "Save not confirmed.") end
		reply = problem
	end
	if not has(player, "AutoBridge.Configure") or (disabled() and clean.Enabled) then
		return false, message("Autorisations modifiées pendant l'enregistrement ; réglage local non appliqué. Actualisez pour vérifier la sauvegarde.",
			"Permissions changed during saving; local setting not applied. Refresh to check the saved configuration.")
	end
	config = clean
	scannedAt = 0
	ctx.Log(player.Name, reset and "ResetAutoBridge" or "ConfigureAutoBridge", nil, reply, "AutoBridge", "info")
	return true, reply
end

function AutoBridge.Execute(player, adapterId, actionId, target, args)
	if not has(player, "AutoBridge.View") or not config.Enabled then return false, message("AutoBridge indisponible ou accès refusé.", "AutoBridge unavailable or access denied.") end
	if not ctx.Guard.Allow(player, "AutoBridgeAction", 8, 10) then return false, message("Trop de requêtes.", "Too many requests.") end
	if type(adapterId) ~= "string" or #adapterId > 40 or type(actionId) ~= "string" or #actionId > 40 then return false, message("Action invalide.", "Invalid action.") end
	local adapter = adapters[adapterId]
	local action = adapter and adapter.Actions[actionId]
	if not action or not has(player, adapter.Permission) or not has(player, action.Permission) then return false, message("Action refusée.", "Action denied.") end
	if adapterId == "teams" and not config.EnableTeamActions then return false, message("Les changements d'équipe sont désactivés.", "Team changes are disabled.") end
	if action.Target then
		if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players then return false, message("Cible invalide.", "Invalid target.") end
		if target == player then
			if not action.AllowSelf then return false, message("Action sur soi refusée.", "Action on yourself denied.") end
		elseif not ctx.Ranks.CanTarget(player, target) then return false, message("Grade de la cible protégé.", "Target's rank is protected.") end
	else
		target = nil
	end
	local probeOk, report = pcall(adapter.Probe, ctx)
	if not probeOk or type(report) ~= "table" or (report.Status ~= "Compatible" and report.Status ~= "Operational") then return false, message("Intégration actuellement incompatible.", "Integration currently incompatible.") end
	local validateOk, clean, problem = pcall(action.Validate, ctx, player, target, args)
	if not validateOk or clean == nil then return false, problem or message("Paramètres invalides.", "Invalid parameters.") end
	-- Validators may yield. Recheck current permissions and hierarchy before the mutation.
	if not config.Enabled or not has(player, action.Permission) or not has(player, adapter.Permission) or not has(player, "AutoBridge.View")
			or (target and (target.Parent ~= Players or (target ~= player and not ctx.Ranks.CanTarget(player, target))))
			or (adapterId == "teams" and not config.EnableTeamActions) then return false, message("Autorisations modifiées : action annulée.", "Permissions changed: action cancelled.") end
	local ok, success, reply = pcall(action.Execute, ctx, player, target, clean)
	if not ok then success, reply = false, message("Erreur de l'adaptateur : action interrompue.", "Adapter error: action interrupted.") end
	ctx.Log(player.Name, "AutoBridge." .. adapterId .. "." .. actionId, target and target.Name or nil, reply or "OK", "AutoBridge", success == false and "warning" or "info")
	return success == true, reply
end

function AutoBridge.Init(context)
	if ctx then return AutoBridge end
	ctx = context
	config = copy(DEFAULTS)
	local initial = type(ctx.Settings.AutoBridge) == "table" and ctx.Settings.AutoBridge or {}
	config = AutoBridge.ValidateConfig(initial, config) or config
	if disabled() then config.Enabled = false end
	scriptConfig = copy(config)
	if ctx.SuiteConfig then config = AutoBridge.ValidateConfig(ctx.SuiteConfig.Snapshot("AutoBridge") or {}, config) or config end
	if disabled() then config.Enabled = false end
	AutoBridge.RegisterAdapter("teams", { Probe = function()
		return { Status = #Teams:GetTeams() > 0 and "Operational" or "Unsupported" }
		end, Actions = { SetTeam = { Permission = "AutoBridge.Configure", Target = true, AllowSelf = true, Label = message("Changer l'équipe", "Change team"),
			Validate = function(_, _, _, args)
				if type(args) ~= "table" or type(args.Team) ~= "string" or #args.Team > 100 then return nil, message("Équipe invalide.", "Invalid team.") end
				for _, team in Teams:GetTeams() do if team.Name == args.Team then return { Team = team } end end
				return nil, message("Équipe introuvable.", "Team not found.")
			end,
			Execute = function(_, _, target, clean)
				if clean.Team.Parent ~= Teams then return false, message("Équipe supprimée.", "Team removed.") end
				target.Team = clean.Team
				target.Neutral = false
				return true, message("Équipe modifiée : %s", "Team changed: %s", target.Name)
	end } } })
	ctx.Remotes.GetAutoBridge.OnServerInvoke = function(player)
		if not has(player, "AutoBridge.View") or not ctx.Guard.Allow(player, "GetAutoBridge", 10, 10) then return { Allowed = false } end
		return AutoBridge.GetState(player)
	end
	ctx.Remotes.RefreshAutoBridge.OnServerInvoke = function(player)
		if not has(player, "AutoBridge.View") or not ctx.Guard.Allow(player, "RefreshAutoBridge", 2, 15) then return false, message("Actualisation limitée.", "Refresh rate limited.") end
		AutoBridge.Discover(true)
		return true, AutoBridge.GetState(player)
	end
	ctx.Remotes.ConfigureAutoBridge.OnServerInvoke = AutoBridge.Configure
	ctx.Remotes.AutoBridgeAction.OnServerInvoke = AutoBridge.Execute
	return AutoBridge
end
return AutoBridge
