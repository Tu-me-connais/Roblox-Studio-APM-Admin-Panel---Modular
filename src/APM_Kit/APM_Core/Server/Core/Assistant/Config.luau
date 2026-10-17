--[[
	Config : réglages ADMINISTRATIFS (globaux) de Sentinel, validés côté serveur. Les préférences LOCALES de chaque admin (activation,
	position, taille, animation) sont ailleurs (Preferences, par compte).
	Sources, de la plus faible à la plus forte : valeurs définies ici · Settings.Assistant (ServerSettings du développeur) · section
	« SentinelAssistant » de SuiteConfig (ce que Sentinel Helper enregistre ; DataStore de l'APM, ou mémoire en Studio).
	Chaque source passe par Config.Merge : valeurs absentes = défauts, valeurs invalides = ignorées (jamais d'erreur), schéma plus récent
	que le serveur = lecture seule (aucune écriture qui l'abimerait). La clé d'API n'est PAS ici : elle reste dans ServerSettings.
]]
local Actions = require(script.Parent.Actions)
local Catalog = require(script.Parent.Catalog)

local Config = {}
Config.SCHEMA = 1
Config.MAX_CUSTOM = 40
Config.MAX_LIST = 60

Config.DEFAULTS = table.freeze({
	Enabled = true,
	MaxHistory = 40, ReplyStyle = "Short", ConfirmDangerous = true,
	AllowAll = true, MaxAllTargets = 25, RatePerWindow = 8,
	DefaultDeployed = true, WaveEnabled = true, WaveInterval = 30, AnimationSpeed = 1,
})
Config.EXTERNAL_DEFAULTS = table.freeze({ Enabled = false, Provider = "OpenAI", Endpoint = "", Model = "", TimeoutSeconds = 8, MaxPerMinute = 6 })

-- Clés par rôle : qui a le droit de modifier quoi (vérifié par le serveur, jamais déduit du client)
Config.GENERAL_KEYS = { "Enabled", "MaxHistory", "ReplyStyle", "ConfirmDangerous", "AllowAll", "MaxAllTargets", "RatePerWindow",
	"DefaultDeployed", "WaveEnabled", "WaveInterval", "AnimationSpeed", "DisabledCommands", "Aliases" }

local PROVIDERS = { OpenAI = true, Anthropic = true }
Config.PROVIDERS = PROVIDERS

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in value do result[key] = copy(item) end
	return result
end
Config.Copy = copy

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function integer(value, low, high, fallback)
	if not finite(value) then return fallback end
	return math.clamp(math.floor(value + .5), low, high)
end
local function number(value, low, high, fallback, step)
	if not finite(value) then return fallback end
	value = math.clamp(value, low, high)
	if step then value = math.floor(value / step + .5) * step end
	return value
end

-- Alias / nom de commande : minuscules, lettres, chiffres et _, 2 à 24 signes
local function name(value)
	if type(value) ~= "string" then return nil end
	value = string.lower(value)
	return Catalog.ValidName(value) and value or nil
end

-- Liste de noms en table { [nom] = true } (DisabledCommands)
local function nameSet(value, fallback)
	if type(value) ~= "table" then return fallback end
	local result, count = {}, 0
	for key, item in value do
		local candidate = type(key) == "string" and item == true and key or (type(item) == "string" and type(key) == "number" and item) or nil
		candidate = candidate and name(candidate)
		if candidate and not result[candidate] then
			count += 1
			if count > Config.MAX_LIST then break end
			result[candidate] = true
		end
	end
	return result
end

-- Alias globaux { [alias] = commande }
local function aliasMap(value, fallback)
	if type(value) ~= "table" then return fallback end
	local result, count = {}, 0
	for alias, target in value do
		alias, target = name(alias), name(target)
		if alias and target and alias ~= target then
			count += 1
			if count > Config.MAX_LIST then break end
			result[alias] = target
		end
	end
	return result
end

local function plainText(value, limit)
	return Actions.CleanText(value, limit)
end

--[[
	Fiche personnalisée -> fiche propre, ou nil + code. features : { IsFeature = function(permission) -> bool } (grille de permissions de l'APM).
	Aucune clé inconnue n'est conservée ; l'action doit appartenir au registre fermé d'Actions.
]]
function Config.CleanCustom(definition, features)
	if type(definition) ~= "table" then return nil, "Invalid" end
	local commandName = name(definition.Name)
	if not commandName then return nil, "Name" end
	local description = definition.Description == nil and "" or plainText(definition.Description, 100)
	if not description then return nil, "Description" end
	local aliases = {}
	if definition.Aliases ~= nil then
		if type(definition.Aliases) ~= "table" or #definition.Aliases > 4 then return nil, "Aliases" end
		for _, alias in definition.Aliases do
			local clean = name(alias)
			if not clean or clean == commandName or table.find(aliases, clean) then return nil, "Aliases" end
			table.insert(aliases, clean)
		end
	end
	local args, seen = {}, {}
	if definition.Args ~= nil then
		if type(definition.Args) ~= "table" or #definition.Args > Actions.MAX_ARGS then return nil, "Args" end
		for _, arg in definition.Args do
			local argName = type(arg) == "table" and type(arg.Name) == "string" and string.lower(arg.Name) or nil
			if not argName or #argName > 12 or not string.match(argName, "^[a-z][a-z0-9_]*$") or seen[argName] or argName == "me" then return nil, "Args" end
			local kind = arg.Type
			if kind ~= "target" and kind ~= "number" and kind ~= "text" and kind ~= "boolean" then kind = "text" end
			seen[argName] = true
			table.insert(args, { Name = argName, Type = kind, Required = arg.Required == true,
				Min = kind == "number" and finite(arg.Min) and arg.Min or nil, Max = kind == "number" and finite(arg.Max) and arg.Max or nil })
		end
	end
	local permission = definition.Permission
	if permission == nil then permission = "Assistant.Use" end
	if type(permission) ~= "string" or #permission < 1 or #permission > 64 or (features and features.IsFeature and not features.IsFeature(permission)) then return nil, "Permission" end
	local action, problem = Actions.Validate(definition.Action, args)
	if not action then return nil, problem end
	return { Name = commandName, Description = description, Aliases = aliases, Args = args, Permission = permission, Action = action }
end

local function cleanExternal(value, base, allowedHosts)
	local result = copy(base)
	if type(value) ~= "table" then return result end
	if type(value.Enabled) == "boolean" then result.Enabled = value.Enabled end
	if type(value.Provider) == "string" and PROVIDERS[value.Provider] then result.Provider = value.Provider end
	if value.Model ~= nil then
		local model = plainText(value.Model, 60)
		if model and string.match(model, "^[%w%._%-:/]*$") then result.Model = model end
	end
	if value.Endpoint ~= nil then
		local endpoint = plainText(value.Endpoint, 200)
		if endpoint == "" then
			result.Endpoint = ""
		elseif endpoint then
			local host = string.match(endpoint, "^https://([%w%.%-]+)/?[^%s\\@]*$")
			local accepted = false
			if host then
				for _, allowed in allowedHosts or {} do
					if type(allowed) == "string" and string.lower(allowed) == string.lower(host) then accepted = true end
				end
			end
			if accepted then result.Endpoint = endpoint end
		end
	end
	result.TimeoutSeconds = integer(value.TimeoutSeconds, 3, 20, result.TimeoutSeconds)
	result.MaxPerMinute = integer(value.MaxPerMinute, 1, 30, result.MaxPerMinute)
	return result
end

--[[
	Applique `patch` sur `base` (config complète) et renvoie une NOUVELLE config propre. Les clés inconnues et les valeurs invalides
	sont ignorées. options : { Features = { IsFeature }, Hosts = {hôtes HTTPS autorisés}, Keys = ensemble de clés autorisées dans le patch }.
]]
function Config.Merge(base, patch, options)
	options = options or {}
	local result = copy(base)
	patch = type(patch) == "table" and patch or {}
	local function allowed(key)
		return patch[key] ~= nil and (options.Keys == nil or options.Keys[key] == true)
	end
	for _, key in { "Enabled", "ConfirmDangerous", "AllowAll", "DefaultDeployed", "WaveEnabled" } do
		if allowed(key) and type(patch[key]) == "boolean" then result[key] = patch[key] end
	end
	if allowed("MaxHistory") then result.MaxHistory = integer(patch.MaxHistory, 10, 100, result.MaxHistory) end
	if allowed("MaxAllTargets") then result.MaxAllTargets = integer(patch.MaxAllTargets, 1, 100, result.MaxAllTargets) end
	if allowed("RatePerWindow") then result.RatePerWindow = integer(patch.RatePerWindow, 2, 30, result.RatePerWindow) end
	if allowed("WaveInterval") then result.WaveInterval = number(patch.WaveInterval, 10, 120, result.WaveInterval, 1) end
	if allowed("AnimationSpeed") then result.AnimationSpeed = number(patch.AnimationSpeed, .5, 2, result.AnimationSpeed, .05) end
	if allowed("ReplyStyle") and (patch.ReplyStyle == "Short" or patch.ReplyStyle == "Detailed") then result.ReplyStyle = patch.ReplyStyle end
	if allowed("DisabledCommands") then result.DisabledCommands = nameSet(patch.DisabledCommands, result.DisabledCommands) end
	if allowed("Aliases") then result.Aliases = aliasMap(patch.Aliases, result.Aliases) end
	if allowed("External") then result.External = cleanExternal(patch.External, result.External, options.Hosts) end
	if allowed("Custom") and type(patch.Custom) == "table" then
		local list, used = {}, {}
		result.Issues = {}
		for _, definition in patch.Custom do
			if #list >= Config.MAX_CUSTOM then break end
			local clean, problem = Config.CleanCustom(definition, options.Features)
			if clean and not used[clean.Name] then
				used[clean.Name] = true
				table.insert(list, clean)
			elseif not clean then
				table.insert(result.Issues, { Name = type(definition) == "table" and tostring(definition.Name) or "?", Code = problem })
			end
		end
		result.Custom = list
	end
	return result
end

-- Config complète par défaut (jamais partagée : toujours une copie)
function Config.Defaults()
	local result = copy(Config.DEFAULTS)
	result.DisabledCommands, result.Aliases, result.Custom, result.Issues = {}, {}, {}, {}
	result.External = copy(Config.EXTERNAL_DEFAULTS)
	return result
end

local ALL_KEYS = {}
for _, key in Config.GENERAL_KEYS do ALL_KEYS[key] = true end
ALL_KEYS.External, ALL_KEYS.Custom = true, true
Config.ALL_KEYS = ALL_KEYS

--[[
	Construit la config EFFECTIVE : défauts -> Settings.Assistant -> section enregistrée.
	Renvoie config, info { Newer = true si la section enregistrée vient d'un schéma plus récent (lecture seule), Migrated, Stored = nombre de clés } .
]]
function Config.Load(settings, stored, options)
	options = options or {}
	local info = { Newer = false, Migrated = false, Stored = 0 }
	local scriptValues = type(settings) == "table" and type(settings.Assistant) == "table" and settings.Assistant or {}
	local hosts = type(scriptValues.External) == "table" and scriptValues.External.Hosts or {}
	local merge = { Features = options.Features, Hosts = hosts }
	local baseline = Config.Merge(Config.Defaults(), scriptValues, merge)
	local effective = baseline
	if type(stored) == "table" and next(stored) ~= nil then
		local version = tonumber(stored.SchemaVersion) or 0
		if version > Config.SCHEMA then
			info.Newer = true
		else
			info.Migrated = version < Config.SCHEMA
			-- schéma 0 (absent) -> 1 : mêmes champs, rien à convertir ; les migrations futures se rangent ici
			for _ in stored do info.Stored += 1 end
			effective = Config.Merge(baseline, stored, merge)
		end
	end
	effective.Issues = effective.Issues or {}
	return effective, info, baseline
end

-- Version prête à écrire dans SuiteConfig (sans les diagnostics ni rien de secret)
function Config.ForStorage(config)
	local result = copy(config)
	result.Issues = nil
	result.SchemaVersion = Config.SCHEMA
	return result
end

-- Ce que reçoit n'importe quel admin autorisé à utiliser Sentinel (pas de liste de commandes désactivées, pas d'IA, aucun secret)
function Config.ClientView(config)
	return { MaxHistory = config.MaxHistory, ReplyStyle = config.ReplyStyle, DefaultDeployed = config.DefaultDeployed, WaveEnabled = config.WaveEnabled,
		WaveInterval = config.WaveInterval, AnimationSpeed = config.AnimationSpeed }
end

return Config
