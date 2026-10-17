-- Distribution privée ; toutes les autorisations restent sur le serveur.
local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Http = game:GetService("HttpService")
local Remotes = require(RS:WaitForChild("APM_Shared").Remotes)
local Sessions = {}
local ctx, template, templates, sessions, pending, connections = nil, nil, nil, {}, {}, {}
local Version = require(script.Parent.Version)
-- Pages are developer-owned. Attributes are their server-readable manifest: never require client code on the server.
local function permittedPages(player)
	local root = SS:FindFirstChild("APM_Extensions")
	local folder = root and root:FindFirstChild("ClientPages")
	local pages, signature = {}, {}
	local visited = 0
	local function issue(path, code, source, field, value, expected, hint)
		if ctx.Extensions then
			ctx.Extensions.Record("ClientPages", path, "Error", code,
				ctx.Extensions.Details(code, field, value, expected, hint, source and source:GetFullName() or folder:GetFullName()))
		end
	end
	local function scan(parent, namespace, path, depth)
		if depth > 8 then
			issue(path, "DepthLimit", parent, "ClientPages", depth, "maximum 8 nested folders")
			return
		end
		local children = parent:GetChildren()
		table.sort(children, function(a, b)
			return a.Name < b.Name
		end)
		for _, source in children do
			if visited >= 200 then
				issue("limit", "SourceLimit", folder, "ClientPages", visited, "up to 200 page ModuleScripts")
				return
			end
			local relative = path .. "/" .. source.Name
			if source:IsA("ModuleScript") then
				visited += 1
				local permission = source:GetAttribute("Permission")
				if source:GetAttribute("ApiVersion") ~= Version.ExtensionApiVersion then
					issue(relative, "InvalidManifest", source, "attribute ApiVersion", source:GetAttribute("ApiVersion"), tostring(Version.ExtensionApiVersion))
				elseif type(permission) ~= "string" or #permission == 0 or #permission > 64 then
					issue(relative, "InvalidManifest", source, "attribute Permission", permission, "declared permission, 1–64 characters")
				elseif not ctx.Ranks.Defaults[permission] then
					issue(relative, "UndeclaredPermission", source, "attribute Permission", permission, "key in Settings.PermissionDefaults",
						{fr="Déclare cette permission dans APM_Extensions.Config.ServerSettings et choisis explicitement le grade minimum.",en="Declare this permission in APM_Extensions.Config.ServerSettings and explicitly choose its minimum rank."})
				else
					if ctx.Extensions then ctx.Extensions.Record("ClientPages",relative,"Ready",nil,{
						SourcePath=source:GetFullName(),
						Message={fr="Métadonnées validées côté serveur. Le code de la page est vérifié sur chaque client autorisé.",en="Metadata passed server checks. Page code is checked on each authorized client."},
					}) end
					if ctx.Ranks.HasPermission(player, permission) then
						table.insert(pages, { Source = source, Namespace = namespace, Path = relative, Permission = permission })
						table.insert(signature, relative .. ":" .. permission)
					end
				end
			elseif source:IsA("Folder") then
				scan(source, namespace, relative, depth + 1)
			end
		end
	end
	if folder then
		local children = folder:GetChildren()
		table.sort(children, function(a, b)
			return a.Name < b.Name
		end)
		for _, namespace in children do
			if namespace:IsA("ModuleScript") then
				issue(namespace.Name, "MisplacedPage", namespace, "Parent", namespace.Parent:GetFullName(), "ClientPages/<ExtensionId>/<Page>",
					{fr="Crée un dossier MonJeu dans ClientPages, puis déplace ce ModuleScript dedans. Voir APM_DeveloperTemplates.ClientPages.",en="Create a MonJeu folder in ClientPages, then move this ModuleScript inside. See APM_DeveloperTemplates.ClientPages."})
			elseif namespace:IsA("Folder") then
				if #namespace.Name > 64 or not namespace.Name:match("^[%w_%.%-]+$") then
					issue(namespace.Name, "InvalidNamespace", namespace, "Name", namespace.Name, "1–64 letters, digits, _ - .")
				else scan(namespace, namespace.Name, namespace.Name, 1) end
			end
		end
	end
	return pages, table.concat(signature, "|")
end
local function payloadSafe(value, depth, budget)
	budget.n += 1
	if budget.n > 128 or depth > 4 then return false end
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" then return true end
	if kind == "number" then return value == value and math.abs(value) < math.huge end
	if kind == "string" then return #value <= 1024 and utf8.len(value) ~= nil end
	if kind == "Instance" then return value:IsA("Player") and value.Parent == Players end
	if kind ~= "table" then return false end
	for key, item in value do
		if (type(key) ~= "string" and type(key) ~= "number") or not payloadSafe(key, depth + 1, budget) or not payloadSafe(item, depth + 1, budget) then return false end
	end
	return true
end
function Sessions.ValidatePayload(...)
	local budget = { n = 0 }
	local args = table.pack(...)
	for i = 1, args.n do if not payloadSafe(args[i], 0, budget) then return false end end
	return true
