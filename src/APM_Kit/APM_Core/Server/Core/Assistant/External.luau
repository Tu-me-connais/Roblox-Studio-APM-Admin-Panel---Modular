--[[
	External : connexion FACULTATIVE à une IA externe pour comprendre des formulations plus naturelles. Sentinel fonctionne sans elle.
	Garde-fous (tous côté serveur) :
	  · désactivée par défaut ; aucune requête HTTP tant que le développeur n'a pas écrit dans ServerSettings (Settings.Assistant.External) une liste
	    d'hôtes HTTPS autorisés ET une clé (SecretName = Secret Roblox, ou ApiKey) ; les admins ne peuvent choisir qu'un hôte de cette liste ;
	  · la clé ne quitte jamais le serveur : ni client, ni DataStore, ni journal, ni réponse à un remote ;
	  · l'IA ne reçoit que le texte tapé et la liste des noms de commandes : ni joueurs, ni identifiants, ni données du jeu ;
	  · l'IA n'appelle rien : sa réponse (JSON strict) est convertie en commande STRUCTURÉE puis repasse par le même moteur et les mêmes
	    contrôles serveur qu'une commande tapée, avec en plus une confirmation de l'admin avant toute exécution ;
	  · délai maximal, limite de requêtes par minute, erreurs réseau et quotas gérés sans bloquer Sentinel.
]]
local HttpService = game:GetService("HttpService")

local External = {}

local DEFAULT_ENDPOINTS = {
	OpenAI = "https://api.openai.com/v1/chat/completions",
	Anthropic = "https://api.anthropic.com/v1/messages",
}

local function hostOf(endpoint)
	return type(endpoint) == "string" and string.match(endpoint, "^https://([%w%.%-]+)/?[^%s\\@]*$") or nil
end

