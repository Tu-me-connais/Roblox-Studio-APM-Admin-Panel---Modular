--[[
	FunnyVisuals : rendu public des décors Funny (procédural, côté client). Toute l'autorité reste sur le serveur
	et le transport privé des admins : ce module ne fait qu'afficher les scènes annoncées dans Workspace.APM_FunnyScenes.

	Sous-modules :
	  Common          palette et petits outils
	  Scenes/<Nom>    un module par décor (Build, et Animate pour la disco)
]]
local RunService = game:GetService("RunService")

local Common = require(script.Common)
local smooth, move = Common.smooth, Common.move

local SCENES = {}
for _, name in { "Confetti", "Disco", "Ducks", "Bubbles", "Potato", "Solar", "Snow", "Hearts", "Fireworks", "Rainbow" } do
	SCENES[name] = require(script.Scenes:WaitForChild(name))
end

local Visuals = {}

function Visuals.Destroy(record)
	if record.AudioLoaded then
		record.AudioLoaded:Disconnect()
		record.AudioLoaded = nil
	end
	if record.Model then
		record.Model:Destroy()
		record.Model = nil
	end
	record.Objects = nil
	record.FadeParts = nil
	record.Beams = nil
	record.Disco = nil
	record.Center = nil
	record.LastElapsed = nil
	record.PartWeights = nil
	record.SolarLight = nil
end

local animate

function Visuals.Build(record, world, random)
	Visuals.Destroy(record)
	random = random or Random.new(record.Seed or 1)
	record.Intensity = math.clamp(tonumber(record.Intensity) or 1, 1, 3)
	local model = Instance.new("Model")
	model.Name = "APM_FunnyLocal_" .. record.Id
	model:SetAttribute("APMFunnyLocal", true)
	model:SetAttribute("Scenario", record.Scenario)
	model:SetAttribute("TargetUserId", record.TargetUserId or (record.Target and record.Target.UserId))
	record.Model = model
	record.World = world
	record.Objects = {}
	record.Beams = {}
	record.PartWeights = {}
	local function part(name, size, color, shape, parent)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Shape = shape or Enum.PartType.Ball
		-- Ball primitives render uniformly; a sphere mesh preserves the sculpted proportions.
		if p.Shape == Enum.PartType.Ball and (math.abs(size.X - size.Y) > .001 or math.abs(size.X - size.Z) > .001) then
			p.Shape = Enum.PartType.Block
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.SmoothPlastic
		p.Parent = parent or model
		return p
	end
	local function object(p, step)
		table.insert(record.Objects, { Object = p, Step = step })
	end
	local function orbit(p, radius, height, phase, speed, offset)
		table.insert(record.Objects, { Object = p, Radius = radius, Height = height, Phase = phase, Speed = speed, Offset = offset or CFrame.new() })
	end
	local function circle(name, radius, color, width, alpha)
		local anchor = part(name, Vector3.one * .05, color)
		anchor.Transparency = 1
		local ring = { Anchor = anchor, Weight = 1, Attachments = {}, Beams = {} }
		for i = 1, 4 do
			local a = (i - 1) * math.pi / 2
			local attachment = Instance.new("Attachment")
			attachment.CFrame = CFrame.fromMatrix(Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0), Vector3.new(-math.sin(a), math.cos(a), 0), Vector3.zAxis)
			attachment.Parent = anchor
			ring.Attachments[i] = attachment
		end
		for i = 1, 4 do
			local beam = Instance.new("Beam")
			beam.Name = name .. "Arc"
			beam.Attachment0 = ring.Attachments[i]
			beam.Attachment1 = ring.Attachments[i % 4 + 1]
			beam.CurveSize0 = radius * .55228475
			beam.CurveSize1 = radius * .55228475
			beam.Width0 = width
			beam.Width1 = width
			beam.FaceCamera = true
			beam.Segments = 10
			beam.LightEmission = .8
			beam.LightInfluence = 0
			beam.Color = ColorSequence.new(color)
			beam.Transparency = NumberSequence.new(alpha or .55)
			beam.Parent = anchor
			table.insert(ring.Beams, beam)
			table.insert(record.Beams, { Beam = beam, Owner = ring })
		end
		return ring
	end
	local function star(name, size, color, parent)
		local m = Instance.new("Model")
		m.Name = name
		m.Parent = parent or model
		local a = part("LongRay", Vector3.new(size * .24, size, size * .12), color, Enum.PartType.Block, m)
		a.Material = Enum.Material.Neon
		m.PrimaryPart = a
		local b = part("CrossRay", Vector3.new(size * .72, size * .24, size * .12), color, Enum.PartType.Block, m)
		b.Material = Enum.Material.Neon
		return m
	end
	local scene = SCENES[record.Scenario]
	if not scene then error("Unknown cosmetic scene: " .. tostring(record.Scenario)) end
	scene.Build({
		record = record, model = model, world = world, random = random, intensity = record.Intensity, seed = record.Seed or 1,
		part = part, object = object, orbit = orbit, circle = circle, star = star,
	})
	record.FadeParts = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and not p:GetAttribute("APMDiscoControlledFade") then table.insert(record.FadeParts, { Part = p, Base = p.Transparency }) end
	end
	animate(record, 0) -- Stage invisibly at the target before parenting into a rendered world.
	model.Parent = world
	if record.Disco and world == workspace and RunService:IsClient() then
		local music = record.Disco.Music
		local function sync()
			if record.Model ~= model or model.Parent ~= world or not music.Parent then return false end
			local elapsed = math.max(0, workspace:GetServerTimeNow() - (record.StartServer or workspace:GetServerTimeNow()))
			if record.Duration and elapsed >= record.Duration then
				music:Stop()
				return false
			end
			if music.TimeLength > 0 then music.TimePosition = elapsed % music.TimeLength end
			return true
		end
		if music.IsLoaded then
			if sync() then music:Play() end
		else
			local loaded
			loaded = music.Loaded:Connect(function()
				loaded:Disconnect()
				if record.AudioLoaded == loaded then record.AudioLoaded = nil end
				if sync() then music:Play() end
			end)
			record.AudioLoaded = loaded
			if sync() then music:Play() end
		end
	end
