--[[
	Profiles : fiche d'un compte, en ligne ou non (Joueurs > OUVRIR LE PROFIL).

	Lignes génériques : âge du compte, Premium, équipe, santé, temps sur le serveur, leaderstats (en ligne) ; dernière visite (hors ligne).
	Les modules ajoutent leurs lignes (ban, avertissements...) et TON JEU peut ajouter les siennes :
	  APMService.AddProfileProvider(function(userId, player) -- player = nil si le compte n'est pas sur ce serveur
	  	return { { Label = "Coins", Value = 1500 }, { Label = { en = "Level", fr = "Niveau" }, Value = 12 } }
	  end)
	Label / Value : texte, clé de traduction, texte multilingue, message (Lang.Msg), date { d = os.time() } ou durée { s = secondes }.
]]
local Players = game:GetService("Players")

local Profiles = {}

local providers = {}
local joinedAt = {} -- [Player] = os.time() d'arrivée sur ce serveur

function Profiles.AddProvider(provider)
	if type(provider) == "function" then
		table.insert(providers, provider)
	end
end

local function healthText(humanoid)
	if humanoid.MaxHealth == math.huge then
		return "inf"
	end
	return string.format("%d / %d", math.floor(humanoid.Health + 0.5), math.floor(humanoid.MaxHealth + 0.5))
end

function Profiles.Init(ctx)
	local Ranks, Guard, R, Msg, Roster = ctx.Ranks, ctx.Guard, ctx.Remotes, ctx.Msg, ctx.Roster

	for _, player in Players:GetPlayers() do
		joinedAt[player] = os.time()
	end
	Players.PlayerAdded:Connect(function(player)
		joinedAt[player] = os.time()
	end)
	Players.PlayerRemoving:Connect(function(player)
		joinedAt[player] = nil
	end)

	R.GetProfile.OnServerInvoke = function(admin, userId)
		if not Ranks.IsAdmin(admin) or not Guard.Allow(admin, "GetProfile", 10, 10) then
			return nil
		end
		userId = tonumber(userId)
		if not Ranks.ValidUserId(userId) then
			return nil
		end
		local profile = { UserId = userId, Rank = Ranks.GetRankByUserId(userId), Rows = {} }
		local function add(label, value)
			table.insert(profile.Rows, { Label = label, Value = value })
		end

		local live = Players:GetPlayerByUserId(userId)
		if live then
			profile.Name, profile.DisplayName, profile.Online = live.Name, live.DisplayName, true
			add("Profile.AccountAge", Msg("Profile.Days", live.AccountAge))
			add("Profile.Premium", live.MembershipType == Enum.MembershipType.Premium and "Common.Yes" or "Common.No")
			add("Profile.Session", { s = os.time() - (joinedAt[live] or os.time()) })
			if live.Team then
				add("Profile.Team", live.Team.Name)
			end
			local humanoid = live.Character and live.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				add("Profile.Health", healthText(humanoid))
			end
			local stats = live:FindFirstChild("leaderstats")
			if stats then
				for _, value in stats:GetChildren() do
					if value:IsA("ValueBase") then
						add(value.Name, tostring(value.Value))
					end
				end
			end
		else
			profile.Online = false
			local entry = Roster.Get(userId)
			profile.Name = entry and entry.n or tostring(userId)
			profile.DisplayName = entry and entry.d or profile.Name
			if not entry and userId > 0 then
				pcall(function()
					profile.Name = Players:GetNameFromUserIdAsync(userId)
					profile.DisplayName = profile.Name
				end)
			end
			add("Profile.LastSeen", entry and { d = tonumber(entry.t) or 0 } or "Profile.Never")
		end

		for _, provider in providers do
			local ok, rows = pcall(provider, userId, live)
			if ok and type(rows) == "table" then
				for _, row in rows do
					if type(row) == "table" and row.Label ~= nil then
						add(row.Label, row.Value)
					end
				end
			elseif not ok then
				warn("[APM] Ligne de profil en erreur : " .. tostring(rows))
			end
		end
		return profile
	end
end

return Profiles

