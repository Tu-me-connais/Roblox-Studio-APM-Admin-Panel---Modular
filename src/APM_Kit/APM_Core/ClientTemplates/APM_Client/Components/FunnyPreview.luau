--[[
	FunnyPreview : aperçu 3D muet d'un décor Funny sur un mannequin, dans un ViewportFrame (onglet Funny).
	Rien n'est répliqué : le monde d'aperçu n'existe que dans la fenêtre du panneau et s'arrête dès qu'elle n'est plus visible.
	  Preview.Create(Core, refs) -> sync(force)   (refs : page, scroll, cadres d'aperçu, sélecteurs scene / intensity, Catalog(), text, alive)
]]
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Preview = {}
Preview.DECORS = { Confetti = true, Ducks = true, Potato = true, Disco = true, Bubbles = true, Solar = true, Snow = true, Hearts = true, Fireworks = true, Rainbow = true }
local DECORS = Preview.DECORS
local PREVIEW_SEQUENCE = { "Confetti", "Ducks", "Rainbow", "Potato", "Disco", "Hearts", "Bubbles", "Fireworks", "Solar", "Snow" }

function Preview.Create(Core, refs)
	local T = Core.T
	local mine = Core.Session
	local page, scroll, viewport, previewFrame = refs.page, refs.scroll, refs.viewport, refs.previewFrame
	local previewBadge, previewTitle, previewHint, replay = refs.previewBadge, refs.previewTitle, refs.previewHint, refs.replay
	local scene, intensity, text, alive = refs.scene, refs.intensity, refs.text, refs.alive
	local previewWorld, previewCamera, previewRecord, previewConnection, previewVisuals
	local previewClock, previewSelection, previewIntensity = 0, nil, nil
	local previewIndex = 1
	local screen = page:FindFirstAncestorOfClass("ScreenGui")
	local function sceneLabel(id)
		for _, entry in refs.Catalog() do
			if entry.Id == id then return Core.Text(entry.Label) end
		end
		return id
	end
	local function previewVisible()
		if not alive() or not Core.HasPermission("Funny.View") or not screen or not screen.Enabled then return false end
		local ancestor = page
		while ancestor and ancestor ~= screen do
			if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
			ancestor = ancestor.Parent
		end
		local top, bottom = previewFrame.AbsolutePosition.Y, previewFrame.AbsolutePosition.Y + previewFrame.AbsoluteSize.Y
		return previewFrame.AbsoluteSize.X > 0 and bottom > scroll.AbsolutePosition.Y and top < scroll.AbsolutePosition.Y + scroll.AbsoluteSize.Y
	end
	local function destroyPreview()
		if previewConnection then
			previewConnection:Disconnect()
			-- Replay and the rotating Surprise preview replace this connection often.
			-- Retire its session entry as well, so a long visit does not retain stale handles.
			local connections = mine and mine.Connections
			local index = connections and table.find(connections, previewConnection)
			if index then table.remove(connections, index) end
			previewConnection = nil
		end
		if previewRecord then
			if previewVisuals and previewVisuals.Destroy then
				pcall(previewVisuals.Destroy, previewRecord)
			elseif previewRecord.Model then
				previewRecord.Model:Destroy()
			end
			previewRecord = nil
		end
		viewport.CurrentCamera = nil
		if previewWorld then
			previewWorld:Destroy()
			previewWorld = nil
		end
		if previewCamera then
			previewCamera:Destroy()
			previewCamera = nil
		end
		previewSelection = nil
	end
	local function part(parent, name, size, color, cframe, shape)
		local object = Instance.new("Part")
		object.Name = name
		object.Size = size
		object.Color = color
		object.CFrame = cframe
		object.Shape = shape or Enum.PartType.Block
		object.Material = Enum.Material.SmoothPlastic
		object.Anchored = true
		object.CanCollide = false
		object.CanTouch = false
		object.CanQuery = false
		object.CastShadow = false
		object.Parent = parent
		return object
	end
	local function fitCamera()
		if not previewCamera then return end
		local aspect = viewport.AbsoluteSize.X / math.max(1, viewport.AbsoluteSize.Y)
		local distance = math.max(19, 18 / math.max(.65, aspect))
		previewCamera.CFrame = CFrame.lookAt(Vector3.new(.58, .30, .78).Unit * distance + Vector3.new(0, 3.8, 0), Vector3.new(0, 3.8, 0))
	end
	local syncPreview
	local function buildPreview(id)
		destroyPreview()
		previewSelection = scene.Get()
		previewIntensity = tonumber(intensity.Get()) or 2
		previewClock = 0
		previewWorld = Instance.new("WorldModel")
		previewWorld.Name = "FunnyPreviewWorld"
		previewWorld.Parent = viewport
		local buildingWorld = previewWorld
		previewCamera = Instance.new("Camera")
		previewCamera.FieldOfView = 48
		previewCamera.Parent = viewport
		viewport.CurrentCamera = previewCamera
		fitCamera()
		local base = part(previewWorld, "Stage", Vector3.new(.22, 13, 13), T.panel, CFrame.new(0, -.24, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
		base.Material = Enum.Material.SmoothPlastic
		local rim = part(previewWorld, "StageRim", Vector3.new(.06, 13.25, 13.25), T.accent:Lerp(T.bg, .60), CFrame.new(0, -.35, 0) * CFrame.Angles(0, 0, math.pi / 2), Enum.PartType.Cylinder)
		rim.Material = Enum.Material.Neon
		local avatar = Instance.new("Model")
		avatar.Name = "PreviewMannequin"
		avatar.Parent = previewWorld
		local root = part(avatar, "HumanoidRootPart", Vector3.new(2, 2, 1), T.accent, CFrame.new(0, 3, 0))
		root.Transparency = 1
		part(avatar, "Torso", Vector3.new(1.7, 1.8, .85), T.accent:Lerp(T.bg, .2), CFrame.new(0, 3, 0))
		local skin = Color3.fromRGB(242, 216, 183)
		part(avatar, "Head", Vector3.new(1.18, 1.18, 1.18), skin, CFrame.new(0, 4.55, 0), Enum.PartType.Ball)
		for _, side in { -1, 1 } do
			part(avatar, "Arm", Vector3.new(.6, 1.85, .7), skin, CFrame.new(side * 1.2, 3, 0) * CFrame.Angles(0, 0, -side * .07))
			part(avatar, "Leg", Vector3.new(.72, 1.85, .76), T.sub:Lerp(T.bg, .65), CFrame.new(side * .45, 1.16, 0))
			part(avatar, "Eye", Vector3.one * .1, T.bg, CFrame.new(side * .21, 4.63, .55), Enum.PartType.Ball)
		end
		if DECORS[id] then
			local shared = ReplicatedStorage:FindFirstChild("APM_Shared")
			local module = shared and shared:FindFirstChild("FunnyVisuals")
			local ok, visuals = pcall(function() return previewVisuals or module and require(module) end)
			if not alive() or previewWorld ~= buildingWorld or not previewVisible() then return end
			previewVisuals = ok and visuals or nil
			previewRecord = { Id = "PrivatePreview", Scenario = id, Root = root, Camera = previewCamera, Intensity = previewIntensity, Seed = 84631, StartServer = 0,
				Duration = scene.Get() == "Random" and 8 or 3600 }
			local built = previewVisuals and pcall(previewVisuals.Build, previewRecord, previewWorld, Random.new(previewRecord.Seed))
			if not built then
				if previewRecord.Model then previewRecord.Model:Destroy() end
				previewRecord = nil
				previewHint.Text = text("Aperçu indisponible. La sélection et le lancement restent disponibles.", "Preview unavailable. You can still choose and start a scene.")
			else
				previewHint.Text = text("Aperçu muet sur un mannequin. Les faisceaux et l'éclairage complet apparaissent en jeu.", "Muted mannequin preview. Beams and full lighting appear in game.")
			end
			previewTitle.Text = (scene.Get() == "Random" and text("Surprise · ", "Surprise · ") or "") .. sceneLabel(id)
		else
			previewTitle.Text = sceneLabel(id)
			previewHint.Text = text("Transformation appliquée au personnage réel au lancement ; ce mannequin sert de repère, sans prédire l'avatar choisi.",
				"The transformation applies to the actual character when started; this mannequin is a reference, not a prediction of the chosen avatar.")
		end
		previewBadge.Text = DECORS[id] and text("APERÇU 3D · MUET", "3D PREVIEW · MUTED") or text("REPÈRE AVATAR", "AVATAR REFERENCE")
		if not previewRecord then return end
		previewConnection = Core.On(RunService.RenderStepped, function(dt)
			if not previewVisible() then
				destroyPreview()
				return
			end
			previewClock += math.min(dt, .1)
			if previewRecord then
				local ok = pcall(previewVisuals.Animate, previewRecord, previewClock)
				if not ok then
					destroyPreview()
					previewHint.Text = text("Aperçu indisponible.", "Preview unavailable.")
					return
				end
			end
			if scene.Get() == "Random" and previewClock >= 8 then
				previewIndex = previewIndex % #PREVIEW_SEQUENCE + 1
				buildPreview(PREVIEW_SEQUENCE[previewIndex])
			end
		end)
	end
	syncPreview = function(force)
		if not previewVisible() then
			destroyPreview()
			return
		end
		if force or previewSelection ~= scene.Get() or previewIntensity ~= (tonumber(intensity.Get()) or 2) then
			buildPreview(scene.Get() == "Random" and PREVIEW_SEQUENCE[previewIndex] or scene.Get())
		end
	end
	Core.On(replay.Activated, function() syncPreview(true) end)
	Core.On(viewport:GetPropertyChangedSignal("AbsoluteSize"), function()
		fitCamera()
		syncPreview()
	end)
	Core.On(scroll:GetPropertyChangedSignal("CanvasPosition"), function() syncPreview() end)
	if screen then Core.On(screen:GetPropertyChangedSignal("Enabled"), function() syncPreview() end) end
	local ancestor = page
	while ancestor and ancestor ~= screen do
		if ancestor:IsA("GuiObject") then Core.On(ancestor:GetPropertyChangedSignal("Visible"), function() syncPreview() end) end
		ancestor = ancestor.Parent
	end
	Core.On(page.Destroying, destroyPreview)
	return syncPreview
end

return Preview
