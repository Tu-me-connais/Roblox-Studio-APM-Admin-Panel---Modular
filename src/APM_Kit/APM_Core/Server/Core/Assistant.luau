--[[
	Assistant : moteur serveur de Sentinel (assistant de commandes flottant) et de Sentinel Helper (sa configuration).
	Ne pas confondre avec Sentinel Guard (Core.Sentinel : détection de triche, permissions « Sentinel.* ») : ici « Assistant.* ».

	Chemin d'une commande : texte -> reconnaissance multilingue (Parser + CommandLocalization : sept langues, une seule ACTION CANONIQUE) -> droits du joueur
	-> plan (cible resolue, valeurs, cle canonique de confirmation) -> confirmation eventuelle -> APMService.perform / Dispatcher.
	La langue de saisie ne va jamais plus loin que la reconnaissance : elle est independante de la langue de l'interface (qui ne sert qu'a afficher la reponse).
	Cible absente = l'administrateur (jamais « all ») ; tout « all » est confirme ; la confirmation porte sur l'action canonique et les joueurs reellement resolus.
	perform est le MÊME cœur que les boutons du panneau : grade, matrice d'accès, hiérarchie, bornes des valeurs, journal. Sentinel n'a donc
	aucun chemin privilégié : le client n'envoie que du texte, le serveur résout, vérifie et exécute. Aucune évaluation de code, jamais.
	Une réussite n'est annoncée qu'après le retour de perform (ou, pour un outil client comme Fly, après l'application sur le client).

	Sous-modules : Parser (texte, cibles) · Unicode (pliage des textes) · CommandLocalization (dictionnaires des sept langues) · Catalog (registre -> commandes) · Config (réglages validés) · Actions (registre fermé des commandes
	personnalisées) · External (IA externe facultative, désactivée par défaut).
	Pour les tests : Assistant.Create(ctx, services) accepte de faux joueurs (services.GetPlayers / IsPlayer).
]]
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local Unicode = require(script.Unicode)
local Parser = require(script.Parser)
local Catalog = require(script.Catalog)
local Config = require(script.Config)
local Actions = require(script.Actions)
local External = require(script.External)

local Assistant = {}
Assistant.Parser, Assistant.Catalog, Assistant.Config, Assistant.Actions, Assistant.Unicode = Parser, Catalog, Config, Actions, Unicode

local CONFIRM_SECONDS = 20
local SECTION = "SentinelAssistant"

