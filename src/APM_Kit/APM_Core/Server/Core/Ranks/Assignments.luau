-- Ranks.Assignments : grades donnés depuis le panneau (clé "Ranks").
local Players = game:GetService("Players")

return function(Ranks, S)
	local Settings, Msg = S.Settings, S.Msg

	-- Grades donnés dans le panneau (clé "Ranks")

	Ranks.Dynamic = {} -- [userId] = Id du grade, ou "None" (retiré alors qu'il était dans Settings.DefaultUsers)
	Ranks.SecurityReady = false
	S.rankRevision = -1

	local function readRankMap(data)
		local map = {}
		for key, rank in data do
			local userId = tonumber(key)
			if userId and Ranks.ValidUserId(userId) and (rank == "None" or Ranks.IsAssignable(rank)) then
				map[userId] = rank
			end
		end
		return map
	end

	function Ranks.LoadRanks()
		local data, ok = S.load("Ranks")
		if not ok then
			Ranks.SecurityReady = false
			return false
		end
		Ranks.SecurityReady = true
		if type(data) ~= "table" then
			if data ~= nil then Ranks.SecurityReady = false; return false end
			Ranks.Dynamic = {}
			S.rankRevision = 0
			return true
		end
		local revision = tonumber(data._Revision) or 0
		if revision < S.rankRevision then
			return true
		end
		S.rankRevision = revision
		Ranks.Dynamic = readRankMap(data)
		return true
	end

	-- Donne (rankId) ou retire (nil) un grade enregistré. Renvoie ok, message.
	function Ranks.SetRank(userId, rankId, validate)
		if typeof(validate) == "Instance" and validate:IsA("Player") then
			local actor = validate
			validate = function()
				return actor.Parent == Players and Ranks.IsAdmin(actor) and Ranks.HasPermission(actor, "APM.ManagePermissions")
					and actor.UserId ~= userId and not Ranks.IsFixed(userId)
					and (Ranks.IsSuper(actor) or (Ranks.Level(Ranks.GetRealRankByUserId(userId)) < Ranks.GetLevel(actor)
						and (not rankId or Ranks.Level(rankId) < Ranks.GetLevel(actor))))
			end
		elseif validate ~= nil and type(validate) ~= "function" then
			return false, Msg("Srv.InvalidParams")
		end
		if not Ranks.ValidUserId(userId) or (validate and not validate()) then
			return false, Msg("Srv.AccessChanged")
		end
		if rankId ~= nil and not Ranks.IsAssignable(rankId) then
			return false, Msg("Srv.UnknownRank")
		end
		local value = rankId
		if value == nil and Settings.DefaultUsers and Settings.DefaultUsers[userId] then
			value = "None" -- sinon le grade de départ reviendrait
		end
		if not S.store and not Ranks.Memory then
			return false, Msg("Srv.RankSaveFailed")
		end
		if not S.store then
			Ranks.Dynamic[userId] = value
			Ranks.SecurityReady = true
			S.publish()
			return true
		end
		local cancelled = false
		local ok, result = pcall(S.store.UpdateAsync, S.store, "Ranks", function(old)
			if validate and not validate() then
				cancelled = true
				return nil
			end
			local map = type(old) == "table" and old or {}
			map[tostring(userId)] = value
			map._Revision = (tonumber(map._Revision) or 0) + 1
			return map
		end)
		if not ok or cancelled or type(result) ~= "table" then
			return false, Msg("Srv.RankSaveFailed")
		end
		local revision = tonumber(result._Revision) or 0
		if revision >= S.rankRevision then
			S.rankRevision = revision
			Ranks.Dynamic = readRankMap(result)
		end
		Ranks.SecurityReady = true
		S.publish()
		return true
	end
end
