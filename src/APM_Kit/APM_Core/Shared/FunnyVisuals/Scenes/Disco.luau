-- FunnyVisuals.Scenes.Disco : boule à miroirs, halos croisés, faisceaux pastel sur le sol et musique synchronisée.
local Common = require(script.Parent.Parent.Common)
local COLORS, palette = Common.COLORS, Common.palette

local Scene = {}

function Scene.Build(k)
	local record, model, world, random, intensity, seed = k.record, k.model, k.world, k.random, k.intensity, k.seed
	local part, object, orbit, circle = k.part, k.object, k.orbit, k.circle
	-- géométrie
	local ball = Instance.new("Model")
	ball.Name = "MirrorBall"
	ball.Parent = model
	local radius = 1.36
	local core = part("DiscoBall", Vector3.one * radius * 1.94, Color3.fromRGB(75, 88, 109), nil, ball)
	core.Material = Enum.Material.Metal
	core.Reflectance = .28
	ball.PrimaryPart = core
	local stem = part("Suspension", Vector3.new(.065, .65, .065), Color3.fromRGB(205, 214, 227), Enum.PartType.Block, ball)
	stem.CFrame = CFrame.new(0, radius + .33, 0)
	stem.Material = Enum.Material.Metal
	local cap = part("TopCap", Vector3.new(.28, .12, .28), Color3.fromRGB(225, 231, 240), nil, ball)
	cap.CFrame = CFrame.new(0, radius + .04, 0)
	cap.Material = Enum.Material.Metal
	local facets = {}
	local bands = 4 + intensity * 2
	local maximumSectors = 8 + intensity * 4
	for band = 1, bands do
		local theta = (band - .5) / bands * math.pi
		local sectors = math.max(6, math.floor(maximumSectors * math.sin(theta) + .5))
		for sector = 1, sectors do
			local phi = (sector - .5) / sectors * math.pi * 2
			local normal = Vector3.new(math.sin(theta) * math.cos(phi), math.cos(theta), math.sin(theta) * math.sin(phi))
			local tangent = Vector3.new(-math.sin(phi), 0, math.cos(phi))
			local down = Vector3.new(math.cos(theta) * math.cos(phi), -math.sin(theta), math.cos(theta) * math.sin(phi))
			local tone = random:NextInteger(178, 238)
			local color = Color3.fromRGB(tone, tone + 3, math.min(tone + 12, 255))
			local tile = part("MirrorFacet", Vector3.new(2 * radius * math.sin(theta) * math.sin(math.pi / sectors) * .91, 2 * radius * math.sin(math.pi / (bands * 2)) * .91, .035), color, Enum.PartType.Block, ball)
			tile.CFrame = CFrame.fromMatrix(normal * radius, tangent, down, normal)
			tile.Material = Enum.Material.Metal
			tile.Reflectance = .42
			table.insert(facets, { Part = tile, Normal = normal, Base = color })
		end
	end
	orbit(ball, 0, 4.9, seed * .001, .55, CFrame.Angles(.06, 0, .04))
	local fill = Instance.new("PointLight")
	fill.Name = "DiscoFill"
	fill.Color = Color3.fromRGB(205, 219, 255)
	fill.Range = 12
	fill.Brightness = 0
	fill.Shadows = false
	fill.Parent = core
	local music = Instance.new("Sound")
	music.Name = "DiscoMusic"
	music.SoundId = "rbxassetid://142376088"
	music.Looped = true
	music.Volume = 0
	music.RollOffMode = Enum.RollOffMode.InverseTapered
	music.RollOffMinDistance = 8
	music.RollOffMaxDistance = 45
	music.Parent = core
	local origin = part("LightOrigin", Vector3.one * .1, Color3.new(1, 1, 1))
	origin.Transparency = 1
	local destinations = part("BeamTargets", Vector3.one * .1, Color3.new(1, 1, 1))
	destinations.Transparency = 1
	local rays = {}
	for i = 1, 2 + intensity * 2 do
		local color = COLORS[(i - 1) % #COLORS + 1]
		local from = Instance.new("Attachment")
		from.Name = "RayOrigin_" .. i
		from.Parent = origin
		local to = Instance.new("Attachment")
		to.Name = "RayTarget_" .. i
		to.Parent = destinations
		local beam = Instance.new("Beam")
		beam.Name = "DiscoBeam"
		beam.Attachment0 = from
		beam.Attachment1 = to
		beam.FaceCamera = true
		beam.Width0 = .04
		beam.Width1 = .7 + intensity * .18
		beam.Segments = 4
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Color = ColorSequence.new(color)
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, .75), NumberSequenceKeypoint.new(.15, .55), NumberSequenceKeypoint.new(.85, .85), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = origin
		local pool = part("LightPool", Vector3.new(.035, 1.4, 1.4), color, Enum.PartType.Cylinder)
		pool.Material = Enum.Material.Neon
		pool.Transparency = .55
		pool:SetAttribute("APMDiscoControlledFade", true)
		local spotlight
		if i <= 2 then
			spotlight = Instance.new("SpotLight")
			spotlight.Name = "DiscoSpot"
			spotlight.Face = Enum.NormalId.Front
			spotlight.Angle = 28
			spotlight.Range = 25
			spotlight.Brightness = 0
			spotlight.Color = color
			spotlight.Shadows = false
			spotlight.Parent = from
		end
		table.insert(rays, { From = from, To = to, Beam = beam, Pool = pool, Light = spotlight, Phase = (i - 1) / (2 + intensity * 2) * math.pi * 2, Hue = (i - 1) / (2 + intensity * 2) })
	end
	local parameters = RaycastParams.new()
	parameters.FilterType = Enum.RaycastFilterType.Exclude
	parameters.FilterDescendantsInstances = { model, record.Root.Parent }
	record.Disco = { Ball = ball, Facets = facets, Origin = origin, Destinations = destinations, Rays = rays, Fill = fill, Music = music, World = world, RayParams = parameters, LastSample = -math.huge }
	for i = 1, 2 do
		local halo = circle("DiscoHalo", 1.73 + i * .1, COLORS[i == 1 and 2 or 4], .035, .45)
		object(halo.Anchor, function(t, c)
			halo.Anchor.CFrame = CFrame.new(c + Vector3.new(0, 4.9 + math.sin(t * 2 + seed * .001) * .22, 0)) * CFrame.Angles(math.pi / 2 + (i == 1 and .22 or -.22), t * .15, i * .2)
			halo.Weight = .7 + .2 * math.sin(t * 1.5 + i)
		end)
	end
	for _, ray in record.Disco.Rays do
		local glow = part("PoolGlow", Vector3.new(.022, 2.25, 2.25), ray.Pool.Color, Enum.PartType.Cylinder)
		glow.Material = Enum.Material.Neon
		glow.Transparency = 1
		glow:SetAttribute("APMDiscoControlledFade", true)
		ray.Glow = glow
	end
