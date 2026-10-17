-- Respawn : fait réapparaître le joueur choisi à son point d'apparition (utilisable sur soi-même).
local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Assistance", 6
M.Color = Color3.fromRGB(70, 170, 100)
M.AllowSelf = true

function M.Execute(ctx, admin, target)
	target:LoadCharacter()
	return true, ctx.Msg("Mod.Respawn.Done", target.Name)
end

return M

