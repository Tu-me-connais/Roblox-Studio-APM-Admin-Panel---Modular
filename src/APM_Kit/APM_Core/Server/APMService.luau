--[[
	APMService : cœur serveur de l'APM (Admin Panel Modulaire).

	Démarré par le bootstrap privé. Les commandes officielles restent dans Modules ; les personnalisations sont chargées
	depuis ServerStorage.APM_Extensions.Commands, hors du Package Core.
	Le modèle complet d'un module est dans le « READ ME!!! » (Name, Category, Mode, Group, Fields, Inputs, MinRank, Execute...).

	Toute demande d'un client est revalidée ici : grade, matrice d'accès, hiérarchie (on n'agit que sur un grade strictement inférieur),
	valeurs des champs (type, bornes, liste de choix) et anti-spam. Chaque action est inscrite dans le journal (onglet Logs).

	API pour tes autres scripts serveur (attendre le rangement du kit au démarrage) :
	  local storage = game:GetService("ServerStorage")
	  local core = assert(storage:WaitForChild("APM_Core", 10), "APM_Core absent : vérifier ToolboxBootstrap")
	  local server = assert(core:WaitForChild("Server", 10), "APM Server absent")
	  local service = assert(server:WaitForChild("APMService", 10), "APMService absent")
	  local APM = require(service)
	  local ctx = APM.WaitForReady() -- appeler depuis ton script, jamais dans Init(api)
	  -- Puis utiliser les méthodes ci-dessous ; WaitForReady n'a pas d'argument de délai.
	  APM.WaitForReady() -> ctx            APM.IsAdmin(player)            APM.GetRank(player)
	  APM.HasRankAtLeast(player, "Staff")   APM.Notify(player, texte, succès)
	  APM.Log(acteur, action, cible, détail, catégorie, "info" | "warning" | "danger")
	  APM.AddProfileProvider(function(userId, player) return { { Label = "Coins", Value = 10 } } end)
	  APM.RegisterOptions("maListe", function() return { { "id", "Texte affiché" } } end)
	  APM.TrackDataStore(DataStoreService:GetDataStore("PlayerData"), "PlayerData") -> DataStore suivi dans l'onglet Stats
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Root = script.Parent
local Shared = ReplicatedStorage:WaitForChild("APM_Shared")
local Lang = require(Shared:WaitForChild("Lang"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local Settings = require(Root:WaitForChild("Settings"))
local CoreFolder = Root:WaitForChild("Core")
local Ranks = require(CoreFolder.Ranks)
local Guard = require(CoreFolder.Guard)
local Journal = require(CoreFolder.Journal)
local Roster = require(CoreFolder.Roster)
local Controls = require(CoreFolder.Controls)
local Announcements = require(CoreFolder.Announcements)
local Grades = require(CoreFolder.Grades)
local Profiles = require(CoreFolder.Profiles)
local TextFilter = require(CoreFolder.TextFilter)
local Sessions = require(CoreFolder.Sessions)
local SuiteConfig = require(CoreFolder.SuiteConfig)
local Preferences = require(CoreFolder.Preferences)
local Extensions = require(CoreFolder.Extensions)
local HomeTelemetry = require(CoreFolder.HomeTelemetry)
local Features = require(CoreFolder.Features)
local Statistics = require(CoreFolder.Statistics)

local Msg = Lang.Msg

local APMService = {}
APMService.ExtensionApiVersion = Extensions.ApiVersion
APMService.Ready = false
APMService.Context = nil
local readyEvent = Instance.new("BindableEvent")
APMService.OnReady = readyEvent.Event

local MODES = { target = true, toggle = true, slider = true, action = true }
local SEVERITIES = { info = true, warning = true, danger = true }
local OPTIONS_CACHE_SECONDS = 5

local optionProviders = {} -- [nom de liste] = function() -> { { id, texte }, ... }

----------------------------------------------------------------------------------------------------------
-- API publique

function APMService.RegisterOptions(name, provider)
	if type(name) == "string" and type(provider) == "function" then
		optionProviders[name] = provider
	end
end

function APMService.AddProfileProvider(provider)
	Profiles.AddProvider(provider)
end

function APMService.IsAdmin(player)
	return Ranks.IsAdmin(player)
end

function APMService.GetRank(player)
	return Ranks.GetRank(player)
end

function APMService.HasRankAtLeast(player, rankId)
	return Ranks.HasRankAtLeast(player, rankId)
end

function APMService.Log(actorName, action, targetName, detail, category, level)
	Journal.Log(actorName, action, targetName, detail, category, level)
end

function APMService.Notify(player, message, success)
	if APMService.Context then
		APMService.Context.Notify(player, message, success)
	end
end

-- Renvoie un DataStore qui s'utilise comme l'original ; ses appels apparaissent dans l'onglet Stats
function APMService.TrackDataStore(store, name)
	return Statistics.WrapDataStore(store, name)
end

function APMService.WaitForReady()
	if not APMService.Ready then
		APMService.OnReady:Wait()
	end
	return APMService.Context
end

----------------------------------------------------------------------------------------------------------
-- Modules

-- Valeurs par défaut d'un module ; libellés par défaut = clés de traduction Mod.<Nom>.Label / .Desc / .<Champ>
local function normalize(module, source)
	module.Name = type(module.Name) == "string" and module.Name ~= "" and module.Name or source.Name
	if type(module.Strings) == "table" then
		Lang.AddAll(module.Strings)
	end
	local prefix = "Mod." .. module.Name .. "."
	if module.Label == nil then
		module.Label = Lang.Has(prefix .. "Label") and prefix .. "Label" or module.Name
	end
	if module.Description == nil and Lang.Has(prefix .. "Desc") then
		module.Description = prefix .. "Desc"
	end
	module.Category = type(module.Category) == "string" and module.Category ~= "" and module.Category or "Players"
	module.Mode = MODES[module.Mode] and module.Mode or "action"
	module.Order = tonumber(module.Order) or 100
	module.Severity = SEVERITIES[module.Severity] and module.Severity or "info"
	if type(module.Fields) == "table" then
		for _, field in module.Fields do
			if type(field) == "table" and field.Label == nil then
				local key = prefix .. tostring(field.Name)
				field.Label = Lang.Has(key) and key or tostring(field.Name)
			end
		end
	end
end

-- Ce que le client reçoit d'un module (sans ses fonctions)
local function publicInfo(module)
	local fields
	if type(module.Fields) == "table" then
		fields = {}
		for _, field in module.Fields do
			table.insert(fields, {
				Name = field.Name, Label = field.Label, Type = field.Type, Options = field.Options, Default = field.Default,
				Min = field.Min, Max = field.Max, Integer = field.Integer, MaxLength = field.MaxLength,
			})
		end
	end
	return {
		Name = module.Name, Label = module.Label, Description = module.Description, Category = module.Category, Mode = module.Mode,
		Group = module.Group, Order = module.Order, Color = module.Color, Min = module.Min, Max = module.Max, Default = module.Default,
		Confirm = module.Confirm, Fields = fields, Inputs = module.Inputs, Strings = module.Strings,
		ExtensionId = module.ExtensionId,
	}
end

----------------------------------------------------------------------------------------------------------

local initializing=false
function APMService.Init(deps)
	local registry=game:GetService("ServerStorage"):FindFirstChild("APM_RuntimeRegistry")
	if registry then
		local owner=registry:FindFirstChild("Service")
		if owner and owner.Value and owner.Value~=script then return require(owner.Value).WaitForReady()end
		if not owner then owner=Instance.new("ObjectValue");owner.Name="Service";owner.Parent=registry end
		owner.Value=script
	end
	if APMService.Context then
		warn("[APM] APMService.Init a déjà été appelé : second appel ignoré.")
		return APMService.Context
	end
	if initializing then return APMService.WaitForReady()end
	initializing=true
	local R = Remotes.All()

	-- Contexte passé à chaque module (Init(ctx) et Execute(ctx, admin, cible, valeur))
	local ctx = {
		Settings = Settings,
		Ranks = Ranks,
		Guard = Guard,
		Remotes = R,
		Controls = Controls,
		Filter = TextFilter,
		Lang = Lang,
		Msg = Msg,
		Roster = Roster,
		Game = type(deps) == "table" and deps or {}, -- services du jeu passés par APM_Boot
		Shared = {}, -- état partagé entre modules (ex. Bring / Return)
		RegisterOptions = APMService.RegisterOptions,
		AddProfileProvider = APMService.AddProfileProvider,
	}
	function ctx.Notify(player, message, success)
		if typeof(player) == "Instance" and player:IsA("Player") and player.Parent then
			R.Notify:FireClient(player, message, success ~= false)
		end
	end
	-- Texte déjà traduit dans la langue d'un joueur (pour player:Kick(), qui affiche un texte brut)
	function ctx.TextFor(player, key, ...)
		return Lang.Get(Lang.ForPlayer(player), key, ...)
	end

	-- réponses par défaut (un module peut les remplacer dans son Init, ex. Warn -> GetWarnings)
	R.GetWarnings.OnServerInvoke = function()
		return {}
	end

	Ranks.Init()
	SuiteConfig.Init(ctx)
	ctx.SuiteConfig = SuiteConfig
	Preferences.Init(ctx)
	Journal.Init(Ranks, R, Settings)
	ctx.Log = Journal.Log
	Roster.Init(Ranks, Settings)
	Controls.Init(ctx)
	Announcements.Init(ctx) -- annonces : style, verrou de rédaction et d'affichage (ctx.Announcements)
	Statistics.Start()
	ctx.Statistics = Statistics
	local homeTelemetry = HomeTelemetry.Create(ctx) -- après Statistics : partage son compteur de cycle serveur
	Grades.Init(ctx)
	Profiles.Init(ctx)

	-- Chargement des modules ------------------------------------------------------------------------------
	local modules, ordered = {}, {}
	local function load(source,extensionId)
		if Settings.DisabledCommands and Settings.DisabledCommands[source.Name] then
			if extensionId then Extensions.Record("Commands", extensionId .. ":" .. source.Name, "Disabled", "DisabledBySettings", { SourcePath = source:GetFullName() }) end
			return
		end
		local ok, result = pcall(require, source)
		if not ok then
			warn(("[APM] Échec du chargement de %s : %s"):format(source:GetFullName(), tostring(result)))
			if extensionId then Extensions.Record("Commands",extensionId..":"..source.Name,"Error","RequireFailed", Extensions.Details("RequireFailed", "require", result, "ModuleScript returning a command", nil, source:GetFullName())) end
			return
		end
		if extensionId then
			local valid,code,details=Extensions.ValidateCommand(result,extensionId,Ranks,source:GetFullName())
			if not valid then Extensions.Record("Commands",extensionId..":"..source.Name,"Error",code,details) return end
			result=table.clone(result)
			result.ExtensionId=extensionId
			result._APMSourcePath=source:GetFullName()
		elseif type(result)=="table" then result.ExtensionId=nil
		end
		if type(result) ~= "table" or type(result.Execute) ~= "function" then
			warn("[APM] Module ignoré (pas de fonction Execute) : " .. source:GetFullName())
			return
		end
		if extensionId then
			local normalized,problem=pcall(normalize,result,source)
			if not normalized then
				warn("[APM] Contrat commande extension "..source.Name.." : "..tostring(problem))
				Extensions.Record("Commands",extensionId..":"..source.Name,"Error","NormalizeFailed", Extensions.Details("NormalizeFailed", "metadata", problem, "normalizable command metadata", nil, source:GetFullName())) return
			end
		else normalize(result,source) end
		if modules[result.Name] then
			warn("[APM] Deux modules s'appellent " .. result.Name .. " : le second est ignoré.")
			if extensionId then Extensions.Record("Commands",extensionId..":"..result.Name,"Error","DuplicateCommand", Extensions.Details("DuplicateCommand", "Name", result.Name, "unique command Name", nil, source:GetFullName())) end
			return
		end
		if Settings.DisabledCommands and Settings.DisabledCommands[result.Name] then
			if extensionId then Extensions.Record("Commands",extensionId..":"..result.Name,"Disabled","DisabledBySettings", { SourcePath=source:GetFullName() }) end
			return
		end
		modules[result.Name] = result
		table.insert(ordered, result)
	end
	local function scan(folder)
		local children=folder:GetChildren()
		table.sort(children,function(a,b) return a.Name<b.Name end)
		for _, child in children do
			if child:IsA("ModuleScript") then
				load(child)
			elseif child:IsA("Folder") then
				scan(child)
			end
		end
	end
	scan(Root:WaitForChild("Modules"))
	for _,entry in Extensions.CommandSources() do load(entry.Source,entry.ExtensionId) end
	table.sort(ordered, function(a, b)
		if a.Order == b.Order then
			return a.Name < b.Name
		end
		return a.Order < b.Order
	end)
	local initialized={}
	for _, module in ordered do
		local valid=true
		if type(module.Init) == "function" then
			local ok, err = pcall(module.Init, ctx)
			if not ok or (module.ExtensionId and err==false) then
				warn(("[APM] Init de %s a échoué : %s"):format(module.Name, tostring(err)))
				if module.ExtensionId then valid=false Extensions.Record("Commands",module.ExtensionId..":"..module.Name,"Error","InitFailed", Extensions.Details("InitFailed", "Init(ctx)", err, "callback completes without error", nil, module._APMSourcePath)) end
			end
		end
		if valid then
			table.insert(initialized,module)
			if module.ExtensionId then Extensions.Record("Commands",module.ExtensionId..":"..module.Name,"Loaded",nil,{SourcePath=module._APMSourcePath}) end
		else modules[module.Name]=nil end
	end
	ordered=initialized
	ctx.Modules = modules
	function ctx.Authorize(admin, moduleName, target)
		return typeof(admin)=="Instance" and admin:IsA("Player") and admin.Parent==Players
			and Ranks.IsAdmin(admin) and Ranks.CanUse(admin, moduleName)
			and (target==nil or (typeof(target)=="Instance" and target:IsA("Player") and target.Parent==Players
				and (target==admin or Ranks.CanTarget(admin,target))))
	end
	function ctx.OnAccessRevoked(player)
		for _,module in ordered do if type(module.OnAccessRevoked) == "function" then pcall(module.OnAccessRevoked,ctx,player) end end
		if ctx.Sentinel and ctx.Sentinel.CleanupPlayer then ctx.Sentinel.CleanupPlayer(player) end
		if ctx.Funny and ctx.Funny.CleanupPlayer then ctx.Funny.CleanupPlayer(player) end
	end
	local function startOptional(name)
		local source=CoreFolder:FindFirstChild(name)
		if not source then warn("[APM] Module facultatif manquant : "..name) return end
		local ok,result=pcall(require,source)
		if not ok then warn("[APM] Chargement "..name.." : "..tostring(result)) return end
		ctx[name]=result
		local initialized,problem=pcall(result.Init,ctx)
		if not initialized then warn("[APM] Init "..name.." : "..tostring(problem)) end
	end
	startOptional("Simulation")
	startOptional("AutoBridge")
	startOptional("Sentinel")
	startOptional("Funny")
	startOptional("Dispatcher") -- actions distribuées aux clients des cibles (Fly, Noclip...) ; démarré AVANT Sentinel qui s'appuie dessus
	startOptional("Assistant") -- Sentinel (assistant flottant) : s'appuie sur ctx.Perform, jamais sur un chemin parallèle
	local registering=true
	function ctx.RegisterExtensionCommand(command,extensionId,sourcePath)
		if not registering then
			Extensions.Record("Commands", extensionId or "invalid", "Error", "RegistrationClosed", Extensions.Details("RegistrationClosed", "RegisterCommand", nil, "registration inside Init(api)", {fr="Enregistre tes commandes directement dans Init(api), avant les tâches différées.",en="Register commands directly in Init(api), before deferred tasks."}, sourcePath))
			return false,"RegistrationClosed"
		end
		local valid,code,details=Extensions.ValidateCommand(command,extensionId,Ranks,sourcePath)
		if not valid then Extensions.Record("Commands",extensionId or "invalid","Error",code,details) return false,code end
		if modules[command.Name] then Extensions.Record("Commands",extensionId..":"..command.Name,"Error","DuplicateCommand", Extensions.Details("DuplicateCommand", "Name", command.Name, "unique command Name", nil, sourcePath)) return false,"DuplicateCommand" end
		if Settings.DisabledCommands and Settings.DisabledCommands[command.Name] then Extensions.Record("Commands",extensionId..":"..command.Name,"Disabled","DisabledBySettings",{SourcePath=sourcePath}) return false,"DisabledBySettings" end
		local result=table.clone(command)
		result.ExtensionId=extensionId
		result._APMSourcePath=sourcePath
		local normalized,problem=pcall(normalize,result,{Name=result.Name})
		if not normalized then Extensions.Record("Commands",extensionId..":"..result.Name,"Error","NormalizeFailed", Extensions.Details("NormalizeFailed", "metadata", problem, "normalizable command metadata", nil, sourcePath)) return false,"NormalizeFailed" end
		if result.Init then
			local ok,problem=pcall(result.Init,ctx)
			if not ok or problem==false then
				warn("[APM] Init commande extension "..result.Name.." : "..tostring(problem))
				Extensions.Record("Commands",extensionId..":"..result.Name,"Error","InitFailed", Extensions.Details("InitFailed", "Init(ctx)", problem, "callback completes without error", nil, sourcePath)) return false,"InitFailed"
			end
		end
		modules[result.Name]=result table.insert(ordered,result)
		Extensions.Record("Commands",extensionId..":"..result.Name,"Loaded",nil,{SourcePath=sourcePath})
		return true
	end
	Extensions.Init(ctx,APMService)
	registering=false
	table.sort(ordered,function(a,b) if a.Order==b.Order then return a.Name<b.Name end return a.Order<b.Order end)
	Ranks.InitModuleAccess(ordered)
	Ranks.InitModuleAccess(Settings.ClientTools or {},true)
	-- catalogue par catégorie de toutes les fonctionnalités (onglet Paramètres), une fois tous les modules chargés
	ctx.Features = Features.Init(ctx, Grades)

	-- Listes de choix (champs Type = "choice" avec Options = "nomDeListe") ------------------------------------
	local optionsCache, optionsAt = nil, -math.huge
	local function optionLists()
		if optionsCache and os.clock() - optionsAt < OPTIONS_CACHE_SECONDS then
			return optionsCache
		end
		local lists = {}
		for name, provider in optionProviders do
			local ok, list = pcall(provider)
			if ok and type(list) == "table" then
				lists[name] = list
			else
				lists[name] = {}
				if not ok then
					warn(("[APM] Liste de choix « %s » en erreur : %s"):format(name, tostring(list)))
				end
			end
		end
		optionsCache, optionsAt = lists, os.clock()
		return lists
	end
	R.GetOptions.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) then
			return {}
		end
		if not Guard.Allow(player, "GetOptions", 10, 10) then
			return nil
		end
		return optionLists()
	end
	local function validChoice(options, id)
		local list = type(options) == "string" and optionLists()[options] or options
		if type(list) ~= "table" then
			return false
		end
		for _, entry in list do
			if type(entry) == "table" and entry[1] == id then
				return true
			end
		end
		return false
	end

	-- Vérifie la valeur envoyée par le client : renvoie la valeur propre, ou nil et un message
	local function sanitize(module, value)
		if type(module.Fields) == "table" and #module.Fields > 0 then
			local source = type(value) == "table" and value or {}
			local clean = {}
			for _, field in module.Fields do
				local raw = source[field.Name]
				if field.Type == "number" then
					local n = tonumber(raw)
					if not n or n ~= n or n == math.huge or n == -math.huge then
						return nil, Msg("Srv.InvalidValue", field.Label)
					end
					n = math.clamp(n, tonumber(field.Min) or -math.huge, tonumber(field.Max) or math.huge)
					clean[field.Name] = field.Integer and math.floor(n) or n
				elseif field.Type == "choice" then
					if type(raw) ~= "string" or not validChoice(field.Options, raw) then
						return nil, Msg("Srv.InvalidChoice", field.Label)
					end
					clean[field.Name] = raw
				else
					local text = type(raw) == "string" and TextFilter.Clamp(raw, tonumber(field.MaxLength) or 100) or ""
					if not text then
						return nil, Msg("Srv.InvalidText", field.Label)
					end
					clean[field.Name] = text
				end
			end
			return clean
		end
		if type(module.Inputs) == "table" then -- paramètres de l'onglet Joueurs (Motif, Durée)
			local source = type(value) == "table" and value or {}
			local clean = {}
			for _, input in module.Inputs do
				if input == "Reason" then
					local text = type(source.Reason) == "string" and TextFilter.Clamp(source.Reason, 200) or ""
					if not text then
						return nil, Msg("Srv.InvalidText", "Players.ReasonHint")
					end
					clean.Reason = text
				elseif input == "Minutes" then
					local n = tonumber(source.Minutes) or 0
					if n ~= n or n < 0 or n == math.huge then
						n = 0
					end
					clean.Minutes = math.min(n, 60 * 24 * 365)
				end
			end
			return clean
		end
		if module.Mode == "toggle" then
			if type(value) == "boolean" then return value end
			return nil, Msg("Srv.InvalidValue",module.Label)
		end
		if module.Mode == "slider" then
			local n = tonumber(value)
			if not n or n ~= n or math.abs(n) == math.huge then
				return nil, Msg("Srv.InvalidValue", module.Label)
			end
			return math.clamp(n, tonumber(module.Min) or 0, tonumber(module.Max) or 100)
		end
		local kind = type(value)
		if kind == "number" then
			return (value == value and math.abs(value) ~= math.huge) and value or nil
		elseif kind == "string" then
			return TextFilter.Clamp(value, 200)
		elseif kind == "boolean" then
			return value
		end
		return nil
	end

	-- API vers le client ---------------------------------------------------------------------------------------
	R.CheckAdmin.OnServerInvoke = function(player)
		Ranks.WaitResolved(player, 8)
		local rank = Ranks.GetRank(player)
		if not rank or not Ranks.IsAdmin(player) then
			return { admin = false }
		end
		return {
			admin = true,
			rank = rank,
			ranks = Ranks.Public(),
			super = Ranks.Super,
			manager = Ranks.Manager,
			announcer = Ranks.Announcer,
			memory = Ranks.Memory,
			permissions = Ranks.GetPermissions(player, false),
			realRank = Ranks.GetRealRank(player),
			actualOwner = Ranks.IsExperienceOwner(player),
			simulation = Ranks.GetSimulation(player),
		}
	end

	R.GetModules.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) then
			return {}
		end
		local list = {}
		for _, module in ordered do
			local info = publicInfo(module)
			-- état actuel d'un outil personnel (interrupteur / curseur) : le panneau reconstruit affiche la vraie valeur
			if (module.Mode == "toggle" or module.Mode == "slider") and type(module.GetState) == "function" then
				local ok, state = pcall(module.GetState, ctx, player)
				if ok and (type(state) == "boolean" or (type(state) == "number" and state == state and math.abs(state) < math.huge)) then
					info.State = state
				end
			end
			table.insert(list, info)
		end
		return list
	end

	-- Exécution d'une action --------------------------------------------------------------------------------
	-- perform : cœur commun du panneau et de l'assistant Sentinel (grade, matrice d'accès, hiérarchie, valeurs, exécution, journal).
	-- Les réponses passent par emit(message, succès) : le panneau les envoie en notification, l'assistant les collecte.
	-- Renvoie (réussi, état, message) ; état : Done | Failed | Error | NotAdmin | Unknown | NoAccess | InvalidTarget | NotOnSelf | Protected | InvalidValue | AccessChanged.
	-- extra.AllowTarget : l'assistant vise un autre joueur avec un module à curseur qui sait agir sur lui (module.ExecuteTarget).
	local function perform(admin, moduleName, target, value, emit, extra)
		emit = type(emit) == "function" and emit or function() end
		if type(moduleName) ~= "string" or moduleName == "" or #moduleName > 64 then
			return false, "Unknown"
		end
		if typeof(admin) ~= "Instance" or not admin:IsA("Player") then
			return false, "NotAdmin"
		end
		if not Ranks.IsAdmin(admin) then
			Journal.LogRefusal(admin, moduleName, Msg("Log.NotAdmin"))
			return false, "NotAdmin"
		end
		local module = modules[moduleName]
		-- action distribuée (Fly, Noclip...) : même contrat (réussi, état, message), exécutée par le Dispatcher sous la même autorité serveur
		if not module and ctx.Dispatcher and ctx.Dispatcher.Handles(moduleName) then
			return ctx.Dispatcher.Perform(admin, moduleName, target, value, emit, extra)
		end
		if not module then
			local message = Msg("Srv.UnknownModule")
			emit(message, false)
			return false, "Unknown", message
		end
		if not Ranks.CanUse(admin, module.Name) then
			local message = Msg("Srv.NoModuleAccess")
			emit(message, false)
			Journal.Log(admin.Name, module.Name, nil, Msg("Log.NoAccess"), "Access", "warning")
			return false, "NoAccess", message
		end

		local remoteTarget = module.Mode ~= "target" and type(extra) == "table" and extra.AllowTarget == true and type(module.ExecuteTarget) == "function"
			and typeof(target) == "Instance" and target:IsA("Player") and target ~= admin
		local targetName
		if module.Mode == "target" or remoteTarget then
			if typeof(target) ~= "Instance" or not target:IsA("Player") or target.Parent ~= Players then
				local message = Msg("Srv.SelectValidPlayer")
				emit(message, false)
				return false, "InvalidTarget", message
			end
			targetName = target.Name
			local isSelf = target == admin
			local selfAllowed = module.AllowSelf == true or (module.AllowSelf == nil and module.Category ~= "Players")
			if isSelf and not selfAllowed then -- sanctions, déplacements entre joueurs... : jamais sur soi-même
				local message = Msg("Srv.NotOnSelf")
				emit(message, false)
				return false, "NotOnSelf", message
			end
			if not isSelf and not Ranks.CanTarget(admin, target) then
				local rank = Ranks.GetRank(target)
				local rankKey = rank and ("Rank." .. rank) or "?"
				local message = rank == Ranks.Super and Msg("Srv.ProtectedTop", target.Name, rankKey) or Msg("Srv.ProtectedRank", target.Name)
				emit(message, false)
				Journal.Log(admin.Name, module.Name, target.Name, Msg("Log.Protected", rankKey), "System", "warning")
				return false, "Protected", message
			end
		else
			target = nil
		end

		local clean, problem = sanitize(module, value)
		if problem then
			emit(problem, false)
			return false, "InvalidValue", problem
		end

		if not ctx.Authorize(admin, module.Name, target) then
			local message = Msg("Srv.AccessChanged")
			emit(message, false)
			return false, "AccessChanged", message
		end
		local ok, success, message = pcall(remoteTarget and module.ExecuteTarget or module.Execute, ctx, admin, target, clean)
		if not ok then
			warn(("[APM] Erreur dans %s : %s"):format(module.Name, tostring(success)))
			local failure = Msg("Srv.InternalError", module.Label)
			emit(failure, false)
			Journal.Log(admin.Name, module.Name, targetName, Msg("Log.Error", tostring(success)), "System", "danger")
			return false, "Error", failure
		end
		if message ~= nil then
			emit(message, success ~= false)
		end
		Statistics.RecordAction(module.Name, module.Category, admin.Name, success ~= false)
		Journal.Log(admin.Name, module.Name, targetName, message or "OK", module.Category, success == false and "warning" or module.Severity)
		return success ~= false, success == false and "Failed" or "Done", message
	end
	local function runAction(admin, moduleName, target, value)
		if not Guard.Allow(admin, "Action", 14, 3) then
			return
		end
		perform(admin, moduleName, target, value, function(message, success)
			ctx.Notify(admin, message, success)
		end)
	end
	ctx.Perform = perform
	ctx.OptionLists = optionLists
	R.Action.OnServerEvent:Connect(runAction)
	ctx.RunAction = runAction
	R.GetRoster.OnServerInvoke = function(player, offset)
		if not Ranks.IsAdmin(player) or not Guard.Allow(player,"GetRoster",4,10) then return nil, nil, 0 end
		offset = offset or 0
		if type(offset) ~= "number" or offset ~= offset or offset < 0 or offset > 20000 or offset % 1 ~= 0 then return nil, nil, 0 end
		local list = Roster.List()
		if player.Parent ~= Players or not Ranks.IsAdmin(player) then return nil, nil, 0 end
		local total, result = #list, {}
		for index = offset + 1, math.min(offset + 200, total) do table.insert(result, list[index]) end
		return result, offset + 200 < total and offset + 200 or nil, total
	end
	R.GetDiagnostics.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) or (not Ranks.IsExperienceOwner(player) and not Ranks.HasPermission(player,"APM.Simulate")) then return nil end
		local data=Sessions.Diagnostics(player)
		data.extensions=Extensions.Snapshot()
		return data
	end
	R.GetHomeSnapshot.OnServerInvoke = function(player,options)
		if not Ranks.IsAdmin(player) or not Ranks.HasPermission(player,"APM.AccessPanel") or not Guard.Allow(player,"GetHomeSnapshot",6,10) then return nil end
		local snapshot = homeTelemetry.Snapshot(player,options)
		if not snapshot then return nil end
		if Ranks.HasPermission(player,"AutoBridge.View") then
			local ok,data = pcall(function() return ctx.AutoBridge and ctx.AutoBridge.GetState(player) end)
			if ok and type(data)=="table" and data.Allowed==true then
				data.ScanAge = data.ScannedAt and data.ScannedAt>0 and math.max(0,math.floor(os.clock()-data.ScannedAt)) or nil
				snapshot.AutoBridge=data
			else snapshot.AutoBridge={Allowed=true,Unavailable=true} end
		end
		if Ranks.HasPermission(player,"Sentinel.View") then
			local ok,data = pcall(function() return ctx.Sentinel and ctx.Sentinel.Snapshot(player) end)
			if ok and type(data)=="table" and data.Allowed==true then
				local recent={} for index,alert in data.Alerts or {} do if index>3 then break end table.insert(recent,alert) end
				snapshot.Sentinel={Allowed=true,Disabled=data.Disabled,Enabled=data.Config.Enabled,Mode=data.Config.Mode,
					TotalAlerts=data.TotalAlerts,HistoryCount=#(data.Alerts or {}),RecentAlerts=recent,TrackedPlayers=data.TrackedPlayers}
			else snapshot.Sentinel={Allowed=true,Unavailable=true} end
		end
		if Ranks.IsExperienceOwner(player) or Ranks.HasPermission(player,"APM.Simulate") then
			local data=Sessions.Diagnostics(player)
			snapshot.Diagnostics={sessionActive=data.sessionActive,authorized=data.authorized,globalAdminRemotes=data.globalAdminRemotes,
				simulation={active=data.simulation and data.simulation.active==true},extensions=Extensions.Snapshot(),core=data.core,configuration=data.configuration}
		end
		-- AutoBridge discovery/adapters may yield: refilter every section before sending.
		if player.Parent~=Players or not Ranks.IsAdmin(player) or not Ranks.HasPermission(player,"APM.AccessPanel") then return nil end
		if not Ranks.HasPermission(player,"AutoBridge.View") then snapshot.AutoBridge=nil end
		if not Ranks.HasPermission(player,"Sentinel.View") then snapshot.Sentinel=nil end
		if not Ranks.IsExperienceOwner(player) and not Ranks.HasPermission(player,"APM.Simulate") then snapshot.Diagnostics=nil snapshot.Performance=nil end
		return snapshot
	end
	R.GetStats.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) or not Ranks.HasPermission(player,"APM.AccessPanel") or not Guard.Allow(player,"GetStats",6,10) then return nil end
		local infra = Ranks.IsExperienceOwner(player) or Ranks.HasPermission(player,"APM.Simulate")
		return Statistics.Snapshot({Players=true,Usage=Ranks.HasPermission(player,"APM.ViewLogs"),Performance=infra,DataStores=infra})
	end
	ctx.ClientToolStates = {}
	R.SetClientTool.OnServerEvent:Connect(function(player,name,state)
		if type(name)~="string" or type(state)~="boolean" then return end
		local known=table.find(Settings.ClientTools or {},name)
		if not known or not Ranks.IsAdmin(player) or not Ranks.CanUse(player,name) then return end
		ctx.ClientToolStates[player]=ctx.ClientToolStates[player] or {}
		ctx.ClientToolStates[player][name]=state or nil
		if ctx.Dispatcher then ctx.Dispatcher.NoteClientState(player,name,state) end -- le serveur suit aussi les effets lancés depuis le panneau de l'admin
	end)
	Players.PlayerRemoving:Connect(function(player) ctx.ClientToolStates[player]=nil end)

	-- Changement de droits (ici ou sur un autre serveur) : chaque client revérifie son grade et sa matrice
	Ranks.OnChanged = function()
		if ctx.Funny and ctx.Funny.Reconcile then ctx.Funny.Reconcile() end
		for _,player in Players:GetPlayers() do
			for _,module in ordered do
				if not Ranks.CanUse(player,module.Name) and type(module.OnAccessRevoked)=="function" then
					local ok, result, reply = pcall(module.OnAccessRevoked,ctx,player)
					if not ok or result == false then
						local sourcePath = module._APMSourcePath or ("APM_Core.Server.Modules." .. module.Name)
						local problem = not ok and result or reply or result
						warn("[APM] OnAccessRevoked " .. sourcePath .. " : " .. tostring(problem))
						Extensions.Record("Commands", (module.ExtensionId or "Core") .. ":" .. module.Name, "Error", "CleanupFailed",
							Extensions.Details("CleanupFailed", "OnAccessRevoked(ctx, player)", problem, "callback completes without error",
								{fr="Le premier argument est ctx ; le joueur est le deuxième. Restaure les effets et libère les connexions.",en="The first argument is ctx; the player is second. Restore effects and disconnect listeners."}, sourcePath))
						ctx.Log(player.Name, "OnAccessRevoked." .. module.Name, player.Name, sourcePath .. " : " .. string.sub(tostring(problem),1,240), "Extensions", "warning")
					end
				end
			end
			for name in ctx.ClientToolStates[player] or {} do if not Ranks.CanUse(player,name) then ctx.ClientToolStates[player][name]=nil end end
			Sessions.Reconcile(player)
		end
	end
	Ranks.StartSync()

	APMService.Context = ctx
	Sessions.Init(ctx)
	APMService.Ready = true
	readyEvent:Fire(ctx)
	print(("[APM] Serveur prêt : %d module(s)%s"):format(#ordered, Ranks.Memory and " (mode mémoire : rien n'est enregistré)" or ""))
	return ctx
end

return APMService
