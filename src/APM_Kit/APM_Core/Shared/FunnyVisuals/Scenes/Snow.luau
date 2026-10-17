-- FunnyVisuals.Scenes.Snow : petit nuage douillet au-dessus de la tête et flocons qui tombent en tourbillonnant.
local Common = require(script.Parent.Parent.Common)
local TAU, smooth = Common.TAU, Common.smooth

local Scene = {}

local CLOUD_HEIGHT = 5.2

function Scene.Build(k)
	local record, random, intensity = k.record, k.random, k.intensity
	local part, object, star = k.part, k.object, k.star
	-- nuage : quelques boules blanches qui respirent doucement
	for i = 1, 6 + intensity do
		local radius = random:NextNumber(.55, 1.05)
		local puff = part("CloudPuff", Vector3.one * radius * 2, Color3.fromRGB(244, 247, 255))
		puff.Transparency = .06
		local offset = Vector3.new(random:NextNumber(-1.7, 1.7), random:NextNumber(-.25, .3), random:NextNumber(-.9, .9))
		local phase = random:NextNumber(0, TAU)
		object(puff, function(t, c)
			puff.CFrame = CFrame.new(c + offset + Vector3.new(math.sin(t * .6 + phase) * .12, CLOUD_HEIGHT + math.sin(t * .9 + phase) * .1, 0))
		end)
	end
	-- flocons : étoiles pâles qui tombent du nuage en se balançant
	for i = 1, 14 + intensity * 8 do
		local flake = star("Snowflake", random:NextNumber(.2, .34), Color3.fromRGB(222, 238, 255))
		local parts = flake:GetChildren()
		local phase, speed = random:NextNumber(), random:NextNumber(.16, .26)
		local x, z = random:NextNumber(-2, 2), random:NextNumber(-1.2, 1.2)
		object(flake, function(t, c)
			local u = (phase + t * speed) % 1
			local at = c + Vector3.new(x + math.sin(t * 1.3 + phase * 9) * .35, CLOUD_HEIGHT - .5 - u * 7.6, z + math.cos(t * 1.1 + phase * 7) * .3)
			flake:PivotTo(CFrame.new(at) * CFrame.Angles(0, t * 1.5 + phase * 5, t * .8 + phase))
			local weight = smooth(u / .12) * smooth((1 - u) / .2)
			for _, p in parts do record.PartWeights[p] = weight end
		end)
	end
end

return Scene
