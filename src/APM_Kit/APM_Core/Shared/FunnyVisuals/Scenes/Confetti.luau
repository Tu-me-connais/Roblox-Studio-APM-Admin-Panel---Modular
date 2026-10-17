-- FunnyVisuals.Scenes.Confetti : confettis pastel qui virevoltent et rubans de soie en spirale.
local Common = require(script.Parent.Parent.Common)
local COLORS, TAU, smooth = Common.COLORS, Common.TAU, Common.smooth

local Scene = {}

function Scene.Build(k)
	local record, random, intensity = k.record, k.random, k.intensity
	local part, object = k.part, k.object
	-- géométrie
	for i = 1, 20 + intensity * 7 do
		local color = COLORS[(i - 1) % #COLORS + 1]
		local p = part("SilkConfetti", Vector3.new(random:NextNumber(.1, .2), .035, random:NextNumber(.23, .4)), color, Enum.PartType.Block)
		local phase = random:NextNumber()
		local azimuth = random:NextNumber(0, TAU)
		local speed = random:NextNumber(.15, .24)
		local spread = random:NextNumber(1.4, 3.5)
		object(p, function(t, c)
			local u = (phase + t * speed) % 1
			local angle = azimuth + t * .38 + u * .8
			record.PartWeights[p] = smooth(u / .13) * smooth((1 - u) / .18)
			p.CFrame = CFrame.new(c + Vector3.new(math.cos(angle) * (spread + u), 6.5 - u * 8, math.sin(angle) * (spread + u)))
				* CFrame.Angles(t * 1.9 + phase * 9, angle, math.sin(t * 2 + phase * 7) * 1.3)
		end)
	end
	for i = 1, 2 + intensity do
		local anchor = part("SilkStreamer", Vector3.one * .05, COLORS[i])
		anchor.Transparency = 1
		local a = Instance.new("Attachment")
		a.Parent = anchor
		local b = Instance.new("Attachment")
		b.Parent = anchor
		local beam = Instance.new("Beam")
		beam.Name = "SilkRibbon"
		beam.Attachment0 = a
		beam.Attachment1 = b
		beam.FaceCamera = true
		beam.Width0 = .14
		beam.Width1 = .035
		beam.CurveSize0 = 1.7
		beam.CurveSize1 = 1.7
		beam.Segments = 12
		beam.LightEmission = .45
		beam.Color = ColorSequence.new(COLORS[i], COLORS[i]:Lerp(Color3.new(1, 1, 1), .45))
		beam.Transparency = NumberSequence.new(.2)
		beam.Parent = anchor
		table.insert(record.Beams, { Beam = beam })
		object(anchor, function(t, c)
			local angle = i * TAU / (2 + intensity) + t * .5
			anchor.CFrame = CFrame.new(c)
			a.CFrame = CFrame.new(math.cos(angle) * 3.4, 3.5 + math.sin(t + i) * .55, math.sin(angle) * 3.4) * CFrame.Angles(0, -angle, 0)
			b.CFrame = CFrame.new(math.cos(angle + 1.2) * 3.4, .2 + math.sin(t + i) * .55, math.sin(angle + 1.2) * 3.4) * CFrame.Angles(0, -angle - 1.2, 0)
		end)
	end
end

return Scene
