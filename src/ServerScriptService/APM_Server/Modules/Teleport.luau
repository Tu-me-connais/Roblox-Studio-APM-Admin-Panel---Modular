--[[
	Teleport : l'admin va auprès du joueur choisi.
	(Jeu à plusieurs zones / mondes ? Fais d'abord voyager l'admin ici avec ton propre service, via ctx.Game.)
]]
local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Movement", 7
M.Color = Color3.fromRGB(120, 100, 200)

function M.Execute(ctx, admin, target)
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	local adminCharacter = admin.Character
	if not targetRoot or not adminCharacter or not adminCharacter:FindFirstChild("HumanoidRootPart") then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	if ctx.Sentinel then ctx.Sentinel.NotifyServerTeleport(admin,4,"APM Teleport") end
	adminCharacter:PivotTo(targetRoot.CFrame * CFrame.new(0, 0, 4))
	return true, ctx.Msg("Mod.Teleport.Done", target.Name)
end

return M
