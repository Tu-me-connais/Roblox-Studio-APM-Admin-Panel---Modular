-- Return : renvoie le joueur choisi là où il était avant d'être amené par le module Bring.
local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Movement", 9
M.Color = Color3.fromRGB(120, 100, 200)

function M.Execute(ctx, admin, target)
	local origins = ctx.Shared.BringOrigins or {}
	local saved = origins[target.UserId]
	if not saved then
		return false, ctx.Msg("Mod.Return.Nothing", target.Name)
	end
	if not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	origins[target.UserId] = nil
	if ctx.Sentinel then ctx.Sentinel.NotifyServerTeleport(target,4,"APM Return") end
	target.Character:PivotTo(saved)
	return true, ctx.Msg("Mod.Return.Done", target.Name)
end

return M
