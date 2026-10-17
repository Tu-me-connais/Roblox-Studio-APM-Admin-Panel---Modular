-- Additive per-account preferences. Authorized private transport only; batched writes.
local Players = game:GetService("Players")
local Preferences = {}
-- Champs personnels enregistrés. Les quatre derniers appartiennent à Sentinel (assistant flottant, 2.10.2) : activation, position et
-- état de rétraction ("x,y,vertical,horizontal"), animation des flèches, taille. Chaque champ garde sa propre version de fusion.
local PREFERENCE_NAMES = { "Language", "Page", "LauncherVisible", "OpenKey", "AssistantEnabled", "AssistantLayout", "AssistantWave", "AssistantScale" }
local function validLayout(value)
	if type(value) ~= "string" or #value > 40 then return false end
	local x, y, v, h = string.match(value, "^(%d%.?%d*),(%d%.?%d*),([01]),([01])$")
	x, y = tonumber(x), tonumber(y)
	return x ~= nil and y ~= nil and x >= 0 and x <= 1 and y >= 0 and y <= 1
end
local allowed = { Home = true, End = true, Insert = true, Delete = true, PageUp = true, PageDown = true }
for byte = 65, 90 do allowed[string.char(byte)] = true end
for _, name in { "Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" } do allowed[name] = true end
for index = 1, 12 do allowed["F" .. index] = true end
function Preferences.Create(ctx, services)
	services = services or {}
	local clock, wait = services.Clock or os.clock, services.Wait or task.wait
	local timestamp = services.Timestamp or function() return DateTime.now().UnixTimestampMillis end
	local origin = services.Origin or game.JobId
	if origin == "" then origin = game:GetService("HttpService"):GenerateGUID(false) end
	local lastStamp = 0
	-- Records, including departed writes, contain only a UserId and preference data, never a Player.
	local records, active = {}, {}
	local sessions = setmetatable({}, { __mode = "k" })
	local api = {}
	local function key(userId)
		return "Preferences_v2_" .. userId
	end
	local function session(player)
		local token = sessions[player]
		if token and token.Closed then return nil end
		if not token then token = {}; sessions[player] = token end
		active[player.UserId] = token
		return token
	end
	local function current(player, token)
		return token and not token.Closed and active[player.UserId] == token and ctx.Ranks.IsAdmin(player)
	end
	local function release(userId, record)
		if records[userId] == record and not active[userId] and not record.Loading and not record.Writing and not next(record.Changes) then
			records[userId] = nil
		end
	end
	local function version(value)
		if type(value) ~= "table" or type(value.At) ~= "number" or value.At ~= value.At or value.At < 0 or value.At >= 2 ^ 53
			or type(value.Source) ~= "string" or #value.Source > 128 then return nil end
		return value
	end
	local function newer(a, b)
		return not b or a.At > b.At or a.At == b.At and a.Source >= b.Source
	end
	local function validate(patch)
		if type(patch) ~= "table" then return nil end
		local clean = {}
		for name, value in patch do
			if name == "Language" then
				if type(value) ~= "string" or value ~= "auto" and not table.find(ctx.Lang.Codes(), value) then return nil end
			elseif name == "Page" then
				if type(value) ~= "string" or #value == 0 or #value > 64 then return nil end
			elseif name == "LauncherVisible" then
				if type(value) ~= "boolean" then return nil end
			elseif name == "OpenKey" then
				if type(value) ~= "string" or not allowed[value] then return nil end
			elseif name == "AssistantEnabled" or name == "AssistantWave" then
				if type(value) ~= "boolean" then return nil end
			elseif name == "AssistantLayout" then
				if not validLayout(value) then return nil end
			elseif name == "AssistantScale" then
				if type(value) ~= "number" or value ~= value or value < .6 or value > 1.5 then return nil end
				value = math.floor(value * 20 + .5) / 20
			else return nil end
			clean[name] = value
		end
		return clean
	end
	local function load(userId)
		local record = records[userId]
		if not record then
			record = { Changes = {}, ChangeVersions = {}, Versions = {}, Attempts = 0, RetryAt = 0 }
			records[userId] = record
		end
		if record.Values then return record end
		if record.Loading then
			record.Loading.Event:Wait()
			return record.Values and record or nil
		end
		local event = Instance.new("BindableEvent")
		record.Loading = event
		local store = ctx.Ranks.GetStore()
		local ok, data = store ~= nil or ctx.Ranks.Memory == true, nil
		if store then ok, data = pcall(store.GetAsync, store, key(userId)) end
		local prefs = {}
		if ok and data ~= nil then
			if type(data) ~= "table" or data.SchemaVersion ~= 2 then
				ok = false
			else
				for _, name in PREFERENCE_NAMES do
					if data[name] ~= nil then
						local clean = validate({ [name] = data[name] })
						if clean then
							prefs[name] = clean[name]
							local saved = type(data.FieldVersions) == "table" and version(data.FieldVersions[name])
							if saved then record.Versions[name] = saved; lastStamp = math.max(lastStamp, saved.At) end
						end
					end
				end
			end
		end
		if ok then record.Values = prefs end
		record.Loading = nil
		event:Fire()
		task.defer(function()
			event:Destroy()
		end)
		release(userId, record)
		return record.Values and record or nil
	end
	function api.Get(player)
		if not ctx.Ranks.IsAdmin(player) or ctx.Guard and not ctx.Guard.Allow(player, "GetPreferences", 12, 10) then return {} end
		local token = session(player)
		if not token then return {} end
		local record = load(player.UserId)
		if not current(player, token) then return {} end
		return table.clone(record and record.Values or {})
	end
	function api.Set(player, patch)
		if not ctx.Ranks.IsAdmin(player) or ctx.Guard and not ctx.Guard.Allow(player, "SetPreferences", 30, 10) then return false end
		local clean = validate(patch)
		if not clean then return false end
		local token = session(player)
		if not token then return false end
		local record = load(player.UserId)
		if not record or not current(player, token) then return false end
		local changed = false
		for name, value in clean do if record.Values[name] ~= value then changed = true end end
		if not changed then return true end -- même valeur (ex. onglet déjà enregistré) : aucune écriture
		lastStamp = math.max(math.floor(timestamp()), lastStamp + 1)
		local changedVersion = { At = lastStamp, Source = origin }
		for name, value in clean do
			if record.Values[name] ~= value then
				record.Values[name] = value
				record.Changes[name] = value
				record.Versions[name] = changedVersion
				record.ChangeVersions[name] = changedVersion
			end
		end
		return true
	end
	local function flush(userId, record, force)
		if not record or not next(record.Changes) then return true end
		if record.Writing or not force and clock() < record.RetryAt then return false end
		local store = ctx.Ranks.GetStore()
		if not store then
			if ctx.Ranks.Memory == true then
				table.clear(record.Changes)
				table.clear(record.ChangeVersions)
				release(userId, record)
				return true
			end
			record.Attempts = math.min(record.Attempts + 1, 7)
			record.RetryAt = clock() + math.min(300, 5 * 2 ^ (record.Attempts - 1))
			return false
		end
		local snapshot = table.clone(record.Changes)
		local versions = table.clone(record.ChangeVersions)
		record.Writing = true
		local ok, result = pcall(store.UpdateAsync, store, key(userId), function(old)
			if old ~= nil and (type(old) ~= "table" or old.SchemaVersion ~= 2) then return nil end
			local updated = table.clone(old or {})
			updated.SchemaVersion = 2
			updated.FieldVersions = table.clone(type(updated.FieldVersions) == "table" and updated.FieldVersions or {})
			-- Versions are assigned when the player chooses a value, never when an old write is retried.
			-- A departed server cannot overwrite a later choice made after reconnecting elsewhere.
			for name, value in snapshot do
				if newer(versions[name], version(updated.FieldVersions[name])) then
					updated[name] = value
					updated.FieldVersions[name] = versions[name]
				end
			end
			return updated
		end)
		record.Writing = false
		if ok and type(result) == "table" then
			for name, value in snapshot do
				if record.ChangeVersions[name] == versions[name] then
					record.Changes[name], record.ChangeVersions[name] = nil, nil
				end
			end
			for _, name in PREFERENCE_NAMES do
				if record.Changes[name] == nil and result[name] ~= nil then
					local clean = validate({ [name] = result[name] })
					if clean then record.Values[name] = clean[name] end
					local saved = type(result.FieldVersions) == "table" and version(result.FieldVersions[name])
					if saved then record.Versions[name] = saved; lastStamp = math.max(lastStamp, saved.At) end
				end
			end
			record.Attempts, record.RetryAt = 0, 0
		else
			record.Attempts = math.min(record.Attempts + 1, 7)
			record.RetryAt = clock() + math.min(300, 5 * 2 ^ (record.Attempts - 1))
		end
		release(userId, record)
		return ok and type(result) == "table" and not next(record.Changes)
	end
	function api.Flush(player)
		return flush(player.UserId, records[player.UserId], true)
	end
	function api.Remove(player)
		local token = sessions[player]
		if token then token.Closed = true end
		if active[player.UserId] == token then active[player.UserId] = nil end
		local record = records[player.UserId]
		flush(player.UserId, record, true)
		if record then release(player.UserId, record) end
	end
	function api.FlushAll(force)
		local deadline, count = clock() + 25, 0
		local queue = {}
		for userId, record in records do
			if next(record.Changes) then table.insert(queue, { Id = userId, Record = record }) end
		end
		table.sort(queue, function(a, b) return a.Record.RetryAt < b.Record.RetryAt end)
		for _, entry in queue do
			if clock() >= deadline or not force and count >= 20 then break end
			local record = entry.Record
			if force then
				while record.Writing and clock() < deadline do wait(.05) end
			end
			if force or clock() >= record.RetryAt then
				count += 1
				flush(entry.Id, record, force == true)
			end
		end
	end
	return api
end
function Preferences.Init(context)
	local api = Preferences.Create(context)
	context.Remotes.GetPreferences.OnServerInvoke = api.Get
	context.Remotes.SetPreferences.OnServerInvoke = api.Set
	Players.PlayerRemoving:Connect(api.Remove)
	task.spawn(function()
		while true do
			task.wait(60)
			api.FlushAll()
		end
	end)
	game:BindToClose(function() api.FlushAll(true) end)
end
return Preferences
