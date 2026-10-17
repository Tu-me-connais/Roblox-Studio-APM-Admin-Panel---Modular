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

-- Variante ciblée, utilisée seulement par l'assistant Sentinel ("speed pseudo 50") : mêmes bornes, même contrôle de hiérarchie (APMService.perform).
-- Le personnage garde sa vitesse jusqu'à sa réapparition ; rien n'est enregistré.
function M.ExecuteTarget(ctx, admin, target, value)
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	if originals[humanoid] == nil then originals[humanoid]=humanoid.WalkSpeed end
	humanoid.WalkSpeed = value
	if ctx.Sentinel then ctx.Sentinel.Exempt(target,3,"APM Speed") end
	return true, ctx.Msg("Mod.Speed.DoneFor", target.Name, value)
end

-- Valeur réglée par l'APM sur le personnage actuel (nil = valeur du jeu)
function M.GetState(ctx, player)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and originals[humanoid] ~= nil then return humanoid.WalkSpeed end
	return nil
end

function M.OnAccessRevoked(ctx,player)
	local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h and originals[h]~=nil then h.WalkSpeed=originals[h] originals[h]=nil end
end
return M
