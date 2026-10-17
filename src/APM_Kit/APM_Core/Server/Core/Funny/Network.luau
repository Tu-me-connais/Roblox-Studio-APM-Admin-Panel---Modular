--[[
	Funny.Network : diffusion « au mieux » des scènes entre les serveurs de la même expérience (MessagingService).
	Studio ne contacte jamais les topics de production. Chaque message reçu est validé champ par champ, dédoublonné,
	limité en débit, et les droits annoncés ne peuvent que restreindre ceux résolus localement.
]]
local Network = {}

local PERMISSIONS = { "APM.AccessPanel", "Funny.View", "Funny.Use", "Funny.Server", "Funny.CrossServer", "Funny.Group", "Funny.Transform", "Funny.Physics" }
local ALLOWED = {}
for _, name in PERMISSIONS do
	ALLOWED[name] = true
end

local function message(fr, en)
	return { fr = fr, en = en }
end

local function finite(n)
	return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function guid(s)
	return type(s) == "string" and #s == 36 and s:match("^[%x%-]+$") ~= nil
end

function Network.Create(ctx, engine, services)
	services = services or {}
	local bus = services.MessagingService or game:GetService("MessagingService")
	local http = services.HttpService or game:GetService("HttpService")
	local now = services.Clock or function() return workspace:GetServerTimeNow() end
	local spawn = services.Spawn or task.spawn
	local delay = services.Delay or task.delay
	local universe = services.GameId or game.GameId
	local origin = services.JobId or game.JobId
	if origin == "" then origin = http:GenerateGUID(false) end
	local studio = services.IsStudio
	if studio == nil then studio = game:GetService("RunService"):IsStudio() end
	local config = ctx.Settings.Funny or {}
	local topic = config.MessagingTopic or "APM_Funny_v1"
	local enabled = config.CrossServerEnabled ~= false and not studio and universe > 0 and type(topic) == "string" and #topic >= 1 and #topic <= 80
	local state = { Available = false, Published = 0, Received = 0, Dropped = 0, LastError = nil,
		Reason = studio and message("Studio : diffusion vers les serveurs publiés désactivée.", "Studio: broadcasting to published servers is disabled.")
			or not enabled and message("Diffusion désactivée ou expérience/topic invalide.", "Broadcast disabled or invalid experience/topic.")
			or message("Connexion à MessagingService…", "Connecting to MessagingService…") }
	local api = {}
	local subscription, retry, destroyed = nil, 5, false
	local seen, stopped, batches, locks, rates, actors, stopAttempts = {}, {}, {}, {}, {}, {}, {}

	local function stopKey(e)
		return e.Origin .. ":" .. e.Actor .. ":" .. e.Batch
	end
	local function prune()
		local time = now()
		for _, cache in { seen, stopped } do
			for key, expiry in cache do
				if expiry <= time then cache[key] = nil end
			end
		end
		for key, batch in batches do
			if batch.Ends <= time then
				batches[key] = nil
				actors[key] = nil
				stopAttempts[key] = nil
			end
		end
		for key, rate in rates do
			if rate.Reset <= time then rates[key] = nil end
		end
	end
	local function remember(cache, key)
		local count = 0
		for _ in cache do count += 1 end
		-- Reject new starts on saturation instead of evicting an unexpired replay fence.
		if not cache[key] and count >= 512 then return false end
		cache[key] = now() + 120
		return true
	end
	local function validate(e)
		if type(e) ~= "table" then return false end
		local keys = { V = true, Id = true, Batch = true, Origin = true, Universe = true, Actor = true, Name = true, Level = true, Permissions = true, Issued = true, Ends = true, Action = true, Request = true }
		for key in e do
			if not keys[key] then return false end
		end
		if e.V ~= 1 or not guid(e.Id) or not guid(e.Batch) or type(e.Origin) ~= "string" or #e.Origin < 1 or #e.Origin > 128 or e.Universe ~= universe
			or not finite(e.Actor) or e.Actor < 1 or e.Actor % 1 ~= 0 or e.Actor >= 2 ^ 53
			or not finite(e.Issued) or not finite(e.Ends) or e.Issued > now() + 5 or e.Issued < now() - 70 or e.Ends <= now() or e.Ends > e.Issued + 60.1
			or (e.Action ~= "Start" and e.Action ~= "Stop") then
			return false
		end
		if e.Action == "Stop" then return e.Request == nil end
		if e.Id ~= e.Batch or type(e.Name) ~= "string" or #e.Name < 1 or #e.Name > 20 or not e.Name:match("^[%w_]+$")
			or not finite(e.Level) or e.Level <= 0 or e.Level > 1000000 or type(e.Permissions) ~= "table" then
			return false
		end
		for name, value in e.Permissions do
			if not ALLOWED[name] or type(value) ~= "boolean" then return false end
		end
		for _, name in { "APM.AccessPanel", "Funny.View", "Funny.Use", "Funny.Server", "Funny.CrossServer" } do
			if e.Permissions[name] ~= true then return false end
		end
		local request = engine.Validate(e.Request)
		return request ~= nil and request.Scope == "Server" and request.Scenario ~= "Random" and e.Ends <= e.Issued + request.Duration + .1
	end
	local function receive(packet)
		if destroyed or not enabled then return end
		prune()
		local data = packet and packet.Data
		if type(data) ~= "string" or #data > 1024 then
			state.Dropped += 1
			return
		end
		local ok, e = pcall(http.JSONDecode, http, data)
		if not ok or not validate(e) then
			state.Dropped += 1
			return
		end
		if e.Origin == origin or seen[e.Id] then
			state.Dropped += 1
			return
		end
		if not remember(seen, e.Id) and e.Action == "Start" then -- before authority can yield
			state.Dropped += 1
			return
		end
		if e.Action == "Stop" then
			remember(stopped, stopKey(e))
			engine.StopNetwork(e.Batch, e.Actor, e.Origin)
			state.Received += 1
			return
		end
		local tombstones = 0
		for _ in stopped do tombstones += 1 end
		if stopped[stopKey(e)] or tombstones >= 512 then
			state.Dropped += 1
			return
		end
		local rateKey = e.Origin .. ":" .. e.Actor
		local rate = rates[rateKey]
		if not rate then
			rate = { Count = 0, Reset = now() + 10 }
			rates[rateKey] = rate
		end
		rate.Count += 1
		if rate.Count > 3 then
			state.Dropped += 1
			return
		end
		spawn(function()
			-- A stop can arrive during a yielding group/avatar lookup. Its tombstone is checked again.
			local success, applied = pcall(engine.StartRemote, e, function() return not destroyed and not stopped[stopKey(e)] and e.Ends > now() end)
			if stopped[stopKey(e)] or destroyed then engine.StopNetwork(e.Batch, e.Actor, e.Origin) end
			if success and applied then
				state.Received += 1
			else
				state.Dropped += 1
				if not success then state.LastError = tostring(applied) end
			end
		end)
	end
	local connect
	connect = function()
		if destroyed or not enabled then return end
		local ok, result = pcall(bus.SubscribeAsync, bus, topic, receive)
		if destroyed then
			if ok and result then result:Disconnect() end
			return
		end
		if ok then
			subscription = result
			state.Available = true
			state.Reason = nil
			state.LastError = nil
			retry = 5
		else
			state.Available = false
			state.Reason = message("MessagingService indisponible ; reconnexion prévue.", "MessagingService unavailable; reconnection scheduled.")
			state.LastError = tostring(result)
			delay(retry, connect)
			retry = math.min(60, retry * 2)
		end
	end
	if enabled then spawn(connect) end
	local function publish(e)
		local ok, data = pcall(http.JSONEncode, http, e)
		if not ok or #data > 1024 then return false, "Message exceeds Roblox's 1 KB limit" end
		local sent, err = pcall(bus.PublishAsync, bus, topic, data)
		if sent then
			state.Published += 1
			return true
		end
		state.LastError = tostring(err)
		return false, tostring(err)
	end
	local function stopBatch(batch)
		remember(stopped, stopKey(batch))
		stopAttempts[batch.Batch] = now()
		engine.StopNetwork(batch.Batch, batch.Actor, origin)
		local e = { V = 1, Id = http:GenerateGUID(false), Batch = batch.Batch, Origin = origin, Universe = universe, Actor = batch.Actor, Action = "Stop", Issued = now(), Ends = now() + 60 }
		local sent = publish(e)
		if sent then
			batches[batch.Batch] = nil
			actors[batch.Batch] = nil
		end
		return sent
	end

	function api.Start(actor, request)
		prune()
		if not state.Available then return false, state.Reason or message("Interserveurs indisponible.", "Cross-server unavailable.") end
		for _, name in { "APM.AccessPanel", "Funny.View", "Funny.Use", "Funny.Server", "Funny.CrossServer" } do
			if not engine.Can(actor, name) then return false, message("Permission interserveurs refusée.", "Cross-server permission denied.") end
		end
		if actor.UserId <= 0 or locks[actor.UserId] then return false, message("Diffusion en cours ou compte de test.", "Broadcast pending or test account.") end
		local clean = engine.Validate(request)
		if not clean or clean.Scope ~= "Server" then return false, message("Paramètres invalides.", "Invalid parameters.") end
		clean.Scenario = engine.ResolveScenario(clean.Scenario)
		local permission = engine.ScenarioPermission(clean.Scenario)
		if permission and not engine.Can(actor, permission) then return false, message("Permission de scène refusée.", "Scene permission denied.") end
		local permissions = {}
		for _, name in PERMISSIONS do permissions[name] = engine.Can(actor, name) end
		local id = http:GenerateGUID(false)
		local e = { V = 1, Id = id, Batch = id, Origin = origin, Universe = universe, Actor = actor.UserId, Name = actor.Name, Level = ctx.Ranks.GetLevel(actor),
			Permissions = permissions, Issued = now(), Ends = now() + clean.Duration, Action = "Start", Request = clean }
		locks[actor.UserId] = true
		batches[id] = e
		actors[id] = actor
		remember(seen, id)
		local ok, success, reply, result = pcall(engine.Start, actor, clean, { Reach = "CrossServer", NetworkId = id, Origin = origin, Ends = e.Ends })
		if not ok or not success or stopped[stopKey(e)] or e.Ends <= now() or not engine.Can(actor, "Funny.CrossServer") then
			engine.StopNetwork(id, actor.UserId, origin)
			batches[id] = nil
			actors[id] = nil
			locks[actor.UserId] = nil
			return false, message("Diffusion annulée ; aucune action distante publiée.", "Broadcast cancelled; no remote action published.")
		end
		local sent = publish(e)
		locks[actor.UserId] = nil
		if not sent then
			engine.StopNetwork(id, actor.UserId, origin)
			batches[id] = nil
			actors[id] = nil
			return false, message("Publication refusée par MessagingService ; effets locaux restaurés.", "MessagingService rejected publication; local effects restored.")
		end
		if stopped[stopKey(e)] or not engine.Can(actor, "Funny.CrossServer") then
			stopBatch(e)
			return false, message("Diffusion révoquée ; arrêt envoyé.", "Broadcast revoked; stop sent.")
		end
		result.NetworkId = id
		return true, message("Effet local lancé ; diffusion envoyée aux serveurs actifs. Réception selon MessagingService.", "Local effect started; broadcast sent to active servers. Delivery depends on MessagingService."), result
	end

	function api.StopSelected(actor, ids)
		local sent = true
		for id in ids do
			local batch = batches[id]
			if batch and batch.Actor == actor.UserId then
				if not stopBatch(batch) then sent = false end
			end
		end
		return sent
	end

	function api.StopMine(actor)
		prune()
		local ids = {}
		for id, batch in batches do
			if batch.Actor == actor.UserId then ids[id] = true end
		end
		local sent = api.StopSelected(actor, ids)
		return sent, message(sent and "Arrêt de mes diffusions envoyé ; durée limite conservée." or "Arrêt local effectué ; envoi distant échoué, expiration automatique maintenue.",
			sent and "Stop for my broadcasts sent; duration limit retained." or "Stopped locally; remote stop failed, automatic expiry retained.")
	end

	function api.Reconcile()
		prune()
		for id, batch in batches do
			local actor = actors[id]
			local permission = engine.ScenarioPermission(batch.Request.Scenario)
			local revoked = not actor or not engine.Can(actor, "APM.AccessPanel") or not engine.Can(actor, "Funny.View") or not engine.Can(actor, "Funny.Use")
				or not engine.Can(actor, "Funny.Server") or not engine.Can(actor, "Funny.CrossServer") or permission and not engine.Can(actor, permission)
			if (revoked or stopped[stopKey(batch)]) and now() - (stopAttempts[id] or -math.huge) >= 5 then stopBatch(batch) end
		end
	end

	function api.Snapshot(actor)
		prune()
		local result = table.clone(state)
		local mine = 0
		for _, batch in batches do
			if batch.Actor == actor.UserId then mine += 1 end
		end
		result.MyBroadcasts = mine
		result.BestEffort = true
		return result
	end

	function api.Destroy()
		destroyed = true
		if subscription then subscription:Disconnect() end
	end
	return api
end

return Network
