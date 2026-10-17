--[[
	SentinelStore : mémoire permanente de Sentinel Guard (DataStore de l'APM ; mémoire du serveur en mode Studio).

	Trois clés dans le DataStore unique de l'APM :
	  Sentinel_P_<userId>  fiche d'un joueur : { v, id, n (pseudo), d (nom affiché), f (1re infraction), t (dernière), c (total),
	                       k (total par type), s (score à la date t), e (événements récents, du plus récent au plus ancien) }
	  Sentinel_Index       résumé de toutes les fiches : { v, p = { [userId] = { n, d, f, t, c, k, s, o, cf } } } -> liste des suspects
	  Sentinel_Audit       journal des réglages et effacements : { v, l = { { t, by, id, a, d, j } } }

	Choix « intelligents » :
	  - le SCORE n'est pas stocké en continu : on garde (s, t) et on le fait décroître d'après la date (demi-vie du réglage
	    SuspectMemory) ; un vieux suspect redescend tout seul, sans réécriture ;
	  - écritures GROUPÉES : au plus une par joueur et par cycle (FLUSH_PLAYERS), plus une pour l'index ; jamais une écriture par alerte ;
	  - chaque événement a un identifiant (serveur + numéro) : une réécriture après une erreur réseau ne compte pas deux fois ;
	  - tout est BORNÉ : 25 événements par fiche, 300 fiches dans l'index, 60 lignes d'audit, rétention en jours (RetentionDays) ;
	  - une lecture ratée n'invente rien et n'écrase rien ; une fiche d'un schéma plus récent n'est jamais modifiée ;
	  - un effacement laisse une pierre tombale { gone } plutôt que d'appeler RemoveAsync (compatible avec les DataStores suivis).
	Les serveurs partagent ces clés : un tricheur repéré sur un serveur apparaît dans la liste des autres.
]]
local Store = {}

local SCHEMA = 1
local PREFIX, INDEX_KEY, AUDIT_KEY = "Sentinel_P_", "Sentinel_Index", "Sentinel_Audit"
local MAX_EVENTS, MAX_INDEX, MAX_AUDIT = 25, 300, 60
local FLUSH_PLAYERS, REMOVE_PER_CYCLE = 10, 6
local INDEX_TTL, DETAIL_TTL, AUDIT_TTL = 30, 20, 30
local WRITE_DELAY, MIN_FLUSH_GAP = 20, 15

