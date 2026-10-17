-- Developer extensions are owned by the experience, outside APM_Core.
local ServerStorage = game:GetService("ServerStorage")
local Extensions = { ApiVersion = 1 }
local records, initialized, recordCount, dropped = {}, false, 0, 0
local MAX_RECORDS, MAX_ENTRIES = 600, 200
local function identifier(value, limit)
	return type(value) == "string" and #value > 0 and #value <= (limit or 40) and value:match("^[%w_%-%.]+$") ~= nil
end
local function finite(value) return type(value) == "number" and value == value and math.abs(value) < math.huge end
local function bounded(value, limit) return string.sub(tostring(value or ""), 1, limit) end
local function received(value)
	local kind = typeof(value)
	if kind == "string" then return bounded(value, 160) end
	if kind == "nil" then return "nil" end
	if kind == "number" or kind == "boolean" then return tostring(value) end
	return "<" .. kind .. ">"
end
local function text(fr, en) return { fr = fr, en = en } end
local EXPECTATIONS = {
	["maximum 200 modules / 8 nested folders"] = {fr="maximum 200 modules / 8 niveaux de dossiers",en="maximum 200 modules / 8 nested folders"},
	["1–40 letters, digits, _ - ."] = {fr="1 à 40 lettres, chiffres, _ - .",en="1–40 letters, digits, _ - ."},
	["1–64 letters, digits, _ - ."] = {fr="1 à 64 lettres, chiffres, _ - .",en="1–64 letters, digits, _ - ."},
	["table containing command metadata and Execute"] = {fr="table contenant les métadonnées de commande et Execute",en="table containing command metadata and Execute"},
	["Players, Moderation, Game or a valid custom identifier"] = {fr="Players, Moderation, Game ou un identifiant personnalisé valide",en="Players, Moderation, Game or a valid custom identifier"},
	["a category other than AutoBridge"] = {fr="une catégorie différente d’AutoBridge",en="a category other than AutoBridge"},
	["finite number"] = {fr="nombre fini",en="finite number"},
	["boolean"] = {fr="booléen",en="boolean"},
	["bounded public text, numbers, colors or tables; no functions or Instances"] = {fr="textes, nombres, couleurs ou tables publics de taille limitée ; aucune fonction ni Instance",en="bounded public text, numbers, colors or tables; no functions or Instances"},
	["list of up to 40 fields"] = {fr="liste de 40 champs au maximum",en="list of up to 40 fields"},
	["consecutive list indices 1..40"] = {fr="indices consécutifs de 1 à 40",en="consecutive list indices 1..40"},
	["field table"] = {fr="table décrivant un champ",en="field table"},
	["unique field identifier"] = {fr="identifiant de champ unique",en="unique field identifier"},
	["option list or registered provider key"] = {fr="liste d’options ou clé d’un fournisseur enregistré",en="option list or registered provider key"},
	["{ \"Reason\", \"Minutes\" } or a subset"] = {fr="{ \"Reason\", \"Minutes\" } ou une partie de cette liste",en="{ \"Reason\", \"Minutes\" } or a subset"},
	["language dictionaries"] = {fr="dictionnaires de langues",en="language dictionaries"},
	["language dictionary"] = {fr="dictionnaire de langue",en="language dictionary"},
	["string translation"] = {fr="traduction sous forme de texte",en="string translation"},
	["permission declared in Settings.PermissionDefaults"] = {fr="permission déclarée dans Settings.PermissionDefaults",en="permission declared in Settings.PermissionDefaults"},
	["table of named actions, or {} for a read-only integration"] = {fr="table d’actions nommées, ou {} pour une intégration en lecture seule",en="table of named actions, or {} for a read-only integration"},
	["up to 40 actions"] = {fr="40 actions au maximum",en="up to 40 actions"},
	["named action table"] = {fr="table décrivant une action nommée",en="named action table"},
	["declared permission"] = {fr="permission déclarée",en="declared permission"},
	["identifier <=20 characters and function"] = {fr="identifiant de 20 caractères maximum et fonction",en="identifier <=20 characters and function"},
	["identifier <=20; AutoBridge enabled"] = {fr="identifiant de 20 caractères maximum ; AutoBridge activé",en="identifier <=20; AutoBridge enabled"},
	["up to 100 ModuleScripts"] = {fr="100 ModuleScripts au maximum",en="up to 100 ModuleScripts"},
	["ModuleScript returning a manifest"] = {fr="ModuleScript renvoyant un manifeste",en="ModuleScript returning a manifest"},
	["manifest table"] = {fr="table de manifeste",en="manifest table"},
	["unique extension Id"] = {fr="Id d’extension unique",en="unique extension Id"},
	["AutoBridge enabled"] = {fr="AutoBridge activé",en="AutoBridge enabled"},
	["valid, unique adapter"] = {fr="adaptateur valide et unique",en="valid, unique adapter"},
	["callback completes without error"] = {fr="fonction exécutée sans erreur",en="callback completes without error"},
	["maximum 8 nested folders"] = {fr="8 niveaux de dossiers au maximum",en="maximum 8 nested folders"},
	["up to 200 page ModuleScripts"] = {fr="200 ModuleScripts de page au maximum",en="up to 200 page ModuleScripts"},
	["declared permission, 1–64 characters"] = {fr="permission déclarée de 1 à 64 caractères",en="declared permission, 1–64 characters"},
	["key in Settings.PermissionDefaults"] = {fr="clé dans Settings.PermissionDefaults",en="key in Settings.PermissionDefaults"},
	["registration inside Init(api)"] = {fr="enregistrement dans Init(api)",en="registration inside Init(api)"},
	["function(ctx, player) completes without error"] = {fr="function(ctx, player) exécutée sans erreur",en="function(ctx, player) completes without error"},
}
local function expectedText(value)
	if type(value) == "table" then
		local result = {}
		for _, code in {"fr","en","es","pt","de","ru","zh"} do if type(value[code]) == "string" then result[code] = bounded(value[code], 300) end end
		return result
	end
	return EXPECTATIONS[value] or bounded(value, 180)
