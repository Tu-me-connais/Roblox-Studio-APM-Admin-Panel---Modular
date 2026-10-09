-- Kill : élimine le personnage du joueur choisi (il réapparaît normalement).
local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Sanctions", 3
M.Color = Color3.fromRGB(170, 60, 60)
M.MinRank = "Staff"
M.Severity = "warning"

function M.Execute(ctx, admin, target)
	local humanoid = target.Character and target.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	humanoid.Health = 0
	return true, ctx.Msg("Mod.Kill.Done", target.Name)
end

return M

