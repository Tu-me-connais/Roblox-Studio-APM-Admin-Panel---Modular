-- FunnyVisuals.Scenes.Potato : une patate souriante en cape violette, couronne dorée et bijoux, entourée d'étoiles.
local Common = require(script.Parent.Parent.Common)
local COLORS, TAU, cameraPosition = Common.COLORS, Common.TAU, Common.cameraPosition

local Scene = {}

function Scene.Build(k)
	local record, model, intensity = k.record, k.model, k.intensity
	local part, object, orbit, star = k.part, k.object, k.orbit, k.star
	-- géométrie
	local potato = Instance.new("Model")
	potato.Name = "PotatoMonarch"
	potato.Parent = model
	local body = part("VelvetPotato", Vector3.new(1.65, 2.05, 1.4), Color3.fromRGB(198, 151, 101), nil, potato)
	potato.PrimaryPart = body
	for _, x in { -.38, .38 } do
		local eye = part("Eye", Vector3.new(.18, .24, .09), Color3.fromRGB(44, 37, 42), nil, potato)
		eye.CFrame = CFrame.new(x, .23, -.68)
		local shine = part("EyeGlint", Vector3.one * .055, Color3.fromRGB(255, 245, 221), nil, potato)
		shine.CFrame = CFrame.new(x - .025, .285, -.732)
		local cheek = part("Blush", Vector3.new(.24, .12, .05), Color3.fromRGB(227, 131, 126), nil, potato)
		cheek.CFrame = CFrame.new(x * 1.4, -.02, -.64)
		local foot = part("RoyalSlipper", Vector3.new(.45, .2, .55), Color3.fromRGB(116, 73, 165), nil, potato)
		foot.CFrame = CFrame.new(x, -.97, -.23)
	end
	local mouth = part("Smile", Vector3.new(.19, .1, .06), Color3.fromRGB(100, 59, 46), nil, potato)
	mouth.CFrame = CFrame.new(0, -.13, -.716)
	local cape = part("VelvetCape", Vector3.new(1.65, 1.68, .28), Color3.fromRGB(123, 74, 171), nil, potato)
	cape.Material = Enum.Material.Fabric
	cape.CFrame = CFrame.new(0, -.14, .59)
	for i = 1, 8 do
		local a = (i - 1) / 8 * TAU
		local crown = part("GoldCrown", Vector3.new(.45, .21, .13), Color3.fromRGB(255, 207, 82), Enum.PartType.Block, potato)
		crown.Material = Enum.Material.Metal
		crown.CFrame = CFrame.new(math.cos(a) * .61, 1.02, math.sin(a) * .53) * CFrame.Angles(0, -a + math.pi / 2, 0)
		if i % 2 == 0 then
			local jewel = part("CrownJewel", Vector3.one * .17, COLORS[(i - 1) % #COLORS + 1], nil, potato)
			jewel.Material = Enum.Material.Neon
			jewel.CFrame = CFrame.new(math.cos(a) * .64, 1.11, math.sin(a) * .57)
		end
	end
	for i = 1, 5 do
		local a = (i - 1) / 5 * TAU
		local point = part("CrownPetal", Vector3.new(.23, .56, .15), Color3.fromRGB(255, 218, 117), Enum.PartType.Block, potato)
		point.Material = Enum.Material.Metal
		point.CFrame = CFrame.new(math.cos(a) * .56, 1.32, math.sin(a) * .47) * CFrame.Angles(0, -a, math.sin(a) * .23)
	end
	for i = 1, 5 do
		local a = i * 2.4
		local spot = part("Freckle", Vector3.one * .066, Color3.fromRGB(130, 89, 58), nil, potato)
		spot.CFrame = CFrame.new(math.cos(a) * .68, math.sin(a) * .7, -.53)
	end
	object(potato, function(t, c)
		local at = c + Vector3.new(0, 4.45 + math.sin(t * 1.3) * .22, 0)
		local cam = cameraPosition(record, at)
		potato:PivotTo(CFrame.lookAt(at, Vector3.new(cam.X, at.Y, cam.Z)) * CFrame.Angles(0, math.sin(t * .8) * .12, math.sin(t * 1.1) * .06))
	end)
	for i = 1, 3 + intensity do
		local sparkle = star("RoyalSparkle", .26 + (i % 2) * .1, Color3.fromRGB(255, 225, 155))
		orbit(sparkle, 1.85, 4.25 + (i % 3) * .25, i * TAU / (3 + intensity), .25, CFrame.Angles(0, 0, .7))
	end
end

return Scene
