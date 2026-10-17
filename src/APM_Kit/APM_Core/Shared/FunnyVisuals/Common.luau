-- FunnyVisuals.Common : palette et petits outils partagés par les décors.
local Common = {}

Common.TAU = math.pi * 2
Common.COLORS = { Color3.fromRGB(255, 126, 158), Color3.fromRGB(99, 220, 224), Color3.fromRGB(255, 211, 121), Color3.fromRGB(170, 149, 255), Color3.fromRGB(164, 232, 201) }
local COLORS = Common.COLORS

function Common.smooth(n)
	n = math.clamp(n, 0, 1)
	return n * n * (3 - 2 * n)
end
local smooth = Common.smooth

function Common.palette(t)
	local f = (t % 1) * #COLORS
	local i = math.floor(f)
	return COLORS[i + 1]:Lerp(COLORS[(i + 1) % #COLORS + 1], smooth(f - i))
end

function Common.move(object, cf)
	if object:IsA("Model") then
		object:PivotTo(cf)
	else
		object.CFrame = cf
	end
end

function Common.cameraPosition(record, center)
	local camera = record.Camera or (record.World == workspace and workspace.CurrentCamera)
	return camera and camera.CFrame.Position or center + Vector3.new(9, 6, 14)
end

return Common
