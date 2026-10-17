-- Heal : remet la santé du joueur choisi au maximum (utilisable sur soi-même).
local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Assistance", 5
M.Color = Color3.fromRGB(70, 170, 100)
M.AllowSelf = true

function M.Execute(ctx, admin, target)
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	humanoid.Health = humanoid.MaxHealth
	return true, ctx.Msg("Mod.Heal.Done", target.Name)
end

return M

