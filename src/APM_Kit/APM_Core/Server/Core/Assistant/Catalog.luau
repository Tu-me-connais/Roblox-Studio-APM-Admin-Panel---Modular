--[[
	Catalog : les commandes de Sentinel SONT le registre existant de l'APM (ctx.Modules + outils client) ; rien n'est réimplémenté.
	Pour chaque module on déduit une fiche (nom tapable, alias, arguments, usage) à partir de ses champs publics
	(Mode, Inputs, Fields, Min / Max, Confirm, AllowSelf...). S'y ajoutent les commandes personnalisées validées de Sentinel Helper.
	Une extension peut ajouter Aliases = { ... } à sa commande, ou Assistant = false pour la garder hors de Sentinel.
	Le catalogue ne donne AUCUN droit : chaque exécution repasse par APMService.perform (grade, matrice, hiérarchie, valeurs).

	Multilingue : les phrases des sept langues (CommandLocalization) mènent à la MÊME fiche que le nom anglais : ByName["volar"] et ByName["fly"] sont
	deux clés de la même entrée { Spec, Negate }. Ordre de priorité d'un nom, jamais arbitraire : noms de modules et d'outils · phrases officielles des
	dictionnaires · commandes personnalisées · alias de modules · alias globaux de Sentinel Helper. Un nom déjà pris par une AUTRE action est refusé et
	listé dans Conflicts ; le même nom pour la même action n'est pas un conflit. Une commande désactivée dans Sentinel n'a aucune phrase, dans aucune langue.
	TargetPolicy dit comment une cible absente se comprend (voir Assistant) :
	  Required     cible obligatoire (kick, freeze, bring...) : jamais de cible implicite
	  OptionalSelf cible facultative : sans cible = l'administrateur lui-même (fly, noclip, speed 50) ; « all » se confirme toujours
	  SelfOnly     agit sur l'administrateur uniquement (invisible, godmode, esp)
	  Observe      spectate : « spectate » seul ouvre la vue libre, « spectate pseudo » observe ce joueur (jamais distribué)
	  None         action globale (timeofday, shutdown, unban)
	  Custom       commande personnalisée : ses propres arguments
]]
local Parser = require(script.Parent.Parser)
local Localization = Parser.Lexicon

local Catalog = {}

-- Commandes locales de l'interface : réservées, aucun module ne peut les masquer (anglais et français historiques + mots ASCII des dictionnaires)
Catalog.LOCAL = { help = "Help", aide = "Help", list = "List", commands = "List", commandes = "List", clear = "Clear", cls = "Clear", effacer = "Clear" }

-- Alias fournis (anglais et français, sans accent). Un alias déjà pris par une autre commande est ignoré (jamais de remplacement silencieux).
local BUILTIN_ALIASES = {
	Kick = { "expulse", "expulser", "virer" }, Ban = { "bannir", "bannis" }, Unban = { "debannir", "deban" },
	Kill = { "tuer" }, Freeze = { "geler", "gele", "fige" }, Mute = { "muet", "silence" }, Warn = { "avertir", "warning" },
	Heal = { "soigner", "soin" }, Respawn = { "reapparaitre" }, Teleport = { "tp", "goto", "aller" },
	Bring = { "amener", "ramener" }, Return = { "renvoyer" }, ToSpawn = { "spawn" },
	Invisible = { "invis", "vanish", "invisibilite" }, Godmode = { "god", "dieu", "invincible" },
	Speed = { "vitesse", "walkspeed", "ws" }, JumpPower = { "jump", "saut", "jp" },
	GiveTool = { "give", "donner" }, TimeOfDay = { "time", "heure" }, Shutdown = { "arret" }, Leaderstats = { "stats", "stat" },
	Fly = { "voler", "vol" }, Noclip = { "nc", "clip" }, ESP = { "radar" }, Spectator = { "spectate", "spec", "observer" },
}

