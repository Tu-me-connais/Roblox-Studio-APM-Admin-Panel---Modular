-- Sentinel Guard: conservative server observations, bounded history and opt-in reactions.
-- A detection is evidence to investigate, never proof of cheating. No automatic ban.
local Players = game:GetService("Players")
local Sentinel = {}
local ctx, config, running = nil, nil, false
local tracked, exemptions, alerts, connections = {}, {}, {}, {}
local totalAlerts, samplePasses = 0, 0
local DEFAULTS = { Enabled = true, Mode = "Observation", Interval = 1, MaxHorizontalSpeed = 90, MaxVerticalSpeed = 180,
	TeleportDistance = 140, LatencyAllowance = 35, SpawnGrace = 8, PhysicsGrace = 3, RequiredSamples = 4,
	AlertCooldown = 15, MaxAlerts = 200, ExemptAdmins = true, NotifyAdmins = true, CorrectPosition = false, EnableKick = false }
local MODES = { Observation = true, Balanced = true, Strict = true }
local BOUNDS = { Interval = { 0.5, 10 }, MaxHorizontalSpeed = { 20, 2000 }, MaxVerticalSpeed = { 40, 4000 },
	TeleportDistance = { 30, 10000 }, LatencyAllowance = { 5, 500 }, SpawnGrace = { 3, 120 }, PhysicsGrace = { 1, 60 },
	RequiredSamples = { 3, 30 }, AlertCooldown = { 3, 300 }, MaxAlerts = { 25, 300 } }
