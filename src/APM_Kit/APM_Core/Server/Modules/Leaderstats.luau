--[[
	Leaderstats (onglet Jeu) : donne, retire ou fixe une valeur du dossier « leaderstats » du joueur choisi (Coins, Points, Kills...).
	Marche avec tout jeu qui utilise le classement Roblox standard (IntValue / NumberValue dans player.leaderstats).
	Les noms proposés sont ceux trouvés chez les joueurs présents.
	⚠ Si ton jeu garde ses données ailleurs (profil, DataStore), crée plutôt ton propre module qui passe par ton service (ctx.Game).
]]
local Players = game:GetService("Players")

local M = {}
M.Category, M.Mode, M.Order = "Game", "target", 10
M.Color = Color3.fromRGB(80, 200, 120)
M.MinRank = "Owner"
M.Severity = "warning"
M.Fields = {
	{ Name = "Stat", Type = "choice", Options = "leaderstats" },
	{ Name = "Op", Type = "choice", Options = { { "give", "Op.Give" }, { "take", "Op.Take" }, { "set", "Op.Set" } }, Default = "give" },
	{ Name = "Amount", Type = "number", Default = 100, Min = -1e15, Max = 1e15 },
}

local function isNumber(value)
	return value:IsA("IntValue") or value:IsA("NumberValue")
end

function M.Init(ctx)
	ctx.RegisterOptions("leaderstats", function()
		local names = {}
		for _, player in Players:GetPlayers() do
			local folder = player:FindFirstChild("leaderstats")
			if folder then
				for _, value in folder:GetChildren() do
					if isNumber(value) then
						names[value.Name] = true
					end
				end
			end
		end
		local list = {}
		for name in names do
			table.insert(list, { name, name })
		end
		table.sort(list, function(a, b)
			return a[1] < b[1]
		end)
		return list
	end)
end

function M.Execute(ctx, admin, target, v)
	local folder = target:FindFirstChild("leaderstats")
	local stat = folder and folder:FindFirstChild(v.Stat)
	if not stat or not isNumber(stat) then
		return false, ctx.Msg("Mod.Leaderstats.NoStat", target.Name, v.Stat)
	end
	local value
	if v.Op == "give" then
		value = stat.Value + v.Amount
	elseif v.Op == "take" then
		value = stat.Value - v.Amount
	else
		value = v.Amount
	end
	if stat:IsA("IntValue") then
		value = math.floor(math.clamp(value, -2 ^ 53, 2 ^ 53))
	end
	stat.Value = value
	return true, ctx.Msg("Mod.Leaderstats.Done", target.Name, stat.Name, tostring(stat.Value))
end

return M