end

-- Animation propre à la disco (reflets des facettes, faisceaux, flaques de lumière, volume)
function Scene.Animate(disco, record, elapsed, fade)
	local center = record.Center or record.Root.Position
	local ballAt = disco.Ball.PrimaryPart.CFrame
	disco.Origin.CFrame = CFrame.new(ballAt.Position)
	disco.Destinations.CFrame = CFrame.new(center)
	local sample = elapsed - disco.LastSample >= .12
	if sample then
		disco.LastSample = elapsed
		local lightDirection = Vector3.new(math.cos(elapsed * .8), .55, math.sin(elapsed * .8)).Unit
		for _, facet in disco.Facets do
			local shine = math.max(0, ballAt:VectorToWorldSpace(facet.Normal):Dot(lightDirection)) ^ 16
			facet.Part.Color = facet.Base:Lerp(Color3.new(1, 1, 1), shine * .9)
		end
	end
	disco.Fill.Brightness = fade * (1.1 + .12 * math.sin(elapsed * 2))
	disco.Music.Volume = .35 * fade * (record.DiscoAudioGain or 1)
	for i, ray in disco.Rays do
		local angle = ray.Phase + elapsed * (.24 + i * .012)
		local radius = 4.4 + record.Intensity * .45 + math.sin(elapsed * .65 + ray.Phase) * .85
		local desired = center + Vector3.new(math.cos(angle) * radius, -3, math.sin(angle) * radius)
		if sample or not ray.Hit then
			local hit = disco.World == workspace and workspace:Raycast(Vector3.new(desired.X, center.Y + 4, desired.Z), Vector3.new(0, -40, 0), disco.RayParams)
			ray.Hit = hit and { Y = hit.Position.Y + .025, Normal = hit.Normal, Surface = true } or { Y = desired.Y, Normal = Vector3.yAxis, Surface = disco.World ~= workspace }
			local color = palette(elapsed * .045 + ray.Hue)
			ray.Beam.Color = ColorSequence.new(color)
			ray.Pool.Color = color
			if ray.Light then ray.Light.Color = color end
		end
		local at = Vector3.new(desired.X, ray.Hit.Y, desired.Z)
		ray.From.CFrame = disco.Origin.CFrame:ToObjectSpace(CFrame.lookAt(ballAt.Position, at))
		ray.To.Position = at - center
		ray.Pool.CFrame = CFrame.lookAt(at, at + ray.Hit.Normal) * CFrame.Angles(0, math.pi / 2, 0)
		ray.Pool.Transparency = ray.Hit.Surface and (1 - .45 * fade) or 1
		ray.Beam.LocalTransparencyModifier = 1 - fade
		if ray.Light then ray.Light.Brightness = fade * (1.8 + .2 * math.sin(elapsed * 2 + ray.Phase)) end
	end
end

return Scene
