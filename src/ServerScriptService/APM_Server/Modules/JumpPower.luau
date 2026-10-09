-- JumpPower (onglet Modération, curseur) : puissance de saut de l'admin. « Reset » remet celle du jeu (StarterPlayer).
local StarterPlayer = game:GetService("StarterPlayer")

local M = {}
local originals = setmetatable({}, {__mode="k"})
M.Category, M.Mode, M.Order = "Moderation", "slider", 6
M.Min, M.Max = 0, 400
M.Default = math.clamp(math.floor(StarterPlayer.CharacterJumpPower + 0.5), M.Min, M.Max)
M.Color = Color3.fromRGB(80, 160, 190)

function M.Execute(ctx, admin, target, value)
	local humanoid = admin.Character and admin.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	if not originals[humanoid] then originals[humanoid]={UseJumpPower=humanoid.UseJumpPower,JumpPower=humanoid.JumpPower,JumpHeight=humanoid.JumpHeight} end
	humanoid.UseJumpPower = true
	humanoid.JumpPower = value
	if ctx.Sentinel then ctx.Sentinel.Exempt(admin,3,"APM JumpPower") end
	return true, ctx.Msg("Mod.JumpPower.Done", value)
end

function M.OnAccessRevoked(ctx,player)
	local h=player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local old=h and originals[h]
	if old then h.UseJumpPower=old.UseJumpPower h.JumpPower=old.JumpPower h.JumpHeight=old.JumpHeight originals[h]=nil end
end
return M
