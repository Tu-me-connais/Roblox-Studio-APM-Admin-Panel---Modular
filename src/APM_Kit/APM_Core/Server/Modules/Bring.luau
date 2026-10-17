-- Bring : amène le joueur choisi devant l'admin. Sa position d'avant est gardée : le module Return (« Renvoyer ») l'y ramène.
local Players = game:GetService("Players")

local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Movement", 8
M.Color = Color3.fromRGB(120, 100, 200)

function M.Init(ctx)
	ctx.Shared.BringOrigins = ctx.Shared.BringOrigins or {} -- [userId] = CFrame d'avant le premier « Amener »
	Players.PlayerRemoving:Connect(function(player)
		ctx.Shared.BringOrigins[player.UserId] = nil
	end)
end

function M.Execute(ctx, admin, target)
	local adminRoot = admin.Character and admin.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not adminRoot or not targetRoot then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	local origins = ctx.Shared.BringOrigins
	if not origins[target.UserId] then
		origins[target.UserId] = target.Character:GetPivot()
	end
	if ctx.Sentinel then ctx.Sentinel.NotifyServerTeleport(target,4,"APM Bring") end
	target.Character:PivotTo(adminRoot.CFrame * CFrame.new(0, 0, -4))
	return true, ctx.Msg("Mod.Bring.Done", target.Name)
end

return M