end
local MESSAGES = {
	InvalidCommand = text("Le contrat de la commande est incomplet ou invalide.", "The command contract is incomplete or invalid."),
	UnsupportedApi = text("La version API de l'extension est incompatible.", "The extension API version is incompatible."),
	InvalidNamespace = text("Le nom du dossier d'extension est invalide.", "The extension folder name is invalid."),
	InvalidManifest = text("Les métadonnées de l'extension sont incomplètes ou incompatibles.", "The extension metadata is incomplete or incompatible."),
	UndeclaredPermission = text("Cette permission n'est pas déclarée dans ServerSettings.", "This permission is not declared in ServerSettings."),
	MisplacedPage = text("Cette page est placée directement dans ClientPages et ne peut pas être chargée.", "This page is directly under ClientPages and cannot be loaded."),
	RequireFailed = text("Le ModuleScript n'a pas pu être chargé.", "The ModuleScript could not be loaded."),
	InitFailed = text("L'initialisation de l'extension a échoué.", "The extension initialization failed."),
	CleanupFailed = text("La restauration après retrait d'accès a échoué.", "Cleanup after access was revoked failed."),
	DuplicateCommand = text("Une commande porte déjà ce nom.", "A command already has this name."),
	DuplicateId = text("Une extension utilise déjà cet identifiant.", "An extension already uses this identifier."),
	SourceLimit = text("La limite de sources d'extension est atteinte.", "The extension source limit has been reached."),
	DepthLimit = text("Les dossiers de cette extension sont trop imbriqués.", "The extension folders are nested too deeply."),
	RegistrationClosed = text("L'enregistrement des commandes est terminé.", "Command registration has already finished."),
	DisabledBySettings = text("Cette commande est désactivée dans ServerSettings.", "This command is disabled in ServerSettings."),
	InvalidAdapter = text("Le contrat de l'adaptateur AutoBridge est invalide.", "The AutoBridge adapter contract is invalid."),
	AdapterRejected = text("AutoBridge a refusé cet adaptateur.", "AutoBridge rejected this adapter."),
}
function Extensions.Details(code, field, value, expected, hint, sourcePath)
	return {
		SourcePath = bounded(sourcePath, 512), Field = bounded(field, 100),
		Received = received(value), Expected = expectedText(expected),
		Message = MESSAGES[code] or text("Valeur d'extension invalide.", "Invalid extension value."),
		Hint = hint or text("Corrige le champ indiqué, puis relance Play.", "Correct the indicated field, then restart Play."),
	}
