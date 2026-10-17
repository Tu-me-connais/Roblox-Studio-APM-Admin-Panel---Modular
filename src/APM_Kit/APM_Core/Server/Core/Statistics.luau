--[[
	Statistics : relevés de l'onglet Stats (utilisation des commandes, joueurs, rendement du serveur, DataStores sollicités).
	Tout reste en mémoire sur CE serveur : aucune écriture DataStore, aucun envoi externe. L'historique repart de zéro à chaque serveur.

	DataStores : le DataStore de l'APM est compté automatiquement (voir Ranks). Pour suivre ceux de ton jeu :
	  local store = APM.TrackDataStore(DataStoreService:GetDataStore("PlayerData"), "PlayerData")
	  -- s'utilise exactement comme le DataStore d'origine (store:GetAsync(...), store:UpdateAsync(...) ...)
	Les clés sont regroupées (chiffres remplacés par #) : « Player_123 » et « Player_456 » comptent pour « Player_# ».
]]
local Statistics = { SampleSeconds = 15, HistorySize = 120, StoreLimit = 16, KeyLimit = 60, ActionLimit = 80, ActorLimit = 80 }

local READS = { GetAsync = true, GetVersionAsync = true, GetVersionAtTimeAsync = true, ListKeysAsync = true, ListVersionsAsync = true, GetSortedAsync = true }
local WRITES = { SetAsync = true, UpdateAsync = true, IncrementAsync = true, RemoveAsync = true, RemoveVersionAsync = true }

local stores, storeCount = {}, 0
local actions, actionCount = {}, 0
local actors, actorCount = {}, 0
local pending = { Actions = 0, Failures = 0, Calls = 0, Errors = 0, Joins = 0, Leaves = 0 }
local totals = { Actions = 0, Failures = 0, Calls = 0, Errors = 0 }
local history = {}
local started = false

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function short(value, limit)
	value = tostring(value)
	if not utf8.len(value) then return "?" end
	local finish = utf8.offset(value, limit + 1)
	return finish and value:sub(1, finish - 1) or value
end

local function keyGroup(key)
	if type(key) ~= "string" then return "(liste)" end
	return short((key:gsub("%-?%d+", "#")), 48)
end

local function record(storeName, method, key, ok, seconds)
	-- Global counters remain exact even when per-store metadata is capped.
	pending.Calls += 1
	totals.Calls += 1
	if not ok then
		pending.Errors += 1
		totals.Errors += 1
	end
	local entry = stores[storeName]
	if not entry then
		if storeCount >= Statistics.StoreLimit then return end
		storeCount += 1
		entry = { Name = storeName, Reads = 0, Writes = 0, Other = 0, Errors = 0, TotalMs = 0, Keys = {}, KeyCount = 0 }
		stores[storeName] = entry
	end
	local kind = READS[method] and "Reads" or WRITES[method] and "Writes" or "Other"
	entry[kind] += 1
	entry.TotalMs += seconds * 1000
	entry.LastAt = os.time()
	local group = keyGroup(key)
	local keyEntry = entry.Keys[group]
	if not keyEntry and entry.KeyCount < Statistics.KeyLimit then
		entry.KeyCount += 1
		keyEntry = { Key = group, Reads = 0, Writes = 0, Other = 0, Errors = 0 }
		entry.Keys[group] = keyEntry
	end
	if keyEntry then keyEntry[kind] += 1 end
	if not ok then
		entry.Errors += 1
		if keyEntry then keyEntry.Errors += 1 end
	end
end

-- Renvoie un objet qui s'utilise comme le DataStore d'origine et compte chaque appel (méthode, clé, erreurs, durée).
function Statistics.WrapDataStore(store, name)
	if typeof(store) ~= "Instance" or not store:IsA("GlobalDataStore") then return store end
	local storeName = short(type(name) == "string" and name ~= "" and name or store.Name, 64)
	local proxy = {}
	return setmetatable(proxy, {
		__index = function(_, member)
			local value = store[member]
			if type(value) ~= "function" then return value end
			local function wrapped(self, ...)
				if self == proxy then self = store end
				local key = ...
				local startedAt = os.clock()
				local result = table.pack(pcall(value, self, ...))
				record(storeName, member, key, result[1], os.clock() - startedAt)
				if not result[1] then error(result[2], 0) end
				return table.unpack(result, 2, result.n)
			end
			rawset(proxy, member, wrapped)
			return wrapped
		end,
		__tostring = function() return tostring(store) end,
	})
end

-- Une commande exécutée depuis le panneau (appelé par APMService après Execute)
function Statistics.RecordAction(moduleName, category, actorName, success)
	if type(moduleName) ~= "string" then return end
	local entry = actions[moduleName]
	if not entry and actionCount < Statistics.ActionLimit then
		actionCount += 1
		entry = { Name = moduleName, Category = type(category) == "string" and category or nil, Count = 0, Failures = 0 }
		actions[moduleName] = entry
	end
	if entry then
		entry.Count += 1
		entry.LastAt = os.time()
		if success == false then entry.Failures += 1 end
	end
	if type(actorName) == "string" then
		local actor = actors[actorName]
		if not actor and actorCount < Statistics.ActorLimit then
			actorCount += 1
			actor = { Name = short(actorName, 40), Count = 0 }
			actors[actorName] = actor
		end
		if actor then actor.Count += 1 end
	end
	pending.Actions += 1
	totals.Actions += 1
	if success == false then
		pending.Failures += 1
		totals.Failures += 1
	end
end

-- Cycle serveur moyen sur les 5 dernières secondes (lu aussi par l'Accueil : un seul compteur par image pour tout l'APM)
local windowHz = nil
function Statistics.HeartbeatHz()
	return windowHz
end

function Statistics.Start(services)
	if started then return end
	started = true
	services = services or {}
	local Players = services.Players or game:GetService("Players")
	local RunService = services.RunService or game:GetService("RunService")
	local Stats = services.Stats or game:GetService("Stats")
	local sessions, finished = {}, {}
	local seen, uniqueCount, newAccounts, joins, leaves, peak = {}, 0, 0, 0, 0, 0
	local frames, frameSeconds = 0, 0
	local function arrive(player)
		if sessions[player] then return end
		sessions[player] = os.clock()
		joins += 1
		pending.Joins += 1
		if not seen[player.UserId] then
			seen[player.UserId] = true
			uniqueCount += 1
			if player.AccountAge < 7 then newAccounts += 1 end
		end
		peak = math.max(peak, #Players:GetPlayers())
	end
	Players.PlayerAdded:Connect(arrive)
	Players.PlayerRemoving:Connect(function(player)
		local since = sessions[player]
		if not since then return end
		sessions[player] = nil
		leaves += 1
		pending.Leaves += 1
		table.insert(finished, os.clock() - since)
		if #finished > 500 then table.remove(finished, 1) end
	end)
	for _, player in Players:GetPlayers() do arrive(player) end
	local windowFrames, windowSeconds = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		if finite(dt) and dt > 0 then
			frames += 1
			frameSeconds += dt
			windowFrames += 1
			windowSeconds += dt
			if windowSeconds >= 5 then
				windowHz = windowFrames / windowSeconds
				windowFrames, windowSeconds = 0, 0
			end
		end
	end)

	local function read(callback)
		local ok, value = pcall(callback)
		return ok and finite(value) and value or nil
	end
	local function sample()
		local online = Players:GetPlayers()
		local pingSum, pingCount = 0, 0
		for _, player in online do
			local ping = read(function() return player:GetNetworkPing() * 1000 end)
			if ping and ping >= 0 then pingSum += ping pingCount += 1 end
		end
		local point = {
			Time = os.time(), Players = #online, PingMs = pingCount > 0 and pingSum / pingCount or nil,
			HeartbeatHz = frameSeconds > 0 and frames / frameSeconds or nil,
			MemoryMb = read(function() return Stats:GetTotalMemoryUsageMb() end),
			ReceiveKbps = read(function() return Stats.DataReceiveKbps end), SendKbps = read(function() return Stats.DataSendKbps end),
			Instances = read(function() return Stats.InstanceCount end),
			Actions = pending.Actions, Failures = pending.Failures, Calls = pending.Calls, Errors = pending.Errors,
			Joins = pending.Joins, Leaves = pending.Leaves,
		}
		frames, frameSeconds = 0, 0
		for key in pending do pending[key] = 0 end
		table.insert(history, point)
		if #history > Statistics.HistorySize then table.remove(history, 1) end
	end
	task.spawn(function()
		while true do
			task.wait(Statistics.SampleSeconds)
			local ok, problem = pcall(sample)
			if not ok then warn("[APM] Statistiques : " .. tostring(problem)) end
		end
	end)

	function Statistics.PlayerSummary()
		local online = Players:GetPlayers()
		local now = os.clock()
		local buckets = { 0, 0, 0, 0, 0 } -- < 5 min, 5-15, 15-30, 30-60, > 60
		local sum, longest = 0, 0
		for _, seconds in finished do
			sum += seconds
			longest = math.max(longest, seconds)
			local minutes = seconds / 60
			local index = minutes < 5 and 1 or minutes < 15 and 2 or minutes < 30 and 3 or minutes < 60 and 4 or 5
			buckets[index] += 1
		end
		local current = {}
		for _, player in online do
			local since = sessions[player]
			if since then table.insert(current, { Name = player.Name, DisplayName = player.DisplayName, Seconds = math.floor(now - since) }) end
		end
		table.sort(current, function(a, b) return a.Seconds > b.Seconds end)
		for index = #current, 6, -1 do current[index] = nil end
		return {
			Online = #online, Peak = math.max(peak, #online), Joins = joins, Leaves = leaves, Unique = uniqueCount, NewAccounts = newAccounts,
			AverageSessionSeconds = #finished > 0 and sum / #finished or nil, LongestSessionSeconds = #finished > 0 and longest or nil,
			FinishedSessions = #finished, SessionBuckets = buckets, LongestOnline = current,
		}
	end
end

local function sortedValues(map, compare, limit)
	local list = {}
	for _, value in map do table.insert(list, table.clone(value)) end
	table.sort(list, compare)
	for index = #list, limit + 1, -1 do list[index] = nil end
	return list
end

local function budgets()
	local list = {}
	local DataStoreService = game:GetService("DataStoreService")
	for _, kind in { "GetAsync", "SetIncrementAsync", "UpdateAsync", "GetSortedAsync", "SetIncrementSortedAsync" } do
		local ok, value = pcall(function() return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType[kind]) end)
		if ok and finite(value) then table.insert(list, { Kind = kind, Budget = value }) end
	end
	return list
