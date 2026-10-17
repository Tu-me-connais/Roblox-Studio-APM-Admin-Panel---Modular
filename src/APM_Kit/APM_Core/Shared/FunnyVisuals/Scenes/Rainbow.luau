-- FunnyVisuals.Scenes.Rainbow : arc-en-ciel qui tourne lentement au-dessus du personnage, posé sur deux petits nuages.
-- Construit en segments (pas en faisceaux) pour apparaître aussi dans l'aperçu 3D du panneau.
local Common = require(script.Parent.Parent.Common)
local TAU, smooth = Common.TAU, Common.smooth

local Scene = {}

local BANDS = {
	Color3.fromRGB(255, 96, 96), Color3.fromRGB(255, 166, 77), Color3.fromRGB(255, 226, 92), Color3.fromRGB(110, 220, 120),
	Color3.fromRGB(90, 180, 255), Color3.fromRGB(120, 110, 240), Color3.fromRGB(196, 120, 240),
}
local OUTER, BAND = 6.8, .28 -- bande intérieure ≈ 5 studs : l'arc passe au-dessus de la tête
local GROUND = -2.9

function Scene.Build(k)
	local record, random, intensity = k.record, k.random, k.intensity
	local part, object, star = k.part, k.object, k.star
	local arc = Instance.new("Model")
	arc.Name = "RainbowArc"
	arc.Parent = k.model
	local segments = 12 + intensity * 2
	for b, color in BANDS do
		local radius = OUTER - (b - 1) * BAND
		local length = 2 * radius * math.sin(math.pi / (2 * segments)) * 1.08
		for s = 1, segments do
			local a = math.pi * (s - .5) / segments
			local segment = part("RainbowBand", Vector3.new(length, BAND, BAND), color, Enum.PartType.Block, arc)
			segment.Material = Enum.Material.Neon
			segment.Transparency = .12
			segment.CFrame = CFrame.new(math.cos(a) * radius, math.sin(a) * radius, 0) * CFrame.Angles(0, 0, a + math.pi / 2)
		end
	end
	-- un petit nuage à chaque pied de l'arc
	local middle = OUTER - BAND * 3
	for _, side in { -1, 1 } do
		for i = 1, 4 do
			local radius = random:NextNumber(.6, .95)
			local puff = part("RainbowCloud", Vector3.one * radius * 2, Color3.fromRGB(246, 248, 255), Enum.PartType.Ball, arc)
			puff.CFrame = CFrame.new(side * middle + random:NextNumber(-.8, .8), random:NextNumber(-.1, .45), random:NextNumber(-.5, .5))
		end
	end
	arc.WorldPivot = CFrame.new()
	object(arc, function(t, c)
		arc:PivotTo(CFrame.new(c + Vector3.new(0, GROUND + math.sin(t * 1.1) * .08, 0)) * CFrame.Angles(0, t * .3, 0))
	end)
	-- étincelles qui scintillent le long de l'arc
	for i = 1, 2 + intensity * 2 do
		local sparkle = star("RainbowSparkle", random:NextNumber(.28, .42), Color3.fromRGB(255, 252, 230))
		local parts = sparkle:GetChildren()
		local phase, speed = random:NextNumber(), random:NextNumber(.2, .35)
		object(sparkle, function(t, c)
			local u = (phase + t * speed) % 1
			local a = math.pi * u
			local spin = t * .3
			local radius = OUTER + .35
			local local3 = Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0)
			local at = CFrame.new(c + Vector3.new(0, GROUND, 0)) * CFrame.Angles(0, spin, 0) * local3
			sparkle:PivotTo(CFrame.new(at) * CFrame.Angles(0, 0, t * 2 + phase * TAU))
			local weight = smooth(u / .2) * smooth((1 - u) / .2) * (.55 + .45 * math.sin(t * 6 + phase * TAU))
			for _, p in parts do record.PartWeights[p] = weight end
		end)
	end
end

return Scene