end
local function abuse(player, reason)
	if ctx.Sentinel and ctx.Sentinel.RecordAbuse then ctx.Sentinel.RecordAbuse(player, reason) end
end
local function allowed(record, caller, name, ...)
	if not record.active or caller ~= record.player or sessions[caller] ~= record or not record.holder.Parent or caller.Parent ~= Players then return false end
	local recovery = name == "RestoreSimulation" and ctx.Ranks.GetSimulation(caller).active == true
	if not recovery and (record.recovery or not ctx.Ranks.HasPermission(caller, "APM.AccessPanel")) then
		abuse(caller, { fr = "Accès ou session révoqué", en = "Access or session revoked" })
		return false
	end
	if not ctx.Guard.Allow(caller, "SessionTotal", 100, 10) or not ctx.Guard.Allow(caller, "Session:" .. name, 30, 10) then
		abuse(caller, ctx.Lang.Phrase({ fr = "Limite de fréquence : %s", en = "Rate limit: %s" }, name))
		return false
	end
	if not Sessions.ValidatePayload(...) then
		abuse(caller, ctx.Lang.Phrase({ fr = "Arguments invalides : %s", en = "Invalid arguments: %s" }, name))
		return false
	end
	return true
end
function Sessions.Send(player, name, ...)
	local record = sessions[player]
	if record and record.active and record.remotes[name] then record.remotes[name]:FireClient(player, ...) end
end
local function finishRetired(record, force)
	if not record.retired or record.destroyQueued or (record.inFlight > 0 and not force) then return end
	record.destroyQueued = true
	if record.retireTimer then
		task.cancel(record.retireTimer)
		record.retireTimer = nil
	end
	-- Let the RemoteFunction callback return its reply before retiring its transport.
	-- Authorization was already invalidated synchronously; no new call can dispatch.
	task.defer(function()
		for _, remote in record.remotes do if remote:IsA("RemoteFunction") then remote.OnServerInvoke = nil end end
		record.holder:Destroy()
	end)
end
function Sessions.Revoke(player, reason)
	local record = sessions[player]
	if not record then return end
	record.active = false
	record.retired = true
	sessions[player] = nil
	if record.remotes.SessionRevoked then record.remotes.SessionRevoked:FireClient(player, reason or "Accès révoqué") end
	for _, connection in record.connections do connection:Disconnect() end
	if ctx.OnAccessRevoked then ctx.OnAccessRevoked(player) end
	for _, name in { "APM_Gui", "APM_Launcher", "APM_Sentinel" } do
		local gui = player:FindFirstChildOfClass("PlayerGui")
		local old = gui and gui:FindFirstChild(name)
		if old then old:Destroy() end
	end
	finishRetired(record)
	if not record.destroyQueued then
		-- A stalled provider must not retain a revoked transport indefinitely.
		record.retireTimer = task.delay(60, function()
			record.retireTimer = nil
			finishRetired(record, true)
		end)
	end
end
local function makeSession(player, gui, recovery)
	local holder = Instance.new("ScreenGui")
	holder.Name = recovery and "APM_Recovery" or "APM_Private"
	holder.ResetOnSpawn = false
	holder:SetAttribute("APMPrivate", true)
	holder:SetAttribute("SessionId", Http:GenerateGUID(false))
	local folder = Instance.new("Folder")
	folder.Name = "APM_Remotes"
	folder.Parent = holder
	local pages, signature = permittedPages(player)
	local record = { player = player, holder = holder, remotes = {}, connections = {}, active = true, recovery = recovery, inFlight = 0, pageSignature = signature }
	table.insert(record.connections, holder.ChildAdded:Connect(function(node)
		if node.Name == "APM_Remotes" and node ~= folder or node.Name == "APM_Client" and record.client and node ~= record.client then node:Destroy() end
	end))
	table.insert(record.connections, folder.ChildAdded:Connect(function(node)
		if record.remotes[node.Name] and record.remotes[node.Name] ~= node then node:Destroy() end
	end))
	sessions[player] = record
	table.insert(record.connections, gui.ChildAdded:Connect(function(node)
		if node ~= holder and node:GetAttribute("APMPrivate") == true and (node.Name == "APM_Private" or node.Name == "APM_Recovery") then node:Destroy() end
	end))
	local function create(name, className)
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = folder
		record.remotes[name] = remote
		if className == "RemoteFunction" then
			remote.OnServerInvoke = function(caller, ...)
				if not allowed(record, caller, name, ...) then return false, { fr = "Demande refusée : autorisation, session ou arguments.", en = "Request refused: authorization, session or arguments." } end
				record.inFlight += 1
				local result = table.pack(pcall(Remotes.Dispatch, name, caller, ...))
				record.inFlight -= 1
				finishRetired(record)
				if not result[1] then
					warn("[APM] Endpoint " .. name .. " : " .. tostring(result[2]))
					return false, { fr = "Erreur serveur ; consulter les diagnostics.", en = "Server error; see diagnostics." }
				end
				if name ~= "RestoreSimulation" and name ~= "SetSimulation" and (not record.active or not ctx.Ranks.HasPermission(caller, "APM.AccessPanel")) then return false, { fr = "Accès révoqué pendant la demande.", en = "Access revoked during the request." } end
				return table.unpack(result, 2, result.n)
			end
		else
			table.insert(record.connections, remote.OnServerEvent:Connect(function(caller, ...)
				if allowed(record, caller, name, ...) then Remotes.Dispatch(name, caller, ...) end
			end))
		end
	end
	if recovery then
		create("RestoreSimulation", "RemoteFunction")
		local recoveryTemplate = templates:FindFirstChild("Recovery")
		assert(recoveryTemplate, "Modèle de récupération manquant")
		recoveryTemplate:Clone().Parent = holder
	else
		for _, name in Remotes.Functions do create(name, "RemoteFunction") end
		for _, name in Remotes.Events do create(name, "RemoteEvent") end
		local client = template:Clone()
		record.client = client
		local extensionPages = Instance.new("Folder")
		extensionPages.Name = "ExtensionPages"
		extensionPages.Parent = client
		for _, entry in pages do
			-- Recheck before source distribution; individual pages may not inherit another page's permission.
			if ctx.Ranks.HasPermission(player, entry.Permission) then
				local namespace = extensionPages
				local parts = string.split(entry.Path, "/")
				for i = 1, #parts - 1 do
					local sub = namespace:FindFirstChild(parts[i])
					if not sub then
						sub = Instance.new("Folder")
						sub.Name = parts[i]
						sub.Parent = namespace
					end
					namespace = sub
				end
				local source = entry.Source:Clone()
				source:SetAttribute("ExtensionId", entry.Namespace)
				source.Parent = namespace
			end
		end
		client.Parent = holder
	end
	holder.Parent = gui
	return record
