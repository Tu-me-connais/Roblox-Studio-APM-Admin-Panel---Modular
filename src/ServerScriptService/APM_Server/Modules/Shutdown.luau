--[[
	Shutdown (onglet Jeu) : prépare une maintenance (mise à jour) : verrouille le serveur tout de suite, annonce la maintenance à chacun
	dans sa langue, puis expulse les joueurs sans grade au bout du délai. Pense à sauvegarder tes données de jeu au départ des joueurs.
]]
local Players = game:GetService("Players")

local M = {}
M.Category, M.Mode, M.Order = "Game", "action", 30
M.Color = Color3.fromRGB(205, 75, 75)
M.MinRank = "Owner"
M.Confirm = true
M.Severity = "danger"
M.Fields = {
	{ Name = "Seconds", Type = "number", Default = 60, Min = 10, Max = 600, Integer = true },
}

local running = false

function M.Execute(ctx, admin, target, v)
	if running then
		return false, ctx.Msg("Mod.Shutdown.Running")
	end
	running = true
	ctx.Controls.SetLocked(true)
	ctx.Log(admin.Name, "ServerLock", nil, ctx.Msg("Log.Locked"), "System", "danger")
	ctx.Remotes.Announcement:FireAllClients(ctx.Msg("Mod.Shutdown.Announce", v.Seconds), admin.Name)
	task.delay(v.Seconds, function()
		for _, player in Players:GetPlayers() do
			if not ctx.Ranks.IsAdmin(player) then
				pcall(function()
					player:Kick(ctx.TextFor(player, "Kick.Maintenance"))
				end)
			end
		end
		running = false
	end)
	return true, ctx.Msg("Mod.Shutdown.Done", v.Seconds)
end

return M

