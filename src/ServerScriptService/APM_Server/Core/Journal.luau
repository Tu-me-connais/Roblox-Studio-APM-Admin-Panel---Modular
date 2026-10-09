--[[
	Journal : journal des actions de l'APM (onglet Logs).

	Les entrées récentes sont gardées en mémoire, envoyées en direct aux admins connectés (LogAdded) et fusionnées dans le DataStore
	(clé "Journal") toutes les FLUSH_SECONDS : l'onglet Logs montre aussi ce qu'ont fait les autres serveurs.
	Une entrée : { time, actor, action, target, detail, category, level }. detail peut être un message traduisible (Lang.Msg) :
	chaque admin le lit dans sa langue. Les refus de non-admins sont limités à une entrée par joueur toutes les 30 s (anti-spam).
]]
local Players = game:GetService("Players")

local Journal = {}

local REFUSAL_DELAY = 30
local FLUSH_SECONDS = 40
local REFRESH_SECONDS = 20

local Ranks, logAddedEvent
local maxLogs = 300
local pending = {} -- entrées pas encore enregistrées (les plus récentes en premier)
local remote = {} -- journal enregistré (tous serveurs), relu au plus toutes les REFRESH_SECONDS
local remoteReadAt = -math.huge
local lastRefusal = {} -- [userId] = os.clock()
local flushing = false

-- Coupe un texte à n caractères sans casser l'UTF-8 (le DataStore refuse un texte invalide)
local function short(text, n)
	text = tostring(text)
	if not utf8.len(text) then
		text = string.gsub(text, "[\128-\255]", "?")
	end
	local cut = utf8.offset(text, n + 1)
	if cut then
		text = string.sub(text, 1, cut - 1) .. "..."
	end
	return text
end

-- Un détail : texte, nombre, ou message traduisible { k, a, n } (arguments nettoyés, 2 niveaux maximum)
local function clean(value, depth)
	local kind = type(value)
	if kind == "string" then
		return short(value, 200)
	elseif kind == "number" or kind == "boolean" then
		return value
	elseif kind == "table" and type(value.k) == "string" and depth < 3 then
		local source = type(value.a) == "table" and value.a or {}
		local count = math.clamp(tonumber(value.n) or #source, 0, 8)
		local args = {}
		for index = 1, count do
			local cleaned = clean(source[index], depth + 1)
			args[index] = cleaned == nil and "" or cleaned
		end
		return { k = short(value.k, 64), a = args, n = count }
	elseif kind == "table" and type(value.d) == "number" then
		return { d = value.d }
	elseif value == nil then
		return nil
	end
	return short(tostring(value), 200)
end

function Journal.Log(actorName, action, targetName, detail, category, level)
	local entry = {
		time = os.time(),
		actor = short(actorName or "?", 40),
		action = short(action or "?", 64),
		target = targetName and short(targetName, 40) or "-",
		detail = clean(detail or "", 0),
		category = short(category or "System", 32),
		level = (level == "danger" or level == "warning") and level or "info",
	}
	table.insert(pending, 1, entry)
	while #pending > maxLogs do
		table.remove(pending)
	end
	if logAddedEvent then
		for _, player in Players:GetPlayers() do
			if Ranks.IsAdmin(player) then
				logAddedEvent:FireClient(player, entry)
			end
		end
	end
end

-- Refus d'un non-admin : une entrée par joueur toutes les REFUSAL_DELAY secondes au plus
function Journal.LogRefusal(player, action, detail)
	local now = os.clock()
	local last = lastRefusal[player.UserId]
	if last and now - last < REFUSAL_DELAY then
		return
	end
	lastRefusal[player.UserId] = now
	Journal.Log(player.Name, action, nil, detail, "System", "warning")
end

local function flush()
	local store = Ranks and Ranks.GetStore()
	if flushing or #pending == 0 or not store then
		return
	end
	flushing = true
	local batch = pending
	pending = {}
	local ok, result = pcall(store.UpdateAsync, store, "Journal", function(old)
		local list = type(old) == "table" and old or {}
		for index = #batch, 1, -1 do -- du plus ancien au plus récent : chacun passe en tête
			table.insert(list, 1, batch[index])
		end
		while #list > maxLogs do
			table.remove(list)
		end
		return list
	end)
	if ok and type(result) == "table" then
		remote, remoteReadAt = result, os.clock()
	else
		warn("[APM] Journal non enregistré : " .. tostring(result))
		for _, entry in batch do -- rien n'est perdu : on réessaie au prochain passage
			table.insert(pending, entry)
		end
	end
	flushing = false
end

-- Le journal affiché : les entrées de ce serveur pas encore enregistrées, puis celles du DataStore
function Journal.Current()
	local store = Ranks.GetStore()
	if store and os.clock() - remoteReadAt > REFRESH_SECONDS then
		remoteReadAt = os.clock()
		local ok, data = pcall(store.GetAsync, store, "Journal")
		if ok and type(data) == "table" then
			remote = data
		end
	end
	local list = table.clone(pending)
	for _, entry in remote do
		table.insert(list, entry)
	end
	table.sort(list, function(a, b)
		return (a.time or 0) > (b.time or 0)
	end)
	while #list > maxLogs do
		table.remove(list)
	end
	return list
end

function Journal.Init(ranks, remotes, settings)
	Ranks = ranks
	maxLogs = tonumber(settings and settings.MaxLogs) or maxLogs
	logAddedEvent = remotes.LogAdded
	remotes.GetLogs.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) then
			return {}
		end
		return Journal.Current()
	end
	Players.PlayerRemoving:Connect(function(player)
		lastRefusal[player.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			flush()
		end
	end)
	game:BindToClose(flush)
end

return Journal