end
function Sessions.Reconcile(player)
	local access = ctx.Ranks.HasPermission(player, "APM.AccessPanel")
	local simulation = ctx.Ranks.GetSimulation(player)
	local recovery = not access and simulation.active == true
	local old = sessions[player]
	local _, signature = permittedPages(player)
	if old and not old.recovery and old.pageSignature ~= signature then
		Sessions.Revoke(player, "Pages autorisées modifiées")
		old = nil
	end
	if old and (old.recovery ~= recovery or (not access and not recovery)) then
		Sessions.Revoke(player)
		old = nil
	end
	if old then
		if not old.recovery then Sessions.Send(player, "RankChanged") end
		return
	end
	if (not access and not recovery) or pending[player] then return end
	pending[player] = true
	task.spawn(function()
		local resolved = ctx.Ranks.WaitResolved(player, 10)
		local gui = resolved and player:WaitForChild("PlayerGui", 10)
		pending[player] = nil
		if not gui or player.Parent ~= Players or sessions[player] then return end
		local nowAccess = ctx.Ranks.HasPermission(player, "APM.AccessPanel")
		local nowRecovery = not nowAccess and ctx.Ranks.GetSimulation(player).active == true
		if nowAccess or nowRecovery then makeSession(player, gui, nowRecovery) end
	end)
end
function Sessions.Diagnostics(player)
	local record = sessions[player]
	local metadata = type(ctx.Settings._APMConfiguration) == "table" and ctx.Settings._APMConfiguration or {}
	return {
		sessionActive = record ~= nil and record.active, recovery = record ~= nil and record.recovery,
		authorized = ctx.Ranks.HasPermission(player, "APM.AccessPanel"), simulation = ctx.Ranks.GetSimulation(player),
		privateTemplate = template:GetFullName(), publicNoticeChannels = { "Announcement", "Warned", "Muted" },
		replicationCaveat = "La simulation après connexion ne prouve pas l'absence de réplication initiale. Vérifier un second client connecté sans grade.",
		globalAdminRemotes = RS:FindFirstChild("APM_Remotes") ~= nil,
		core = { Version = Version.Version, Channel = Version.Channel, ApiVersion = Version.CoreApiVersion, DataSchemaVersion = Version.DataSchemaVersion },
		extensions = ctx.Extensions and ctx.Extensions.Snapshot() or nil,
		configuration = {
			SourcePath = string.sub(tostring(metadata.SourcePath or ""),1,512),
			DuplicateConfigurations = metadata.DuplicateConfigurations == true,
			StudioMemory = metadata.StudioMemory == true,
			MemoryMode = ctx.Ranks.Memory == true,
		},
	}
end
function Sessions.Init(context)
	if ctx then
		assert(ctx == context, "[APM] Sessions already initialized")
		return
	end
	ctx = context
	templates = script.Parent.Parent.Parent:WaitForChild("ClientTemplates", 10)
	assert(templates, "Modèles privés manquants")
	template = templates:WaitForChild("APM_Client", 10)
	assert(template, "APM_Client manquant")
	Remotes.Configure(Sessions)
	table.insert(connections, Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			if ctx.Ranks.WaitResolved(player, 10) then Sessions.Reconcile(player) end
		end)
	end))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		Sessions.Revoke(player, "Déconnexion")
		pending[player] = nil
	end))
	for _, player in Players:GetPlayers() do Sessions.Reconcile(player) end
end
return Sessions