-- Durée minimale (en minutes) d'une durée NON NULLE, pour les modules qui travaillent en minutes entières : Ban arrondit à la minute ENTIÈRE vers le bas,
-- donc une durée plus courte (30 s, 0,5) deviendrait un bannissement DÉFINITIF. Un module peut déclarer MinMinutes lui-même ; sans valeur, toute durée positive passe.
local BUILTIN_MIN_MINUTES = { Ban = 1 }

-- Commandes qui n'ont aucun sens (ou sont trop risquées) sur tout le serveur : Teleport déplace l'admin lui-même
local NO_ALL = { Teleport = true }

local KIND_BY_MODE = { target = "Target", toggle = "Toggle", slider = "Slider", action = "Global" }

local function lowerName(name)
	return Parser.Normalize(tostring(name))
end

local function validName(name)
	return type(name) == "string" and #name >= 2 and #name <= 24 and string.match(name, "^[a-z][a-z0-9_]*$") ~= nil
end

-- les mots ASCII des commandes locales de toutes les langues (« ayuda », « hilfe », « liste »...) sont réservés eux aussi
if Localization ~= nil then
	for word, kind in Localization.Lexicon.Local do
		if validName(word) and not Catalog.LOCAL[word] then Catalog.LOCAL[word] = kind end
	end
end

-- Arguments supplémentaires d'un module (après la cible) : Inputs (Reason, Minutes) ou Fields typés
local function extraArguments(module)
	local args = {}
	if type(module.Fields) == "table" and #module.Fields > 0 then
		for _, field in module.Fields do
			if type(field) == "table" and type(field.Name) == "string" then
				table.insert(args, {
					Name = string.lower(field.Name), Field = field.Name,
					Type = field.Type == "number" and "number" or (field.Type == "choice" and "choice" or "text"),
					Min = tonumber(field.Min), Max = tonumber(field.Max), Integer = field.Integer == true,
					Default = field.Default, Optional = field.Default ~= nil or (field.Type ~= "number" and field.Type ~= "choice"),
					MaxLength = tonumber(field.MaxLength), Options = field.Type == "choice" and field.Options or nil,
				})
			end
		end
	elseif type(module.Inputs) == "table" then
		for _, input in module.Inputs do
			if input == "Reason" then
				table.insert(args, { Name = "reason", Field = "Reason", Type = "text", Optional = true })
			elseif input == "Minutes" then
				table.insert(args, { Name = "minutes", Field = "Minutes", Type = "duration", Optional = true, MinMinutes = tonumber(module.MinMinutes) or BUILTIN_MIN_MINUTES[module.Name] })
			end
		end
	end
	return args
end

--[[
	Emplacements d'arguments d'une commande, dans l'ordre de l'usage : SOURCE UNIQUE de la ligne d'usage, de l'aide (catalogue) et de l'autocomplétion.
	Chaque emplacement : { Type = target | state | number | duration | text | choice, Display = "<player|me|all>", Optional, ... }.
	Target : All (« all » proposé par la commande ; les réglages de Sentinel Helper peuvent encore le refuser), Self (viser soi-même permis), Off (spectate off).
]]
local function slotsOf(spec)
	local slots = {}
	local function add(slot) table.insert(slots, slot) end
	if spec.Kind == "Target" then
		add({ Type = "target", Display = "<player|me|all>", All = spec.AllowAll == true, Self = spec.SelfAllowed == true })
	elseif spec.Kind == "Slider" then
		add({ Type = "target", Optional = true, Display = spec.Targetable and "[player|all]" or "[me]", All = spec.Targetable == true, Self = true, MeOnly = not spec.Targetable })
		add({ Type = "number", Display = string.format("<%d-%d>", spec.Min or 0, spec.Max or 100), Min = spec.Min, Max = spec.Max, Reset = true })
	elseif spec.Kind == "Tool" and spec.Distributed then
		add({ Type = "target", Optional = true, Display = "[player|me|all]", All = true, Self = true })
		add({ Type = "state", Optional = true, Display = "[on|off]" })
	elseif spec.Kind == "Tool" and spec.Module == "Spectator" then
		add({ Type = "target", Optional = true, Display = "[player|off]", All = false, Self = false, Off = true })
	elseif spec.Kind == "Toggle" or spec.Kind == "Tool" then
		add({ Type = "state", Optional = true, Display = "[on|off]" })
	end
	for _, arg in spec.Args do
		local kind = arg.Type == "boolean" and "state" or arg.Type
		add({ Type = kind, Display = arg.Optional and ("[" .. arg.Name .. "]") or ("<" .. arg.Name .. ">"), Optional = arg.Optional == true, Name = arg.Name,
			Min = arg.Min, Max = arg.Max, Options = arg.Options, MinMinutes = arg.MinMinutes })
	end
	if spec.Kind == "Global" and #spec.Args == 0 then add({ Type = "text", Display = "[value]", Optional = true }) end
	return slots
