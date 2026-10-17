-- TimeOfDay (onglet Jeu) : change l'heure du jeu (Lighting.ClockTime) pour tout le serveur.
local Lighting = game:GetService("Lighting")

local M = {}
M.Category, M.Mode, M.Order = "Game", "action", 20
M.Color = Color3.fromRGB(240, 190, 70)
M.MinRank = "CoOwner"
M.Fields = {
	{ Name = "Hour", Type = "number", Default = 14, Min = 0, Max = 24 },
}

function M.Execute(ctx, admin, target, v)
	Lighting.ClockTime = v.Hour % 24
	return true, ctx.Msg("Mod.TimeOfDay.Done", Lighting.TimeOfDay)
end

return M

