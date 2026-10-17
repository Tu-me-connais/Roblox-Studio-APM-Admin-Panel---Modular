--[[
	Sentinel Guard : observations serveur prudentes, historique borné et réactions optionnelles.

	Un cycle (config.Interval) :
	  1. MESURE de chaque joueur : vitesse, saut de position, temps passé en l'air sans tomber, personnage dans le décor,
	     valeurs de WalkSpeed / saut du Humanoid.
	  2. ORIGINE : le mouvement vient-il du SERVEUR ou du JOUEUR ? Indices : déclaré par un script ou un outil APM, personnage
	     ancré ou piloté par le serveur, plusieurs joueurs déplacés au même moment, destination très fréquentée, point
	     d'apparition. Chaque décision garde la liste de ses raisons et un niveau de confiance.
	  3. DÉCISION : un événement attribué au serveur est seulement noté (« activité serveur reconnue ») ; un événement attribué au
	     joueur crée une alerte, ajoute des points à sa fiche de suspect et déclenche les réactions choisies par le développeur.

	Limite à connaître : Roblox n'indique pas quel script a déplacé un personnage. « Déclaré » signifie que le script a appelé
	Sentinel.NotifyServerTeleport / Sentinel.Exempt avant de déplacer (les outils APM le font). Un déplacement serveur non déclaré
	est reconnu seulement par les autres indices ; sinon il est attribué au joueur avec une confiance moyenne.
	Un signal isolé ne sanctionne jamais : aucun bannissement automatique, expulsion seulement si le développeur l'autorise.
]]
local Players = game:GetService("Players")

local Sentinel = {}
local ctx, config, running, Msg = nil, nil, false, nil
local scriptConfig
local tracked, exemptions, alerts, connections = {}, {}, {}, {}
local suspects, serverMoves, destinations = {}, {}, {}
local totalAlerts, samplePasses, serverMoveCount = 0, 0, 0
local spawnCache, spawnCacheAt = {}, -math.huge
local destinationsPrunedAt = -math.huge
local Store -- mémoire permanente (module SentinelStore) ; nil si le module est absent

-- Les développeurs peuvent réagir eux-mêmes : Sentinel.Alerted:Connect(function(alert) ... end)
local alertedEvent = Instance.new("BindableEvent")
Sentinel.Alerted = alertedEvent.Event