end

local function usageOf(spec)
	local parts = { spec.Name }
	for _, slot in spec.Slots do table.insert(parts, slot.Display) end
	return table.concat(parts, " ")
end

local function moduleSpec(module)
	local kind = KIND_BY_MODE[module.Mode]
	if not kind or module.Assistant == false or type(module.Name) ~= "string" then return nil end
	local spec = {
		Name = lowerName(module.Name), Module = module.Name, Source = module.ExtensionId and "Extension" or "Module", Kind = kind,
		Category = module.Category, Label = module.Label, Description = module.Description,
		Confirm = module.Confirm == true or module.Severity == "danger" and module.Confirm ~= false,
		AllowAll = not (module.Confirm == true or module.Severity == "danger" and module.Confirm ~= false) and not NO_ALL[module.Name],
		Severity = module.Severity, Args = extraArguments(module), Aliases = {},
		Min = tonumber(module.Min), Max = tonumber(module.Max), Default = tonumber(module.Default),
		Targetable = type(module.ExecuteTarget) == "function",
		HasState = type(module.GetState) == "function", HasTargetState = type(module.GetTargetState) == "function",
		SelfAllowed = module.AllowSelf == true or (module.AllowSelf == nil and module.Category ~= "Players"),
	}
	-- cible absente : cible obligatoire, soi-même (facultative) ou soi-même seulement
	if kind == "Target" then
		spec.TargetPolicy = "Required"
	elseif kind == "Slider" then
		spec.TargetPolicy = spec.Targetable and "OptionalSelf" or "SelfOnly"
	elseif kind == "Toggle" then
		spec.TargetPolicy = "SelfOnly"
	else
		spec.TargetPolicy = "None"
	end
	spec.Undoable = kind == "Toggle" or (kind == "Target" and spec.HasTargetState)
	for _, alias in BUILTIN_ALIASES[module.Name] or {} do table.insert(spec.Aliases, alias) end
	if not module.ExtensionId then spec.Official = true end
	if type(module.Aliases) == "table" then
		for _, alias in module.Aliases do
			if type(alias) == "string" and validName(lowerName(alias)) then table.insert(spec.Aliases, lowerName(alias)) end
		end
	end
	return spec
end

-- Outils client (Fly, Noclip...) : ils agissent sur l'appareil de l'admin ; le serveur autorise, le client exécute
local function toolSpec(entry, index, ctx)
	local name = type(entry) == "string" and entry or (type(entry) == "table" and entry.Name) or (type(index) == "string" and index)
	if type(name) ~= "string" or name == "" then return nil end
	local spec = {
		Name = lowerName(name), Module = name, Source = "Tool", Kind = "Tool", Category = "Moderation", Args = {}, Aliases = {},
		Label = "Tool." .. name .. ".Label", Description = "Tool." .. name .. ".Desc", Undoable = true,
	}
	for _, alias in BUILTIN_ALIASES[name] or {} do table.insert(spec.Aliases, alias) end
	-- Distribuée : le Dispatcher sait l'appliquer sur le client d'un autre joueur (Fly, Noclip). Sinon : effet local de l'admin (ESP, Spectator).
	spec.Distributed = ctx ~= nil and ctx.Dispatcher ~= nil and ctx.Dispatcher.Handles(name) == true
	spec.TargetPolicy = spec.Distributed and "OptionalSelf" or (name == "Spectator" and "Observe" or "SelfOnly")
	return spec
