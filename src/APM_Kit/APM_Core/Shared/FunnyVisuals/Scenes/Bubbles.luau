-- FunnyVisuals.Scenes.Bubbles : bulles irisées qui montent doucement, contour lumineux et reflets nacrés.
local Common = require(script.Parent.Parent.Common)
local COLORS, TAU, smooth, cameraPosition = Common.COLORS, Common.TAU, Common.smooth, Common.cameraPosition

local Scene = {}

function Scene.Build(k)
	local record, random, intensity = k.record, k.random, k.intensity
	local part, object, circle = k.part, k.object, k.circle
	-- géométrie
	local count = 4 + intensity * 2
	for i = 1, count do
		local radius = random:NextNumber(.3, .75)
		local bubble = part("IridescentBubble", Vector3.one * radius * 2, COLORS[(i - 1) % #COLORS + 1])
		bubble.Material = Enum.Material.Glass
		bubble.Transparency = .84
		bubble.Reflectance = .15
		local sheen = part("SoftHighlight", Vector3.new(radius * .52, radius * .095, .025), Color3.fromRGB(238, 255, 255))
		sheen.Transparency = .23
		local glint = part("PearlHighlight", Vector3.one * radius * .12, Color3.new(1, 1, 1))
		glint.Transparency = .12
		local ring = circle("BubbleRim", radius, Color3.fromRGB(183, 231, 255), .016, .38)
		local phase = (i - 1) / count
		object(bubble, function(t, c)
			local u = (phase + t * .075) % 1
			local a = phase * TAU + t * .18
			local at = c + Vector3.new(math.cos(a) * (2.5 + phase * 1.8), -.7 + u * 6.5, math.sin(a) * (2.5 + phase * 1.8))
			local cf = CFrame.lookAt(at, cameraPosition(record, at))
			local weight = smooth(u / .15) * smooth((1 - u) / .2)
			bubble.CFrame = cf
			sheen.CFrame = cf * CFrame.new(-radius * .25, radius * .34, -radius * .92) * CFrame.Angles(0, 0, -.52)
			glint.CFrame = cf * CFrame.new(radius * .33, -radius * .28, -radius * .91)
			record.PartWeights[bubble] = weight
			record.PartWeights[sheen] = weight
			record.PartWeights[glint] = weight
			ring.Anchor.CFrame = cf
			ring.Weight = weight
		end)
	end
end

return Scene
