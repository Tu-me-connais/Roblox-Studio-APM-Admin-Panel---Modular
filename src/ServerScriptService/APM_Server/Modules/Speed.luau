-- Speed (onglet Modération, curseur) : vitesse de marche de l'admin. « Reset » remet la vitesse du jeu (StarterPlayer).
local StarterPlayer = game:GetService("StarterPlayer")

local M = {}
local originals = setmetatable({}, {__mode="k"})
M.Category, M.Mode, M.Order = "Moderation", "slider", 5
M.Min, M.Max = 0, 250
M.Default = math.clamp(math.floor(StarterPlayer.CharacterWalkSpeed + 0.5), M.Min, M.Max)
M.Color = Color3.fromRGB(80, 160, 190)

function M.Execute(ctx, admin, target, value)
	local humanoid = admin.Character and admin.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	if originals[humanoid] == nil then originals[humanoid]=humanoid.WalkSpeed end
	humanoid.WalkSpeed = value
	if ctx.Sentinel then ctx.Sentinel.Exempt(admin,3,"APM Speed") end
	return true, ctx.Msg("Mod.Speed.Done", value)
end

function M.OnAccessRevoked(ctx,player)
	local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h and originals[h]~=nil then h.WalkSpeed=originals[h] originals[h]=nil end
end
return M
