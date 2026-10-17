-- FunnyVisuals.Scenes.Hearts : cœurs lumineux qui montent en spirale, et un grand cœur qui bat au-dessus de la tête.
local Common = require(script.Parent.Parent.Common)
local TAU, smooth, cameraPosition = Common.TAU, Common.smooth, Common.cameraPosition

local Scene = {}

local PINKS = { Color3.fromRGB(255, 92, 138), Color3.fromRGB(255, 140, 178), Color3.fromRGB(236, 72, 112), Color3.fromRGB(255, 186, 206) }

-- Un cœur = deux boules (les lobes) + un losange (la pointe), centré sur l'origine du modèle
local function heart(k, name, size, color)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = k.model
	local parts = {}
	for _, side in { -1, 1 } do
		local lobe = k.part("HeartLobe", Vector3.one * size * .58, color, Enum.PartType.Ball, model)
		lobe.CFrame = CFrame.new(side * size * .24, size * .14, 0)
		table.insert(parts, lobe)
	end
	local tip = k.part("HeartTip", Vector3.new(size * .58, size * .58, size * .3), color, Enum.PartType.Block, model)
	tip.CFrame = CFrame.new(0, -size * .14, 0) * CFrame.Angles(0, 0, math.pi / 4)
	table.insert(parts, tip)
	for _, p in parts do
		p.Material = Enum.Material.Neon
		p.Transparency = .12
	end
	model.WorldPivot = CFrame.new()
	return model, parts
end

function Scene.Build(k)
	local record, random, intensity = k.record, k.random, k.intensity
	local object = k.object
	-- grand cœur qui bat au-dessus de la tête
	local big = heart(k, "BeatingHeart", 1.3, PINKS[1])
	object(big, function(t, c)
		local beat = 1 + .12 * math.max(0, math.sin(t * 7)) ^ 6 + .08 * math.max(0, math.sin(t * 7 - .9)) ^ 6
		local at = c + Vector3.new(0, 4.5 + math.sin(t * 1.4) * .12, 0)
		big:PivotTo(CFrame.lookAt(at, cameraPosition(record, at)))
		big:ScaleTo(beat)
	end)
	-- petits cœurs en spirale
	for i = 1, 6 + intensity * 4 do
		local size = random:NextNumber(.38, .62)
		local model, parts = heart(k, "FloatingHeart", size, PINKS[(i - 1) % #PINKS + 1])
		local phase, speed = random:NextNumber(), random:NextNumber(.13, .2)
		local radius, turn = random:NextNumber(1.8, 3.2), random:NextNumber(0, TAU)
		object(model, function(t, c)
			local u = (phase + t * speed) % 1
			local angle = turn + t * .7 + u * 2.4
			local at = c + Vector3.new(math.cos(angle) * radius, -2.4 + u * 7, math.sin(angle) * radius)
			model:PivotTo(CFrame.lookAt(at, cameraPosition(record, at)) * CFrame.Angles(0, 0, math.sin(t * 2.2 + phase * 9) * .3))
			local weight = smooth(u / .15) * smooth((1 - u) / .25)
			for _, p in parts do record.PartWeights[p] = weight end
		end)
	end
end

return Scene