local ctx, Ranks
local policy = { Persist = true, RetentionDays = 30, HalfLife = 900 }
local pending = {}       -- [userId] = { Name, Display, Score, Events = { plus récent d'abord } }
local pendingAudit = {}  -- entrées pas encore écrites (plus récente d'abord)
local removeQueue = {}   -- [userId] = true : fiches à effacer
local clearAll = false
local memory = {}        -- stockage du mode mémoire
local indexCache, indexAt = nil, -math.huge
local auditCache, auditAt = nil, -math.huge
local detailCache = {}   -- [userId] = { At, Record }
local status = { LastWrite = 0, LastError = nil, Writes = 0 }
local flushing, flushScheduled = false, false
local lastFlushAt = -math.huge
local serial = 0
local jobShort

local function deepCopy(value)
	if type(value) ~= "table" then return value end
	local copy = {}
	for key, item in value do copy[key] = deepCopy(item) end
	return copy
end

-- Copie compatible DataStore : nombres finis, chaînes UTF-8 courtes, profondeur et taille bornées
local function clean(value, depth)
	local kind = type(value)
	if kind == "number" then
		return (value == value and math.abs(value) < math.huge) and value or 0
	elseif kind == "boolean" then
		return value
	elseif kind == "string" then
		if not utf8.len(value) then value = string.gsub(value, "[\128-\255]", "?") end
		local cut = utf8.offset(value, 121)
		return cut and string.sub(value, 1, cut - 1) or value
	elseif kind == "table" and (depth or 0) < 4 then
		local copy, count = {}, 0
		for key, item in value do
			count += 1
			if count > 40 then break end
			if type(key) == "string" or type(key) == "number" then
				local cleaned = clean(item, (depth or 0) + 1)
				if cleaned ~= nil then copy[key] = cleaned end
			end
		end
		return copy
	end
	return nil
end

local function mode()
	if Ranks and Ranks.GetStore() then return "DataStore" end
	if Ranks and Ranks.Memory == true then return "Memory" end
	return "Unavailable"
end

local function readKey(key)
	local current = mode()
	if current == "Memory" then
		return true, deepCopy(memory[key])
	elseif current == "DataStore" then
		local store = Ranks.GetStore()
		local ok, value = pcall(store.GetAsync, store, key)
		if ok then return true, value end
		status.LastError = string.sub(tostring(value), 1, 160)
		return false, nil
	end
	return false, nil
end

-- transform(old) -> nouvelle valeur, ou nil pour annuler. Renvoie ok, valeur écrite.
local function updateKey(key, transform)
	local current = mode()
	if current == "Memory" then
		local result = transform(deepCopy(memory[key]))
		if result == nil then return false, nil end
		memory[key] = deepCopy(result)
		return true, deepCopy(result)
	elseif current == "DataStore" then
		local store = Ranks.GetStore()
		local ok, result = pcall(store.UpdateAsync, store, key, transform)
		if ok and result ~= nil then return true, result end
		if not ok then status.LastError = string.sub(tostring(result), 1, 160) end
		return false, nil
	end
	return false, nil
end

local function cutoff()
	return os.time() - policy.RetentionDays * 86400
end
local function decayed(summary, now)
	local age = math.max(0, now - (tonumber(summary.t) or now))
	return (tonumber(summary.s) or 0) * 0.5 ^ (age / math.max(60, policy.HalfLife))
end

-- Ôte de l'index ce qui dépasse la rétention puis les fiches les moins suspectes au-delà de MAX_INDEX
local function pruneIndex(players)
	local limit, now = cutoff(), os.time()
	local count = 0
	for key, summary in players do
		if type(summary) ~= "table" or (tonumber(summary.t) or 0) < limit then
			players[key] = nil
		else
			count += 1
		end
	end
	if count > MAX_INDEX then
		local list = {}
		for key, summary in players do table.insert(list, { key, decayed(summary, now), tonumber(summary.t) or 0 }) end
		table.sort(list, function(a, b)
			if a[2] ~= b[2] then return a[2] > b[2] end
			return a[3] > b[3]
		end)
		for index = MAX_INDEX + 1, #list do players[list[index][1]] = nil end
	end
end

local function packEvent(event, reaction)
	serial += 1
	local why = {}
	for index, item in type(event.Why) == "table" and event.Why or {} do
		if index > 8 then break end
		if type(item) == "table" and type(item.Code) == "string" then
			table.insert(why, { c = item.Code, v = clean(item.V) })
		end
	end
	return { i = jobShort .. "-" .. serial, t = tonumber(event.Time) or os.time(), k = tostring(event.Kind), o = tostring(event.Origin),
		c = tostring(event.Confidence or "Low"), w = why, d = clean(event.Data) or {}, r = tostring(reaction or "Logged"), j = jobShort }
end

local function unpackEvent(item)
	local why = {}
	for _, entry in type(item.w) == "table" and item.w or {} do
		if type(entry) == "table" and type(entry.c) == "string" then table.insert(why, { Code = entry.c, V = entry.v }) end
	end
	return { Id = item.i, Time = item.t, Kind = item.k, Origin = item.o, Confidence = item.c, Why = why, Data = item.d or {}, Reaction = item.r, Server = item.j }
end

----------------------------------------------------------------------------------------------------------

function Store.Init(context)
	ctx = context
	Ranks = ctx.Ranks
	jobShort = game.JobId ~= "" and string.sub(game.JobId, 1, 8) or "studio"
end

-- policy : { Persist, RetentionDays, HalfLife (secondes) }
function Store.SetPolicy(newPolicy)
	if type(newPolicy) ~= "table" then return end
	if type(newPolicy.Persist) == "boolean" then policy.Persist = newPolicy.Persist end
	if tonumber(newPolicy.RetentionDays) then policy.RetentionDays = math.clamp(math.floor(newPolicy.RetentionDays), 1, 365) end
	if tonumber(newPolicy.HalfLife) then policy.HalfLife = math.max(60, newPolicy.HalfLife) end
end

function Store.Mode()
	return mode()
end

-- Met une infraction en file ; l'écriture groupée part quelques secondes plus tard
function Store.Record(player, event, score, reaction)
	if not policy.Persist or mode() == "Unavailable" then return end
	local entry = pending[player.UserId]
	if not entry then
		entry = { Events = {} }
		pending[player.UserId] = entry
	end
	entry.Name, entry.Display, entry.Score = player.Name, player.DisplayName, math.floor((tonumber(score) or 0) + 0.5)
	table.insert(entry.Events, 1, packEvent(event, reaction))
	while #entry.Events > MAX_EVENTS do table.remove(entry.Events) end
	if not flushScheduled then
		flushScheduled = true
		task.delay(WRITE_DELAY, function()
			flushScheduled = false
			Store.Flush()
		end)
	end
end

function Store.Audit(player, action, detail)
	if mode() == "Unavailable" then return end
	table.insert(pendingAudit, 1, { t = os.time(), by = string.sub(player.Name, 1, 40), id = player.UserId, a = tostring(action),
		d = clean(tostring(detail or "")), j = jobShort })
	while #pendingAudit > MAX_AUDIT do table.remove(pendingAudit) end
	task.spawn(Store.Flush)
end

-- Écrit tout ce qui attend. Renvoie true si tout est passé (ou s'il n'y avait rien à écrire).
function Store.Flush(force)
	if flushing then return false end
	local current = mode()
	if current == "Unavailable" then return false end
	if next(pending) == nil and #pendingAudit == 0 and next(removeQueue) == nil and not clearAll then return true end
	if force ~= true and os.clock() - lastFlushAt < MIN_FLUSH_GAP and not clearAll and next(removeQueue) == nil and #pendingAudit == 0 then
		-- trop tôt : on réessaie à la fin du délai (le minuteur de Record s'en charge)
		if not flushScheduled then
			flushScheduled = true
			task.delay(MIN_FLUSH_GAP, function()
				flushScheduled = false
				Store.Flush()
			end)
		end
		return false
	end
	flushing = true
	lastFlushAt = os.clock()
	local allOk = true
	local summaries, removed = {}, {}

	-- fiches des joueurs (au plus FLUSH_PLAYERS par cycle)
	local handled = 0
	for userId, entry in pending do
		if handled >= FLUSH_PLAYERS then break end
		handled += 1
		local batch = table.clone(entry.Events)
		if #batch == 0 then
			pending[userId] = nil
		else
			local name, display, score = entry.Name, entry.Display, entry.Score
			local ok, record = updateKey(PREFIX .. userId, function(old)
				if old ~= nil and type(old) ~= "table" then return nil end
				if type(old) == "table" and (tonumber(old.v) or SCHEMA) > SCHEMA then return nil end
				local rec = (type(old) == "table" and not old.gone) and old or { v = SCHEMA, id = userId, c = 0, k = {}, e = {} }
				rec.e = type(rec.e) == "table" and rec.e or {}
				rec.k = type(rec.k) == "table" and rec.k or {}
				local known = {}
				for _, existing in rec.e do
					if type(existing) == "table" and existing.i then known[existing.i] = true end
				end
				local added = 0
				for _, event in batch do
					if not known[event.i] then
						table.insert(rec.e, event)
						rec.k[event.k] = (tonumber(rec.k[event.k]) or 0) + 1
						rec.t = math.max(tonumber(rec.t) or 0, event.t)
						rec.f = math.min(tonumber(rec.f) or event.t, event.t)
						added += 1
					end
				end
				rec.c = (tonumber(rec.c) or 0) + added
				table.sort(rec.e, function(a, b) return (tonumber(a.t) or 0) > (tonumber(b.t) or 0) end)
				local limit, kept = cutoff(), {}
				for _, event in rec.e do
					if #kept < MAX_EVENTS and (tonumber(event.t) or 0) >= limit then table.insert(kept, event) end
				end
				rec.e = kept
				rec.n, rec.d, rec.s = name, display, score
				return rec
			end)
			if ok and type(record) == "table" then
				-- retire de la file les événements écrits ; ceux arrivés pendant l'écriture restent
				local queued = pending[userId]
				if queued then
					for _, written in batch do
						local at = table.find(queued.Events, written)
						if at then table.remove(queued.Events, at) end
					end
					if #queued.Events == 0 then pending[userId] = nil end
				end
				detailCache[userId] = nil
				local last = record.e and record.e[1]
				summaries[userId] = { n = record.n, d = record.d, f = record.f, t = record.t, c = record.c, k = record.k, s = record.s,
					o = last and last.o or nil, cf = last and last.c or nil }
			else
				allOk = false
			end
		end
	end

	-- fiches à effacer (pierre tombale) et index
	local removedCount = 0
	for userId in removeQueue do
		if removedCount >= REMOVE_PER_CYCLE then break end
		removedCount += 1
		local ok = updateKey(PREFIX .. userId, function(old)
			if type(old) == "table" and (tonumber(old.v) or SCHEMA) > SCHEMA then return nil end
			return { v = SCHEMA, gone = os.time() }
		end)
		if ok then
			removeQueue[userId] = nil
			removed[userId] = true
			detailCache[userId] = nil
		else
			allOk = false
		end
	end
	if next(summaries) ~= nil or next(removed) ~= nil or clearAll then
		local wipe = clearAll
		local ok, result = updateKey(INDEX_KEY, function(old)
			if old ~= nil and type(old) ~= "table" then return nil end
			if type(old) == "table" and (tonumber(old.v) or SCHEMA) > SCHEMA then return nil end
			local index = type(old) == "table" and old or { v = SCHEMA, p = {} }
			index.p = (not wipe and type(index.p) == "table") and index.p or {}
			for userId, summary in summaries do index.p[tostring(userId)] = summary end
			for userId in removed do index.p[tostring(userId)] = nil end
			pruneIndex(index.p)
			return index
		end)
		if ok and type(result) == "table" then
			indexCache, indexAt = result.p or {}, os.clock()
			if wipe then clearAll = false end
		else
			allOk = false
		end
	end

	-- journal des réglages
	if #pendingAudit > 0 then
		local batch = table.clone(pendingAudit)
		local ok = updateKey(AUDIT_KEY, function(old)
			if old ~= nil and type(old) ~= "table" then return nil end
			local data = type(old) == "table" and old or { v = SCHEMA, l = {} }
			data.l = type(data.l) == "table" and data.l or {}
			for index = #batch, 1, -1 do table.insert(data.l, 1, batch[index]) end
			while #data.l > MAX_AUDIT do table.remove(data.l) end
			return data
		end)
		if ok then
			for _, written in batch do
				local at = table.find(pendingAudit, written)
				if at then table.remove(pendingAudit, at) end
			end
			auditCache = nil
		else
			allOk = false
		end
	end

	if allOk then
		status.LastWrite, status.LastError = os.time(), nil
		status.Writes += 1
	end
	flushing = false
	-- il en reste (plus de FLUSH_PLAYERS joueurs, effacements nombreux) : un autre cycle
	if next(pending) ~= nil or next(removeQueue) ~= nil then
		if not flushScheduled then
			flushScheduled = true
			task.delay(MIN_FLUSH_GAP, function()
				flushScheduled = false
				Store.Flush()
			end)
		end
	end
	return allOk
end

-- Résumé de toutes les fiches enregistrées : { [userIdTexte] = { n, d, f, t, c, k, s, o, cf } }
function Store.Index(force)
	if mode() == "Unavailable" then return {} end
	if force or not indexCache or os.clock() - indexAt > INDEX_TTL then
		indexAt = os.clock() -- évite que plusieurs lectures partent ensemble
		local ok, data = readKey(INDEX_KEY)
		if ok then
			if type(data) == "table" and type(data.p) == "table" then
				indexCache = data.p
			elseif data == nil then
				indexCache = indexCache or {}
			end
		end
	end
	local view = {}
	for key, summary in indexCache or {} do
		if not removeQueue[tonumber(key)] and not clearAll then view[key] = summary end
	end
	-- les fiches en attente d'écriture comptent déjà
	for userId, entry in pending do
		local previous = view[tostring(userId)]
		local last = entry.Events[1]
		if last then
			local kinds = previous and deepCopy(previous.k) or {}
			for _, event in entry.Events do kinds[event.k] = (tonumber(kinds[event.k]) or 0) + 1 end
			view[tostring(userId)] = { n = entry.Name, d = entry.Display, f = previous and previous.f or entry.Events[#entry.Events].t, t = last.t,
				c = (previous and tonumber(previous.c) or 0) + #entry.Events, k = kinds, s = entry.Score, o = last.o, cf = last.c }
		end
	end
	return view
end

-- Événements détaillés d'un joueur (écrits + en attente), du plus récent au plus ancien
function Store.Details(userId)
	if mode() == "Unavailable" then return {} end
	local cached = detailCache[userId]
	local stored = {}
	if cached and os.clock() - cached.At < DETAIL_TTL then
		stored = cached.Events
	else
		local ok, record = readKey(PREFIX .. userId)
		if ok and type(record) == "table" and not record.gone and type(record.e) == "table" then stored = record.e end
		detailCache[userId] = { At = os.clock(), Events = stored }
	end
	local list, seen = {}, {}
	local entry = pending[userId]
	for _, event in entry and entry.Events or {} do
		seen[event.i] = true
		table.insert(list, unpackEvent(event))
	end
	for _, event in stored do
		if type(event) == "table" and not seen[event.i] then table.insert(list, unpackEvent(event)) end
	end
	table.sort(list, function(a, b) return (tonumber(a.Time) or 0) > (tonumber(b.Time) or 0) end)
	return list
end

function Store.Remove(userId)
	pending[userId] = nil
	detailCache[userId] = nil
	removeQueue[userId] = true
	task.spawn(Store.Flush)
end

function Store.RemoveAll()
	local ok, data = readKey(INDEX_KEY)
	if ok and type(data) == "table" and type(data.p) == "table" then
		for key in data.p do
			local userId = tonumber(key)
			if userId then removeQueue[userId] = true end
		end
	end
	for userId in pending do removeQueue[userId] = true end
	table.clear(pending)
	table.clear(detailCache)
	clearAll = true
	task.spawn(Store.Flush)
end

-- Journal des réglages (récent d'abord), lecture mise en cache
function Store.GetAudit()
	if mode() == "Unavailable" then return {} end
	if not auditCache or os.clock() - auditAt > AUDIT_TTL then
		auditAt = os.clock()
		local ok, data = readKey(AUDIT_KEY)
		if ok then auditCache = (type(data) == "table" and type(data.l) == "table") and data.l or {} end
	end
	local list = {}
	for _, item in pendingAudit do table.insert(list, item) end
	for _, item in auditCache or {} do table.insert(list, item) end
	local result = {}
	for index, item in list do
		if index > 20 then break end
		if type(item) == "table" then table.insert(result, deepCopy(item)) end
	end
	return result
end

function Store.Status()
	local events = 0
	for _, entry in pending do events += #entry.Events end
	local stored = 0
	for _ in indexCache or {} do stored += 1 end
	return { Mode = mode(), Persist = policy.Persist, RetentionDays = policy.RetentionDays, Stored = stored, PendingPlayers = (function()
		local n = 0
		for _ in pending do n += 1 end
		return n
	end)(), PendingEvents = events, LastWrite = status.LastWrite, Writes = status.Writes, LastError = status.LastError }
end

return Store