end

animate = function(record, elapsed)
	if not record.Model or not record.Root then return end
	local position = record.Root.Position
	local dt = record.LastElapsed and math.clamp(elapsed - record.LastElapsed, 0, .1) or .1
	if not record.Center or (record.Center - position).Magnitude > 32 or dt == 0 then
		record.Center = position
	else
		record.Center = record.Center:Lerp(position, 1 - math.exp(-dt * 16))
	end
	record.LastElapsed = elapsed
	local center = record.Center
	local fade = smooth(elapsed / .7)
	if record.Duration then fade = math.min(fade, smooth((record.Duration - elapsed) / .9)) end
	fade *= math.clamp(record.Opacity or 1, 0, 1)
	for _, item in record.Objects do
		if item.Step then
			item.Step(elapsed, center)
		else
			local angle = item.Phase + elapsed * item.Speed
			local at = CFrame.new(center + Vector3.new(math.cos(angle) * item.Radius, item.Height + math.sin(elapsed * 2 + item.Phase) * .22, math.sin(angle) * item.Radius))
				* CFrame.Angles(0, -angle, 0) * item.Offset
			move(item.Object, at)
		end
	end
	if record.Disco then
		SCENES.Disco.Animate(record.Disco, record, elapsed, fade)
		for _, ray in record.Disco.Rays do
			if ray.Glow then
				ray.Glow.CFrame = ray.Pool.CFrame
				ray.Glow.Color = ray.Pool.Color
				ray.Glow.Transparency = ray.Hit.Surface and (1 - .14 * fade) or 1
			end
		end
	end
	if record.SolarLight then record.SolarLight.Brightness = .65 * fade end
	for _, entry in record.FadeParts do
		entry.Part.Transparency = 1 - (1 - entry.Base) * fade * (record.PartWeights[entry.Part] or 1)
	end
	for _, entry in record.Beams do
		entry.Beam.LocalTransparencyModifier = 1 - fade * (entry.Owner and entry.Owner.Weight or 1)
	end
end
Visuals.Animate = animate