local DEFAULTS = {
	-- général
	Enabled = true, Mode = "Observation", Interval = 1,
	-- détections (un interrupteur chacune)
	DetectSpeed = true, DetectTeleport = true, DetectFly = false, DetectNoclip = false, DetectHumanoid = true, DetectAbuse = true,
	-- plafonds
	MaxHorizontalSpeed = 90, MaxVerticalSpeed = 180, SpeedLimitEnabled = false, SpeedLimit = 50, SpeedTolerance = 15,
	JumpLimitEnabled = false, JumpHeightLimit = 30, EnforceLimits = false,
	-- téléportation / vol
	TeleportDistance = 140, TeleportConfirm = 1, FlySeconds = 4,
	-- tolérances
	LatencyAllowance = 35, SpawnGrace = 8, PhysicsGrace = 3, RequiredSamples = 4, AlertCooldown = 15, MaxAlerts = 200, SuspectMemory = 60,
	-- exceptions et réactions
	ExemptAdmins = true, NotifyAdmins = true, CorrectPosition = false, EnableKick = false,
	-- historique permanent (DataStore de l'APM) : dates, infractions, positions
	PersistHistory = true, RetentionDays = 30,
	-- fenêtre de 3 positions : un rattrapage de lag n'est pas une téléportation ; zones où Sentinel ne signale rien
	LagFilter = true, SafeZones = {},
}
local MODES = { Observation = true, Balanced = true, Strict = true }
local MULTIPLIER = { Strict = 1.15, Balanced = 1.4, Observation = 1.6 }
local BOUNDS = {
	Interval = { 0.5, 10 }, MaxHorizontalSpeed = { 20, 2000 }, MaxVerticalSpeed = { 40, 4000 }, SpeedLimit = { 8, 1000 }, SpeedTolerance = { 0, 100 },
	JumpHeightLimit = { 3, 500 }, TeleportDistance = { 30, 10000 }, TeleportConfirm = { 1, 10 }, FlySeconds = { 2, 60 },
	LatencyAllowance = { 5, 500 }, SpawnGrace = { 3, 120 }, PhysicsGrace = { 1, 60 }, RequiredSamples = { 3, 30 },
	AlertCooldown = { 3, 300 }, MaxAlerts = { 25, 300 }, SuspectMemory = { 5, 720 }, RetentionDays = { 1, 365 },
}
local INTEGER = { RequiredSamples = true, MaxAlerts = true, SuspectMemory = true, TeleportConfirm = true, FlySeconds = true, SpeedTolerance = true, RetentionDays = true }
local SAFE_PHYSICS_STATES = { [Enum.HumanoidStateType.Physics] = true, [Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true, [Enum.HumanoidStateType.PlatformStanding] = true }
local POINTS = { Speed = 8, Teleport = 15, Fly = 12, Noclip = 12, Humanoid = 6, RemoteAbuse = 5 }
local CONFIDENCE_WEIGHT = { High = 1, Medium = 0.8, Low = 0.5 }
local MAX_SUSPECTS, MAX_EVENTS, MAX_MOVES, MAX_ALERTS_SENT = 60, 12, 40, 100
local DESTINATION_CELL, DESTINATION_MEMORY, POPULAR_PLAYERS = 24, 600, 3
local MAX_ZONES = 40
local lagFiltered = 0

local function disabled()
	return type(ctx.Settings.Modules) == "table" and ctx.Settings.Modules.Sentinel == false
end
local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) ~= math.huge
end
local function copy(source)
	local result = {}
	for key, value in source do result[key] = value end
	return result
end
local function deepCopy(value, depth)
	if type(value) ~= "table" then return value end
	if (depth or 0) > 5 then return nil end
	local result = {}
	for key, item in value do result[key] = deepCopy(item, (depth or 0) + 1) end
	return result
end
local function msg(fr, en, ...)
	if select("#", ...) > 0 then return { p = { fr = fr, en = en }, a = { ... }, n = select("#", ...) } end
	return { fr = fr, en = en }
end
local function pick(value, code)
	if type(value) == "table" then return tostring(value[code] or value.en or value.fr or "") end
	return tostring(value)
end
local function round1(n)
	return math.floor(n * 10 + 0.5) / 10
end
local function vec(position)
	return { x = math.floor(position.X + 0.5), y = math.floor(position.Y + 0.5), z = math.floor(position.Z + 0.5) }
end
local function has(player, name)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
		and ctx.Ranks.HasPermission(player, "APM.AccessPanel") and ctx.Ranks.HasPermission(player, name)
end

----------------------------------------------------------------------------------------------------------
-- Zones sûres : { Id, Name, X, Y, Z, Radius } ; Sentinel ne signale rien dans la zone ni pour un déplacement qui en part ou y arrive

local function cleanZone(raw)
	if type(raw) ~= "table" then return nil end
	local x, y, z, radius = tonumber(raw.X), tonumber(raw.Y), tonumber(raw.Z), tonumber(raw.Radius)
	if not (finite(x) and finite(y) and finite(z) and finite(radius)) then return nil end
	if math.abs(x) > 1e6 or math.abs(y) > 1e6 or math.abs(z) > 1e6 then return nil end
	local name = type(raw.Name) == "string" and raw.Name or ""
	if not utf8.len(name) then name = string.gsub(name, "[\128-\255]", "?") end
	local cut = utf8.offset(name, 41)
	if cut then name = string.sub(name, 1, cut - 1) end
	return { Id = math.floor(tonumber(raw.Id) or 0), Name = name, X = math.floor(x + 0.5), Y = math.floor(y + 0.5), Z = math.floor(z + 0.5),
		Radius = math.clamp(math.floor(radius + 0.5), 3, 2000) }
end
local function cleanZones(value)
	local list, used = {}, {}
	if type(value) ~= "table" then return list end
	for _, raw in value do
		if #list >= MAX_ZONES then break end
		local zone = cleanZone(raw)
		if zone then
			if zone.Id <= 0 or used[zone.Id] then
				local id = 1
				while used[id] do id += 1 end
				zone.Id = id
			end
			used[zone.Id] = true
			table.insert(list, zone)
		end
	end
	return list
end
local function zoneAt(position)
	for _, zone in config.SafeZones or {} do
		local dx, dy, dz = position.X - zone.X, position.Y - zone.Y, position.Z - zone.Z
		if dx * dx + dy * dy + dz * dz <= zone.Radius * zone.Radius then return zone end
	end
	return nil
end

function Sentinel.ValidateConfig(patch, base)
	if type(patch) ~= "table" then return nil, msg("Configuration invalide.", "Invalid configuration.") end
	local clean = copy(base or DEFAULTS)
	for key, value in patch do
		if key == "Mode" then
			if not MODES[value] then return nil, msg("Mode inconnu.", "Unknown mode.") end
			clean.Mode = value
		elseif key == "SafeZones" then
			clean.SafeZones = cleanZones(value)
		elseif BOUNDS[key] then
			local bound = BOUNDS[key]
			if not finite(value) or value < bound[1] or value > bound[2] then return nil, msg("Valeur hors limites : %s", "Value out of range: %s", key) end
			clean[key] = INTEGER[key] and math.floor(value) or value
		elseif type(DEFAULTS[key]) == "boolean" then
			if type(value) ~= "boolean" then return nil, msg("Booléen attendu : %s", "Boolean expected: %s", key) end
			clean[key] = value
		else
			return nil, msg("Paramètre inconnu : %s", "Unknown setting: %s", tostring(key))
		end
	end
	return clean
end

----------------------------------------------------------------------------------------------------------
-- Évaluations pures (utilisées par le runtime ET par le diagnostic synthétique)

-- Vitesse et saut de position. sample : { Dt, Horizontal, Vertical, WalkSpeed, PlatformSpeed, Ping, Grounded, Grace }
-- Renvoie flags ("speed", "teleport", "vertical") et mesures { Horizontal, Vertical, Limit, Speed, Dt, Ping, Jump }.
function Sentinel.EvaluateSample(settings, sample)
	local dt = sample.Dt
	if not finite(dt) or dt < 0.1 or dt > math.max(3, settings.Interval * 3) or sample.Grace then return {} end
	local horizontal = finite(sample.Horizontal) and math.max(0, sample.Horizontal) or 0
	local vertical = finite(sample.Vertical) and math.max(0, sample.Vertical) or 0
	local walk = finite(sample.WalkSpeed) and math.max(0, sample.WalkSpeed) or 16
	local platform = finite(sample.PlatformSpeed) and math.clamp(sample.PlatformSpeed, 0, 500) or 0
	local ping = finite(sample.Ping) and math.clamp(sample.Ping, 0, 2) or 0
	local multiplier = MULTIPLIER[settings.Mode] or 1.6
	local slack = settings.LatencyAllowance * (1 + ping * 3)
	-- distance que le joueur peut légitimement parcourir pendant dt
	local allowed, speedLimit
	if settings.SpeedLimitEnabled then
		-- plafond précis choisi par le développeur : marge réseau réduite (pas la marge générale)
		speedLimit = settings.SpeedLimit * (1 + (settings.SpeedTolerance or 15) / 100)
		allowed = speedLimit * dt + 6 * (1 + ping * 3) + platform * dt
	else
		speedLimit = math.max(settings.MaxHorizontalSpeed, walk * 3) * multiplier
		allowed = (speedLimit + platform) * dt + slack
	end
	local flags = {}
	local jump = horizontal > settings.TeleportDistance + allowed
	if settings.DetectTeleport ~= false and jump then table.insert(flags, "teleport") end
	if settings.DetectSpeed ~= false and horizontal > allowed then table.insert(flags, "speed") end
	-- Vertical motion in jumping/freefall/climbing is ambiguous and does not contribute a vertical strike.
	if settings.DetectSpeed ~= false and sample.Grounded and vertical > settings.MaxVerticalSpeed * dt + slack then table.insert(flags, "vertical") end
	return flags, { Horizontal = math.floor(horizontal), Vertical = math.floor(vertical), Limit = math.floor(allowed), SpeedLimit = math.floor(speedLimit),
		Speed = math.floor(horizontal / dt * 10) / 10, Dt = math.floor(dt * 100) / 100, Ping = math.floor(ping * 1000), Jump = jump }
end

-- Temps passé en l'air sans tomber : vrai si le joueur « flotte » depuis assez longtemps
function Sentinel.EvaluateFly(settings, hoverSeconds)
	return settings.DetectFly ~= false and finite(hoverSeconds) and hoverSeconds >= settings.FlySeconds
end

-- Valeurs du Humanoid au-dessus des plafonds. values : { WalkSpeed, JumpHeight }
function Sentinel.EvaluateHumanoid(settings, values)
	local flags = {}
	if settings.DetectHumanoid ~= false then
		if settings.SpeedLimitEnabled and finite(values.WalkSpeed) and values.WalkSpeed > settings.SpeedLimit * 1.001 then table.insert(flags, "walkspeed") end
		if settings.JumpLimitEnabled and finite(values.JumpHeight) and values.JumpHeight > settings.JumpHeightLimit * 1.001 then table.insert(flags, "jumpheight") end
	end
	return flags
end

local function jumpHeightOf(humanoid)
	if humanoid.UseJumpPower then
		local gravity = math.max(workspace.Gravity, 1)
		return humanoid.JumpPower * humanoid.JumpPower / (2 * gravity)
	end
	return humanoid.JumpHeight
end

----------------------------------------------------------------------------------------------------------
-- Mémoire : suspects, activité serveur, alertes

local function halfLife()
	return math.max(60, config.SuspectMemory * 60 / 4) -- un événement isolé retombe sous 1 point au bout de SuspectMemory minutes
end
local function scoreOf(suspect)
	return suspect.Score * 0.5 ^ ((os.clock() - suspect.ScoreAt) / halfLife())
end
local function levelOf(score)
	return score >= 60 and "High" or score >= 25 and "Medium" or "Low"
end

local function trimAlerts()
	while #alerts > config.MaxAlerts do table.remove(alerts) end
end

local function pruneSuspects()
	local limit = os.time() - config.SuspectMemory * 60
	local count = 0
	for userId, suspect in suspects do
		if suspect.LastAt < limit or scoreOf(suspect) < 1 then
			suspects[userId] = nil
		else
			count += 1
		end
	end
	if count > MAX_SUSPECTS then
		local list = {}
		for userId, suspect in suspects do table.insert(list, { userId, scoreOf(suspect) }) end
		table.sort(list, function(a, b) return a[2] > b[2] end)
		for index = MAX_SUSPECTS + 1, #list do suspects[list[index][1]] = nil end
	end
end

local function addSuspectEvent(player, event)
	local suspect = suspects[player.UserId]
	if not suspect then
		suspect = { UserId = player.UserId, Score = 0, ScoreAt = os.clock(), Count = 0, Kinds = {}, Events = {}, FirstAt = os.time() }
		suspects[player.UserId] = suspect
	end
	suspect.Name, suspect.DisplayName, suspect.LastAt = player.Name, player.DisplayName, os.time()
	local points = (POINTS[event.Kind] or 5) * (CONFIDENCE_WEIGHT[event.Confidence] or 0.5)
	suspect.Score = math.min(100, scoreOf(suspect) + points)
	suspect.ScoreAt = os.clock()
	suspect.Count += 1
	suspect.Kinds[event.Kind] = (suspect.Kinds[event.Kind] or 0) + 1
	table.insert(suspect.Events, 1, event)
	while #suspect.Events > MAX_EVENTS do table.remove(suspect.Events) end
	pruneSuspects()
end

local function recordServerMove(player, kind, origin, why, confidence, data, reason)
	local state = tracked[player]
	local now = os.clock()
	if state and now - (state.MoveAt or -math.huge) < 3 then return end
	if state then state.MoveAt = now end
	serverMoveCount += 1
	table.insert(serverMoves, 1, { Id = serverMoveCount, Time = os.time(), UserId = player.UserId, Name = player.Name, Kind = kind,
		Origin = origin, Confidence = confidence, Why = why, Data = data, Reason = reason })
	while #serverMoves > MAX_MOVES do table.remove(serverMoves) end
end

----------------------------------------------------------------------------------------------------------
-- Origine d'un mouvement : serveur ou joueur ?

local function spawnPositions()
	if os.clock() - spawnCacheAt > 60 then
		spawnCacheAt = os.clock()
		spawnCache = {}
		for _, item in workspace:GetDescendants() do
			if item:IsA("SpawnLocation") then
				table.insert(spawnCache, { Position = item.Position, Radius = math.max(item.Size.X, item.Size.Z) / 2 + 12 })
				if #spawnCache >= 64 then break end
			end
		end
	end
	return spawnCache
end

-- Combien de joueurs DIFFÉRENTS sont arrivés dans cette zone récemment (celui-ci compris) ?
local function noteDestination(userId, position, now)
	local key = math.floor(position.X / DESTINATION_CELL) .. "|" .. math.floor(position.Y / DESTINATION_CELL) .. "|" .. math.floor(position.Z / DESTINATION_CELL)
	local cell = destinations[key]
	if not cell then
		cell = { Players = {}, At = now }
		destinations[key] = cell
	end
	cell.Players[userId], cell.At = now, now
	local count = 0
	for id, at in cell.Players do
		if now - at > DESTINATION_MEMORY then cell.Players[id] = nil else count += 1 end
	end
	return count
end
local function pruneDestinations(now)
	if now - destinationsPrunedAt < 60 then return end
	destinationsPrunedAt = now
	local count = 0
	for key, cell in destinations do
		if now - cell.At > DESTINATION_MEMORY then destinations[key] = nil else count += 1 end
	end
	if count > 400 then table.clear(destinations) end
end

-- Renvoie origine ("ServerLikely" | "Player" | "Unknown"), confiance, liste de raisons { { Code, V } }
local function classify(m, kind, jumpers, popular)
	local why = {}
	local serverScore, playerScore = 0, 0
	local function add(side, code, points, value)
		if side == "server" then serverScore += points else playerScore += points end
		table.insert(why, { Code = code, V = value })
	end
	if kind == "RemoteAbuse" then
		return "Player", "High", { { Code = "ClientRemote" } }
	end
	local root, humanoid = m.Root, m.Humanoid
	if root then
		if root.Anchored then
			add("server", "Anchored", 4)
		else
			local ok, owner = pcall(root.GetNetworkOwner, root)
			if ok then
				if owner == nil then add("server", "ServerOwned", 4)
				elseif owner == m.Player then add("player", "ClientOwned", 1) end
			end
		end
	end
	if kind == "Teleport" then
		if jumpers >= 2 then add("server", "Simultaneous", 3, jumpers) end
		if popular >= POPULAR_PLAYERS then add("server", "PopularDestination", 3, popular) end
		for _, spawn in spawnPositions() do
			if (spawn.Position - m.Position).Magnitude <= spawn.Radius then
				add("server", "AtSpawn", 3)
				break
			end
		end
		-- indices qui ressemblent à un déplacement choisi par le joueur
		for _, other in Players:GetPlayers() do
			local otherRoot = other ~= m.Player and other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot and otherRoot:IsA("BasePart") and (otherRoot.Position - m.Position).Magnitude <= 8 then
				add("player", "NearPlayer", 1, math.floor((otherRoot.Position - m.Position).Magnitude + 0.5))
				break
			end
		end
		if m.Position.Y < workspace.FallenPartsDestroyHeight + 100 then add("player", "UnderMap", 1) end
	end
	if humanoid then
		local walk = humanoid.WalkSpeed
		if kind == "Speed" or kind == "Teleport" then
			if walk <= 24 then add("player", "WalkSpeedNormal", 2, math.floor(walk + 0.5)) end
		elseif kind == "Humanoid" then
			add("player", "WalkSpeedModified", 2)
		end
	end
	add("player", "NoServerAction", 1)
	if serverScore >= 3 then
		return "ServerLikely", serverScore >= 6 and "High" or "Medium", why
	elseif playerScore >= 2 then
		return "Player", playerScore >= 5 and "High" or playerScore >= 3 and "Medium" or "Low", why
	end
	return "Unknown", "Low", why
end

----------------------------------------------------------------------------------------------------------
-- Alertes et réactions

local function eventMessage(kind, data)
	if kind == "Teleport" then
		return Msg("Sentinel.Event.Teleport", data.Distance, data.Dt)
	elseif kind == "Speed" then
		if data.Vertical then return Msg("Sentinel.Event.Vertical", data.Speed, data.Dt) end
		return Msg("Sentinel.Event.Speed", data.Speed, data.Limit, data.Dt)
	elseif kind == "Fly" then
		return Msg("Sentinel.Event.Fly", data.Seconds)
	elseif kind == "Noclip" then
		return Msg("Sentinel.Event.Noclip", data.Part or "?", data.Samples)
	elseif kind == "Humanoid" then
		return Msg(data.Property == "WalkSpeed" and "Sentinel.Event.WalkSpeed" or "Sentinel.Event.JumpHeight", data.Value, data.Limit)
	elseif kind == "RemoteAbuse" then
		return Msg("Sentinel.Event.RemoteAbuse", data.Category, data.Count)
	end
	return Msg("Sentinel.Event.Generic", kind)
end

local function addAlert(player, kind, detail, data, origin, why, confidence, evidence, isTest, reaction)
	totalAlerts += 1
	local alert = { Id = totalAlerts, Time = os.time(), UserId = player.UserId, Name = player.Name, Kind = kind, Detail = detail,
		Evidence = evidence or 0, Mode = config.Mode, Test = isTest == true, Reaction = reaction or Msg("Sentinel.Reaction.Logged"),
		Confidence = Msg("Sentinel.Confidence.Heuristic"), Origin = origin, ConfidenceLevel = confidence, Why = why, Data = data }
	table.insert(alerts, 1, alert)
	trimAlerts()
	ctx.Log("Sentinel", isTest and "Sentinel.Test" or "Sentinel.Alert", player.Name, detail, "Sentinel", isTest and "info" or "warning")
	if config.NotifyAdmins and not isTest and origin ~= "Server" then
		for _, admin in Players:GetPlayers() do
			if has(admin, "Sentinel.View") then ctx.Notify(admin, Msg("Sentinel.Notify", player.Name, detail), false) end
		end
		alert.Reaction = Msg("Sentinel.Reaction.Notified")
	end
	return alert
end

-- Un signal est confirmé : classement d'origine, puis alerte / suspect / réactions
local function emit(m, kind, data, now, jumpers)
	local player, state = m.Player, m.State
	local popular = 0
	if kind == "Teleport" and m.Position then
		popular = noteDestination(player.UserId, m.Position, now)
	end
	local origin, confidence, why = classify(m, kind, jumpers or 1, popular)
	if origin == "ServerLikely" then
		recordServerMove(player, kind, "ServerLikely", why, confidence, data, nil)
		return nil
	end
	state.AlertAt = state.AlertAt or {}
	if now - (state.AlertAt[kind] or -math.huge) < config.AlertCooldown then return nil end
	state.AlertAt[kind] = now
	local detail = eventMessage(kind, data)
	local evidence = kind == "Speed" and state.Streak or kind == "Teleport" and state.TeleportHits or 0
	local alert = addAlert(player, kind, detail, data, origin, why, confidence, evidence, false)
	local event = { Id = alert.Id, Time = alert.Time, Kind = kind, Origin = origin, Confidence = confidence, Why = why, Data = data }
	addSuspectEvent(player, event)

	-- réactions (toutes optionnelles, choisies par le développeur)
	local corrected, kicked = false, false
	if origin == "Player" and m.Root and (kind == "Teleport" or kind == "Speed" and state.TeleportSamples >= config.RequiredSamples)
			and config.Mode ~= "Observation" and config.CorrectPosition and state.SafeCFrame and state.SafeAt
			and now - state.SafeAt <= 30 and now - state.LastCorrect >= 10 then
		m.Root.CFrame = state.SafeCFrame
		m.Root.AssemblyLinearVelocity = Vector3.zero
		state.LastCorrect = now
		state.LastPosition = nil
		corrected = true
		alert.Reaction = Msg("Sentinel.Reaction.Corrected")
		Sentinel.NotifyServerTeleport(player, config.PhysicsGrace, "Sentinel correction")
	end
	-- Kicking additionally requires explicit server opt-in, Strict mode, a long repeated teleport streak AND refused remote evidence.
	-- Movement alone never triggers a kick; production defaults keep this disabled.
	if origin == "Player" and config.Mode == "Strict" and config.EnableKick and ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true
			and state.Streak >= math.max(12, config.RequiredSamples * 3) and state.TeleportSamples >= 12
			and state.Abuse >= 20 and now - state.AbuseAt <= 60 then
		kicked = true
		alert.Reaction = Msg("Sentinel.Reaction.Kicked")
		local kickText = msg("Requêtes abusives répétées et mouvements invalides. Rejoins le serveur ou contacte la modération.",
			"Repeated invalid requests and movement. Rejoin or contact moderation.")
		player:Kick(ctx.Lang and ctx.Lang.Text(ctx.Lang.ForPlayer(player), kickText) or kickText.en)
	end
	event.Reaction = alert.Reaction
	if Store and config.PersistHistory then
		local code = kicked and "Kicked" or corrected and "Corrected" or config.NotifyAdmins and "Notified" or "Logged"
		local live = suspects[player.UserId]
		Store.Record(player, event, live and scoreOf(live) or 0, code)
	end
	local ok, problem = pcall(function()
		alertedEvent:Fire(deepCopy({ UserId = player.UserId, Name = player.Name, Kind = kind, Origin = origin, Confidence = confidence,
			Data = data, Why = why, Corrected = corrected, Kicked = kicked }))
	end)
	if not ok then warn("[APM] Sentinel.Alerted : " .. tostring(problem)) end
	return alert
end

----------------------------------------------------------------------------------------------------------
-- Exemptions déclarées par le serveur

function Sentinel.Exempt(player, seconds, reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players or not finite(seconds) then return false end
	local untilAt = os.clock() + math.clamp(seconds, 0, 120)
	local previous = exemptions[player]
	exemptions[player] = { Until = math.max(untilAt, previous and previous.Until or 0), Reason = string.sub(tostring(reason or "Server-authorized mechanic"), 1, 100) }
	local state = tracked[player]
	if state then
		-- la position n'est PAS oubliée : le déplacement déclaré est mesuré puis rangé dans « activité serveur reconnue »
		state.Streak, state.TeleportSamples, state.TeleportHits, state.Hover, state.NoclipSamples = 0, 0, 0, 0, 0
	end
	return true
end
function Sentinel.NotifyServerTeleport(player, seconds, reason)
	return Sentinel.Exempt(player, seconds or 4, reason or "Server teleport")
end
function Sentinel.CleanupPlayer(player)
	local state = tracked[player]
	if state and state.Connection then state.Connection:Disconnect() end
	tracked[player], exemptions[player] = nil, nil
end

local function track(player)
	if tracked[player] then return end
	local state = { Streak = 0, TeleportSamples = 0, TeleportHits = 0, TeleportAt = -math.huge, Abuse = 0, AbuseAt = os.clock(),
		AlertAt = {}, GraceUntil = os.clock() + config.SpawnGrace, LastCorrect = -math.huge, Hover = 0, NoclipSamples = 0, MoveAt = -math.huge }
	tracked[player] = state
	state.Connection = player.CharacterAdded:Connect(function()
		state.Streak, state.TeleportSamples, state.TeleportHits, state.Hover, state.NoclipSamples = 0, 0, 0, 0, 0
		state.LastPosition, state.PrevPosition, state.SafeCFrame = nil, nil, nil
		state.GraceUntil = os.clock() + config.SpawnGrace
	end)
end

-- Server gateway only; no client can submit arbitrary records through an endpoint.
function Sentinel.RecordAbuse(player, category, detail)
	if not ctx or not config.Enabled or config.DetectAbuse == false or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then return end
	track(player)
	local state, now = tracked[player], os.clock()
	if now - state.AbuseAt > 60 then state.Abuse, state.AbuseAt = 0, now end
	state.Abuse = math.min(state.Abuse + 1, 100)
	if state.Abuse >= 8 then
		local label = type(category) == "table" and { fr = string.sub(pick(category, "fr"), 1, 50), en = string.sub(pick(category, "en"), 1, 50) }
			or string.sub(tostring(category), 1, 50)
		emit({ Player = player, State = state }, "RemoteAbuse", { Category = label, Count = state.Abuse }, now, 1)
	end
end

----------------------------------------------------------------------------------------------------------
-- Cycle de surveillance

-- Personnage dans le décor : renvoie la pièce solide qui le contient, ou nil
local function noclipPart(m)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { m.Character }
	params.MaxParts = 12
	pcall(function() params.RespectCanCollide = true end)
	pcall(function() params.CollisionGroup = m.Root.CollisionGroup end)
	local parts = workspace:GetPartBoundsInBox(CFrame.new(m.Position), Vector3.new(1.2, 1.6, 0.8), params)
	for _, part in parts do
		-- pièces pleines, immobiles et en forme de bloc : peu de faux positifs (arches, échelles et maillages arrondis ignorés)
		if part.Anchored and part.CanCollide and not part:IsA("TrussPart") and not part:IsA("Terrain")
				and math.min(part.Size.X, part.Size.Y, part.Size.Z) >= 0.4
				and (part:IsA("WedgePart") or part:IsA("CornerWedgePart") or (part:IsA("Part") and part.Shape == Enum.PartType.Block)
					or (part:IsA("MeshPart") and part.CollisionFidelity == Enum.CollisionFidelity.Box)) then
			return part
		end
	end
	return nil
end

-- Phase 1 : mesure d'un joueur (aucune décision ici)
local function measure(player, now)
	local state = tracked[player]
	if not state then
		track(player)
		state = tracked[player]
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		state.LastPosition, state.Hover, state.NoclipSamples = nil, 0, 0
		return nil
	end
	local exempt = exemptions[player]
	if exempt and now >= exempt.Until then
		exemptions[player] = nil
		exempt = nil
	end
	local adminExempt = config.ExemptAdmins and ctx.Ranks.IsAdmin(player) and ctx.Ranks.HasPermission(player, "APM.AccessPanel")
	local humanoidState = humanoid:GetState()
	local physics = humanoid.SeatPart ~= nil or humanoid.Sit or humanoid.PlatformStand or SAFE_PHYSICS_STATES[humanoidState] == true
	if physics then state.GraceUntil = math.max(state.GraceUntil, now + config.PhysicsGrace) end
	local position = root.Position
	if not finite(position.X) or not finite(position.Y) or not finite(position.Z) then
		state.LastPosition = nil
		return nil
	end
	local lastPosition, lastAt = state.LastPosition, state.LastAt
	-- fenêtre de 3 positions : avant-dernière, dernière, actuelle. L'avant-dernière est oubliée au cycle suivant.
	local beforePosition, beforeAt = state.PrevPosition, state.PrevAt
	state.PrevPosition, state.PrevAt = lastPosition, lastAt
	state.LastPosition, state.LastAt = position, now
	local m = { Player = player, State = state, Humanoid = humanoid, Root = root, Character = character, Position = position,
		LastPosition = lastPosition, LastAt = lastAt, Before = beforePosition, BeforeAt = beforeAt, Exempt = exempt, AdminExempt = adminExempt, Grace = now < state.GraceUntil, Physics = physics,
		HumanoidState = humanoidState, Flags = {} }
	local ping = 0
	local okPing, value = pcall(player.GetNetworkPing, player)
	if okPing and finite(value) then ping = math.clamp(value, 0, 2) end
	m.Grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	if lastPosition and lastAt and not adminExempt then
		local platformSpeed = 0
		if m.Grounded then
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { character }
			local hit = workspace:Raycast(position, Vector3.new(0, -7, 0), params)
			if hit and hit.Instance:IsA("BasePart") then platformSpeed = hit.Instance.AssemblyLinearVelocity.Magnitude end
		end
		local delta = position - lastPosition
		m.Delta, m.Dt = delta, now - lastAt
		m.Ping, m.PlatformSpeed = ping, platformSpeed
		-- grâce ignorée pour un déplacement déclaré : on veut le mesurer pour le ranger dans l'activité serveur
		local flags, measures = Sentinel.EvaluateSample(config, { Dt = m.Dt, Horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude,
			Vertical = math.abs(delta.Y), WalkSpeed = humanoid.WalkSpeed, PlatformSpeed = platformSpeed, Ping = ping, Grounded = m.Grounded,
			Grace = m.Grace and exempt == nil })
		m.Flags, m.Measures = flags, measures
		m.Jump = measures ~= nil and measures.Jump == true
	end
	return m
end

local function flagged(list, name)
	return table.find(list, name) ~= nil
end

-- Phase 2 : décision pour un joueur mesuré
local function resolve(m, now, jumpers)
	local state = m.State
	local function calm()
		state.Streak, state.TeleportSamples, state.TeleportHits, state.Hover, state.NoclipSamples = 0, 0, 0, 0, 0
	end
	if m.AdminExempt then
		calm()
		return
	end
	local flags = m.Flags
	local teleport = flagged(flags, "teleport")
	local speed = flagged(flags, "speed") or flagged(flags, "vertical")
	if m.Exempt then
		calm()
		if m.Measures and (teleport or speed or m.Jump) then
			local data = { From = vec(m.LastPosition), To = vec(m.Position), Distance = math.floor(m.Measures.Horizontal), Dt = m.Measures.Dt, WalkSpeed = round1(m.Humanoid.WalkSpeed) }
			if m.Jump then noteDestination(m.Player.UserId, m.Position, now) end
			recordServerMove(m.Player, teleport and "Teleport" or "Speed", "Server", { { Code = "Declared", V = m.Exempt.Reason } }, "High", data, m.Exempt.Reason)
		end
		return
	end
	if m.Grace then
		calm()
		return
	end
	-- zone sûre définie par le développeur : rien n'est signalé dedans, ni pour un déplacement qui en part ou qui y arrive
	local zone = zoneAt(m.Position) or (m.LastPosition and zoneAt(m.LastPosition)) or nil
	if zone then
		if m.Measures and (teleport or speed or m.Jump) then
			local data = { From = vec(m.LastPosition), To = vec(m.Position), Distance = math.floor(m.Measures.Horizontal), Dt = m.Measures.Dt,
				WalkSpeed = round1(m.Humanoid.WalkSpeed) }
			if m.Jump then noteDestination(m.Player.UserId, m.Position, now) end
			local label = zone.Name ~= "" and zone.Name or ("#" .. tostring(zone.Id))
			recordServerMove(m.Player, teleport and "Teleport" or "Speed", "SafeZone", { { Code = "SafeZone", V = label } }, "High", data, label)
		end
		calm()
		return
	end
	local humanoid, root = m.Humanoid, m.Root

	-- valeurs du personnage (WalkSpeed / saut) : alerte puis, si demandé, remise au plafond
	local walk, jumpHeight = humanoid.WalkSpeed, jumpHeightOf(humanoid)
	for _, flag in Sentinel.EvaluateHumanoid(config, { WalkSpeed = walk, JumpHeight = jumpHeight }) do
		local isWalk = flag == "walkspeed"
		emit(m, "Humanoid", { Property = isWalk and "WalkSpeed" or "JumpHeight", Value = round1(isWalk and walk or jumpHeight),
			Limit = isWalk and config.SpeedLimit or config.JumpHeightLimit, Position = vec(m.Position) }, now, jumpers)
	end
	if config.EnforceLimits then
		if config.SpeedLimitEnabled and walk > config.SpeedLimit then humanoid.WalkSpeed = config.SpeedLimit end
		if config.JumpLimitEnabled and jumpHeight > config.JumpHeightLimit then
			if humanoid.UseJumpPower then
				humanoid.JumpPower = math.sqrt(2 * math.max(workspace.Gravity, 1) * config.JumpHeightLimit)
			else
				humanoid.JumpHeight = config.JumpHeightLimit
			end
		end
	end

	-- rattrapage de lag : si la distance parcourue depuis 2 cycles reste compatible avec la vitesse autorisée, la "téléportation"
	-- n'est que le serveur qui rattrape une position en retard (paquets bloqués puis livrés d'un coup)
	if config.LagFilter and m.Measures and m.Before and m.BeforeAt and (teleport or speed) then
		local flagsWindow = Sentinel.EvaluateSample(config, { Dt = now - m.BeforeAt,
			Horizontal = Vector3.new(m.Position.X - m.Before.X, 0, m.Position.Z - m.Before.Z).Magnitude, Vertical = math.abs(m.Position.Y - m.Before.Y),
			WalkSpeed = humanoid.WalkSpeed, PlatformSpeed = m.PlatformSpeed or 0, Ping = m.Ping or 0, Grounded = m.Grounded })
		if #flagsWindow == 0 then
			lagFiltered += 1
			flags, teleport, speed = {}, false, false
			m.Jump = false
		end
	end

	-- saut de position / vitesse
	if m.Measures then
		if #flags == 0 then
			state.Streak = math.max(0, state.Streak - 1)
			state.TeleportSamples = math.max(0, state.TeleportSamples - 1)
			if m.Grounded and now - state.LastCorrect > config.PhysicsGrace and state.Streak == 0 then state.SafeCFrame, state.SafeAt = root.CFrame, now end
		else
			local data = { From = vec(m.LastPosition), To = vec(m.Position), Distance = math.floor(m.Measures.Horizontal), Dt = m.Measures.Dt,
				Speed = m.Measures.Speed, Limit = math.floor(m.Measures.SpeedLimit), WalkSpeed = round1(walk),
				Before = m.Before and vec(m.Before) or nil }
			if teleport then
				state.TeleportSamples += 1
				if now - state.TeleportAt > 30 then state.TeleportHits = 0 end
				state.TeleportHits += 1
				state.TeleportAt = now
				if state.TeleportHits >= config.TeleportConfirm then
					emit(m, "Teleport", data, now, jumpers)
					state.TeleportHits = 0
				end
			elseif m.Jump then
				noteDestination(m.Player.UserId, m.Position, now)
			end
			if speed and not teleport then
				state.Streak += 1
				if flagged(flags, "vertical") and not flagged(flags, "speed") then
					data.Vertical = true
					data.Speed = math.floor(m.Measures.Vertical / math.max(m.Measures.Dt, 0.1))
				end
				if state.Streak >= config.RequiredSamples then emit(m, "Speed", data, now, jumpers) end
			end
		end
	end

	-- vol : en l'air, sans tomber ni monter, depuis assez longtemps
	local airborne = not m.Grounded and not m.Physics and m.HumanoidState ~= Enum.HumanoidStateType.Climbing
		and m.HumanoidState ~= Enum.HumanoidStateType.Swimming
	if config.DetectFly and airborne and m.Delta and m.Dt and not m.Jump then
		if math.abs(m.Delta.Y) / m.Dt < 8 then state.Hover += m.Dt else state.Hover = 0 end
	else
		state.Hover = 0
	end
	if Sentinel.EvaluateFly(config, state.Hover) then
		emit(m, "Fly", { Seconds = math.floor(state.Hover * 10) / 10, Position = vec(m.Position) }, now, jumpers)
		state.Hover = 0
	end

	-- personnage coincé dans le décor
	if config.DetectNoclip then
		local part = noclipPart(m)
		if part then state.NoclipSamples += 1 else state.NoclipSamples = 0 end
		if state.NoclipSamples >= config.RequiredSamples then
			emit(m, "Noclip", { Part = string.sub(part and part.Name or "?", 1, 40), Samples = state.NoclipSamples, Position = vec(m.Position) }, now, jumpers)
			state.NoclipSamples = 0
		end
	end
end

local function pass()
	local now = os.clock()
	samplePasses += 1
	pruneDestinations(now)
	local measured = {}
	for _, player in Players:GetPlayers() do
		local ok, result = pcall(measure, player, now)
		if ok then
			if result then table.insert(measured, result) end
		elseif ctx.Guard.Allow(player, "SentinelSamplingError", 1, 60) then
			ctx.Log("Sentinel", "Sentinel.Error", player.Name, msg("Échantillon ignoré : %s", "Sample skipped: %s", string.sub(tostring(result), 1, 160)), "Sentinel", "warning")
		end
	end
	-- combien de joueurs ont fait un bond de la taille d'une téléportation pendant CE cycle ? (événement serveur probable)
	local jumpers = 0
	for _, m in measured do
		if m.Jump and not m.AdminExempt then jumpers += 1 end
	end
	for _, m in measured do
		local ok, problem = pcall(resolve, m, now, jumpers)
		if not ok and ctx.Guard.Allow(m.Player, "SentinelSamplingError", 1, 60) then
			ctx.Log("Sentinel", "Sentinel.Error", m.Player.Name, msg("Décision ignorée : %s", "Decision skipped: %s", string.sub(tostring(problem), 1, 160)), "Sentinel", "warning")
		end
	end
end

----------------------------------------------------------------------------------------------------------
-- Lecture et actions (panneau)

local function liveSuspectList()
	pruneSuspects()
	local list = {}
	for userId, suspect in suspects do
		local score = scoreOf(suspect)
		if score >= 1 then
			local kinds = {}
			for kind, count in suspect.Kinds do table.insert(kinds, { Kind = kind, Count = count }) end
			table.sort(kinds, function(a, b)
				if a.Count ~= b.Count then return a.Count > b.Count end
				return a.Kind < b.Kind
			end)
			local events = {}
			for index, event in suspect.Events do events[index] = deepCopy(event) end
			table.insert(list, { UserId = userId, Name = suspect.Name, DisplayName = suspect.DisplayName, Score = math.floor(score + 0.5),
				Level = levelOf(score), Count = suspect.Count, FirstAt = suspect.FirstAt, LastAt = suspect.LastAt,
				Online = Players:GetPlayerByUserId(userId) ~= nil, Kinds = kinds, Events = events })
		end
	end
	table.sort(list, function(a, b)
		if a.Score ~= b.Score then return a.Score > b.Score end
		return a.LastAt > b.LastAt
	end)
	return list
end

-- Suspects de CE serveur + fiches enregistrées (autres serveurs, parties précédentes) : le score d'une fiche ancienne est
-- recalculé d'après sa date, il redescend tout seul.
local function suspectList()
	local list = liveSuspectList()
	if not Store or not config.PersistHistory then return list end
	local byId = {}
	for _, entry in list do byId[entry.UserId] = entry end
	local now, half = os.time(), halfLife()
	for key, summary in Store.Index() do
		local userId = tonumber(key)
		if userId and type(summary) == "table" then
			local existing = byId[userId]
			if existing then
				existing.Persisted = true
				existing.Total = math.max(tonumber(summary.c) or 0, existing.Count)
				existing.FirstAt = math.min(tonumber(summary.f) or existing.FirstAt, existing.FirstAt)
			else
				local age = math.max(0, now - (tonumber(summary.t) or now))
				local score = (tonumber(summary.s) or 0) * 0.5 ^ (age / half)
				local kinds = {}
				for kind, count in type(summary.k) == "table" and summary.k or {} do
					table.insert(kinds, { Kind = tostring(kind), Count = tonumber(count) or 0 })
				end
				table.sort(kinds, function(a, b)
					if a.Count ~= b.Count then return a.Count > b.Count end
					return a.Kind < b.Kind
				end)
				table.insert(list, { UserId = userId, Name = tostring(summary.n or userId), DisplayName = summary.d, Score = math.floor(score + 0.5),
					Level = levelOf(score), Count = tonumber(summary.c) or 0, Total = tonumber(summary.c) or 0, FirstAt = tonumber(summary.f) or 0,
					LastAt = tonumber(summary.t) or 0, Online = Players:GetPlayerByUserId(userId) ~= nil, Kinds = kinds, Events = {},
					Persisted = true, LastOrigin = summary.o, LastConfidence = summary.cf })
			end
		end
	end
	table.sort(list, function(a, b)
		if a.Score ~= b.Score then return a.Score > b.Score end
		return a.LastAt > b.LastAt
	end)
	while #list > 100 do table.remove(list) end
	return list
end

function Sentinel.GetSuspects()
	return suspectList()
end

function Sentinel.Snapshot(player)
	if player and not has(player, "Sentinel.View") then return { Allowed = false } end
	local history = {}
	for index, alert in alerts do
		if index > MAX_ALERTS_SENT then break end
		table.insert(history, deepCopy(alert))
	end
	local moves = {}
	for index, move in serverMoves do moves[index] = deepCopy(move) end
	local count, grace = 0, 0
	for target, state in tracked do
		if target.Parent == Players then
			count += 1
			if os.clock() < state.GraceUntil or exemptions[target] then grace += 1 end
		end
	end
	local list = suspectList()
	local audit = Store and Store.GetAudit() or {}
	-- Persistence reads can yield while only Sentinel.View is revoked (the panel may stay open).
	if player and not has(player, "Sentinel.View") then return { Allowed = false } end
	return { Allowed = true, Disabled = disabled(), Config = copy(config), Bounds = BOUNDS, Alerts = history, Suspects = list, ServerMoves = moves,
		ConfigSource = ctx.SuiteConfig and ctx.SuiteConfig.Provenance("Sentinel", scriptConfig, config) or nil,
		Persist = Store and Store.Status() or { Mode = "Unavailable", Persist = false }, Audit = audit,
		TrackedPlayers = count, GracePlayers = grace, TotalAlerts = totalAlerts, SamplePasses = samplePasses, ServerMoveCount = serverMoveCount, LagFiltered = lagFiltered,
		KickAllowedByServer = ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true, Now = os.time(), SchemaVersion = 3,
		Diagnostic = msg("Observation serveur ; ownership client, latence et mécanique personnalisée limitent la certitude. Les exceptions sont exclusivement accordées par les scripts serveur.",
			"Server observation; client ownership, latency and custom mechanics limit certainty. Exemptions are granted by server scripts only.") }
end

-- Applique une configuration DÉJÀ VALIDÉE : mêmes contrôles de droits, enregistrement (SuiteConfig), puis activation.
-- Utilisée par les réglages du panneau et par l'ajout / la suppression d'une zone sûre.
local function applyConfig(player, clean, reset)
	if disabled() and clean.Enabled then return false, msg("Sentinel désactivé dans Settings.Modules côté serveur.", "Sentinel disabled in server-side Settings.Modules.") end
	if clean.EnableKick and not (ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true) then
		return false, msg("Les kicks automatiques doivent être autorisés explicitement dans Settings.Sentinel.AllowKick côté serveur.",
			"Automatic kicks must be explicitly allowed in server-side Settings.Sentinel.AllowKick.")
	end
	local reply = msg("Appliqué pour cette session.", "Applied for this session.")
	if ctx.SuiteConfig then
		local authorize = function()
			return has(player, "Sentinel.Configure") and (not disabled() or not clean.Enabled)
				and (not clean.EnableKick or (ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true))
		end
		local saved, err
		if reset then saved, err = ctx.SuiteConfig.Reset("Sentinel", authorize)
		else saved, err = ctx.SuiteConfig.Save("Sentinel", clean, authorize) end
		if not saved then return false, err or msg("Sauvegarde non confirmée.", "Save not confirmed.") end
		reply = err
	end
	if not has(player, "Sentinel.Configure") or (disabled() and clean.Enabled)
		or (clean.EnableKick and not (ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true)) then
		return false, msg("Autorisations modifiées pendant l'enregistrement ; réglage local non appliqué. Actualisez pour vérifier la sauvegarde.",
			"Permissions changed during saving; local setting not applied. Refresh to check the saved configuration.")
	end
	local changed = {}
	for key, value in clean do
		if key ~= "SafeZones" and config[key] ~= value then table.insert(changed, key) end
	end
	local before, after = config.SafeZones or {}, clean.SafeZones or {}
	local zonesChanged = #before ~= #after
	if not zonesChanged then
		for index, zone in after do
			local old = before[index]
			if not old or old.X ~= zone.X or old.Y ~= zone.Y or old.Z ~= zone.Z or old.Radius ~= zone.Radius or old.Name ~= zone.Name then zonesChanged = true break end
		end
	end
	if zonesChanged then table.insert(changed, "SafeZones") end
	table.sort(changed)
	config = clean
	if Store then
		Store.SetPolicy({ Persist = config.PersistHistory, RetentionDays = config.RetentionDays, HalfLife = halfLife() })
		if #changed > 0 then Store.Audit(player, "Config", table.concat(changed, ", ")) end
	end
	trimAlerts()
	for _, state in tracked do
		state.Streak, state.TeleportSamples, state.TeleportHits, state.Hover, state.NoclipSamples = 0, 0, 0, 0, 0
		state.LastPosition, state.PrevPosition = nil, nil
		state.GraceUntil = os.clock() + config.PhysicsGrace
	end
	ctx.Log(player.Name, reset and "ResetSentinel" or "ConfigureSentinel", nil, reply, "Sentinel", "info")
	return true, reply
end

function Sentinel.Configure(player, patch)
	if not has(player, "Sentinel.Configure") then return false, msg("Accès refusé.", "Access denied.") end
	if not ctx.Guard.Allow(player, "ConfigureSentinel", 3, 10) then return false, msg("Modifications trop fréquentes.", "Changes too frequent.") end
	local reset = type(patch) == "table" and patch.ResetToScript == true
	if type(patch) == "table" and patch.ResetToScript ~= nil then
		if not reset then return false, msg("Demande de réinitialisation invalide.", "Invalid reset request.") end
		for key in patch do if key ~= "ResetToScript" then return false, msg("La réinitialisation doit être envoyée seule.", "Reset must be requested on its own.") end end
	end
	local clean, problem = Sentinel.ValidateConfig(reset and {} or patch, reset and scriptConfig or config)
	if not clean then return false, problem end
	if reset then
		if disabled() then clean.Enabled = false end
		if not (ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true) then clean.EnableKick = false end
	end
	return applyConfig(player, clean, reset)
end

-- Actions du panneau : "Details" (userId, lecture) | "ClearSuspect" (userId) | "ClearAll" | "AddZone" ({ Name, X, Y, Z, Radius }) | "RemoveZone" (id)
function Sentinel.Action(player, action, arg)
	-- historique d'un joueur : lecture, permission Sentinel.View
	if action == "Details" then
		if not has(player, "Sentinel.View") then return false, Msg("Srv.AccessDenied") end
		if not ctx.Guard.Allow(player, "SentinelDetails", 20, 10) then return false, Msg("Srv.TooManyChanges") end
		local userId = tonumber(arg)
		if not finite(userId) then return false, Msg("Srv.InvalidParams") end
		local list = Store and config.PersistHistory and Store.Details(userId) or {}
		if #list == 0 then
			local live = suspects[userId]
			for _, event in live and live.Events or {} do table.insert(list, deepCopy(event)) end
		end
		if not has(player, "Sentinel.View") then return false, Msg("Srv.AccessDenied") end
		return true, list
	end
	if not has(player, "Sentinel.Configure") then return false, Msg("Srv.AccessDenied") end
	if not ctx.Guard.Allow(player, "SentinelAction", 10, 10) then return false, Msg("Srv.TooManyChanges") end
	if action == "ClearSuspect" then
		local userId = tonumber(arg)
		if not finite(userId) then return false, Msg("Srv.InvalidParams") end
		local label = suspects[userId] and suspects[userId].Name or tostring(userId)
		suspects[userId] = nil
		if Store then
			Store.Remove(userId)
			Store.Audit(player, "ClearSuspect", label)
		end
		return true, Msg("Sentinel.Cleared")
	elseif action == "ClearAll" then
		table.clear(suspects)
		table.clear(alerts)
		table.clear(serverMoves)
		table.clear(destinations)
		if Store then
			Store.RemoveAll()
			Store.Audit(player, "ClearAll", "")
		end
		ctx.Log(player.Name, "ClearSentinel", nil, Msg("Sentinel.Log.ClearedAll"), "Sentinel", "info")
		return true, Msg("Sentinel.ClearedAll")
	elseif action == "AddZone" then
		local zone = cleanZone(arg)
		if not zone then return false, Msg("Srv.InvalidParams") end
		local zones = {}
		local highest = 0
		for _, existing in config.SafeZones or {} do
			table.insert(zones, existing)
			highest = math.max(highest, existing.Id)
		end
		if #zones >= MAX_ZONES then return false, Msg("Sentinel.Zones.Full") end
		zone.Id = highest + 1
		table.insert(zones, zone)
		local clean = copy(config)
		clean.SafeZones = zones
		local ok, reply = applyConfig(player, clean)
		if ok then return true, Msg("Sentinel.Zones.Added") end
		return false, reply
	elseif action == "RemoveZone" then
		local id = tonumber(arg)
		if not finite(id) then return false, Msg("Srv.InvalidParams") end
		local zones, found = {}, false
		for _, existing in config.SafeZones or {} do
			if existing.Id == id then found = true else table.insert(zones, existing) end
		end
		if not found then return false, Msg("Srv.InvalidParams") end
		local clean = copy(config)
		clean.SafeZones = zones
		local ok, reply = applyConfig(player, clean)
		if ok then return true, Msg("Sentinel.Zones.Removed") end
		return false, reply
	end
	return false, Msg("Srv.InvalidParams")
end

-- Diagnostic synthétique : aucune mesure réelle, personne n'est déplacé ni sanctionné
local TEST_LABELS = { normal = "Sentinel.Test.Normal", speed = "Sentinel.Test.Speed", teleport = "Sentinel.Test.Teleport", fly = "Sentinel.Test.Fly",
	walkspeed = "Sentinel.Test.WalkSpeed", grace = "Sentinel.Test.Grace" }
local PRIMARY_FLAGS = { "teleport", "speed", "vertical", "fly", "walkspeed", "jumpheight" }
local FLAG_KIND_KEYS = { teleport = "Sentinel.Kind.Teleport", speed = "Sentinel.Kind.Speed", vertical = "Sentinel.Kind.Speed",
	fly = "Sentinel.Kind.Fly", walkspeed = "Sentinel.Kind.Humanoid", jumpheight = "Sentinel.Kind.Humanoid" }
function Sentinel.Test(player, scenario)
	if not has(player, "Sentinel.Test") then return false, msg("Accès refusé.", "Access denied.") end
	if disabled() then return false, msg("Sentinel désactivé dans Settings.Modules côté serveur.", "Sentinel disabled in server-side Settings.Modules.") end
	if not ctx.Guard.Allow(player, "TestSentinel", 3, 10) then return false, msg("Tests trop fréquents.", "Tests too frequent.") end
	if type(scenario) ~= "string" or not TEST_LABELS[scenario] then return false, msg("Scénario invalide.", "Invalid scenario.") end
	local flags, off = {}, false
	if scenario == "speed" or scenario == "teleport" or scenario == "normal" or scenario == "grace" then
		local sample = { Dt = 1, Horizontal = scenario == "speed" and (config.SpeedLimitEnabled and config.SpeedLimit * 3 or 220) or scenario == "teleport" and 1000 or 16,
			Vertical = 0, WalkSpeed = 16, Ping = 0.1, Grounded = true, Grace = scenario == "grace" }
		flags = Sentinel.EvaluateSample(config, sample)
		if scenario == "speed" and config.DetectSpeed == false then off = true end
		if scenario == "teleport" and config.DetectTeleport == false then off = true end
	elseif scenario == "fly" then
		off = config.DetectFly == false
		if Sentinel.EvaluateFly(config, config.FlySeconds + 1) then flags = { "fly" } end
	elseif scenario == "walkspeed" then
		off = not config.SpeedLimitEnabled or config.DetectHumanoid == false
		flags = Sentinel.EvaluateHumanoid(config, { WalkSpeed = (config.SpeedLimitEnabled and config.SpeedLimit or 50) * 2, JumpHeight = 7 })
	end
	local label = TEST_LABELS[scenario]
	local detail
	if scenario == "grace" then
		detail = Msg("Sentinel.Test.GraceResult")
	elseif #flags > 0 then
		local primary
		for _, name in PRIMARY_FLAGS do
			if table.find(flags, name) then primary = name break end
		end
		detail = Msg("Sentinel.Test.Flagged", label, FLAG_KIND_KEYS[primary] or "Sentinel.Kind.Speed")
	elseif off then
		detail = Msg("Sentinel.Test.Disabled", label)
	else
		detail = Msg("Sentinel.Test.Clean", label)
	end
	addAlert(player, "Diagnostic", detail, { Scenario = scenario, Flags = table.concat(flags, ",") }, "Server", {}, "High", 0, true)
	return true, detail
end

function Sentinel.Init(context)
	if ctx then return Sentinel end
	ctx = context
	Msg = ctx.Msg
	config = copy(DEFAULTS)
	local initial = {}
	for key, value in type(ctx.Settings.Sentinel) == "table" and ctx.Settings.Sentinel or {} do if DEFAULTS[key] ~= nil then initial[key] = value end end
	config = Sentinel.ValidateConfig(initial, config) or config
	if disabled() then config.Enabled = false end
	if not (ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true) then config.EnableKick = false end
	scriptConfig = deepCopy(config)
	if ctx.SuiteConfig then config = Sentinel.ValidateConfig(ctx.SuiteConfig.Snapshot("Sentinel") or {}, config) or config end
	if disabled() then config.Enabled = false end
	if not (ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true) then config.EnableKick = false end
	-- mémoire permanente : dates, infractions, positions (DataStore de l'APM)
	local storeModule = script.Parent:FindFirstChild("SentinelStore")
	if storeModule then
		local okStore, loaded = pcall(require, storeModule)
		if okStore and type(loaded) == "table" then
			Store = loaded
			Store.Init(ctx)
			Store.SetPolicy({ Persist = config.PersistHistory, RetentionDays = config.RetentionDays, HalfLife = halfLife() })
		else
			warn("[APM] SentinelStore indisponible : " .. tostring(loaded))
		end
	end
	ctx.Remotes.GetSentinel.OnServerInvoke = function(player)
		if not has(player, "Sentinel.View") or not ctx.Guard.Allow(player, "GetSentinel", 10, 10) then return { Allowed = false } end
		return Sentinel.Snapshot(player)
	end
	ctx.Remotes.ConfigureSentinel.OnServerInvoke = Sentinel.Configure
	ctx.Remotes.TestSentinel.OnServerInvoke = Sentinel.Test
	ctx.Remotes.SentinelAction.OnServerInvoke = Sentinel.Action
	for _, player in Players:GetPlayers() do track(player) end
	table.insert(connections, Players.PlayerAdded:Connect(track))
	table.insert(connections, Players.PlayerRemoving:Connect(Sentinel.CleanupPlayer))
	running = true
	task.spawn(function()
		while running do
			task.wait(config.Interval)
			if not running then break end
			if config.Enabled then pass() end
		end
	end)
	if Store then
		-- filet de sécurité : écriture périodique, et à l'arrêt du serveur
		task.spawn(function()
			while running do
				task.wait(45 + math.random() * 10)
				if running then Store.Flush() end
			end
		end)
		game:BindToClose(function() Store.Flush(true) end)
	end
	return Sentinel
end

function Sentinel.Destroy()
	running = false
	for _, connection in connections do connection:Disconnect() end
	table.clear(connections)
	for player in tracked do Sentinel.CleanupPlayer(player) end
	table.clear(exemptions)
end

return Sentinel
