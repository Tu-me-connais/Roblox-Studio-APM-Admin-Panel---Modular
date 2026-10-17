-- FunnyVisuals.Scenes.Solar : un soleil miniature, des planètes aux orbites inclinées, des anneaux et de la poussière d'étoiles.
local Common = require(script.Parent.Parent.Common)
local COLORS, TAU = Common.COLORS, Common.TAU

local Scene = {}

function Scene.Build(k)
	local record, model, intensity = k.record, k.model, k.intensity
	local part, object, orbit, circle, star = k.part, k.object, k.orbit, k.circle, k.star
	-- géométrie
	local sun = Instance.new("Model")
	sun.Name = "TinySun"
	sun.Parent = model
	local core = part("Sun", Vector3.one * .92, Color3.fromRGB(255, 210, 126), nil, sun)
	core.Material = Enum.Material.Neon
	sun.PrimaryPart = core
	local corona = part("Corona", Vector3.one * 1.13, Color3.fromRGB(255, 182, 110), nil, sun)
	corona.Material = Enum.Material.Neon
	corona.Transparency = .87
	local light = Instance.new("PointLight")
	light.Name = "SolarGlow"
	light.Color = core.Color
	light.Range = 7
	light.Brightness = 0
	light.Shadows = false
	light.Parent = core
	record.SolarLight = light
	object(sun, function(t, c) sun:PivotTo(CFrame.new(c + Vector3.new(0, 4.5 + math.sin(t) * .12, 0)) * CFrame.Angles(0, t * .28, 0)) end)
	local planetColors = { Color3.fromRGB(126, 202, 227), Color3.fromRGB(224, 144, 114), Color3.fromRGB(179, 151, 230), Color3.fromRGB(168, 208, 179), Color3.fromRGB(224, 190, 140) }
	for i = 1, 2 + intensity do
		local orbitRadius = 1.55 + i * .43
		local tilt = CFrame.Angles(.24 + i * .1, 0, (i - 3) * .15)
		local path = circle("OrbitPath", orbitRadius, planetColors[i], .02, .72)
		local planet = Instance.new("Model")
		planet.Name = "Planet" .. i
		planet.Parent = model
		local size = .34 + i * .075
		local body = part("PlanetBody", Vector3.one * size, planetColors[i], nil, planet)
		planet.PrimaryPart = body
		if i == 3 then
			for n = 1, 16 do
				local a = (n - 1) / 16 * TAU
				local ring = part("SaturnRing", Vector3.new(.11, .025, .23), Color3.fromRGB(224, 204, 255), Enum.PartType.Block, planet)
				ring.CFrame = CFrame.Angles(.2, 0, .25) * CFrame.new(math.cos(a) * size * .85, 0, math.sin(a) * size * .85) * CFrame.Angles(0, -a, 0)
				ring.Material = Enum.Material.Neon
				ring.Transparency = .2
			end
		end
		local phase = i * 2.3
		object(planet, function(t, c)
			local orbitCf = CFrame.new(c + Vector3.new(0, 4.5, 0)) * tilt
			local a = phase + t * (.34 - i * .025)
			path.Anchor.CFrame = orbitCf * CFrame.Angles(math.pi / 2, 0, 0)
			planet:PivotTo(orbitCf * CFrame.new(math.cos(a) * orbitRadius, 0, math.sin(a) * orbitRadius) * CFrame.Angles(0, t * .4, 0))
		end)
	end
	for i = 1, 4 do
		local sparkle = star("Stardust", .16, COLORS[i])
		orbit(sparkle, 3.9, 4.3 + (i % 3) * .35, i * math.pi / 2, .14)
	end
end

return Scene
