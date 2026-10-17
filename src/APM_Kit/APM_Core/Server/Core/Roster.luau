--[[
	Roster : annuaire de tous les joueurs venus dans le jeu (onglet Joueurs, portée « Global » ; dernière visite dans le profil).
	Chaque serveur fusionne ses visites dans la clé DataStore "Roster". Le contrat enregistré reste { n, d, t }.
	Settings.MaxRoster limite l'historique; les joueurs actuellement présents restent visibles dans la liste.
]]
local Players = game:GetService("Players")
local Roster = {}
local FLUSH_SECONDS, FLUSH_JITTER, CACHE_SECONDS, LIST_SECONDS = 300, 60, 60, 5
local Ranks
local maxEntries = 20000
local seen, seenCount, inFlight = {}, 0, nil
local cache, cacheAt, cacheRevision = {}, -math.huge, 0
local listCache, listAt = nil, -math.huge
local flushing = false
local pruneRequested = false

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function entryLimit(value)
	local maximum = tonumber(value)
	if not finite(maximum) then return 20000 end
	return math.clamp(math.floor(maximum), 0, 20000)
end
local function userId(value)
	if type(value) ~= "number" and type(value) ~= "string" then return nil end
	local id = tonumber(value)
	return finite(id) and id ~= 0 and id % 1 == 0 and math.abs(id) < 2 ^ 53 and id or nil
end
local function name(value, fallback)
	if type(value) ~= "string" or #value == 0 or #value > 256 or not utf8.len(value) then return fallback end
	local cut = utf8.offset(value, 65)
	return cut and value:sub(1, cut - 1) or value
end
local function cleanEntry(id, entry)
	if type(entry) ~= "table" then return nil end
	local n = name(entry.n, tostring(id))
	local d = name(entry.d, nil)
	local t = finite(entry.t) and math.clamp(math.floor(entry.t), 0, 2 ^ 53 - 1) or 0
	return { n = n, d = d ~= n and d or nil, t = t }
end
local function merge(map, key, entry)
	local previous = map[key]
	if not previous or entry.t >= previous.t then map[key] = entry end
end
local function cleanMap(data)
	local map = {}
	for key, entry in type(data) == "table" and data or {} do
		local id = userId(key)
		local clean = id and cleanEntry(id, entry)
		if clean then merge(map, tostring(id), clean) end
	end
	return map
end
local function prune(map, maximum)
	local list = {}
	for key, entry in map do table.insert(list, { Key = key, Time = entry.t }) end
	if #list > maximum then
		table.sort(list, function(a, b)
			if a.Time ~= b.Time then return a.Time < b.Time end
			return tostring(a.Key) < tostring(b.Key)
		end)
		for index = 1, #list - maximum do map[list[index].Key] = nil end
	end
	return math.min(#list, maximum)
end
local function note(player)
	listCache = nil
	local id = userId(player.UserId)
	if not id then return end
	if maxEntries == 0 then pruneRequested = true; return end
	if not seen[id] then seenCount += 1 end
	seen[id] = cleanEntry(id, { n = player.Name, d = player.DisplayName, t = os.time() })
	if seenCount > maxEntries then
		-- One insertion exceeds the bound by at most one; avoid sorting the whole history on every join.
		local oldest, oldestAt
		for key, entry in seen do
			if oldest == nil or entry.t < oldestAt or (entry.t == oldestAt and key < oldest) then oldest, oldestAt = key, entry.t end
		end
		seen[oldest] = nil
		seenCount -= 1
	end
end

local function flush()
	local store = Ranks and Ranks.GetStore()
	if flushing or (not next(seen) and not pruneRequested) or not store then return end
	flushing = true
	local batch, pruning = seen, pruneRequested
	pruneRequested = false
	seen, seenCount, inFlight = {}, 0, batch
	local ok, result = pcall(store.UpdateAsync, store, "Roster", function(old)
		local map = cleanMap(old)
		for id, entry in batch do merge(map, tostring(id), entry) end
		prune(map, maxEntries)
		return map
	end)
	if ok and type(result) == "table" then
		cache = cleanMap(result)
		prune(cache, maxEntries)
		cacheAt, cacheRevision = os.clock(), cacheRevision + 1
		listCache = nil
	else
		warn("[APM] Annuaire non enregistré : " .. tostring(result))
		pruneRequested = pruneRequested or pruning
		for id, entry in batch do
			-- A visit noted during UpdateAsync takes precedence over the older in-flight batch.
			if not seen[id] or entry.t > seen[id].t then seen[id] = entry end
		end
		seenCount = prune(seen, maxEntries)
		listCache = nil
	end
	inFlight = nil
	flushing = false
end

local function refreshCache()
	local store = Ranks and Ranks.GetStore()
	if store and os.clock() - cacheAt > CACHE_SECONDS then
		local revision = cacheRevision
		cacheAt = os.clock()
		local ok, data = pcall(store.GetAsync, store, "Roster")
		-- A read begun before a newer flush/read must not replace that newer cache.
		if ok and type(data) == "table" and revision == cacheRevision then
			cache = cleanMap(data)
			prune(cache, maxEntries)
			cacheRevision += 1
			listCache = nil
		end
	end
end

function Roster.Get(value)
	local id = userId(value)
	if not id then return nil end
	local entry = seen[id] or (inFlight and inFlight[id])
	if not entry then
		refreshCache()
		entry = cache[tostring(id)]
	end
	return entry and table.clone(entry) or nil
end
local function copyList(list)
	local copy = {}
	for index, entry in list do copy[index] = table.clone(entry) end
	return copy
end
function Roster.List()
	if listCache and os.clock() - listAt < LIST_SECONDS then return copyList(listCache) end
	refreshCache()
	local map = cleanMap(cache)
	for id, entry in inFlight or {} do merge(map, tostring(id), entry) end
	for id, entry in seen do merge(map, tostring(id), entry) end
	prune(map, maxEntries)
	local online = {}
	for _, player in Players:GetPlayers() do
		local id = userId(player.UserId)
		if id then
			online[id] = true
			map[tostring(id)] = cleanEntry(id, { n = player.Name, d = player.DisplayName, t = os.time() })
		end
	end
	local list = {}
	for key, entry in map do
		local id = tonumber(key)
		table.insert(list, { userId = id, name = entry.n, displayName = entry.d or entry.n,
			online = online[id] == true, lastSeen = online[id] and os.time() or entry.t })
	end
	table.sort(list, function(a, b)
		if a.online ~= b.online then return a.online end
		if a.lastSeen ~= b.lastSeen then return a.lastSeen > b.lastSeen end
		return a.userId < b.userId
	end)
	listCache, listAt = list, os.clock()
	return copyList(list)
end

function Roster.Init(ranks, settings)
	Ranks = ranks
	maxEntries = entryLimit(settings and settings.MaxRoster)
	for _, player in Players:GetPlayers() do note(player) end
	Players.PlayerAdded:Connect(note)
	Players.PlayerRemoving:Connect(note)
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS + math.random() * FLUSH_JITTER)
			flush()
		end
	end)
	game:BindToClose(flush)
end
return Roster
