-- Live server readings only. No DataStore writes, client-reported device data or remote providers.
local Version = require(script.Parent.Version)
local Telemetry = { PlayerPageSize = 20, LeaderstatsLimit = 40 }
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function read(callback)
	local ok, value = pcall(callback)
	return ok and finite(value) and value or nil
end
local function short(value, limit)
	if type(value) ~= "string" or not utf8.len(value) then return nil end
	local finish = utf8.offset(value, limit + 1)
	return finish and value:sub(1, finish - 1) .. "…" or value
end
function Telemetry.Options(options)
	if options == nil then return { Search = "", Offset = 0 } end
	if type(options) ~= "table" then return nil end
	for key in options do if key ~= "Search" and key ~= "Offset" then return nil end end
	local search, offset = options.Search, options.Offset
	if search == nil then search = "" end
	if offset == nil then offset = 0 end
	if type(search) ~= "string" or #search > 64 or not utf8.len(search)
			or not finite(offset) or offset < 0 or offset > 10000 or offset % 1 ~= 0 then return nil end
	return { Search = search:match("^%s*(.-)%s*$"), Offset = offset }
end
function Telemetry.Create(ctx, services)
	-- En production, le cycle serveur vient du compteur de Statistics ; avec des services injectés (tests), compteur propre.
	local sharedClock = services == nil and ctx.Statistics and type(ctx.Statistics.HeartbeatHz) == "function" and ctx.Statistics or nil
	services = services or { Players = game:GetService("Players"), RunService = game:GetService("RunService"),
		Workspace = workspace, DataModel = game, Lighting = game:GetService("Lighting"), Stats = game:GetService("Stats"),
		Teams = game:GetService("Teams"), Marketplace = game:GetService("MarketplaceService"), Clock = os.clock, Unix = os.time }
	local Players, RunService, W, G = services.Players, services.RunService, services.Workspace, services.DataModel
	local clock, unix = services.Clock, services.Unix
	local startedAt = unix() - math.max(0, math.floor(W.DistributedGameTime))
	local tracked, connections = {}, {}
	local joins, leaves, peak, windowFrames, windowSeconds, frequency = 0, 0, 0, 0, 0, nil
	local metadata = { State = "Loading" }
	local self = {}
	local function arrive(player)
		if tracked[player] then return end
		tracked[player] = { Clock = clock(), Unix = unix() }
		joins += 1
		peak = math.max(peak, #Players:GetPlayers())
	end
	table.insert(connections, Players.PlayerAdded:Connect(arrive))
	table.insert(connections, Players.PlayerRemoving:Connect(function(player)
		if tracked[player] then
			tracked[player] = nil
			leaves += 1
		end
	end))
	for _, player in Players:GetPlayers() do arrive(player) end
	if not sharedClock then table.insert(connections, RunService.Heartbeat:Connect(function(dt)
		if not finite(dt) or dt <= 0 then return end
		windowFrames += 1
		windowSeconds += dt
		if windowSeconds >= 5 then
			frequency = windowFrames / windowSeconds
			windowFrames = 0
			windowSeconds = 0
		end
	end)) end
	if services.Marketplace and G.PlaceId > 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return services.Marketplace:GetProductInfoAsync(G.PlaceId, Enum.InfoType.Asset)
			end)
			metadata.State = ok and type(info) == "table" and "Available" or "Unavailable"
			if metadata.State == "Available" then
				metadata.Name = short(info.Name, 120)
				local creator = info.Creator
				if type(creator) == "table" and (creator.CreatorTargetId or creator.Id) == G.CreatorId then metadata.CreatorName = short(creator.Name, 80) end
			end
		end)
	else
		metadata.State = "Unavailable"
	end
	local function stats(player)
		local list, truncated = {}, false
		local folder = player:FindFirstChild("leaderstats")
		if not folder then return list, truncated end
		local children = folder:GetChildren()
		table.sort(children, function(a, b)
			return a.Name < b.Name
		end)
		for _, value in children do
			if value:IsA("IntValue") or value:IsA("NumberValue") or value:IsA("BoolValue") or value:IsA("StringValue") then
				if #list >= Telemetry.LeaderstatsLimit then
					truncated = true
					break
				end
				local raw = value.Value
				local clean
				if type(raw) == "string" then clean = short(raw, 256)
				elseif finite(raw) or type(raw) == "boolean" then clean = raw end
				if clean ~= nil then table.insert(list, { Name = short(value.Name, 80), Value = clean, Type = value.ClassName }) end
			end
		end
		return list, truncated
	end
	local function character(player)
		local model = player.Character
		if not model or not model.Parent then return { Status = "Absent" } end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		local data = { Status = humanoid and (humanoid.Health > 0 and "Alive" or "Dead") or "Loading" }
		if humanoid then
			data.Health = read(function()
				return humanoid.Health
			end)
			data.MaxHealth = read(function()
				return humanoid.MaxHealth
			end)
			data.WalkSpeed = read(function()
				return humanoid.WalkSpeed
			end)
			data.JumpMode = humanoid.UseJumpPower and "Power" or "Height"
			data.JumpValue = read(function()
				return humanoid.UseJumpPower and humanoid.JumpPower or humanoid.JumpHeight
			end)
			data.RigType = humanoid.RigType.Name
			data.State = humanoid:GetState().Name
			data.Seated = humanoid.Sit
		end
		if root and root:IsA("BasePart") then
			local p = root.Position
			if finite(p.X) and finite(p.Y) and finite(p.Z) then data.Position = { X = p.X, Y = p.Y, Z = p.Z } end
		end
		return data
	end
	function self.Snapshot(viewer, options)
		options = Telemetry.Options(options)
		if not options or not ctx.Ranks.IsAdmin(viewer) or not ctx.Ranks.HasPermission(viewer, "APM.AccessPanel") then return nil end
		local online = Players:GetPlayers()
		table.sort(online, function(a, b)
			return a.Name:lower() == b.Name:lower() and a.UserId < b.UserId or a.Name:lower() < b.Name:lower()
		end)
		local summary = { Connected = 0, Alive = 0, Dead = 0, NoCharacter = 0, Admins = 0, PingSamples = 0, TeamCount = #services.Teams:GetTeams() }
		local rows, matched = {}, {}
		local pingSum = 0
		local search = options.Search:lower()
		for _, player in online do
			if player.Parent == Players then
				summary.Connected += 1
				local body = character(player)
				if body.Status == "Alive" then summary.Alive += 1 elseif body.Status == "Dead" then summary.Dead += 1 else summary.NoCharacter += 1 end
				local resolved = ctx.Ranks.WaitResolved(player, 0)
				local admin = resolved and ctx.Ranks.HasPermission(player, "APM.AccessPanel") or false
				if admin then summary.Admins += 1 end
				local ping = read(function()
					return player:GetNetworkPing() * 1000
				end)
				if ping and ping >= 0 then
					pingSum += ping
					summary.PingSamples += 1
				else
					ping = nil
				end
				if search == "" or player.Name:lower():find(search, 1, true) or player.DisplayName:lower():find(search, 1, true) or tostring(player.UserId):find(search, 1, true) then
					table.insert(matched, { Player = player, Character = body, PingMs = ping, Resolved = resolved, Admin = admin })
				end
			end
		end
		if summary.PingSamples > 0 then summary.AveragePingMs = pingSum / summary.PingSamples end
		peak = math.max(peak, summary.Connected)
		local offset = #matched > 0 and math.min(options.Offset, math.floor((#matched - 1) / Telemetry.PlayerPageSize) * Telemetry.PlayerPageSize) or 0
		for index = offset + 1, math.min(offset + Telemetry.PlayerPageSize, #matched) do
			local entry = matched[index]
			local player = entry.Player
			local since = tracked[player]
			local values, truncated = stats(player)
			local team = player.Team
			table.insert(rows, { UserId = player.UserId, Name = player.Name, DisplayName = player.DisplayName, AccountAgeDays = player.AccountAge,
				VerifiedBadge = player.HasVerifiedBadge, Rank = entry.Resolved and (ctx.Ranks.GetRank(player) or "None") or nil,
				RankResolved = entry.Resolved, PanelAccess = entry.Admin, Team = team and team.Name or nil, Neutral = player.Neutral,
				PingMs = entry.PingMs, JoinedAt = since and since.Unix or nil, SessionSeconds = since and math.max(0, math.floor(clock() - since.Clock)) or nil,
				Character = entry.Character, Leaderstats = values, LeaderstatsTruncated = truncated })
		end
		local studio = RunService:IsStudio()
		local serverType = studio and "Studio" or G.PrivateServerId ~= "" and (G.PrivateServerOwnerId ~= 0 and "Private" or "Reserved") or "Public"
		local uptime = math.max(0, math.floor(W.DistributedGameTime))
		local server = { Players = summary.Connected, MaxPlayers = Players.MaxPlayers, AvailableSlots = math.max(0, Players.MaxPlayers - summary.Connected),
			UptimeSeconds = uptime, StartedAt = startedAt, PlaceId = G.PlaceId, UniverseId = G.GameId, PlaceVersion = G.PlaceVersion,
			PlaceName = metadata.Name, MetadataState = metadata.State, CreatorType = G.CreatorType.Name, CreatorId = G.CreatorId, CreatorName = metadata.CreatorName,
			JobId = G.JobId ~= "" and G.JobId or nil, PrivateServerId = G.PrivateServerId ~= "" and G.PrivateServerId or nil,
			PrivateServerOwnerId = G.PrivateServerOwnerId ~= 0 and G.PrivateServerOwnerId or nil, Type = serverType, Studio = studio,
			MemoryMode = ctx.Ranks.Memory == true, Locked = ctx.Controls.IsLocked(), PeakPlayers = peak, ObservedJoins = joins, ObservedLeaves = leaves,
			Gravity = W.Gravity, FallenPartsDestroyHeight = W.FallenPartsDestroyHeight, StreamingEnabled = W.StreamingEnabled,
			StreamingMinRadius = W.StreamingEnabled and read(function()
				return W.StreamingMinRadius
			end) or nil,
			StreamingTargetRadius = W.StreamingEnabled and read(function()
				return W.StreamingTargetRadius
			end) or nil,
			GameClockTime = services.Lighting.ClockTime, APM = { Version = Version.Version, Channel = Version.Channel, DataSchema = Version.DataSchemaVersion,
				ApiVersion = Version.CoreApiVersion } }
		local performance
		if ctx.Ranks.IsExperienceOwner(viewer) or ctx.Ranks.HasPermission(viewer, "APM.Simulate") then
			performance = { HeartbeatHz = sharedClock and sharedClock.HeartbeatHz() or frequency, HeartbeatWindowSeconds = 5,
				MemoryMb = read(function()
					return services.Stats:GetTotalMemoryUsageMb()
			end) }
			for _, key in { "InstanceCount", "PrimitivesCount", "MovingPrimitivesCount", "ContactsCount", "DataReceiveKbps", "DataSendKbps", "PhysicsReceiveKbps",
				"PhysicsSendKbps" } do
				performance[key] = read(function()
					return services.Stats[key]
				end)
			end
		end
		return { SchemaVersion = 1, GeneratedAt = unix(), Server = server, Performance = performance,
			Players = { Summary = summary, Rows = rows, Offset = offset, PageSize = Telemetry.PlayerPageSize, Total = #matched, Search = options.Search,
				NextOffset = offset + Telemetry.PlayerPageSize < #matched and offset + Telemetry.PlayerPageSize or nil } }
	end
	function self.Destroy()
		for _, connection in connections do connection:Disconnect() end
		table.clear(tracked)
	end
	return self
end
return Telemetry
