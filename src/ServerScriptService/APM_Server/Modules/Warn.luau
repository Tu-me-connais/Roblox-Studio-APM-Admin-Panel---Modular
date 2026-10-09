--[[
	Warn : avertissement enregistré (historique par joueur dans le DataStore de l'APM, clé « Warn_<userId> », Settings.MaxWarnings entrées).
	Le joueur voit une fenêtre d'avertissement dans SA langue (APM_Notices) ; l'onglet Joueurs et la fiche profil rappellent ses avertissements.
	Mode mémoire (Studio sans DataStore) : l'historique reste sur ce serveur.
]]
local HttpService = game:GetService("HttpService")

local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Sanctions", 10
M.Color = Color3.fromRGB(210, 150, 60)
M.MinRank = "Staff"
M.Inputs = { "Reason" }
M.Severity = "warning"

local context
local memory = {} -- [userId] = historique (mode mémoire)

local function key(userId)
	return "Warn_" .. userId
end

-- Historique d'un compte (le plus récent en premier) ; nil si la lecture échoue
local function load(userId)
	local store = context.Ranks.GetStore()
	local list
	if store then
		local ok, value = pcall(store.GetAsync, store, key(userId))
		if not ok then
			return nil
		end
		list = type(value) == "table" and value or {}
	else
		list = memory[userId] or {}
	end
	local safe = {}
	for _, entry in list do
		if type(entry) == "table" then
			local copy = table.clone(entry)
			if copy.filtered ~= true then
				copy.reason = context.Msg("Srv.ReasonHidden")
			end
			table.insert(safe, copy)
		end
	end
	return safe
end

function M.Init(ctx)
	context = ctx
	ctx.Remotes.GetWarnings.OnServerInvoke = function(admin, userId)
		if not ctx.Ranks.IsAdmin(admin) or not ctx.Guard.Allow(admin, "GetWarnings", 6, 10) then
			return {}
		end
		userId = tonumber(userId)
		if not ctx.Ranks.ValidUserId(userId) then
			return {}
		end
		return load(userId) or {}
	end
	ctx.AddProfileProvider(function(userId)
		local list = load(userId)
		return { { Label = "Profile.Warnings", Value = list and #list or "-" } }
	end)
end

function M.Execute(ctx, admin, target, value)
	local reason = value.Reason or ""
	reason = string.gsub(reason, "^%s+", "")
	reason = string.gsub(reason, "%s+$", "")
	local broadcast, personal = ctx.Msg("Mod.Warn.NoReason"), ctx.Msg("Mod.Warn.NoReason")
	if reason ~= "" then
		local filtered = ctx.Filter.Strings(reason, admin.UserId, target.UserId)
		if not filtered then
			return false, ctx.Msg("Srv.FilterDown")
		end
		broadcast, personal = filtered.Broadcast, filtered.Personal
	end
	if not target.Parent or not ctx.Authorize(admin, "Warn", target) then
		return false, ctx.Msg("Srv.AccessChanged")
	end

	local record = { id = HttpService:GenerateGUID(false), reason = broadcast, filtered = true, by = admin.Name, authorId = admin.UserId, time = os.time() }
	local max = tonumber(ctx.Settings.MaxWarnings) or 25
	local list
	local store = ctx.Ranks.GetStore()
	if store then
		for attempt = 1, 2 do
			local ok, result = pcall(store.UpdateAsync, store, key(target.UserId), function(old)
				if not ctx.Authorize(admin,"Warn",target) then return nil end
				local entries = type(old) == "table" and old or {}
				for _, entry in entries do
					if type(entry) == "table" and entry.id == record.id then
						return entries -- déjà écrit (nouvelle tentative)
					end
				end
				table.insert(entries, 1, record)
				while #entries > max do
					table.remove(entries)
				end
				return entries
			end)
			if ok and type(result) == "table" then
				list = result
				break
			end
			if attempt < 2 then
				task.wait(0.5)
			end
		end
		if not list then
			return false, ctx.Msg("Mod.Warn.NotConfirmed")
		end
	else
		list = memory[target.UserId] or {}
		memory[target.UserId] = list
		table.insert(list, 1, record)
		while #list > max do
			table.remove(list)
		end
	end
	if target.Parent then
		ctx.Remotes.Warned:FireClient(target, personal, admin.Name, #list)
	end
	return true, ctx.Msg("Mod.Warn.Done", target.Name, #list, broadcast)
end

return M