end
local function safeText(value)
	if type(value) == "table" then return { fr = bounded(value.fr, 300), en = bounded(value.en, 300) } end
	return bounded(value, 300)
end
local function publicData(value, depth, budget)
	budget.n += 1
	if budget.n > 1000 or depth > 5 then return false end
	local kind = typeof(value)
	if kind == "nil" or kind == "boolean" or kind == "Color3" then return true end
	if kind == "number" then return finite(value) end
	if kind == "string" then return #value <= 4096 and utf8.len(value) ~= nil end
	if kind ~= "table" then return false end
	for key, item in value do
		if (type(key) ~= "string" and type(key) ~= "number") or not publicData(key, depth + 1, budget) or not publicData(item, depth + 1, budget) then return false end
	end
	return true
end
local function children(folder)
	local list = folder:GetChildren()
	table.sort(list, function(a, b) return a.Name < b.Name end)
	return list
end
function Extensions.Root()
	local root = ServerStorage:FindFirstChild("APM_Extensions")
	if root and (root:IsA("Folder") or root:IsA("Model")) then return root end
	return nil
end
function Extensions.Record(kind, id, status, code, details)
	details = type(details) == "table" and details or {}
	local source = bounded(details.SourcePath, 512)
	local key = kind .. ":" .. tostring(id) .. ":" .. tostring(status) .. ":" .. tostring(code) .. ":" .. source .. ":" .. tostring(details.Field or "")
	if not records[key] then
		if recordCount >= MAX_RECORDS then dropped += 1 return end
		recordCount += 1
	end
	records[key] = {
		Kind = bounded(kind, 30), Id = bounded(id, 160), Status = bounded(status, 30), Code = code and bounded(code, 60) or nil,
		SourcePath = source, Field = bounded(details.Field, 100), Received = bounded(details.Received, 160), Expected = expectedText(details.Expected),
		Message = safeText(details.Message or (code and MESSAGES[code]) or ""), Hint = safeText(details.Hint or ""),
	}
end
function Extensions.Snapshot()
	local entries, loaded, errors = {}, 0, 0
	for _, record in records do
		table.insert(entries, table.clone(record))
		if record.Status == "Error" then errors += 1 elseif record.Status == "Loaded" then loaded += 1 end
	end
	table.sort(entries, function(a, b)
		if (a.Status == "Error") ~= (b.Status == "Error") then return a.Status == "Error" end
		if a.Kind == b.Kind then if a.Id == b.Id then return a.SourcePath < b.SourcePath end return a.Id < b.Id end
		return a.Kind < b.Kind
	end)
	local total = #entries
	while #entries > MAX_ENTRIES do table.remove(entries) end
	return { ApiVersion = Extensions.ApiVersion, Present = Extensions.Root() ~= nil, Loaded = loaded, Errors = errors,
		Entries = entries, Total = total, Truncated = total > MAX_ENTRIES or dropped > 0 }