end

-- Commande personnalisée validée (Config.CleanCustom) -> fiche
local function customSpec(def)
	local args = {}
	for _, arg in def.Args do
		table.insert(args, { Name = arg.Name, Field = arg.Name, Type = arg.Type, Min = arg.Min, Max = arg.Max, Optional = arg.Required ~= true })
	end
	return { Name = def.Name, Module = def.Name, Source = "Custom", Kind = "Custom", Category = "Assistant", Args = args, TargetPolicy = "Custom", Undoable = false,
		Label = def.Name, Description = def.Description, Aliases = table.clone(def.Aliases or {}), Permission = def.Permission, Definition = def }
end

--[[
	Construit le catalogue. Renvoie { ByName = { [nom ou phrase] = { Spec, Negate, Languages? } }, Specs = { fiches }, Names = { tous les noms tapables, triés },
	Conflicts = { ... }, MaxWords = plus longue phrase en mots, Compiled = index multilingue }.
	`Negate` : « unfly », « unfreeze », « 停止飞行 »... (mise à l'arrêt d'un outil ou d'un état que le module sait lire).
]]
function Catalog.Build(ctx, config)
	config = config or {}
	local disabled = type(config.DisabledCommands) == "table" and config.DisabledCommands or {}
	local byName, specs, conflicts = {}, {}, {}
	local function same(entry, spec, negate)
		return entry.Spec == spec and entry.Negate == (negate == true)
	end
	local function claim(name, spec, negate)
		if not validName(name) or Catalog.LOCAL[name] then
			table.insert(conflicts, { Name = name, With = Catalog.LOCAL[name] and "Local" or "Invalid" })
			return false
		end
		local current = byName[name]
		if current then
			if same(current, spec, negate) then return true end -- déjà réservé pour cette même action : pas un conflit
			table.insert(conflicts, { Name = name, With = current.Spec.Name })
			return false
		end
		byName[name] = { Spec = spec, Negate = negate == true }
		return true
	end
	local pending = {}
	local function register(spec)
		if not spec or disabled[spec.Name] or disabled[string.lower(spec.Module)] then return end
		if byName[spec.Name] then
			table.insert(conflicts, { Name = spec.Name, With = byName[spec.Name].Spec.Name })
			return
		end
		if not claim(spec.Name, spec) then return end
		table.insert(specs, spec)
		table.insert(pending, spec)
	end
	-- 1. noms de modules, puis d'outils
	local modules = type(ctx.Modules) == "table" and ctx.Modules or {}
	local ordered = {}
	for _, module in modules do table.insert(ordered, module) end
	table.sort(ordered, function(a, b) return tostring(a.Name) < tostring(b.Name) end)
	for _, module in ordered do register(moduleSpec(module)) end
	local tools = type(ctx.Settings) == "table" and type(ctx.Settings.ClientTools) == "table" and ctx.Settings.ClientTools or {}
	for index, entry in tools do register(toolSpec(entry, index, ctx)) end

	-- 2. phrases officielles des dictionnaires (sept langues), avant les commandes personnalisées et les alias : un nom officiel ne peut pas être détourné
	local compiled
	if Localization ~= nil then
		local available, bySpec = {}, {}
		for _, spec in specs do
			available[spec.Module] = { Undoable = spec.Undoable == true }
			bySpec[spec.Module] = spec
		end
		local ok, result = pcall(Localization.Compile, Localization, available)
		if ok then
			compiled = result
			local keys = {}
			for key in compiled.Phrases do table.insert(keys, key) end
			table.sort(keys)
			for _, key in keys do
				local slot, spec = compiled.Phrases[key], bySpec[compiled.Phrases[key].Module]
				local current = byName[key]
				if current then
					if same(current, spec, slot.Negate) then
						current.Languages = current.Languages or slot.Languages
					else
						table.insert(conflicts, { Name = key, With = current.Spec.Name })
					end
				else
					byName[key] = { Spec = spec, Negate = slot.Negate, Languages = slot.Languages, Localized = true }
				end
			end
		else
			warn("[APM] Sentinel : index multilingue indisponible : " .. tostring(result))
		end
	end

	-- 3. commandes personnalisées validées
	for _, def in type(config.Custom) == "table" and config.Custom or {} do register(customSpec(def)) end
	-- alias propres à chaque fiche, puis variantes « un... »
	for _, spec in pending do
		for _, alias in spec.Aliases do claim(alias, spec) end
	end
	for _, spec in pending do
		if spec.Undoable then
			claim("un" .. spec.Name, spec, true)
			for _, alias in spec.Aliases do claim("un" .. alias, spec, true) end
		end
	end
	-- alias globaux définis dans Sentinel Helper : vers une commande existante seulement
	for alias, target in type(config.Aliases) == "table" and config.Aliases or {} do
		local entry = type(target) == "string" and byName[target]
		if entry and not entry.Negate then claim(alias, entry.Spec) end
	end
	table.sort(specs, function(a, b) return a.Name < b.Name end)
	for _, spec in specs do
		spec.Slots = slotsOf(spec)
		spec.Usage = usageOf(spec)
	end
	local names = {}
	for name in byName do table.insert(names, name) end
	for name in Catalog.LOCAL do table.insert(names, name) end
	table.sort(names)
	return { ByName = byName, Specs = specs, Names = names, Conflicts = conflicts, MaxWords = compiled and compiled.MaxWords or 1, Compiled = compiled }
end

--[[
	Trouve la commande au début de `tokens` : essaie d'abord la phrase la plus longue (« stop vol », « modo dios », « server herunterfahren »), puis les
	plus courtes. Renvoie entrée, nombre de mots consommés ; nil, 0 si rien ne correspond. Aucune approximation : la phrase doit être exacte (accents,
	majuscules et espaces multiples exceptés).
]]
function Catalog.Find(catalog, tokens)
	local limit = math.min(catalog.MaxWords or 1, #tokens)
	for count = limit, 1, -1 do
		local words = table.create(count)
		for index = 1, count do words[index] = Parser.Normalize(tokens[index]) end
		local entry = catalog.ByName[table.concat(words, " ")]
		if entry then return entry, count end
	end
	return nil, 0
end

-- Alias officiels par langue (Sentinel Helper) : { [code] = { { Module, On = {...}, Off = {...} } } } ; nil si le dictionnaire est indisponible
function Catalog.Describe(catalog)
	if Localization == nil or not catalog.Compiled then return nil end
	return Localization:Describe(catalog.Compiled)
end

-- Un nom est-il disponible pour une commande personnalisée / un alias ? (aucun module, outil, alias, phrase officielle, mot réservé ou commande locale ne porte ce nom)
function Catalog.IsNameFree(catalog, name, ignoreSpec)
	if not validName(name) or Catalog.LOCAL[name] then return false end
	if Localization ~= nil and Localization:Reserved(Parser.Normalize(name)) ~= nil then return false end
	local entry = catalog.ByName[name]
	return entry == nil or (ignoreSpec ~= nil and entry.Spec == ignoreSpec)
end

Catalog.ValidName = validName

-- Mots d'un vocabulaire d'arguments ({ [mot plié] = langues }) en liste triée, courts d'abord : sert à l'autocomplétion du client (au plus 60 mots de 16 caractères)
function Catalog.WordList(set)
	local list = {}
	for word in type(set) == "table" and set or {} do
		if type(word) == "string" and (utf8.len(word) or 99) <= 16 and #list < 200 then table.insert(list, word) end
	end
	table.sort(list, function(a, b)
		local la, lb = utf8.len(a) or #a, utf8.len(b) or #b
		if la ~= lb then return la < lb end
		return a < b
	end)
	while #list > 60 do table.remove(list) end
	return list
end

return Catalog