local INTEGER = { RequiredSamples = true, MaxAlerts = true }
local SAFE_PHYSICS_STATES = { [Enum.HumanoidStateType.Physics] = true, [Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true, [Enum.HumanoidStateType.PlatformStanding] = true }
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
local function msg(fr, en) return { fr = fr, en = en } end
local function has(player, name)
	return typeof(player) == "Instance" and player:IsA("Player") and player.Parent == Players
		and ctx.Ranks.HasPermission(player, "APM.AccessPanel") and ctx.Ranks.HasPermission(player, name)
end
function Sentinel.ValidateConfig(patch, base)
	if type(patch) ~= "table" then return nil, "Configuration invalide." end
	local clean = copy(base or DEFAULTS)
	for key, value in patch do
		if key == "Mode" then
			if not MODES[value] then return nil, "Mode inconnu." end
			clean.Mode = value
		elseif BOUNDS[key] then
			local bound = BOUNDS[key]
			if not finite(value) or value < bound[1] or value > bound[2] then return nil, "Valeur hors limites : " .. key end
			clean[key] = INTEGER[key] and math.floor(value) or value
		elseif type(DEFAULTS[key]) == "boolean" then
			if type(value) ~= "boolean" then return nil, "Booléen attendu : " .. key end
			clean[key] = value
		else return nil, "Paramètre inconnu : " .. tostring(key) end
	end
	return clean
end

-- Pure observation classifier used by the runtime and synthetic diagnostics.
function Sentinel.EvaluateSample(settings, sample)
	local dt = sample.Dt
	if not finite(dt) or dt < 0.1 or dt > math.max(3, settings.Interval * 3) or sample.Grace then return {} end
	local horizontal = finite(sample.Horizontal) and math.max(0, sample.Horizontal) or 0
	local vertical = finite(sample.Vertical) and math.max(0, sample.Vertical) or 0
	local walk = finite(sample.WalkSpeed) and math.max(0, sample.WalkSpeed) or 16
	local platform = finite(sample.PlatformSpeed) and math.clamp(sample.PlatformSpeed, 0, 500) or 0
	local ping = finite(sample.Ping) and math.clamp(sample.Ping, 0, 2) or 0
	local multiplier = settings.Mode == "Strict" and 1.15 or settings.Mode == "Balanced" and 1.4 or 1.6
	local allowedSpeed = math.max(settings.MaxHorizontalSpeed, walk * 3) * multiplier + platform
	local slack = settings.LatencyAllowance * (1 + ping * 3)
	local horizontalLimit = allowedSpeed * dt + slack
	local flags = {}
	if horizontal > horizontalLimit then table.insert(flags, "speed") end
	if horizontal > settings.TeleportDistance * multiplier + horizontalLimit then table.insert(flags, "teleport") end
	-- Vertical motion in jumping/freefall/climbing is ambiguous and does not contribute a vertical strike.
	if sample.Grounded and vertical > settings.MaxVerticalSpeed * dt + slack then table.insert(flags, "vertical") end
	return flags, { Horizontal = math.floor(horizontal), Vertical = math.floor(vertical), Limit = math.floor(horizontalLimit),
		Dt = math.floor(dt * 100) / 100, Ping = math.floor(ping * 1000) }
end

local function trimAlerts()
	while #alerts > config.MaxAlerts do table.remove(alerts) end
end
local function addAlert(player, kind, detail, evidence, isTest)
	totalAlerts += 1
	local alert = { Id = totalAlerts, Time = os.time(), UserId = player.UserId, Name = player.Name,
		Kind = kind, Detail = string.sub(tostring(detail), 1, 420), Evidence = evidence or 0, Mode = config.Mode,
		Test = isTest == true, Reaction = "Logged", Confidence = "Heuristique ; vérifier les mécaniques du jeu et la latence." }
	table.insert(alerts, 1, alert)
	trimAlerts()
	ctx.Log("Sentinel", isTest and "Sentinel.Test" or "Sentinel.Alert", player.Name,
		(isTest and "DIAGNOSTIC SYNTHÉTIQUE : " or "") .. alert.Detail, "Sentinel", isTest and "info" or "warning")
	if config.NotifyAdmins and not isTest then
		for _, admin in Players:GetPlayers() do
			if has(admin, "Sentinel.View") then ctx.Notify(admin, msg("Sentinel : " .. player.Name .. " — " .. alert.Detail,
				"Sentinel: " .. player.Name .. " — " .. alert.Detail), false) end
		end
		alert.Reaction = "Logged + admin alert"
	end
	return alert
end

function Sentinel.Exempt(player, seconds, reason)
	if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players or not finite(seconds) then return false end
	local untilAt = os.clock() + math.clamp(seconds, 0, 120)
	local previous = exemptions[player]
	exemptions[player] = { Until = math.max(untilAt, previous and previous.Until or 0), Reason = string.sub(tostring(reason or "Server-authorized mechanic"), 1, 100) }
	local state = tracked[player]
	if state then state.Streak = 0; state.LastPosition = nil end
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
	local state = { Streak = 0, TeleportSamples = 0, Abuse = 0, AbuseAt = os.clock(), LastAlert = -math.huge,
		GraceUntil = os.clock() + config.SpawnGrace, LastCorrect = -math.huge }
	tracked[player] = state
	state.Connection = player.CharacterAdded:Connect(function()
		state.Streak, state.TeleportSamples, state.LastPosition, state.SafeCFrame = 0, 0, nil, nil
		state.GraceUntil = os.clock() + config.SpawnGrace
	end)
end

-- Server gateway only; no client can submit arbitrary records through an endpoint.
function Sentinel.RecordAbuse(player, category, detail)
	if not ctx or not config.Enabled or typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then return end
	track(player)
	local state, now = tracked[player], os.clock()
	if now - state.AbuseAt > 60 then state.Abuse, state.AbuseAt = 0, now end
	state.Abuse = math.min(state.Abuse + 1, 100)
	if state.Abuse >= 8 and now - state.LastAlert >= config.AlertCooldown then
		state.LastAlert = now
		addAlert(player, "RemoteAbuse", "Requêtes refusées répétées (" .. state.Abuse .. "/60 s) : " .. string.sub(tostring(category), 1, 50)
			.. ". " .. string.sub(tostring(detail or "Validation serveur"), 1, 160), state.Abuse)
	end
end

local function samplePlayer(player, now)
	local state = tracked[player]
	if not state then track(player); state = tracked[player] end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then state.LastPosition = nil; return end
	local exempt = exemptions[player]
	if exempt and now >= exempt.Until then exemptions[player] = nil; exempt = nil end
	local adminExempt = config.ExemptAdmins and ctx.Ranks.IsAdmin(player) and ctx.Ranks.HasPermission(player, "APM.AccessPanel")
	local physics = humanoid.SeatPart ~= nil or humanoid.Sit or humanoid.PlatformStand or SAFE_PHYSICS_STATES[humanoid:GetState()]
	if physics then state.GraceUntil = math.max(state.GraceUntil, now + config.PhysicsGrace) end
	local position = root.Position
	if not finite(position.X) or not finite(position.Y) or not finite(position.Z) then state.LastPosition = nil; return end
	local lastPosition, lastAt = state.LastPosition, state.LastAt
	state.LastPosition, state.LastAt = position, now
	if adminExempt or exempt or now < state.GraceUntil or not lastPosition then
		state.Streak, state.TeleportSamples = 0, 0
		return
	end
	local ping = 0
	local ok, value = pcall(player.GetNetworkPing, player)
	if ok and finite(value) then ping = math.clamp(value, 0, 2) end
	local grounded = humanoid.FloorMaterial ~= Enum.Material.Air
	local platformSpeed = 0
	if grounded then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		local hit = workspace:Raycast(position, Vector3.new(0, -7, 0), params)
		if hit and hit.Instance:IsA("BasePart") then platformSpeed = hit.Instance.AssemblyLinearVelocity.Magnitude end
	end
	local delta = position - lastPosition
	local flags, measures = Sentinel.EvaluateSample(config, { Dt = now - lastAt,
		Horizontal = Vector3.new(delta.X, 0, delta.Z).Magnitude, Vertical = math.abs(delta.Y), WalkSpeed = humanoid.WalkSpeed,
		PlatformSpeed = platformSpeed, Ping = ping, Grounded = grounded })
	if #flags == 0 then
		state.Streak = math.max(0, state.Streak - 1)
		state.TeleportSamples = math.max(0, state.TeleportSamples - 1)
		if grounded and now - state.LastCorrect > config.PhysicsGrace and state.Streak == 0 then state.SafeCFrame, state.SafeAt = root.CFrame, now end
		return
	end
	state.Streak += 1
	if table.find(flags, "teleport") then state.TeleportSamples += 1 end
	if state.Streak < config.RequiredSamples or now - state.LastAlert < config.AlertCooldown then return end
	state.LastAlert = now
	local detail = ("Mouvement répété : %s, %d studs horizontaux / %.2f s, limite %d ; ping %d ms. Vérifier capacités, physique et téléports autorisés.")
		:format(table.concat(flags, ", "), measures.Horizontal, measures.Dt, measures.Limit, measures.Ping)
	local alert = addAlert(player, "Movement", detail, state.Streak)
	-- Correction is optional, requires repeated teleport evidence and a recent ground-validated position.
	if config.Mode ~= "Observation" and config.CorrectPosition and state.TeleportSamples >= config.RequiredSamples
		and state.SafeCFrame and state.SafeAt and now - state.SafeAt <= 30 and now - state.LastCorrect >= 10 then
		root.CFrame = state.SafeCFrame
		root.AssemblyLinearVelocity = Vector3.zero
		state.LastCorrect = now
		alert.Reaction = "Corrected to recent server-observed grounded position"
		Sentinel.NotifyServerTeleport(player, config.PhysicsGrace, "Sentinel correction")
	end
	-- Kicking additionally requires explicit server opt-in, Strict mode, a long repeated teleport streak AND refused remote evidence.
	-- Movement alone never triggers a kick; production defaults keep this disabled.
	if config.Mode == "Strict" and config.EnableKick and ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true
		and state.Streak >= math.max(12, config.RequiredSamples * 3) and state.TeleportSamples >= 12
		and state.Abuse >= 20 and now - state.AbuseAt <= 60 then
		alert.Reaction = "Kick by explicit configured multi-signal rule"
		player:Kick(ctx.Lang and ctx.Lang.ForPlayer(player) == "fr" and "Requêtes abusives répétées et mouvements invalides. Rejoins le serveur ou contacte la modération."
			or "Repeated invalid requests and movement. Rejoin or contact moderation.")
	end
end

function Sentinel.Snapshot(player)
	if player and not has(player, "Sentinel.View") then return { Allowed = false } end
	local history = {}
	for _, alert in alerts do table.insert(history, copy(alert)) end
	local count, grace = 0, 0
	for target, state in tracked do
		if target.Parent == Players then count += 1; if os.clock() < state.GraceUntil or exemptions[target] then grace += 1 end end
	end
	return { Allowed = true, Disabled = disabled(), Config = copy(config), Alerts = history, TrackedPlayers = count, GracePlayers = grace,
		TotalAlerts = totalAlerts, SamplePasses = samplePasses, KickAllowedByServer = ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true,
		SchemaVersion = 2, Diagnostic = "Observation serveur ; ownership client, latence et mécanique personnalisée limitent la certitude. Les exceptions sont exclusivement accordées par les scripts serveur." }
end
function Sentinel.Configure(player, patch)
	if not has(player, "Sentinel.Configure") then return false, msg("Accès refusé.", "Access denied.") end
	if not ctx.Guard.Allow(player, "ConfigureSentinel", 3, 10) then return false, "Modifications trop fréquentes." end
	local clean, problem = Sentinel.ValidateConfig(patch, config)
	if not clean then return false, problem end
	if disabled() and clean.Enabled then return false, "Sentinel désactivé dans Settings.Modules côté serveur." end
	if clean.EnableKick and not (ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true) then return false, "Les kicks automatiques doivent être autorisés explicitement dans Settings.Sentinel.AllowKick côté serveur." end
	if ctx.SuiteConfig then
		local saved, err = ctx.SuiteConfig.Save("Sentinel", clean, function()
			return has(player, "Sentinel.Configure") and (not disabled() or not clean.Enabled)
		end)
		if not saved then return false, err or "Sauvegarde non confirmée." end
	end
	if not has(player, "Sentinel.Configure") or (disabled() and clean.Enabled) then return false, "Autorisations modifiées : configuration annulée." end
	config = clean
	trimAlerts()
	for _, state in tracked do state.Streak, state.TeleportSamples, state.LastPosition = 0, 0, nil; state.GraceUntil = os.clock() + config.PhysicsGrace end
	ctx.Log(player.Name, "ConfigureSentinel", nil, "Mode " .. config.Mode .. ", intervalle " .. config.Interval .. " s", "Sentinel", "info")
	return true, msg("Réglages Sentinel appliqués.", "Sentinel settings applied.")
end
function Sentinel.Test(player, scenario)
	if not has(player, "Sentinel.Test") then return false, msg("Accès refusé.", "Access denied.") end
	if disabled() then return false, "Sentinel désactivé dans Settings.Modules côté serveur." end
	if not ctx.Guard.Allow(player, "TestSentinel", 3, 10) then return false, "Tests trop fréquents." end
	if scenario ~= "normal" and scenario ~= "speed" and scenario ~= "teleport" and scenario ~= "grace" then return false, "Scénario invalide." end
	local sample = { Dt = 1, Horizontal = scenario == "speed" and 220 or scenario == "teleport" and 1000 or 16,
		Vertical = 0, WalkSpeed = 16, Ping = 0.1, Grounded = true, Grace = scenario == "grace" }
	local flags = Sentinel.EvaluateSample(config, sample)
	local detail = "Test " .. scenario .. " : " .. (#flags > 0 and table.concat(flags, ", ") or "aucun signal") .. ". Données synthétiques ; aucun mouvement, privilège ou sanction modifié."
	addAlert(player, "Diagnostic", detail, 0, true)
	return true, detail
end

function Sentinel.Init(context)
	if ctx then return Sentinel end
	ctx = context
	config = copy(DEFAULTS)
	local initial = {}
	for key, value in type(ctx.Settings.Sentinel) == "table" and ctx.Settings.Sentinel or {} do if DEFAULTS[key] ~= nil then initial[key] = value end end
	config = Sentinel.ValidateConfig(initial, config) or config
	if ctx.SuiteConfig then config = Sentinel.ValidateConfig(ctx.SuiteConfig.Snapshot("Sentinel") or {}, config) or config end
	if disabled() then config.Enabled = false end
	if not (ctx.Settings.Sentinel and ctx.Settings.Sentinel.AllowKick == true) then config.EnableKick = false end
	ctx.Remotes.GetSentinel.OnServerInvoke = function(player)
		if not has(player, "Sentinel.View") or not ctx.Guard.Allow(player, "GetSentinel", 10, 10) then return { Allowed = false } end
		return Sentinel.Snapshot(player)
	end
	ctx.Remotes.ConfigureSentinel.OnServerInvoke = Sentinel.Configure
	ctx.Remotes.TestSentinel.OnServerInvoke = Sentinel.Test
	for _, player in Players:GetPlayers() do track(player) end
	table.insert(connections, Players.PlayerAdded:Connect(track))
	table.insert(connections, Players.PlayerRemoving:Connect(Sentinel.CleanupPlayer))
	running = true
	task.spawn(function()
		while running do
			task.wait(config.Interval)
			if not running then break end
			if config.Enabled then
				samplePasses += 1
				for _, player in Players:GetPlayers() do
					local ok, err = pcall(samplePlayer, player, os.clock())
					if not ok and ctx.Guard.Allow(player, "SentinelSamplingError", 1, 60) then
						ctx.Log("Sentinel", "Sentinel.Error", player.Name, "Échantillon ignoré : " .. string.sub(tostring(err), 1, 160), "Sentinel", "warning")
					end
				end
			end
		end
	end)
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