end
function Extensions.CommandSources()
	local root = Extensions.Root()
	local folder = root and root:FindFirstChild("Commands")
	local sources = {}
	if not folder or not folder:IsA("Folder") then return sources end
	local function limit(node, namespace)
		Extensions.Record("Commands", namespace, "Error", "SourceLimit", Extensions.Details("SourceLimit", "Commands", #sources, "maximum 200 modules / 8 nested folders", nil, node:GetFullName()))
	end
	local function visit(node, namespace, depth)
		if depth > 8 or #sources >= 200 then limit(node, namespace) return end
		for _, child in children(node) do
			if #sources >= 200 then limit(node, namespace) return end
			if child:IsA("ModuleScript") then table.insert(sources, { Source = child, ExtensionId = namespace })
			elseif child:IsA("Folder") then visit(child, namespace, depth + 1) end
		end
	end
	for _, child in children(folder) do
		if #sources >= 200 then limit(folder, "limit") break end
		if not identifier(child.Name) then
			Extensions.Record("Commands", child.Name, "Error", "InvalidNamespace", Extensions.Details("InvalidNamespace", "Name", child.Name, "1–40 letters, digits, _ - .", nil, child:GetFullName()))
		elseif child:IsA("ModuleScript") then table.insert(sources, { Source = child, ExtensionId = child.Name })
		elseif child:IsA("Folder") then visit(child, child.Name, 1) end
	end
	return sources
end
function Extensions.ValidateCommand(command, namespace, ranks, sourcePath)
	local function fail(code, field, value, expected, hint)
		return false, code, Extensions.Details(code, field, value, expected, hint, sourcePath)
	end
	if not identifier(namespace) then return fail("InvalidNamespace", "ExtensionId", namespace, "1–40 letters, digits, _ - .") end
	if type(command) ~= "table" then return fail("InvalidCommand", "return", command, "table containing command metadata and Execute") end
	if command.ApiVersion ~= Extensions.ApiVersion then return fail("UnsupportedApi", "ApiVersion", command.ApiVersion, tostring(Extensions.ApiVersion)) end
	if not identifier(command.Name, 64) then return fail("InvalidCommand", "Name", command.Name, "1–64 letters, digits, _ - .") end
	if type(command.Execute) ~= "function" then return fail("InvalidCommand", "Execute", command.Execute, "function(ctx, admin, target, value)") end
	if not identifier(command.Category, 64) then return fail("InvalidCommand", "Category", command.Category, "Players, Moderation, Game or a valid custom identifier") end
	if type(command.MinRank) ~= "string" or not ranks.ById[command.MinRank] then
		local ids = {} for id in ranks.ById do table.insert(ids, id) end table.sort(ids)
		return fail("InvalidCommand", "MinRank", command.MinRank, table.concat(ids, ", "), text("Utilise un Id présent dans Settings.Ranks.", "Use an Id declared in Settings.Ranks."))
	end
	if string.lower(command.Category) == "autobridge" then return fail("AutoBridgeHomeOnly", "Category", command.Category, "a category other than AutoBridge") end
	if command.Mode ~= nil and command.Mode ~= "action" and command.Mode ~= "target" and command.Mode ~= "toggle" and command.Mode ~= "slider" then return fail("InvalidMode", "Mode", command.Mode, "action | target | toggle | slider") end
	if command.Order ~= nil and not finite(command.Order) then return fail("InvalidOrder", "Order", command.Order, "finite number") end
	for _, key in { "Init", "OnAccessRevoked" } do
		if command[key] ~= nil and type(command[key]) ~= "function" then return fail(key == "Init" and "InvalidInit" or "InvalidCleanup", key, command[key], key == "Init" and "function(ctx)" or "function(ctx, player)") end
	end
	if command.Color ~= nil and typeof(command.Color) ~= "Color3" then return fail("InvalidColor", "Color", command.Color, "Color3") end
	for _, key in { "Confirm", "AllowSelf" } do
		if command[key] ~= nil and type(command[key]) ~= "boolean" then return fail("InvalidTargetPolicy", key, command[key], "boolean") end
	end
	for _, key in { "Min", "Max", "Default" } do
		if command[key] ~= nil and (key ~= "Default" or command.Mode == "slider") and not finite(command[key]) then return fail("InvalidNumber", key, command[key], "finite number") end
	end
	if command.Min ~= nil and command.Max ~= nil and command.Min > command.Max then return fail("InvalidRange", "Min", command.Min, "Min <= Max (" .. tostring(command.Max) .. ")") end
	local budget = { n = 0 }
	for _, key in { "Name", "Label", "Description", "Category", "Mode", "Group", "Order", "Color", "Min", "Max", "Default", "Confirm", "Fields", "Inputs", "Strings" } do
		if not publicData(command[key], 0, budget) then return fail("InvalidPublicData", key, command[key], "bounded public text, numbers, colors or tables; no functions or Instances") end
	end
	if command.Fields ~= nil then
		if type(command.Fields) ~= "table" or #command.Fields > 40 then return fail("InvalidFields", "Fields", command.Fields, "list of up to 40 fields") end
		local names, count = {}, 0
		for index, field in command.Fields do
			count += 1
			local path = "Fields[" .. tostring(index) .. "]"
			if count > 40 or type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #command.Fields then return fail("InvalidFields", path, index, "consecutive list indices 1..40") end
			if type(field) ~= "table" then return fail("InvalidField", path, field, "field table") end
			if not identifier(field.Name, 64) or names[field.Name] then return fail("InvalidField", path .. ".Name", field.Name, "unique field identifier") end
			if field.Type ~= "number" and field.Type ~= "choice" and field.Type ~= "text" and field.Type ~= "string" then return fail("InvalidField", path .. ".Type", field.Type, "number | choice | text | string") end
			names[field.Name] = true
			for _, key in { "Min", "Max", "Default", "MaxLength" } do
				if field[key] ~= nil and (key ~= "Default" or field.Type == "number") and not finite(field[key]) then return fail("InvalidFieldNumber", path .. "." .. key, field[key], "finite number") end
			end
			if field.Min ~= nil and field.Max ~= nil and field.Min > field.Max then return fail("InvalidFieldRange", path .. ".Min", field.Min, "Min <= Max (" .. tostring(field.Max) .. ")") end
			if field.Type == "choice" and type(field.Options) ~= "table" and type(field.Options) ~= "string" then return fail("InvalidOptions", path .. ".Options", field.Options, "option list or registered provider key") end
		end
	end
	if command.Inputs ~= nil then
		if type(command.Inputs) ~= "table" or #command.Inputs > 2 then return fail("InvalidInputs", "Inputs", command.Inputs, '{ "Reason", "Minutes" } or a subset') end
		local count = 0
		for index, input in command.Inputs do
			count += 1
			if count > 2 or type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > #command.Inputs or (input ~= "Reason" and input ~= "Minutes") then return fail("InvalidInput", "Inputs[" .. tostring(index) .. "]", input, "Reason | Minutes") end
		end
	end
	if command.Strings ~= nil then
		if type(command.Strings) ~= "table" then return fail("InvalidStrings", "Strings", command.Strings, "language dictionaries") end
		for code, dictionary in command.Strings do
			if type(code) ~= "string" or type(dictionary) ~= "table" then return fail("InvalidStrings", "Strings." .. tostring(code), dictionary, "language dictionary") end
			for key, value in dictionary do
				if type(key) ~= "string" or type(value) ~= "string" then return fail("InvalidStrings", "Strings." .. code .. "." .. tostring(key), value, "string translation") end
			end
		end
	end
	return true
end
function Extensions.ValidateAdapter(adapter, ctx, sourcePath)
	local function fail(field, value, expected)
		return false, "InvalidAdapter", Extensions.Details("InvalidAdapter", field, value, expected, nil, sourcePath)
	end
	if type(adapter) ~= "table" then return fail("Adapter", adapter, "table") end
	if type(adapter.Permission) ~= "string" or not ctx.Ranks.Defaults[adapter.Permission] then return fail("Adapter.Permission", adapter.Permission, "permission declared in Settings.PermissionDefaults") end
	if type(adapter.Probe) ~= "function" then return fail("Adapter.Probe", adapter.Probe, "function(ctx) -> {Status, Name, Count, Detail}") end
	if type(adapter.Actions) ~= "table" then return fail("Adapter.Actions", adapter.Actions, "table of named actions, or {} for a read-only integration") end
	local count = 0
	for name, action in adapter.Actions do
		count += 1
		if count > 40 then return fail("Adapter.Actions", count, "up to 40 actions") end
		local path = "Adapter.Actions." .. tostring(name)
		if not identifier(name, 40) or type(action) ~= "table" then return fail(path, action, "named action table") end
		if type(action.Permission) ~= "string" or not ctx.Ranks.Defaults[action.Permission] then return fail(path .. ".Permission", action.Permission, "declared permission") end
		if type(action.Validate) ~= "function" then return fail(path .. ".Validate", action.Validate, "function(ctx, admin, target, args) -> clean, error") end
		if type(action.Execute) ~= "function" then return fail(path .. ".Execute", action.Execute, "function(ctx, admin, target, clean) -> success, message") end
	end
	return true
end
function Extensions.Init(ctx, service)
	if initialized then return Extensions end
	initialized = true
	ctx.Extensions = Extensions
	local root = Extensions.Root()
	if not root then return Extensions end
	local ids = {}
	local function makeApi(namespace, sourcePath)
		local api = { ApiVersion = Extensions.ApiVersion, Id = namespace }
		function api.RegisterCommand(command) return ctx.RegisterExtensionCommand(command, namespace, sourcePath) end
		function api.RegisterOptions(name, provider)
			if not identifier(name, 20) or type(provider) ~= "function" then
				Extensions.Record("Server", namespace, "Error", "InvalidOptionsProvider", Extensions.Details("InvalidOptionsProvider", "RegisterOptions", name, "identifier <=20 characters and function", nil, sourcePath))
				return nil, "InvalidOptionsProvider"
			end
			local key = namespace .. "." .. name
			service.RegisterOptions(key, provider)
			return key
		end
		function api.AddProfileProvider(provider)
			if type(provider) ~= "function" then return false, "InvalidProfileProvider" end
			service.AddProfileProvider(provider) return true
		end
		function api.RegisterAdapter(name, adapter)
			local valid, code, details = Extensions.ValidateAdapter(adapter, ctx, sourcePath)
			if not identifier(name, 20) or not valid or not ctx.AutoBridge then
				Extensions.Record("Adapters", namespace .. "_" .. tostring(name), "Error", code or "InvalidAdapter", details or Extensions.Details("InvalidAdapter", "Name / AutoBridge", name, "identifier <=20; AutoBridge enabled", nil, sourcePath))
				return false, code or "InvalidAdapter"
			end
			local id = namespace .. "_" .. name
			if #id > 40 then return false, "AdapterIdTooLong" end
			return ctx.AutoBridge.RegisterAdapter(id, adapter)
		end
		function api.HasPermission(player, permission) return ctx.Ranks.CanUse(player, permission) end
		function api.CanTarget(player, target) return ctx.Ranks.CanTarget(player, target) end
		function api.Authorize(player, command, target) return ctx.Authorize(player, command, target) end
		function api.Notify(player, message, success) ctx.Notify(player, message, success) end
		function api.Log(actor, action, target, detail, level) ctx.Log(actor, namespace .. "." .. tostring(action), target, detail, "Extensions", level or "info") end
		return table.freeze(api)
	end
	for _, kind in { "Adapters", "Server" } do
		local folder = root:FindFirstChild(kind)
		if folder and folder:IsA("Folder") then
			local count = 0
			for _, source in children(folder) do
				if source:IsA("ModuleScript") then
					count += 1
					if count > 100 then Extensions.Record(kind, "limit", "Error", "SourceLimit", Extensions.Details("SourceLimit", kind, count, "up to 100 ModuleScripts", nil, folder:GetFullName())) break end
					local path = source:GetFullName()
					local ok, manifest = pcall(require, source)
					local id = ok and type(manifest) == "table" and manifest.Id or source.Name
					local code, details
					local function problem(reason, field, value, expected, hint)
						code = reason details = Extensions.Details(reason, field, value, expected, hint, path)
					end
					if not ok then problem("RequireFailed", "require", manifest, "ModuleScript returning a manifest")
					elseif type(manifest) ~= "table" then problem("InvalidManifest", "return", manifest, "manifest table")
					elseif manifest.ApiVersion ~= Extensions.ApiVersion then problem("UnsupportedApi", "ApiVersion", manifest.ApiVersion, tostring(Extensions.ApiVersion))
					elseif not identifier(id) then problem("InvalidManifest", "Id", id, "1–40 letters, digits, _ - .")
					elseif ids[id] then problem("DuplicateId", "Id", id, "unique extension Id")
					elseif kind == "Adapters" then
						local valid, issue, data = Extensions.ValidateAdapter(manifest.Adapter, ctx, path)
						if not valid then code, details = issue, data
						elseif not ctx.AutoBridge then problem("InvalidAdapter", "Settings.Modules.AutoBridge", false, "AutoBridge enabled")
						else local ready, issue = ctx.AutoBridge.RegisterAdapter(id, manifest.Adapter) if not ready then problem("AdapterRejected", "Adapter", issue, "valid, unique adapter") end end
					elseif type(manifest.Init) ~= "function" then problem("InvalidInit", "Init", manifest.Init, "function(api)")
					else
						local ready, issue = pcall(manifest.Init, makeApi(id, path))
						if not ready or issue == false then problem("InitFailed", "Init(api)", issue, "callback completes without error") end
					end
					if not code then ids[id] = true else warn("[APM] Extension " .. path .. " : " .. tostring(code) .. " · " .. tostring(details and details.Received)) end
					Extensions.Record(kind, id, code and "Error" or "Loaded", code, details or { SourcePath = path })
				end
			end
		end
	end
	return Extensions
end
return Extensions
