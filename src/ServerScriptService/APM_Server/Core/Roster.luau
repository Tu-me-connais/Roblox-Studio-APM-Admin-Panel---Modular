--[[
	Roster : annuaire de tous les joueurs venus dans le jeu (onglet Joueurs, portée « Global » ; dernière visite dans le profil).

	Chaque serveur note les joueurs qu'il voit (nom, pseudo, dernière visite) et fusionne ces notes dans le DataStore de l'APM
	(clé "Roster") toutes les FLUSH_SECONDS et au départ d'un joueur. Limité à Settings.MaxRoster comptes (les plus anciens tombent).
]]
local Players = game:GetService("Players")

local Roster = {}

local FLUSH_SECONDS = 120
local CACHE_SECONDS = 30

local Ranks
local maxEntries = 20000
local seen = {} -- [userId] = { n, d, t } vus par ce serveur, pas encore enregistrés
local cache, cacheAt = {}, -math.huge
local flushing = false

local function note(player)
	seen[player.UserId] = { n = player.Name, d = player.DisplayName, t = os.time() }
end

local function flush()
	local store = Ranks and Ranks.GetStore()
	if flushing or not next(seen) or not store then
		return
	end
	flushing = true
	local batch = seen
	seen = {}
	local ok, result = pcall(store.UpdateAsync, store, "Roster", function(old)
		local map = type(old) == "table" and old or {}
		for userId, entry in batch do
			map[tostring(userId)] = entry
		end
		local count = 0
		for _ in map do
			count += 1
		end
		if count > maxEntries then -- au-delà de la limite, les visites les plus anciennes tombent
			local list = {}
			for key, entry in map do
				table.insert(list, { key, type(entry) == "table" and entry.t or 0 })
			end
			table.sort(list, function(a, b)
				return a[2] < b[2]
			end)
			for index = 1, count - maxEntries do
				map[list[index][1]] = nil
			end
		end
		return map
	end)
	if ok and type(result) == "table" then
		cache, cacheAt = result, os.clock()
	else
		warn("[APM] Annuaire non enregistré : " .. tostring(result))
		for userId, entry in batch do
			if not seen[userId] then
				seen[userId] = entry
			end
		end
	end
	flushing = false
end

local function refreshCache()
	local store = Ranks and Ranks.GetStore()
	if store and os.clock() - cacheAt > CACHE_SECONDS then
		cacheAt = os.clock()
		local ok, data = pcall(store.GetAsync, store, "Roster")
		if ok and type(data) == "table" then
			cache = data
		end
	end
end

-- Une fiche de l'annuaire : { n = nom, d = pseudo, t = dernière visite } ou nil
function Roster.Get(userId)
	if seen[userId] then
		return seen[userId]
	end
	refreshCache()
	local entry = cache[tostring(userId)]
	return type(entry) == "table" and entry or nil
end

-- L'annuaire : { { userId, name, displayName, online, lastSeen }, ... } (en ligne d'abord, puis par dernière visite)
function Roster.List()
	refreshCache()
	local map = {}
	for key, entry in cache do
		local userId = tonumber(key)
		if userId and type(entry) == "table" then
			map[userId] = entry
		end
	end
	for userId, entry in seen do
		map[userId] = entry
	end
	for _, player in Players:GetPlayers() do
		if not map[player.UserId] then
			map[player.UserId] = { n = player.Name, d = player.DisplayName, t = os.time() }
		end
	end
	local list = {}
	for userId, entry in map do
		local online = Players:GetPlayerByUserId(userId) ~= nil
		table.insert(list, {
			userId = userId,
			name = entry.n or tostring(userId),
			displayName = entry.d or entry.n or tostring(userId),
			online = online,
			lastSeen = online and os.time() or entry.t or 0,
		})
	end
	table.sort(list, function(a, b)
		if a.online ~= b.online then
			return a.online
		end
		return a.lastSeen > b.lastSeen
	end)
	return list
end

function Roster.Init(ranks, settings)
	Ranks = ranks
	maxEntries = tonumber(settings and settings.MaxRoster) or maxEntries
	for _, player in Players:GetPlayers() do
		note(player)
	end
	Players.PlayerAdded:Connect(note)
	Players.PlayerRemoving:Connect(function(player)
		note(player)
		task.spawn(flush)
	end)
	task.spawn(function()
		while true do
			task.wait(FLUSH_SECONDS)
			flush()
		end
	end)
	game:BindToClose(flush)
end

return Roster

