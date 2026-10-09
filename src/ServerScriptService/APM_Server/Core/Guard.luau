--[[ Guard : limite le nombre d'appels d'un joueur par fenêtre de temps (anti-spam des remotes de l'APM). ]]
local Players = game:GetService("Players")

local Guard = {}

local buckets = {} -- [userId .. ":" .. clé] = { nombre, début de la fenêtre }

-- Autorise au plus `max` appels de `key` par fenêtre de `seconds` secondes pour ce joueur
function Guard.Allow(player, key, max, seconds)
	local id = player.UserId .. ":" .. key
	local now = os.clock()
	local bucket = buckets[id]
	if not bucket or now - bucket[2] >= seconds then
		bucket = { 0, now }
		buckets[id] = bucket
	end
	bucket[1] += 1
	return bucket[1] <= max
end

Players.PlayerRemoving:Connect(function(player)
	local prefix = player.UserId .. ":"
	for id in buckets do
		if string.sub(id, 1, #prefix) == prefix then
			buckets[id] = nil
		end
	end
end)

return Guard