end

-- sections : { Usage = bool, Players = bool, Performance = bool, DataStores = bool } (droits déjà vérifiés par l'appelant)
function Statistics.Snapshot(sections)
	local points = {}
	for index, point in history do
		local copy = { Time = point.Time }
		if sections.Players then copy.Players, copy.PingMs, copy.Joins, copy.Leaves = point.Players, point.PingMs, point.Joins, point.Leaves end
		if sections.Usage then copy.Actions, copy.Failures = point.Actions, point.Failures end
		if sections.Performance then
			copy.HeartbeatHz, copy.MemoryMb, copy.ReceiveKbps, copy.SendKbps, copy.Instances = point.HeartbeatHz, point.MemoryMb, point.ReceiveKbps, point.SendKbps, point.Instances
		end
		if sections.DataStores then copy.Calls, copy.Errors = point.Calls, point.Errors end
		points[index] = copy
	end
	local snapshot = { SchemaVersion = 1, GeneratedAt = os.time(), SampleSeconds = Statistics.SampleSeconds, HistorySize = Statistics.HistorySize, History = points }
	if sections.Usage then
		snapshot.Usage = {
			Total = totals.Actions, Failures = totals.Failures,
			Modules = sortedValues(actions, function(a, b) return a.Count > b.Count or (a.Count == b.Count and a.Name < b.Name) end, 12),
			Actors = sortedValues(actors, function(a, b) return a.Count > b.Count or (a.Count == b.Count and a.Name < b.Name) end, 8),
		}
	end
	if sections.Players and Statistics.PlayerSummary then snapshot.Players = Statistics.PlayerSummary() end
	if sections.DataStores then
		local list, keys = {}, {}
		for _, entry in stores do
			local calls = entry.Reads + entry.Writes + entry.Other
			table.insert(list, { Name = entry.Name, Reads = entry.Reads, Writes = entry.Writes, Other = entry.Other, Errors = entry.Errors,
				Calls = calls, AverageMs = calls > 0 and entry.TotalMs / calls or nil, LastAt = entry.LastAt })
			for _, key in entry.Keys do
				table.insert(keys, { Store = entry.Name, Key = key.Key, Reads = key.Reads, Writes = key.Writes, Errors = key.Errors, Calls = key.Reads + key.Writes + key.Other })
			end
		end
		table.sort(list, function(a, b) return a.Calls > b.Calls or (a.Calls == b.Calls and a.Name < b.Name) end)
		table.sort(keys, function(a, b) return a.Calls > b.Calls or (a.Calls == b.Calls and a.Key < b.Key) end)
		for index = #keys, 11, -1 do keys[index] = nil end
		snapshot.DataStores = { Total = totals.Calls, Errors = totals.Errors, Stores = list, Keys = keys, Budgets = budgets() }
	end
	return snapshot
end

return Statistics
