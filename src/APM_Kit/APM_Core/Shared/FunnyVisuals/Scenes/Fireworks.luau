-- FunnyVisuals.Scenes.Fireworks : petites fusées qui montent autour du personnage et éclatent en gerbes colorées.
local Common = require(script.Parent.Parent.Common)
local TAU, smooth = Common.TAU, Common.smooth
-- Couleurs saturées : la palette pastel commune paraît blanche une fois en néon sur le ciel.
local COLORS = { Color3.fromRGB(255, 64, 88), Color3.fromRGB(255, 152, 36), Color3.fromRGB(255, 222, 52), Color3.fromRGB(70, 226, 110),
	Color3.fromRGB(64, 150, 255), Color3.fromRGB(186, 86, 255) }

local Scene = {}

local RISE = .32 -- part du cycle consacrée à la montée

function Scene.Build(k)
	local record, random, intensity = k.record, k.random, k.intensity
	local part, object = k.part, k.object
	local rockets = 2 + intensity
	for i = 1, rockets do
		local color = COLORS[(i - 1) % #COLORS + 1]
		local rocket = part("Rocket", Vector3.one * .24, Color3.fromRGB(255, 240, 205))
		rocket.Material = Enum.Material.Neon
		local sparks = {}
		for j = 1, 10 + intensity * 3 do
			local spark = part("Spark", Vector3.one * random:NextNumber(.16, .24), color:Lerp(Color3.new(1, 1, 1), random:NextNumber(0, .15)))
			spark.Material = Enum.Material.Neon
			local theta, z = random:NextNumber(0, TAU), random:NextNumber(-1, 1)
			local ring = math.sqrt(1 - z * z)
			sparks[j] = { Part = spark, Direction = Vector3.new(ring * math.cos(theta), z, ring * math.sin(theta)) }
		end
		local phase = (i - 1) / rockets + random:NextNumber(0, .08)
		local period = random:NextNumber(2.6, 3.4)
		local ground = Vector3.new(random:NextNumber(-3, 3), -2.6, random:NextNumber(-3, 3))
		local height = random:NextNumber(6.5, 8)
		local spread = random:NextNumber(2.3, 3)
		object(rocket, function(t, c)
			local u = (phase + t / period) % 1
			local base = c + ground
			local top = base + Vector3.new(0, height, 0)
			if u < RISE then
				local a = smooth(u / RISE)
				rocket.CFrame = CFrame.new(base:Lerp(top, a) + Vector3.new(math.sin(u * 40) * .05, 0, 0))
				record.PartWeights[rocket] = smooth(u / .06)
				for _, spark in sparks do
					spark.Part.CFrame = CFrame.new(top)
					record.PartWeights[spark.Part] = 0
				end
			else
				local b = (u - RISE) / (1 - RISE)
				record.PartWeights[rocket] = 0
				local reach = spread * (1 - (1 - b) ^ 3)
				local fall = Vector3.new(0, 1.5 * b * b, 0)
				local weight = 1 - smooth(b)
				for _, spark in sparks do
					spark.Part.CFrame = CFrame.new(top + spark.Direction * reach - fall)
					record.PartWeights[spark.Part] = weight
				end
			end
		end)
	end
end

return Scene