local started = false
function Visuals.Start()
	if started or not RunService:IsClient() then return end
	started = true
	local players = game:GetService("Players")
	local tracked, retiring = {}, {}
	local folder, addConnection, removeConnection
	local function retire(marker, immediate)
		local record = tracked[marker]
		tracked[marker] = nil
		if not record then return end
		if record.Model and not immediate then
			record.RetireAt = os.clock()
			record.RetireOpacity = record.Opacity or 1
			table.insert(retiring, record)
		else
			Visuals.Destroy(record)
		end
	end
	local function attach(marker)
		if tracked[marker] or not marker:IsA("Model") or marker:GetAttribute("APMFunny") ~= true or marker:GetAttribute("RenderVisual") ~= true then return end
		local scenario = marker:GetAttribute("Scenario")
		if type(scenario) ~= "string" or not SCENES[scenario] then return end
		tracked[marker] = { Id = marker.Name, Scenario = scenario, Intensity = marker:GetAttribute("Intensity"), Seed = marker:GetAttribute("Seed") or 1,
			StartServer = marker:GetAttribute("StartServer") or workspace:GetServerTimeNow(), Duration = marker:GetAttribute("Duration") or 5, TargetUserId = marker:GetAttribute("TargetUserId") }
	end
	local function watch(nextFolder)
		if folder == nextFolder then return end
		for marker in tracked do retire(marker) end
		if addConnection then
			addConnection:Disconnect()
			removeConnection:Disconnect()
		end
		folder = nextFolder
		if folder then
			for _, marker in folder:GetChildren() do attach(marker) end
			addConnection = folder.ChildAdded:Connect(attach)
			removeConnection = folder.ChildRemoved:Connect(function(marker) retire(marker) end)
		end
	end
	-- Le dossier des scènes est suivi par événements plutôt que recherché à chaque image.
	local function locate()
		watch(workspace:FindFirstChild("APM_FunnyScenes"))
	end
	workspace.ChildAdded:Connect(function(child)
		if child.Name == "APM_FunnyScenes" and child ~= folder then locate() end
	end)
	workspace.ChildRemoved:Connect(function(child)
		if child == folder then locate() end
	end)
	locate()
	local accumulator = 0
	local candidates = {}
	local selection = {}
	RunService.RenderStepped:Connect(function(dt)
		-- Aucune scène suivie ni en disparition : rien à animer (cas de presque toutes les images).
		-- accumulator est gardé prêt pour que la première scène soit sélectionnée dès l'image suivante.
		if next(tracked) == nil and #retiring == 0 then
			accumulator = .15
			return
		end
		local camera = workspace.CurrentCamera
		local now = workspace:GetServerTimeNow()
		accumulator += dt
		-- A hard client budget and a low-rate distance sort avoid multiplying heavy geometry in crowded servers.
		if accumulator >= .15 then
			accumulator = 0
			table.clear(candidates)
			table.clear(selection)
			for marker, record in tracked do
				local player = players:GetPlayerByUserId(record.TargetUserId)
				local char = player and player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if marker:GetAttribute("State") ~= "Running" or now - record.StartServer >= record.Duration or hum and hum.Health <= 0 then
					retire(marker)
				elseif not root or not hum then
					-- A streamed character may arrive after its marker; keep the marker eligible for retry.
					if record.Model then Visuals.Destroy(record) end
					record.Root = nil
				elseif camera then
					record.Root = root
					record.Camera = camera
					record.Distance = (camera.CFrame.Position - root.Position).Magnitude
					if record.Distance <= 150 then table.insert(candidates, record) end
				end
			end
			table.sort(candidates, function(a, b)
				if a.Distance == b.Distance then return a.Id < b.Id end
				return a.Distance < b.Distance
			end)
			for i = 1, math.min(8, #candidates) do selection[candidates[i]] = true end
		end
		local audible = 0
		for _, record in tracked do
			if selection[record] and record.Scenario == "Disco" and record.Distance <= 45 then audible += 1 end
		end
		local builds = 0
		local modelCount = 0
		for _, record in tracked do
			if record.Model then modelCount += 1 end
		end
		for _, record in retiring do
			if record.Model then modelCount += 1 end
		end
		for marker, record in tracked do
			if selection[record] and record.Root and record.Root.Parent then
				if not record.Model and builds < 1 and modelCount < 8 then
					builds += 1
					modelCount += 1
					record.Visibility = 0
					record.Opacity = 0
					local ok, err = pcall(Visuals.Build, record, workspace, Random.new(record.Seed))
					if not ok then
						warn("[APM] Funny visual: " .. tostring(err))
						retire(marker, true)
					end
				end
				if record.Model then
					record.Visibility = math.min(1, (record.Visibility or 0) + dt / .45)
					record.Opacity = smooth(record.Visibility)
					record.DiscoAudioGain = 1 / math.max(1, audible)
					if record.Distance < 65 or not record.LastUpdate or now - record.LastUpdate >= 1 / 30 then
						record.LastUpdate = now
						local ok, err = pcall(animate, record, math.max(0, now - record.StartServer))
						if not ok then
							warn("[APM] Funny animation: " .. tostring(err))
							retire(marker, true)
						end
					end
				end
			elseif record.Model then
				record.Visibility = math.max(0, (record.Visibility or 1) - dt / .35)
				record.Opacity = smooth(record.Visibility)
				if record.Root and record.Root.Parent then
					local ok, err = pcall(animate, record, math.max(0, now - record.StartServer))
					if not ok then
						warn("[APM] Funny fade: " .. tostring(err))
						retire(marker, true)
					end
				end
				if record.Opacity <= 0 then Visuals.Destroy(record) end
			end
		end
		for i = #retiring, 1, -1 do
			local record = retiring[i]
			local alpha = (os.clock() - record.RetireAt) / .35
			if alpha >= 1 or not record.Model or not record.Root or not record.Root.Parent then
				Visuals.Destroy(record)
				table.remove(retiring, i)
			else
				record.Opacity = record.RetireOpacity * (1 - smooth(alpha))
				local ok = pcall(animate, record, math.max(0, now - record.StartServer))
				if not ok then
					Visuals.Destroy(record)
					table.remove(retiring, i)
				end
			end
		end
	end)
end

return Visuals