function Assistant.Create(ctx, services)
	services = services or {}
	local Ranks, Guard = ctx.Ranks, ctx.Guard
	local function Msg(key, ...)
		return ctx.Msg(key, ...)
	end
	local clock = services.Clock or os.clock
	local function isPlayer(value)
		if services.IsPlayer then return services.IsPlayer(value) end
		return typeof(value) == "Instance" and value:IsA("Player") and value.Parent == Players
	end
	local function getPlayers()
		return services.GetPlayers and services.GetPlayers() or Players:GetPlayers()
	end

	local api = {}
	local config, info, baseline, loaded = nil, nil, nil, false
	local catalog = nil
	local pending = {} -- [userId] = { Token, Key, Expires } : confirmations en attente
	local busy = {} -- [userId] = true : une commande à la fois par admin
	local external = External.Create(ctx, services.External)
	local features = { IsFeature = function(name) return Ranks.IsFeature(name) end }

	----------------------------------------------------------------------------------------------------------
	-- Configuration (chargement paresseux : la matrice des permissions n'est complète qu'une fois l'APM prêt)

	local function ensureConfig()
		if loaded then return config end
		loaded = true
		local stored = ctx.SuiteConfig and ctx.SuiteConfig.Snapshot(SECTION) or {}
		config, info, baseline = Config.Load(ctx.Settings, stored, { Features = features })
		return config
	end
	local function getCatalog()
		ensureConfig()
		if not catalog then catalog = Catalog.Build(ctx, config) end
		return catalog
	end
	local function moduleEnabled()
		local modules = type(ctx.Settings) == "table" and ctx.Settings.Modules
		return not (type(modules) == "table" and modules.Assistant == false)
	end
	local function featureOn()
		return moduleEnabled() and ensureConfig().Enabled == true
	end
	local function allowedToUse(player)
		return isPlayer(player) and featureOn() and Ranks.IsAdmin(player) and Ranks.HasPermission(player, "Assistant.Use")
	end

	----------------------------------------------------------------------------------------------------------
	-- Résultats : tables simples, textes traduisibles chez celui qui les lit

	local function result(ok, code, text, extra)
		local value = { Ok = ok, Code = code, Text = text }
		if extra then for key, item in extra do value[key] = item end end
		return value
	end
	local function candidates()
		local list = {}
		for _, player in getPlayers() do
			if isPlayer(player) then table.insert(list, { UserId = player.UserId, Name = player.Name, DisplayName = player.DisplayName, Ref = player }) end
		end
		table.sort(list, function(a, b) return a.Name < b.Name end)
		return list
	end
	local function usageResult(spec)
		return result(false, "Invalid", Msg("Assistant.Usage", spec.Usage))
	end
	local function log(player, action, target, detail, level)
		if ctx.Log then ctx.Log(player.Name, action, target, detail, "Assistant", level or "info") end
	end

	----------------------------------------------------------------------------------------------------------
	-- Confirmation : un jeton à usage unique, lié à l'admin ET a la commande CANONIQUE (action, sens, cibles reellement resolues, valeurs) et non au texte tape, valable 20 secondes

	-- shown : texte à renvoyer avec le jeton quand ce n'est pas celui que l'admin a tapé (proposition de l'IA externe)
	local function askConfirmation(player, key, summary, shown, text)
		local token = string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 12)
		pending[player.UserId] = { Token = token, Key = key, Text = text, Expires = clock() + CONFIRM_SECONDS }
		return result(false, "Confirm", summary, { Confirm = { Token = token, Command = shown, Seconds = CONFIRM_SECONDS } })
	end
	-- Un jeton présenté est consommé quoi qu'il arrive (usage unique) ; renvoie l'enregistrement s'il était valable (bon jeton, pas expiré)
	local function takePending(player, token)
		local record = pending[player.UserId]
		if type(token) ~= "string" or not record then return nil end
		pending[player.UserId] = nil
		if record.Token == token and clock() <= record.Expires then return record end
		return nil
	end
	-- La confirmation présentée couvre-t-elle CETTE commande ? Oui si sa clé canonique est identique, ou si c'est la proposition de l'IA confirmée telle quelle.
	local function confirmedFor(cx, key)
		if cx.Confirmed then return true end
		local record = cx.Presented
		return record ~= nil and (record.Key == key or (record.Text ~= nil and record.Text == cx.TextKey))
	end

	----------------------------------------------------------------------------------------------------------
	-- Arguments

	-- Id d'une liste de choix : exact, sinon insensible à la casse, sinon dernier segment unique ; sinon tel quel (le serveur refusera)
	local function matchChoice(arg, token)
		local list = type(arg.Options) == "string" and ctx.OptionLists and ctx.OptionLists()[arg.Options] or arg.Options
		if type(list) ~= "table" then return token end
		local wanted, found = Parser.Normalize(token), nil
		for _, entry in list do
			local id = type(entry) == "table" and entry[1]
			if id == token then return token end
			if type(id) == "string" then
				local normalized = Parser.Normalize(id)
				if normalized == wanted or string.match(normalized, "[^%.]+$") == wanted then
					if found and found ~= id then return token end
					found = id
				end
			end
		end
		if found then return found end
		-- « donner », « dar », « geben », « дать », « 给 » : mot de choix de la langue, ramené à l'identifiant du module (give / take / set / once / keep)
		local canonical = Parser.Choice(wanted)
		if canonical then
			for _, entry in list do
				if type(entry) == "table" and entry[1] == canonical then return canonical end
			end
		end
		return token
	end

	-- Arguments positionnels (Fields) -> table { [champ] = valeur } ; nil + code si invalide
	local function positional(args, tokens)
		local value = {}
		for index, arg in args do
			local token = tokens[index]
			if arg.Type == "text" and index == #args and index <= #tokens then
				token = table.concat(tokens, " ", index)
			end
			if token == nil then
				if arg.Default ~= nil then
					value[arg.Field] = arg.Default
				elseif not arg.Optional then
					return nil, "Missing"
				end
			elseif arg.Type == "number" then
				local number = Parser.Number(token)
				if not number then return nil, "Invalid" end
				if arg.Min and number < arg.Min or arg.Max and number > arg.Max then return nil, "Invalid" end
				value[arg.Field] = arg.Integer and math.floor(number) or number
			elseif arg.Type == "choice" then
				value[arg.Field] = matchChoice(arg, token)
			else
				value[arg.Field] = token
			end
		end
		if #tokens > #args and not (args[#args] and args[#args].Type == "text") then return nil, "Invalid" end
		return value
	end

	-- Motif et durée libres (Inputs) : la première durée reconnue (5, 5m, 2h...) est la durée, le reste est le motif
	local function inputs(args, tokens)
		local value, rest = {}, table.clone(tokens)
		for _, arg in args do
			if arg.Type == "duration" then
				for index, token in rest do
					local minutes = Parser.Duration(token)
					if minutes then
						-- une durée que la commande ne sait pas honorer (Ban : minute entière) est refusée, jamais arrondie vers le bas (0 = définitif)
						if arg.MinMinutes and minutes > 0 and minutes < arg.MinMinutes then return nil, "TooShort", arg.MinMinutes end
						-- 10 s = 0,167 minute : trois décimales suffisent (les modules affichent la valeur telle quelle)
						value[arg.Field] = math.floor(minutes * 1000 + 0.5) / 1000
						table.remove(rest, index)
						break
					elseif index == 1 and Parser.LooksLikeDuration(token) then
						return nil, "BadDuration" -- « 1w » : format inconnu, pas avalable dans le motif
					end
				end
			end
		end
		for _, arg in args do
			if arg.Field == "Reason" then
				value.Reason = table.concat(rest, " ")
				rest = {}
			end
		end
		if #rest > 0 then return nil, "Invalid" end
		return value
	end

	local function targetArguments(spec, tokens)
		if #spec.Args == 0 then
			if #tokens > 0 then return nil, "Invalid" end
			return nil
		end
		if spec.Args[1].Type == "duration" or spec.Args[1].Field == "Reason" then return inputs(spec.Args, tokens) end
		return positional(spec.Args, tokens)
	end

	----------------------------------------------------------------------------------------------------------
	-- Exécution d'une commande de module (cible unique ou tous)

	-- Joue perform sur une liste de joueurs et résume. `each(target)` peut refuser un joueur (renvoie nil, "Skip").
	local function performOn(player, spec, targets, value, options)
		local done, failed, skipped, firstFailure, detail, protected = 0, 0, 0, nil, nil, 0
		local module = ctx.Modules and ctx.Modules[spec.Module]
		for _, target in targets do
			if not isPlayer(player) then break end
			local skip = false
			-- « all » saute l'admin quand la commande ne s'applique pas à soi-même ; une cible unique laisse perform répondre
			if options.Mode == "Target" and #targets > 1 and target == player and not spec.SelfAllowed then
				skip = true
			end
			if not skip and spec.HasTargetState and module then
				local ok, active = pcall(module.GetTargetState, ctx, target)
				if ok then
					if options.Negate and not active then
						firstFailure = firstFailure or Msg("Assistant.NotActive", target.Name)
						skip = true
						failed += (#targets == 1) and 1 or 0
					elseif not options.Negate and active then
						firstFailure = firstFailure or Msg("Assistant.AlreadyOn", target.Name)
						skip = true
						failed += (#targets == 1) and 1 or 0
					end
				end
			end
			if skip then
				skipped += 1
			else
				local ok, code, message = ctx.Perform(player, spec.Module, options.Mode == "Target" and target or (target ~= player and target or nil), value, nil, { AllowTarget = options.AllowTarget })
				if ok then
					done += 1
					detail = detail or message
				else
					-- un joueur protégé (grade égal ou supérieur) est compté à part : « all » ne contourne jamais une protection
					if code == "Protected" then protected += 1 else failed += 1 end
					firstFailure = firstFailure or message
					options.LastCode = code
				end
			end
		end
		return done, failed, skipped, firstFailure, detail, protected
	end

	-- Bilan chiffré (plusieurs cibles) : « Freeze : 8 affecté(s), 2 protégé(s), 0 échec(s), 1 ignoré(s) » ; une cible : phrase simple
	local function summarize(spec, total, done, failed, skipped, firstFailure, detail, code, protected)
		protected = protected or 0
		local detailed = config.ReplyStyle == "Detailed"
		if done == 0 then
			if total > 1 and (firstFailure or protected > 0) then
				return result(false, (protected > 0 and failed == 0) and "Protected" or "Failed", Msg("Assistant.Tally", spec.Module, 0, protected, failed, skipped),
					{ Details = firstFailure and { firstFailure } or nil })
			end
			if firstFailure then return result(false, code == "Protected" and "Protected" or "Failed", firstFailure) end
			return result(false, "Unavailable", Msg("Assistant.Unavailable"))
		end
		if total <= 1 and failed == 0 and protected == 0 then
			return result(true, "Done", detailed and detail or Msg("Assistant.Done"))
		end
		local complete = failed + skipped + protected == 0
		return result(true, complete and "Done" or "Partial", Msg("Assistant.Tally", spec.Module, done, protected, failed, skipped),
			{ Details = (not complete and firstFailure) and { firstFailure } or nil })
	end

	----------------------------------------------------------------------------------------------------------
	-- Analyse et exécution

	local run
	local planFor

	local function resolveOne(query)
		return Parser.ResolveTarget(query, candidates())
	end

	local function targetProblem(resolved)
		if resolved.Kind == "Ambiguous" then
			return result(false, "Ambiguous", Msg("Assistant.Ambiguous", table.concat(resolved.Matches, ", ")), { Matches = resolved.Matches })
		end
		return result(false, "NotFound", Msg("Assistant.NotFound"))
	end

	-- Un mot réservé (on / off, oui / non, ja / nein, да / нет...) qui est aussi le pseudo d'un joueur présent n'est JAMAIS deviné : on demande de préciser (@identifiant)
	local function reservedClash(token)
		local clashes = Parser.Clashes(Parser.Normalize(token), candidates())
		if #clashes == 0 then return nil end
		table.sort(clashes, function(a, b) return a.Name < b.Name end)
		local matches = {}
		for index = 1, math.min(#clashes, 4) do matches[index] = string.format("%s (@%d)", clashes[index].Name, clashes[index].UserId) end
		return targetProblem({ Kind = "Ambiguous", Matches = matches })
	end

	local function allTargets()
		ensureConfig()
		local list = {}
		for _, candidate in candidates() do
			if #list >= config.MaxAllTargets then break end
			table.insert(list, candidate.Ref)
		end
		return list
	end

	--[[
		Sélection canonique d'une cible : LA règle de tout Sentinel, identique dans les sept langues puisqu'elle ne voit que le résultat de la reconnaissance.
		  cible absente             -> l'administrateur lui-même si la commande le permet (OptionalSelf, SelfOnly), sinon erreur d'usage. JAMAIS « all ».
		  me / moi / yo / ich / я / 我  ou son propre pseudo -> l'administrateur
		  all / tous / todos / alle / все / 所有人 -> tous les joueurs (au plus MaxAllTargets), seulement si la commande et les réglages l'autorisent
		  autre mot                 -> un joueur ; ambigu ou inconnu = refus, jamais de tirage au sort
		validate (facultatif) : appelée une fois le joueur désigné trouvé, avant les contrôles d'autorisation ; renvoie un résultat d'erreur ou nil.
		Renvoie { Kind = "Self" | "Single" | "All", Players = { joueurs }, Implicit = bool }, ou nil + résultat d'erreur.
	]]
	local function selectTargets(player, spec, token, validate)
		local policy = spec.TargetPolicy
		if token == nil then
			if policy == "OptionalSelf" or policy == "SelfOnly" then return { Kind = "Self", Players = { player }, Implicit = true } end
			return nil, usageResult(spec)
		end
		local resolved = resolveOne(token)
		if resolved.Kind == "None" or resolved.Kind == "Ambiguous" then return nil, targetProblem(resolved) end
		if validate then
			local problem = validate()
			if problem then return nil, problem end
		end
		if resolved.Kind == "Me" or (resolved.Kind == "Single" and resolved.Player.Ref == player) then
			return { Kind = "Self", Players = { player }, Implicit = false }
		end
		if policy == "SelfOnly" then return nil, result(false, "Unavailable", Msg("Assistant.OnlyYou", spec.Name)) end
		if resolved.Kind == "All" then
			ensureConfig()
			if not (config.AllowAll and (spec.Kind ~= "Target" or spec.AllowAll)) then return nil, result(false, "Unavailable", Msg("Assistant.Unavailable")) end
			return { Kind = "All", Players = allTargets(), Implicit = false }
		end
		return { Kind = "Single", Players = { resolved.Player.Ref }, Implicit = false }
	end

	-- Clé canonique d'une commande : action, sens, sorte de cible, joueurs réellement visés, valeurs. Indépendante de la langue et de la formulation.
	local function valueKey(value)
		if type(value) == "table" then
			local keys = {}
			for key in value do table.insert(keys, tostring(key)) end
			table.sort(keys)
			local parts = {}
			for _, key in keys do table.insert(parts, key .. "=" .. tostring(value[key])) end
			return table.concat(parts, ";")
		end
		return value == nil and "" or tostring(value)
	end
	local function planKey(spec, off, selection, value)
		local ids = {}
		if selection then
			for _, target in selection.Players do table.insert(ids, tostring(target.UserId)) end
			table.sort(ids)
		end
		return table.concat({ spec.Module, off and "off" or "on", selection and selection.Kind or "-", table.concat(ids, ","), valueKey(value) }, "|")
	end
	-- Ce que l'admin confirme : l'action canonique, le sens, la cible résolue (avec le nombre de joueurs pour « all »), puis son propre texte
	local function describePlan(plan, clean)
		local selection = plan.Selection
		local target = ""
		if selection then
			if selection.Kind == "All" then
				target = string.format(" > all [%d]", #selection.Players)
			elseif selection.Kind == "Self" then
				target = " > me"
			else
				target = " > " .. tostring(selection.Players[1].Name)
			end
		end
		return string.format("%s%s%s : %s", plan.Spec.Module, plan.Off and " (off)" or "", target, clean)
	end

	----------------------------------------------------------------------------------------------------------
	-- Plans : un plan ne change RIEN (on peut le calculer à blanc) et porte Execute(), l'exécution une fois les contrôles et la confirmation passés.
	-- plan = { Entry, Spec, Off, Selection, Value, Key, NeedsConfirm, Execute } ; en cas de refus : nil + résultat d'erreur.

	-- Commande à cible (Kick, Freeze, Bring...) : la cible est OBLIGATOIRE
	local function planTarget(player, entry, tokens)
		local spec = entry.Spec
		local rest = table.move(tokens, 2, #tokens, 1, {})
		local value
		local selection, problem = selectTargets(player, spec, tokens[1], function()
			local parsed, bad, detail = targetArguments(spec, rest)
			if bad == "TooShort" then return result(false, "Invalid", Msg("Assistant.DurationTooShort", detail)) end
			if bad == "BadDuration" then return result(false, "Invalid", Msg("Assistant.DurationInvalid")) end
			if bad then return usageResult(spec) end
			value = parsed
			return nil
		end)
		if not selection then return nil, problem end
		local plan = { Entry = entry, Spec = spec, Off = entry.Negate, Selection = selection, Value = value }
		plan.Key = planKey(spec, plan.Off, selection, value)
		plan.NeedsConfirm = selection.Kind == "All" or (spec.Confirm == true and config.ConfirmDangerous == true)
		plan.Execute = function()
			local options = { Mode = "Target", Negate = entry.Negate }
			local done, failed, skipped, firstFailure, detail, protected = performOn(player, spec, selection.Players, value, options)
			return summarize(spec, #selection.Players, done, failed, skipped, firstFailure, detail, options.LastCode, protected)
		end
		return plan
	end

	-- Outil personnel à interrupteur (Invisible, Godmode) : agit sur l'administrateur seulement
	local function planToggle(player, entry, tokens)
		local spec = entry.Spec
		local state
		if entry.Negate then state = false end
		for _, token in tokens do
			local isMe = Parser.IsMe(Parser.Normalize(token))
			local boolean = Parser.Boolean(token)
			if isMe then
				local clash = reservedClash(token)
				if clash then return nil, clash end
			elseif boolean ~= nil and state == nil then
				local clash = reservedClash(token)
				if clash then return nil, clash end
				state = boolean
			else
				local other = resolveOne(token)
				if other.Kind == "Single" or other.Kind == "All" then return nil, result(false, "Unavailable", Msg("Assistant.OnlyYou", spec.Name)) end
				return nil, usageResult(spec)
			end
		end
		local plan = { Entry = entry, Spec = spec, Off = state == false, Selection = { Kind = "Self", Players = { player }, Implicit = #tokens == 0 }, NeedsConfirm = false }
		plan.Key = planKey(spec, plan.Off, plan.Selection, state)
		plan.Execute = function()
			local value = state
			if value == nil then
				local module = ctx.Modules and ctx.Modules[spec.Module]
				local ok, current = false, nil
				if module and type(module.GetState) == "function" then ok, current = pcall(module.GetState, ctx, player) end
				value = not (ok and current == true)
			end
			local success, code, message = ctx.Perform(player, spec.Module, nil, value, nil)
			if not success then return result(false, code == "NoAccess" and "Denied" or "Failed", message or Msg("Assistant.Unavailable")) end
			return result(true, "Done", config.ReplyStyle == "Detailed" and message or Msg("Assistant.Done"))
		end
		return plan
	end

	-- Curseur (Speed, JumpPower) : « speed 50 », « speed pseudo 50 », « speed all 50 », « speed reset » (et leurs équivalents dans les autres langues)
	local function planSlider(player, entry, tokens)
		local spec = entry.Spec
		if #tokens == 0 or #tokens > 2 then return nil, usageResult(spec) end
		local valueToken = tokens[#tokens]
		local value
		if Parser.IsReset(valueToken) then
			value = spec.Default
		else
			value = Parser.Number(valueToken)
		end
		if value == nil or (spec.Min and value < spec.Min) or (spec.Max and value > spec.Max) then return nil, usageResult(spec) end
		local selection, problem = selectTargets(player, spec, #tokens == 2 and tokens[1] or nil)
		if not selection then return nil, problem end
		local plan = { Entry = entry, Spec = spec, Off = false, Selection = selection, Value = value }
		plan.Key = planKey(spec, false, selection, value)
		plan.NeedsConfirm = selection.Kind == "All"
		plan.Execute = function()
			local options = { Mode = "Slider", AllowTarget = true }
			local done, failed, skipped, firstFailure, detail, protected = performOn(player, spec, selection.Players, value, options)
			return summarize(spec, #selection.Players, done, failed, skipped, firstFailure, detail, options.LastCode, protected)
		end
		return plan
	end

	-- Action globale (TimeOfDay, Shutdown, Unban...)
	local function planGlobal(player, entry, tokens)
		local spec = entry.Spec
		local value
		if #spec.Args > 0 then
			local problem
			value, problem = positional(spec.Args, tokens)
			if problem then return nil, usageResult(spec) end
		elseif #tokens == 1 then
			value = Parser.Number(tokens[1]) or tokens[1]
		elseif #tokens > 1 then
			return nil, usageResult(spec)
		end
		local plan = { Entry = entry, Spec = spec, Off = false, Value = value }
		plan.Key = planKey(spec, false, nil, value)
		plan.NeedsConfirm = spec.Confirm == true and config.ConfirmDangerous == true
		plan.Execute = function()
			local success, code, message = ctx.Perform(player, spec.Module, nil, value, nil)
			if not success then return result(false, code == "NoAccess" and "Denied" or "Failed", message or Msg("Assistant.Unavailable")) end
			return result(true, "Done", config.ReplyStyle == "Detailed" and message or Msg("Assistant.Done"))
		end
		return plan
	end

	--[[
		Outils client. Quatre cas, trois classes (voir ActionCatalog) :
		  Fly, Noclip   action DISTRIBUÉE : le serveur autorise, instruit le client de chaque cible (Dispatcher, hiérarchie respectée, « all » compris)
		                et n'annonce la réussite qu'après la réponse du client. Ni Sentinel ni le client ne s'accordent rien eux-mêmes.
		                « fly » seul = l'administrateur ; « fly pseudo » = ce joueur ; « fly all » = tous (toujours confirmé)
		  Spectator     effet local de l'admin : « spectate pseudo » = l'admin observe ce joueur ; rien n'est fait à la cible
		  ESP           vue locale de l'admin, jamais donnée à un autre joueur
	]]
	local function planTool(player, entry, tokens)
		local spec = entry.Spec
		local state = entry.Negate ~= true
		local stateSet = entry.Negate == true
		local targetToken
		for _, token in tokens do
			local boolean = Parser.Boolean(token)
			if boolean ~= nil and not stateSet then
				local clash = reservedClash(token)
				if clash then return nil, clash end
				state, stateSet = boolean, true
			elseif targetToken == nil then
				targetToken = token
			else
				return nil, usageResult(spec)
			end
		end
		if not Ranks.CanUse(player, spec.Module) then return nil, result(false, "Denied", Msg("Assistant.Denied")) end

		local dispatcher = spec.Distributed and ctx.Dispatcher or nil
		if dispatcher then
			local selection, problem = selectTargets(player, spec, targetToken)
			if not selection then return nil, problem end
			local plan = { Entry = entry, Spec = spec, Off = not state, Selection = selection }
			plan.Key = planKey(spec, not state, selection, nil)
			plan.NeedsConfirm = selection.Kind == "All" -- une action sur tout le serveur demande toujours une confirmation
			plan.Execute = function()
				local targets = selection.Players
				local tally = dispatcher.Apply(player, spec.Module, targets, state)
				if not isPlayer(player) then return result(false, "Denied", Msg("Assistant.Denied")) end
				local ok, code, text, details = dispatcher.Summarize(tally)
				if ok and #targets == 1 and tally.Pending == 0 and config.ReplyStyle ~= "Detailed" then text = Msg("Assistant.Done") end
				return result(ok, code, text, (details and #details > 0) and { Details = details } or nil)
			end
			return plan
		end

		local resolved = targetToken and resolveOne(targetToken) or nil
		if resolved and (resolved.Kind == "None" or resolved.Kind == "Ambiguous") then return nil, targetProblem(resolved) end
		local own = resolved == nil or resolved.Kind == "Me" or (resolved.Kind == "Single" and resolved.Player.Ref == player)
		local plan = { Entry = entry, Spec = spec, Off = not state, NeedsConfirm = false }
		local function client(extra)
			return result(true, "Client", Msg("Assistant.Done"), { Client = extra })
		end
		if spec.Module == "Spectator" then
			-- spectate : observation LOCALE de l'admin (jamais distribuée) ; « spectate » seul = vue libre, « spectate pseudo » = observer ce joueur
			plan.Key = planKey(spec, not state, nil, resolved and resolved.Player and resolved.Player.UserId or nil)
			if not state then
				plan.Execute = function() return client({ Tool = spec.Module, State = false }) end
			elseif resolved == nil then
				plan.Execute = function() return client({ Tool = spec.Module, State = true }) end
			elseif resolved.Kind == "All" then
				return nil, result(false, "Invalid", Msg("Assistant.SpectateAll"))
			elseif own then
				return nil, result(false, "Invalid", Msg("Assistant.SpectateSelf"))
			else
				plan.Execute = function() return client({ Tool = spec.Module, State = true, Target = resolved.Player.UserId }) end
			end
			return plan
		end
		if not own then
			return nil, result(false, "Unavailable", Msg(spec.Module == "ESP" and "Assistant.LocalOnly" or "Assistant.OnlyYou", spec.Module))
		end
		plan.Selection = { Kind = "Self", Players = { player }, Implicit = resolved == nil }
		plan.Key = planKey(spec, not state, plan.Selection, nil)
		plan.Execute = function() return client({ Tool = spec.Module, State = state }) end
		return plan
	end

	-- Aperçu à blanc d'une étape de commande personnalisée : sa clé canonique, vise-t-elle « all », est-elle sensible ? nil si l'étape est invalide (elle échouera à l'exécution)
	local function previewStep(player, command)
		local clean = Parser.Clean(command)
		if not clean then return nil end
		local tokens = Parser.Tokenize(clean)
		if not tokens then return nil end
		tokens = Parser.StripPoliteness(tokens)
		local entry, used = Catalog.Find(getCatalog(), tokens)
		if not entry or entry.Spec.Kind == "Custom" then return nil end
		local plan = planFor(player, entry, table.move(tokens, used + 1, #tokens, 1, {}), { Depth = 1, Confirmed = false })
		if not plan then return nil end
		return { Key = plan.Key, All = plan.Selection ~= nil and plan.Selection.Kind == "All", Dangerous = plan.Spec.Confirm == true }
	end

	-- Commande personnalisée (données validées de Sentinel Helper, jamais du code)
	local function planCustom(player, entry, tokens, cx)
		local spec = entry.Spec
		local definition = spec.Definition
		if not (Ranks.IsAdmin(player) and Ranks.HasPermission(player, definition.Permission)) then return nil, result(false, "Denied", Msg("Assistant.Denied")) end
		local values, targetValue = {}, nil
		for index, arg in definition.Args do
			local token = tokens[index]
			if arg.Type == "text" and index == #definition.Args and index <= #tokens then token = table.concat(tokens, " ", index) end
			if token == nil then
				if arg.Required then return nil, usageResult(spec) end
			elseif arg.Type == "number" then
				local number = Parser.Number(token)
				if not number or (arg.Min and number < arg.Min) or (arg.Max and number > arg.Max) then return nil, usageResult(spec) end
				values[arg.Name] = number
			elseif arg.Type == "boolean" then
				local boolean = Parser.Boolean(token)
				if boolean == nil then return nil, usageResult(spec) end
				values[arg.Name] = boolean and "on" or "off"
			else
				values[arg.Name] = token
				if arg.Type == "target" and not targetValue then targetValue = token end
			end
		end
		if #tokens > #definition.Args and not (#definition.Args > 0 and definition.Args[#definition.Args].Type == "text") then return nil, usageResult(spec) end
		local action = definition.Action
		local plan = { Entry = entry, Spec = spec, Off = false, Value = values }
		if action.Type == "Run" then
			if cx.Depth >= 1 then return nil, result(false, "Unavailable", Msg("Assistant.Unavailable")) end -- pas d'imbrication
			-- chaque étape est analysée À BLANC avant la première exécution : la confirmation porte sur les actions canoniques et les cibles réellement résolues
			local commands, keys, anyAll, anyDangerous = {}, {}, false, false
			for index, step in action.Steps do
				commands[index] = Actions.Expand(step.Command, values, "me")
				local preview = previewStep(player, commands[index])
				keys[index] = preview and preview.Key or ("?" .. Parser.Normalize(commands[index]))
				if preview then
					anyAll = anyAll or preview.All
					anyDangerous = anyDangerous or preview.Dangerous
				end
			end
			plan.Key = "Custom|" .. spec.Name .. "|" .. table.concat(keys, ">")
			-- une seule confirmation couvre toute la chaîne ; elle est demandée AVANT la première étape
			plan.NeedsConfirm = anyAll or (anyDangerous and config.ConfirmDangerous == true)
			plan.Execute = function(inner)
				local stepConfirmed = inner.Confirmed or plan.NeedsConfirm
				for index, command in commands do
					local step = run(player, command, nil, inner.Depth + 1, stepConfirmed)
					if not step.Ok and step.Code ~= "Client" then
						return result(false, step.Code, Msg("Assistant.CustomFailed", spec.Name, index), { Details = { step.Text } })
					end
					if not isPlayer(player) then break end
				end
				return result(true, "Done", Msg("Assistant.CustomDone", spec.Name))
			end
			return plan
		end
		local subject
		if action.Type == "Teleport" and action.Who == "Target" then
			local resolved = resolveOne(targetValue or "")
			if resolved.Kind == "None" or resolved.Kind == "Ambiguous" then return nil, targetProblem(resolved) end
			if resolved.Kind == "All" then return nil, result(false, "Unavailable", Msg("Assistant.Unavailable")) end
			subject = resolved.Kind == "Me" and player or resolved.Player.Ref
		end
		plan.Key = "Custom|" .. spec.Name .. "|" .. valueKey(values)
		plan.NeedsConfirm = false
		plan.Execute = function()
			local host = {
				Msg = Msg,
				CanTarget = function(admin, target) return Ranks.CanTarget(admin, target) end,
				NotifyTeleport = function(who) if ctx.Sentinel and ctx.Sentinel.NotifyServerTeleport then ctx.Sentinel.NotifyServerTeleport(who, 4, "Sentinel custom command") end end,
				Character = function(who) return who.Character end,
			}
			local ok, code, message = Actions.Execute(host, player, action, values, subject)
			return result(ok, code, message)
		end
		return plan
	end

	planFor = function(player, entry, tokens, cx)
		ensureConfig()
		local kind = entry.Spec.Kind
		if kind == "Target" then return planTarget(player, entry, tokens)
		elseif kind == "Toggle" then return planToggle(player, entry, tokens)
		elseif kind == "Slider" then return planSlider(player, entry, tokens)
		elseif kind == "Global" then return planGlobal(player, entry, tokens)
		elseif kind == "Tool" then return planTool(player, entry, tokens)
		elseif kind == "Custom" then return planCustom(player, entry, tokens, cx)
		end
		return nil, result(false, "Unavailable", Msg("Assistant.Unavailable"))
	end

	-- Aide : liste des commandes utilisables par CE joueur, ou détail d'une commande
	--[[
		Ce que CE joueur a le droit de lancer, calculé ICI (grade, matrice d'accès, permission d'une commande personnalisée) : c'est la même règle que celle de `run`.
		Le client n'en reçoit qu'un reflet (Locked) pour dessiner un cadenas ; il ne donne aucun droit : chaque commande retourne à `run`, qui revérifie tout.
	]]
	local function permitted(player, spec)
		if spec.Kind == "Custom" then
			return Ranks.IsAdmin(player) and Ranks.HasPermission(player, spec.Permission)
		end
		return Ranks.CanUse(player, spec.Module)
	end
	local function usableSpecs(player)
		local list = {}
		for _, spec in getCatalog().Specs do
			if permitted(player, spec) then table.insert(list, spec) end
		end
		return list
	end
	-- Identifiants d'un choix (Leaderstats : statistique, opération ; GiveTool : outil...), au plus 40 : sert à l'autocomplétion
	local function choiceIds(slot, lists)
		local source = slot.Options
		local list = type(source) == "string" and lists[source] or source
		local ids = {}
		if type(list) == "table" then
			for _, entry in list do
				local id = type(entry) == "table" and entry[1] or entry
				if type(id) == "string" and #ids < 40 then table.insert(ids, id) end
			end
		end
		return ids
	end
	-- Emplacements d'arguments (Catalog.Slots) sous leur forme publique : du texte et des nombres, jamais de fonction ni de référence
	local function publicSlots(spec, lists)
		local list = {}
		for _, slot in spec.Slots or {} do
			local entry = { Type = slot.Type, Display = slot.Display, Optional = slot.Optional == true, Name = slot.Name, Min = slot.Min, Max = slot.Max,
				All = slot.All == true, Self = slot.Self == true, Off = slot.Off == true, MeOnly = slot.MeOnly == true, Reset = slot.Reset == true, MinMinutes = slot.MinMinutes }
			if slot.Type == "choice" then entry.Options = choiceIds(slot, lists) end
			table.insert(list, entry)
		end
		return list
	end
	local function publicSpec(spec, locked, lists)
		return { Name = spec.Name, Usage = spec.Usage, Description = spec.Description, Label = spec.Label, Kind = spec.Kind, Aliases = spec.Aliases,
			Locked = locked == true, Confirm = spec.Confirm == true, Slots = publicSlots(spec, lists or {}) }
	end
	-- TOUTES les commandes du catalogue de Sentinel (celles que l'administrateur n'a pas désactivées), chacune avec son verrou ; usable = combien sont permises
	local function catalogList(player)
		local lists = ctx.OptionLists and ctx.OptionLists() or {}
		local list, usable = {}, 0
		for _, spec in getCatalog().Specs do
			local locked = not permitted(player, spec)
			if not locked then usable += 1 end
			table.insert(list, publicSpec(spec, locked, lists))
		end
		return list, usable
	end
	local function runHelp(player, tokens)
		if tokens[1] then
			local entry = Catalog.Find(getCatalog(), tokens)
			if entry then
				if permitted(player, entry.Spec) then
					local lists = ctx.OptionLists and ctx.OptionLists() or {}
					return result(true, "Help", Msg("Assistant.HelpOne", entry.Spec.Usage), { Help = { publicSpec(entry.Spec, false, lists) } })
				end
				return result(false, "Denied", Msg("Assistant.Denied"))
			end
			return result(false, "Unknown", Msg("Assistant.Unknown"))
		end
		-- le catalogue : toutes les commandes, les interdites avec leur cadenas (Locked) ; le serveur seul calcule les verrous
		local list, usable = catalogList(player)
		return result(true, "Help", Msg("Assistant.HelpCatalog", usable, #list), { Help = list, Catalog = true })
	end

	-- Mots d'une seule pièce que CE joueur peut taper (noms, alias, formes d'arrêt, toutes langues) : base des suggestions. Aucune commande interdite n'y figure.
	local function usableWords(player)
		local allowed = {}
		for _, spec in usableSpecs(player) do allowed[spec] = true end
		local words = {}
		for key, entry in getCatalog().ByName do
			if allowed[entry.Spec] and not string.find(key, " ", 1, true) then table.insert(words, key) end
		end
		table.sort(words)
		return words
	end

	-- Phrase non comprise : suggestions locales, puis (facultatif) IA externe qui ne fait que PROPOSER une commande
	local function runUnknown(player, clean, verb, depth)
		local suggestions = Parser.Suggest(verb, usableWords(player), 3)
		if #suggestions == 0 and depth == 0 and ensureConfig().External.Enabled then
			local status = external.Status(config)
			if status.Available then
				local ok, proposal = external.Interpret(player, clean, getCatalog(), config)
				if not allowedToUse(player) then return result(false, "Denied", Msg("Assistant.Denied")) end
				if ok then
					local words = { proposal.Command }
					for _, argument in proposal.Arguments do
						table.insert(words, string.find(argument, "%s") and ('"' .. string.gsub(argument, '"', "") .. '"') or argument)
					end
					local proposed = table.concat(words, " ")
					-- la confirmation porte sur la commande canonique de la proposition (action + cibles résolues) quand elle est analysable
					local preview = previewStep(player, proposed)
					return askConfirmation(player, preview and preview.Key or Parser.Normalize(proposed), Msg("Assistant.ConfirmAI", proposed), proposed, Parser.Normalize(proposed))
				end
				if proposal ~= "NoCommand" and proposal ~= "Invalid" then return result(false, "External", Msg("Assistant.External." .. tostring(proposal))) end
			elseif Ranks.HasPermission(player, "Assistant.Configure") or Ranks.HasPermission(player, "Assistant.External") then
				-- l'IA externe est activée mais pas prête : celui qui peut la régler apprend ce qui manque (les autres voient « commande inconnue »)
				return result(false, "External", Msg("Assistant.External." .. tostring(status.Reason)))
			end
		end
		if #suggestions > 0 then return result(false, "Unknown", Msg("Assistant.UnknownSuggest", table.concat(suggestions, ", "))) end
		return result(false, "Unknown", Msg("Assistant.Unknown"))
	end

	-- Cœur : une ligne de commande -> résultat (appelé par le remote, par les étapes d'une commande personnalisée et par les tests)
	-- Texte -> reconnaissance multilingue (Catalog.Find) -> action canonique -> droits -> plan (cible, valeurs) -> confirmation -> exécution
	run = function(player, text, confirmToken, depth, confirmed)
		depth = depth or 0
		local clean, problem = Parser.Clean(text)
		if not clean then return result(false, "Invalid", Msg(problem == "Empty" and "Assistant.Empty" or "Assistant.Invalid")) end
		local tokens = Parser.Tokenize(clean)
		if not tokens then return result(false, "Invalid", Msg("Assistant.Invalid")) end
		tokens = Parser.StripPoliteness(tokens)
		local verb = Parser.Normalize(tokens[1] or "")
		local rest = table.move(tokens, 2, #tokens, 1, {})
		local presented
		if depth == 0 and not confirmed then presented = takePending(player, confirmToken) end
		local localKind = Parser.LocalCommand(verb)
		if localKind == "Help" then return runHelp(player, rest) end
		if localKind == "List" then return runHelp(player, {}) end
		if localKind == "Clear" then return result(true, "Clear", Msg("Assistant.Cleared")) end
		local entry, used = Catalog.Find(getCatalog(), tokens)
		if not entry then return runUnknown(player, clean, verb, depth) end
		rest = table.move(tokens, used + 1, #tokens, 1, {})
		local spec = entry.Spec
		local permitted
		if spec.Kind == "Custom" then
			permitted = Ranks.IsAdmin(player) and Ranks.HasPermission(player, spec.Permission)
		else
			permitted = Ranks.CanUse(player, spec.Module)
		end
		if not permitted then
			log(player, "Assistant", spec.Module, Msg("Assistant.Log.Denied", spec.Name), "warning")
			return result(false, "Denied", Msg("Assistant.Denied"))
		end
		local cx = { Clean = clean, Confirmed = confirmed == true, Depth = depth, Presented = presented, TextKey = Parser.Normalize(clean) }
		local plan, refusal = planFor(player, entry, rest, cx)
		local outcome
		if not plan then
			outcome = refusal
		elseif plan.NeedsConfirm and not confirmedFor(cx, plan.Key) then
			outcome = askConfirmation(player, plan.Key, Msg("Assistant.ConfirmNeeded", describePlan(plan, clean)))
		else
			outcome = plan.Execute(cx)
		end
		if depth == 0 and outcome.Code ~= "Confirm" then
			log(player, "Assistant", spec.Module, Unicode.Truncate(clean, 120), outcome.Ok and "info" or "warning")
		end
		return outcome
	end

	--[[
		Point d'entrée du remote RunAssistant(texte, jeton de confirmation) : droits, fréquence, une commande à la fois, puis run.
		Toute exception est capturée : le client reçoit une erreur claire, jamais un blocage.
	]]
	function api.Run(player, text, confirmToken)
		if not isPlayer(player) then return result(false, "Denied", Msg("Assistant.Denied")) end
		if not allowedToUse(player) then return result(false, "Disabled", Msg(featureOn() and "Assistant.Denied" or "Assistant.Disabled")) end
		if confirmToken ~= nil and (type(confirmToken) ~= "string" or #confirmToken > 32) then return result(false, "Invalid", Msg("Assistant.Invalid")) end
		if not Guard.Allow(player, "AssistantRun", config.RatePerWindow, 10) then
			if ctx.Sentinel and ctx.Sentinel.RecordAbuse then ctx.Sentinel.RecordAbuse(player, { fr = "Sentinel : fréquence excessive", en = "Sentinel: excessive rate" }) end
			return result(false, "RateLimited", Msg("Assistant.RateLimited"))
		end
		if busy[player.UserId] then return result(false, "Busy", Msg("Assistant.Busy")) end
		busy[player.UserId] = true
		local ok, outcome = pcall(run, player, text, confirmToken, 0, false)
		busy[player.UserId] = nil
		if not ok then
			warn("[APM] Sentinel : " .. tostring(outcome))
			return result(false, "Error", Msg("Assistant.Error"))
		end
		if not isPlayer(player) then return result(false, "Denied", Msg("Assistant.Denied")) end
		return outcome
	end

	----------------------------------------------------------------------------------------------------------
	-- Ce que voit un admin autorisé à utiliser Sentinel

	function api.GetClientState(player)
		if not isPlayer(player) or not Ranks.IsAdmin(player) then return { Allowed = false } end
		if not moduleEnabled() or not Ranks.HasPermission(player, "Assistant.Use") then return { Allowed = false } end
		ensureConfig()
		if not config.Enabled then return { Allowed = true, Enabled = false } end
		-- Commands : TOUT le catalogue avec les verrous calculés ici ; Words : chaque mot tapable (nom, alias, phrase de l'une des sept langues, forme d'arrêt) des commandes
		-- PERMISES -> indice dans Commands (négatif = forme d'arrêt). L'autocomplétion du client travaille sur cette seule table : aucune commande interdite ou inexistante.
		local commands, words, usable = catalogList(player), {}, {}
		for index, entry in commands do
			if not entry.Locked then usable[entry.Name] = index end
		end
		for key, entry in getCatalog().ByName do
			local index = usable[entry.Spec.Name]
			if index then words[key] = entry.Negate and -index or index end
		end
		local vocabulary = Parser.Lexicon and Parser.Lexicon.Lexicon
		local localWords = table.clone(Catalog.LOCAL)
		for word, kind in vocabulary and vocabulary.Local or {} do localWords[word] = kind end
		return { Allowed = true, Enabled = true, Config = Config.ClientView(config), Commands = commands, Words = words, Local = { "help", "list", "clear" },
			LocalWords = localWords, Vocabulary = vocabulary and { Me = Catalog.WordList(vocabulary.Me), All = Catalog.WordList(vocabulary.All),
				On = Catalog.WordList(vocabulary.True), Off = Catalog.WordList(vocabulary.False), Reset = Catalog.WordList(vocabulary.Reset) } or nil,
			AllowAll = config.AllowAll == true, External = ctx.Ranks.HasPermission(player, "Assistant.Configure") and external.Status(config).Available or nil }
	end

	----------------------------------------------------------------------------------------------------------
	-- Sentinel Helper : lecture et écriture des réglages ADMINISTRATIFS (chaque clé exige sa propre permission, vérifiée ici)

	local function can(player, permission)
		return isPlayer(player) and Ranks.IsAdmin(player) and Ranks.HasPermission(player, permission)
	end
	local function helperAccess(player)
		return can(player, "Assistant.Configure") or can(player, "Assistant.Commands")
	end

	local function broadcastChange()
		catalog = nil
		if ctx.Remotes and ctx.Remotes.AssistantChanged then ctx.Remotes.AssistantChanged:FireAllClients() end
	end

	-- Liste de TOUTES les commandes du registre (même désactivées dans Sentinel), pour l'écran des commandes désactivées
	local function registryNames()
		local full = Catalog.Build(ctx, { Custom = {}, Aliases = {}, DisabledCommands = {} })
		local list = {}
		for _, spec in full.Specs do
			if spec.Kind ~= "Custom" then table.insert(list, { Name = spec.Name, Usage = spec.Usage, Label = spec.Label, Kind = spec.Kind }) end
		end
		return list
	end

	function api.GetAdminState(player)
		if not helperAccess(player) then return nil end
		ensureConfig()
		local view = Config.Copy(config)
		local permissions = {}
		for name in Ranks.Defaults do
			if string.sub(name, 1, 1) ~= "$" and Ranks.HasPermission(player, name) then table.insert(permissions, name) end
		end
		table.sort(permissions)
		local conflicts = {}
		for index, conflict in getCatalog().Conflicts do
			if index > 20 then break end
			table.insert(conflicts, conflict)
		end
		local state = {
			Config = view, Baseline = Config.ForStorage(baseline), Newer = info.Newer, Migrated = info.Migrated, Stored = info.Stored,
			Can = { Configure = can(player, "Assistant.Configure"), Commands = can(player, "Assistant.Commands"), External = can(player, "Assistant.External") },
			Registry = registryNames(), Permissions = permissions, Conflicts = conflicts,
			Storage = ctx.SuiteConfig and ctx.SuiteConfig.Provenance and ctx.SuiteConfig.Provenance(SECTION, Config.ForStorage(baseline), Config.ForStorage(config)) or nil,
			Limits = { MaxCustom = Config.MAX_CUSTOM, MaxList = Config.MAX_LIST, MaxSteps = Actions.MAX_STEPS, MaxArgs = Actions.MAX_ARGS, Coordinate = Actions.COORDINATE_LIMIT },
		}
		if can(player, "Assistant.External") or can(player, "Assistant.Configure") then state.ExternalStatus = external.Status(config) end
		-- reconnaissance multilingue : langues de commande, alias officiels par langue (lecture seule), prefixes d'arret, etat des dictionnaires
		local lexicon = Parser.Lexicon
		if lexicon then
			local languages = lexicon:LanguageList()
			local prefixes = {}
			for _, language in languages do prefixes[language.Code] = lexicon:OffPrefixes(language.Code) end
			local report = lexicon:Report()
			state.Languages, state.OffPrefixes = languages, prefixes
			state.Aliases = Catalog.Describe(getCatalog())
			state.Localization = { Collisions = #report.Collisions, Problems = #report.Problems }
		end
		return state
	end

	local function persist(player, newConfig, neededPermissions)
		local function authorize()
			for _, permission in neededPermissions do
				if not can(player, permission) then return false end
			end
			return true
		end
		if info.Newer then return false, Msg("Assistant.Config.ReadOnly") end
		if not ctx.SuiteConfig then return false, Msg("Assistant.Config.Unavailable") end
		local saved, message = ctx.SuiteConfig.Save(SECTION, Config.ForStorage(newConfig), authorize)
		if not saved then return false, message end
		config = newConfig
		info.Stored = 1
		log(player, "Assistant.Config", nil, Msg("Assistant.Log.ConfigSaved"), "warning")
		broadcastChange()
		return true, message
	end

	--[[
		Enregistre un correctif de réglages. Chaque clé appartient à un rôle : réglages généraux (Assistant.Configure), commandes personnalisées
		(Assistant.Commands), IA externe (Assistant.External). Une clé hors des droits de l'appelant refuse TOUTE la demande.
	]]
	function api.Save(player, patch)
		if not helperAccess(player) then return false, Msg("Assistant.Denied") end
		if type(patch) ~= "table" then return false, Msg("Assistant.Invalid") end
		ensureConfig()
		local keys, needed = {}, {}
		for key in patch do
			if type(key) ~= "string" or not Config.ALL_KEYS[key] then return false, Msg("Assistant.Invalid") end
			local permission = key == "External" and "Assistant.External" or (key == "Custom" and "Assistant.Commands" or "Assistant.Configure")
			if not can(player, permission) then return false, Msg("Assistant.Denied") end
			keys[key] = true
			needed[permission] = true
		end
		if next(keys) == nil then return false, Msg("Assistant.Invalid") end
		local list = {}
		for permission in needed do table.insert(list, permission) end
		local merged = Config.Merge(config, patch, { Keys = keys, Features = features, Hosts = (ctx.Settings.Assistant and ctx.Settings.Assistant.External or {}).Hosts })
		return persist(player, merged, list)
	end

	function api.Reset(player)
		if not can(player, "Assistant.Configure") or not can(player, "Assistant.Commands") then return false, Msg("Assistant.Denied") end
		ensureConfig()
		if info.Newer then return false, Msg("Assistant.Config.ReadOnly") end
		if not ctx.SuiteConfig then return false, Msg("Assistant.Config.Unavailable") end
		local saved, message = ctx.SuiteConfig.Reset(SECTION, function() return can(player, "Assistant.Configure") and can(player, "Assistant.Commands") end)
		if not saved then return false, message end
		config = Config.Merge(baseline, {}, {})
		config.Issues = {}
		info.Stored = 0
		log(player, "Assistant.Config", nil, Msg("Assistant.Log.ConfigReset"), "warning")
		broadcastChange()
		return true, message
	end

	-- Crée ou remplace UNE commande personnalisée (original : ancien nom en cas de renommage)
	function api.SaveCustom(player, definition, original)
		if not can(player, "Assistant.Commands") then return false, Msg("Assistant.Denied") end
		if type(definition) ~= "table" or (original ~= nil and type(original) ~= "string") then return false, Msg("Assistant.Invalid") end
		ensureConfig()
		local clean, problem = Config.CleanCustom(definition, features)
		if not clean then return false, Msg("Assistant.Config.CustomInvalid", tostring(problem)) end
		if not Ranks.HasPermission(player, clean.Permission) then return false, Msg("Assistant.Config.PermissionNotHeld", clean.Permission) end
		-- noms libres : ni module, ni outil, ni alias, ni commande locale, ni autre commande personnalisée
		local others = {}
		for _, existing in config.Custom do
			if existing.Name ~= original then table.insert(others, existing) end
		end
		if #others >= Config.MAX_CUSTOM then return false, Msg("Assistant.Config.TooMany") end
		local reference = Catalog.Build(ctx, { Custom = others, Aliases = config.Aliases, DisabledCommands = {} })
		for _, candidateName in { clean.Name, table.unpack(clean.Aliases) } do
			if not Catalog.IsNameFree(reference, candidateName) then return false, Msg("Assistant.Config.NameTaken", candidateName) end
		end
		table.insert(others, clean)
		table.sort(others, function(a, b) return a.Name < b.Name end)
		local merged = Config.Merge(config, { Custom = others }, { Keys = { Custom = true }, Features = features })
		return persist(player, merged, { "Assistant.Commands" })
	end

	function api.DeleteCustom(player, commandName)
		if not can(player, "Assistant.Commands") or type(commandName) ~= "string" then return false, Msg("Assistant.Denied") end
		ensureConfig()
		local others, found = {}, false
		for _, existing in config.Custom do
			if existing.Name == commandName then found = true else table.insert(others, existing) end
		end
		if not found then return false, Msg("Assistant.NotFound") end
		local merged = Config.Merge(config, { Custom = others }, { Keys = { Custom = true }, Features = features })
		return persist(player, merged, { "Assistant.Commands" })
	end

	-- Test de la liaison avec l'IA externe (une requête, limitée par minute) : ne renvoie qu'un code, jamais la réponse brute
	function api.TestExternal(player)
		if not can(player, "Assistant.External") then return false, Msg("Assistant.Denied") end
		ensureConfig()
		local ok, outcome = external.Interpret(player, "bring me", getCatalog(), config)
		if not can(player, "Assistant.External") then return false, Msg("Assistant.Denied") end
		if ok then return true, Msg("Assistant.External.Works") end
		return false, Msg("Assistant.External." .. tostring(outcome))
	end

	-- Analyse à blanc (aucune exécution) : comment Sentinel comprend ce texte ? Sert au test de Sentinel Helper.
	function api.Explain(player, text)
		if not helperAccess(player) then return nil end
		local clean = Parser.Clean(text)
		if not clean then return { Kind = "Invalid" } end
		local tokens = Parser.Tokenize(clean)
		if not tokens then return { Kind = "Invalid" } end
		tokens = Parser.StripPoliteness(tokens)
		local verb = Parser.Normalize(tokens[1] or "")
		if Parser.LocalCommand(verb) then return { Kind = "Local", Command = verb } end
		local entry, used = Catalog.Find(getCatalog(), tokens)
		if not entry then return { Kind = "Unknown", Suggestions = Parser.Suggest(verb, getCatalog().Names, 3) } end
		local spec = entry.Spec
		local languages = {}
		for code in entry.Languages or {} do table.insert(languages, code) end
		table.sort(languages)
		local info = { Kind = spec.Kind, Command = spec.Name, Module = spec.Module, Usage = spec.Usage, Negate = entry.Negate, Confirm = spec.Confirm == true,
			Source = spec.Source, Languages = languages, Words = used }
		-- analyse a blanc de la cible et du sens : rien n'est execute
		local plan, refusal = planFor(player, entry, table.move(tokens, used + 1, #tokens, 1, {}), { Depth = 1, Confirmed = false })
		if plan then
			info.Off = plan.Off == true
			info.NeedsConfirm = plan.NeedsConfirm == true
			if plan.Selection then info.Target = { Kind = plan.Selection.Kind, Implicit = plan.Selection.Implicit == true, Count = #plan.Selection.Players } end
		elseif refusal then
			info.Problem = refusal.Code
		end
		return info
	end

	function api.Forget(player)
		pending[player.UserId], busy[player.UserId] = nil, nil
	end
	function api.Reload()
		loaded, catalog = false, nil
	end
	function api.GetConfig()
		return ensureConfig()
	end
	function api.Catalog()
		return getCatalog()
	end
	function api.ExternalService()
		return external
	end

	return api
end

----------------------------------------------------------------------------------------------------------
-- Branchement dans l'APM

function Assistant.Init(ctx)
	if ctx.Assistant and ctx.Assistant.Run then return ctx.Assistant end
	local api = Assistant.Create(ctx)
	ctx.Assistant = api
	local R = ctx.Remotes
	R.RunAssistant.OnServerInvoke = function(player, text, confirmToken)
		return api.Run(player, text, confirmToken)
	end
	R.GetAssistant.OnServerInvoke = function(player)
		if not ctx.Guard.Allow(player, "GetAssistant", 12, 10) then return { Allowed = false } end
		return api.GetClientState(player)
	end
	R.ConfigureAssistant.OnServerInvoke = function(player, action, payload, extra)
		if type(action) ~= "string" or not ctx.Guard.Allow(player, "ConfigureAssistant", 20, 10) then return false, ctx.Msg("Assistant.RateLimited") end
		if action == "Get" then
			local state = api.GetAdminState(player)
			if not state then return false, ctx.Msg("Assistant.Denied") end
			return true, state
		elseif action == "Save" then
			return api.Save(player, payload)
		elseif action == "Reset" then
			return api.Reset(player)
		elseif action == "SaveCustom" then
			return api.SaveCustom(player, payload, extra)
		elseif action == "DeleteCustom" then
			return api.DeleteCustom(player, payload)
		elseif action == "TestExternal" then
			return api.TestExternal(player)
		elseif action == "Explain" then
			return true, api.Explain(player, payload)
		end
		return false, ctx.Msg("Assistant.Invalid")
	end
	game:GetService("Players").PlayerRemoving:Connect(api.Forget)
	return api
end

return Assistant
