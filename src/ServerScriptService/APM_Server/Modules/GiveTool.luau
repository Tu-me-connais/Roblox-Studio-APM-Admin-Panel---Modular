--[[
	GiveTool (onglet Jeu) : donne au joueur choisi un Tool trouvé dans Settings.ToolSources (ServerStorage par défaut, sous-dossiers compris).
	« Gardé après réapparition » le copie aussi dans son StarterGear.
]]
local M = {}
M.Category, M.Mode, M.Order = "Game", "target", 11
M.Color = Color3.fromRGB(90, 160, 235)
M.MinRank = "CoOwner"
M.Severity = "warning"
M.Fields = {
	{ Name = "Tool", Type = "choice", Options = "tools" },
	{ Name = "Keep", Type = "choice", Options = { { "once", "Mod.GiveTool.Once" }, { "keep", "Mod.GiveTool.Always" } }, Default = "once" },
}

-- Tous les Tool des sources : { [chemin] = Tool }, liste de choix
local function scan(ctx)
	local found, list = {}, {}
	for _, source in ctx.Settings.ToolSources or {} do
		if typeof(source) == "Instance" then
			for _, item in source:GetDescendants() do
				if item:IsA("Tool") then
					local id = item:GetFullName()
					if not found[id] then
						found[id] = item
						table.insert(list, { id, item.Name .. "  ·  " .. item.Parent.Name })
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)
	return found, list
end

function M.Init(ctx)
	ctx.RegisterOptions("tools", function()
		local _, list = scan(ctx)
		return list
	end)
end

function M.Execute(ctx, admin, target, v)
	local found = scan(ctx)
	local tool = found[v.Tool]
	if not tool then
		return false, ctx.Msg("Mod.GiveTool.Unknown")
	end
	local backpack = target:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, ctx.Msg("Srv.CharacterNotFound")
	end
	tool:Clone().Parent = backpack
	if v.Keep == "keep" then
		local gear = target:FindFirstChild("StarterGear")
		if gear then
			tool:Clone().Parent = gear
		end
	end
	return true, ctx.Msg("Mod.GiveTool.Done", target.Name, tool.Name)
end

return M

