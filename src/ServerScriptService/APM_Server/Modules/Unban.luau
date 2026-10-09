-- Unban : lève un ban depuis l'onglet Bannissements (Core.Action("Unban", nil, userId)). Ne crée aucun bouton dans l'onglet Joueurs.
local M = {}
M.Category, M.Mode, M.Order = "Bans", "action", 900
M.MinRank = "Staff"
M.Severity = "warning"

function M.Execute(ctx, admin, target, value)
	local userId = tonumber(value)
	if not ctx.Ranks.ValidUserId(userId) then
		return false, ctx.Msg("Srv.InvalidUserId")
	end
	local removed, err = ctx.Controls.Unban(userId,function() return ctx.Authorize(admin,"Unban",nil) end)
	if not removed then
		return false, err or ctx.Msg("Mod.Unban.NotBanned")
	end
	return true, ctx.Msg("Mod.Unban.Done", userId)
end

return M
