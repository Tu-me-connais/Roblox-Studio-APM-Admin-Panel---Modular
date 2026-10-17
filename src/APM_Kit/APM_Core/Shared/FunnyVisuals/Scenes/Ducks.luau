-- FunnyVisuals.Scenes.Ducks : petits canards qui se dandinent autour du personnage, sur des ondulations turquoise.
local Common = require(script.Parent.Parent.Common)
local TAU = Common.TAU

local Scene = {}

function Scene.Build(k)
	local record, model, world, intensity = k.record, k.model, k.world, k.intensity
	local part, object, circle = k.part, k.object, k.circle
	-- géométrie
	local count = 2 + intensity
	for i = 1, count do
		local duck = Instance.new("Model")
		duck.Name = "RubberDuck" .. i
		duck.Parent = model
		local gold = Color3.fromRGB(255, 207, 75)
		local body = part("Body", Vector3.new(1.14, .8, 1.4), gold, nil, duck)
		duck.PrimaryPart = body
		local head = part("Head", Vector3.one * .73, gold, nil, duck)
		head.CFrame = CFrame.new(0, .55, -.4)
		local beak = part("SoftBeak", Vector3.new(.57, .2, .44), Color3.fromRGB(255, 139, 60), nil, duck)
		beak.CFrame = CFrame.new(0, .38, -.82)
		for _, x in { -.23, .23 } do
			local eye = part("Eye", Vector3.new(.13, .17, .08), Color3.fromRGB(27, 35, 46), nil, duck)
			eye.CFrame = CFrame.new(x, .66, -.7)
			local shine = part("EyeGlint", Vector3.one * .044, Color3.new(1, 1, 1), nil, duck)
			shine.CFrame = CFrame.new(x - .022, .696, -.744)
			local wing = part("Wing", Vector3.new(.19, .4, .81), Color3.fromRGB(255, 231, 131), nil, duck)
			wing.CFrame = CFrame.new(x > 0 and .5 or -.5, 0, .07) * CFrame.Angles(0, 0, x > 0 and -.2 or .2)
		end
		local tail = part("Tail", Vector3.new(.33, .35, .5), gold, nil, duck)
		tail.CFrame = CFrame.new(0, .16, .64) * CFrame.Angles(-.45, 0, 0)
		local ripple = circle("DuckRipple", .78, Color3.fromRGB(131, 226, 238), .025, .67)
		local phase = (i - 1) / count * TAU
		local lastGround = -math.huge
		local ground = -2.5
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model, record.Root.Parent }
		object(duck, function(t, c)
			local a = phase + t * .46
			local radius = 3.1 + intensity * .18
			local at = c + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
			if world == workspace and t - lastGround > .22 then
				lastGround = t
				local hit = workspace:Raycast(at + Vector3.yAxis * 3, Vector3.new(0, -15, 0), params)
				ground = hit and hit.Position.Y - c.Y or -2.5
			end
			local y = c.Y + ground + .5 + math.abs(math.sin(t * 3.2 + phase)) * .13
			duck:PivotTo(CFrame.lookAt(Vector3.new(at.X, y, at.Z), Vector3.new(at.X - math.sin(a), y, at.Z + math.cos(a))) * CFrame.Angles(0, 0, math.sin(t * 3.2 + phase) * .07))
			ripple.Anchor.CFrame = CFrame.new(at.X, c.Y + ground + .035, at.Z) * CFrame.Angles(math.pi / 2, 0, 0)
			ripple.Weight = .55 + .2 * math.sin(t * 1.7 + phase)
		end)
	end
end

return Scene
