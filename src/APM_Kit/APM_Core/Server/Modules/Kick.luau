-- Kick : expulse le joueur choisi. Motif facultatif (filtré par Roblox), affiché au joueur dans SA langue.
local M = {}
M.Category, M.Mode, M.Group, M.Order = "Players", "target", "Sanctions", 1
M.Color = Color3.fromRGB(200, 120, 40)
M.MinRank = "Staff"
M.Inputs = { "Reason" }
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
	if not target.Parent or not ctx.Authorize(admin, "Kick", target) then
		return false, ctx.Msg("Srv.AccessChanged")
	end
	local text = ctx.TextFor(target, "Kick.ByAdmin")
	if filtered.Personal ~= "" then
		text ..= ctx.TextFor(target, "Kick.Reason", filtered.Personal)
	end
	target:Kick(text)
	return true, ctx.Msg("Mod.Kick.Done", target.Name, filtered.Broadcast ~= "" and ctx.Msg("Msg.Reason", filtered.Broadcast) or "")
end

return M
