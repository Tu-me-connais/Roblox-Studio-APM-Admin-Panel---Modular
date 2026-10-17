--[[
	Fly (contrôleur client) : vol libre. WASD / ZQSD pour avancer selon la caméra, Espace monte, Maj / Ctrl descend
	(tactile / manette : le joystick suit la caméra). C'est LE contrôleur de Fly : le serveur le pilote (ActionExecutor) et l'outil du panneau
	(Tools/Fly) s'en sert aussi, donc jamais deux contrôleurs sur le même personnage.
]]
local Fly = {}

local DEFAULT_SPEED = 70

function Fly.Create(env)
	local controller = {}
	local connection, velocity, orient, attachment, humanoidRef

	local function down(...)
		for _, key in { ... } do
			if env.IsKeyDown(key) then
				return true
			end
		end
		return false
	end

	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		for _, item in { velocity, orient, attachment } do
			if item then
				item:Destroy()
			end
		end
		velocity, orient, attachment = nil, nil, nil
		if humanoidRef and humanoidRef.Parent then
			humanoidRef.PlatformStand = false
			humanoidRef:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		humanoidRef = nil
	end

	function controller.Start(params)
		stop()
		local character = env.Character()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			return false
		end
		local speed = type(params) == "table" and tonumber(params.Speed) or DEFAULT_SPEED
		humanoidRef = humanoid
		humanoid.PlatformStand = true
		attachment = Instance.new("Attachment")
		attachment.Name = "APM_FlyAttachment"
		attachment.Parent = root
		velocity = Instance.new("LinearVelocity")
		velocity.Attachment0 = attachment
		velocity.MaxForce = math.huge
		velocity.RelativeTo = Enum.ActuatorRelativeTo.World
		velocity.VectorVelocity = Vector3.zero
		velocity.Parent = root
		orient = Instance.new("AlignOrientation")
		orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
		orient.Attachment0 = attachment
		orient.MaxTorque = math.huge
		orient.Responsiveness = 30
		orient.Parent = root
		connection = env.RenderStepped:Connect(function()
			local camera = env.Camera()
			if not camera or not root.Parent or not velocity then
				return
			end
			local look = camera.CFrame
			local direction = Vector3.zero
			if not env.TextBoxFocused() then
				if down(Enum.KeyCode.W, Enum.KeyCode.Z) then
					direction += look.LookVector
				end
				if down(Enum.KeyCode.S) then
					direction -= look.LookVector
				end
				if down(Enum.KeyCode.D) then
					direction += look.RightVector
				end
				if down(Enum.KeyCode.A, Enum.KeyCode.Q) then
					direction -= look.RightVector
				end
				if down(Enum.KeyCode.Space) then
					direction += Vector3.yAxis
				end
				if down(Enum.KeyCode.LeftShift, Enum.KeyCode.LeftControl) then
					direction -= Vector3.yAxis
				end
			end
			if direction.Magnitude == 0 and humanoid.MoveDirection.Magnitude > 0 then -- tactile / manette
				local flat = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
				local forward = flat.Magnitude > 0 and flat.Unit:Dot(humanoid.MoveDirection) or 0
				direction = humanoid.MoveDirection + Vector3.yAxis * (look.LookVector.Y * forward)
			end
			velocity.VectorVelocity = direction.Magnitude > 0 and direction.Unit * speed or Vector3.zero
			local flatLook = Vector3.new(look.LookVector.X, 0, look.LookVector.Z)
			if flatLook.Magnitude > 0 and orient then
				orient.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook)
			end
		end)
		return true
	end

	function controller.Stop()
		stop()
	end

	return controller
end

return Fly
