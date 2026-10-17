--[[
	Ban : bannit le joueur choisi, sur TOUS les serveurs et à chacun de ses retours (DataStore, voir Core/Controls).
	Durée en minutes (vide / 0 = définitif), motif facultatif filtré par Roblox. Levée : onglet Bannissements (module Unban).
]]
local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Sanctions", 2
M.Color = Color3.fromRGB(190, 60, 60)
M.MinRank = "Staff"
M.Inputs = { "Reason", "Minutes" }
M.Confirm = true
M.Severity = "danger"

function M.Execute(ctx, admin, target, value)
	local filtered = { Broadcast = "", Personal = "" }
	if value.Reason ~= "" then
		filtered = ctx.Filter.Strings(value.Reason, admin.UserId, target.UserId)
		if not filtered then
			return false, ctx.Msg("Srv.FilterDown")
		end
	end
	if not target.Parent or not ctx.Authorize(admin, "Ban", target) then
		return false, ctx.Msg("Srv.AccessChanged")
	end
	return ctx.Controls.Ban(admin.Name, target.UserId, target.Name, target.DisplayName, value.Minutes, filtered.Broadcast, true, filtered.Personal, function() return ctx.Authorize(admin,"Ban",target) end)
end

return M