--[[
	Crée le service. services (tests) : Request(options) -> réponse de type HttpService:RequestAsync ; HttpEnabled() ; Secret(nom) ; Clock().
	ctx.Settings.Assistant.External contient les réglages du développeur (Hosts, SecretName, ApiKey) : jamais copiés ailleurs.
]]
function External.Create(ctx, services)
	services = services or {}
	local clock = services.Clock or os.clock
	local request = services.Request or function(options) return HttpService:RequestAsync(options) end
	local httpEnabled = services.HttpEnabled or function() return HttpService.HttpEnabled end
	local getSecret = services.Secret or function(secretName) return HttpService:GetSecret(secretName) end
	local api = {}
	local recent, perAdmin = {}, {}

	local function developer()
		local settings = type(ctx.Settings) == "table" and type(ctx.Settings.Assistant) == "table" and ctx.Settings.Assistant.External or nil
		return type(settings) == "table" and settings or {}
	end

	local function endpointFor(config)
		local chosen = config.External.Endpoint
		if type(chosen) == "string" and chosen ~= "" then return chosen end
		local fromScript = developer().Endpoint
		if type(fromScript) == "string" and fromScript ~= "" then return fromScript end
		return DEFAULT_ENDPOINTS[config.External.Provider]
	end

	local function hostAllowed(host)
		local hosts = developer().Hosts
		if type(hosts) ~= "table" or host == nil then return false end
		for _, allowed in hosts do
			if type(allowed) == "string" and string.lower(allowed) == string.lower(host) then return true end
		end
		return false
	end

	--[[
		État pour l'admin (sans aucun secret) : Available, Reason (premier obstacle), Checks (liste de contrôle pour Sentinel Helper),
		Provider, Host. Reason : Disabled | NoHosts | HostNotAllowed | NoKey | HttpDisabled | NoModel.
	]]
	function api.Status(config)
		local external = config.External
		local hosts = developer().Hosts
		local endpoint = endpointFor(config)
		local host = hostOf(endpoint)
		local secretName, apiKey = developer().SecretName, developer().ApiKey
		local checks = {
			Enabled = external.Enabled == true,
			Hosts = type(hosts) == "table" and #hosts > 0,
			Endpoint = host ~= nil and hostAllowed(host),
			Key = (type(secretName) == "string" and secretName ~= "") or (type(apiKey) == "string" and apiKey ~= ""),
			Http = httpEnabled() == true,
			Model = type(external.Model) == "string" and external.Model ~= "",
		}
		local reason
		if not checks.Enabled then reason = "Disabled"
		elseif not checks.Hosts then reason = "NoHosts"
		elseif not checks.Endpoint then reason = "HostNotAllowed"
		elseif not checks.Key then reason = "NoKey"
		elseif not checks.Http then reason = "HttpDisabled"
		elseif not checks.Model then reason = "NoModel" end
		return { Available = reason == nil, Reason = reason, Checks = checks, Provider = external.Provider, Host = host }
	end

	local function allowRequest(player, perMinute)
		local now = clock()
		local function prune(list)
			while list[1] and now - list[1] > 60 do table.remove(list, 1) end
			return list
		end
		local mine = prune(perAdmin[player.UserId] or {})
		perAdmin[player.UserId] = mine
		prune(recent)
		if #recent >= perMinute * 3 or #mine >= perMinute then return false end
		table.insert(recent, now)
		table.insert(mine, now)
		return true
	end

	local function systemPrompt(catalog)
		local names = {}
		for _, spec in catalog.Specs do table.insert(names, spec.Usage) end
		return "You translate one administrator request into exactly one command from a fixed list. "
			.. "Answer with a single JSON object and nothing else: {\"command\":\"<name>\",\"arguments\":[\"<text>\", ...]}. "
			.. "Use only a command name from the list, the player name or me/all as the first argument when the usage shows <player>. "
			.. "If nothing fits, answer {\"command\":null}. Never invent commands, never explain. Commands (usage):\n" .. table.concat(names, "\n")
	end

	local function build(config, catalog, text)
		local external = config.External
		local endpoint = endpointFor(config)
		local headers = { ["Content-Type"] = "application/json" }
		local secretName, apiKey = developer().SecretName, developer().ApiKey
		local credential
		if type(secretName) == "string" and secretName ~= "" then
			local ok, secret = pcall(getSecret, secretName)
			if not ok or secret == nil then return nil, "NoKey" end
			credential = secret
		else
			credential = apiKey
		end
		local body
		if external.Provider == "Anthropic" then
			headers["x-api-key"] = credential
			headers["anthropic-version"] = "2023-06-01"
			body = { model = external.Model, max_tokens = 150, system = systemPrompt(catalog), messages = { { role = "user", content = text } } }
		else
			if type(credential) == "string" then
				headers["Authorization"] = "Bearer " .. credential
			else
				local prefixed = credential.AddPrefix and credential:AddPrefix("Bearer ") or credential
				headers["Authorization"] = prefixed
			end
			body = { model = external.Model, temperature = 0, max_tokens = 150,
				messages = { { role = "system", content = systemPrompt(catalog) }, { role = "user", content = text } } }
		end
		return { Url = endpoint, Method = "POST", Headers = headers, Body = HttpService:JSONEncode(body) }
	end

	-- L'IA peut entourer son JSON de texte ou de balises : on isole le premier objet, puis on valide chaque champ
	local function parseAnswer(content, catalog)
		if type(content) ~= "string" or #content > 4000 then return nil, "Invalid" end
		local fragment = string.match(content, "%b{}")
		if not fragment then return nil, "Invalid" end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, fragment)
		if not ok or type(decoded) ~= "table" then return nil, "Invalid" end
		if decoded.command == nil or decoded.command == false then return nil, "NoCommand" end
		if type(decoded.command) ~= "string" then return nil, "Invalid" end
		local command = string.lower(decoded.command)
		local entry = catalog.ByName[command]
		if not entry then return nil, "Invalid" end
		local arguments = {}
		if decoded.arguments ~= nil then
			if type(decoded.arguments) ~= "table" or #decoded.arguments > 6 then return nil, "Invalid" end
			for _, item in decoded.arguments do
				if type(item) == "number" and item == item and math.abs(item) < 1e9 then item = tostring(item) end
				if type(item) ~= "string" or #item > 80 or not utf8.len(item) or string.find(item, "%c") then return nil, "Invalid" end
				table.insert(arguments, item)
			end
		end
		return { Command = command, Arguments = arguments }
	end

	--[[
		Interprète `text`. Renvoie true + { Command, Arguments } ou false + code (Disabled, NoHosts, HostNotAllowed, NoKey, HttpDisabled, NoModel,
		RateLimited, Timeout, Auth, Quota, Failed, Invalid, NoCommand). Ne peut jamais faire plus que PROPOSER une commande.
	]]
	function api.Interpret(player, text, catalog, config)
		local status = api.Status(config)
		if not status.Available then return false, status.Reason end
		if type(text) ~= "string" or #text > 400 then return false, "Invalid" end
		if not allowRequest(player, config.External.MaxPerMinute) then return false, "RateLimited" end
		local options, problem = build(config, catalog, text)
		if not options then return false, problem end
		local finished, answer = false, nil
		local waiting = coroutine.running()
		local function finish(value)
			if finished then return end
			finished, answer = true, value
			if coroutine.status(waiting) == "suspended" then task.spawn(waiting) end
		end
		task.spawn(function()
			local ok, response = pcall(request, options)
			finish({ Ok = ok, Response = response })
		end)
		task.delay(config.External.TimeoutSeconds, function() finish({ Timeout = true }) end)
		if not finished then coroutine.yield() end
		if answer.Timeout then return false, "Timeout" end
		if not answer.Ok or type(answer.Response) ~= "table" then return false, "Failed" end
		local response = answer.Response
		if response.Success ~= true then
			local code = tonumber(response.StatusCode)
			if code == 401 or code == 403 then return false, "Auth" end
			if code == 429 then return false, "Quota" end
			return false, "Failed"
		end
		local ok, decoded = pcall(HttpService.JSONDecode, HttpService, tostring(response.Body))
		if not ok or type(decoded) ~= "table" then return false, "Invalid" end
		local content
		if config.External.Provider == "Anthropic" then
			local first = type(decoded.content) == "table" and decoded.content[1]
			content = type(first) == "table" and first.text or nil
		else
			local choice = type(decoded.choices) == "table" and decoded.choices[1]
			local message = type(choice) == "table" and choice.message
			content = type(message) == "table" and message.content or nil
		end
		local result, code = parseAnswer(content, catalog)
		if not result then return false, code end
		return true, result
	end

	function api.ParseAnswer(content, catalog)
		return parseAnswer(content, catalog)
	end

	return api
end

return External
