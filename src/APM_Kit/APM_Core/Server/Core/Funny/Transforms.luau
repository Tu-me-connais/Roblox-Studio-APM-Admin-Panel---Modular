-- Funny.Transforms : transformations du personnage avec restauration exacte ; APIs d'avatar côté serveur uniquement.
local TweenService = game:GetService("TweenService")

local Transforms = {}

local PARTS = {
	Head = { "Head", "Face", "HeadColor", "HeadScale" },
	Face = { "Face" },
	Torso = { "Torso", "TorsoColor" },
	LeftArm = { "LeftArm", "LeftArmColor" },
	RightArm = { "RightArm", "RightArmColor" },
	LeftLeg = { "LeftLeg", "LeftLegColor" },
	RightLeg = { "RightLeg", "RightLegColor" },
}
Transforms.BodyParts = PARTS
Transforms.Ids = { BigHead = true, Skin = true, ReverseGravity = true, UpsideDown = true, BodyParts = true }
Transforms.Physics = { ReverseGravity = true, UpsideDown = true }

function Transforms.CopyPart(destination, source, part)
	assert(PARTS[part], "Unsupported body part")
	for _, property in PARTS[part] do
		destination[property] = source[property]
	end
	return destination
end

function Transforms.Create(ctx, services)
	services = services or {}
	local players = services.Players or game:GetService("Players")
	local world = services.Workspace or workspace
	local clock = services.Clock or os.clock
	local getDescription = services.GetDescription or function(hum) return hum:GetAppliedDescription() end
	local applyDescription = services.ApplyDescription or function(hum, desc) hum:ApplyDescriptionResetAsync(desc) end
	local fetchDescription = services.FetchDescription or function(id) return players:GetHumanoidDescriptionFromUserIdAsync(id) end
	local resolveName = services.ResolveName or function(name) return players:GetUserIdFromNameAsync(name) end
	local fetchName = services.FetchName or function(id) return players:GetNameFromUserIdAsync(id) end
	local takeNetwork = services.TakeNetwork or function(root)
		local before = { Auto = root:GetNetworkOwnershipAuto(), Player = root:GetNetworkOwner() }
		root:SetNetworkOwner(nil)
		return before
	end
	local restoreNetwork = services.RestoreNetwork or function(root, before)
		-- Preserve ownership assigned by another system while the effect was active.
		if root:GetNetworkOwner() ~= nil then return end
		if before.Auto then
			root:SetNetworkOwnershipAuto()
		else
			root:SetNetworkOwner(before.Player and before.Player.Parent == players and before.Player or nil)
		end
	end
	local tween = services.Tween or function(instance, property, value, seconds)
		local t = TweenService:Create(instance, TweenInfo.new(seconds or .4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { [property] = value })
		t:Play()
		return t
	end
	local api = {}
	-- Cache court des avatars résolus : un effet lancé sur tout le serveur ne relit pas le même compte pour chaque joueur.
	local SKIN_CACHE_SECONDS, SKIN_CACHE_SIZE = 60, 16
	local skinCache = {} -- [compte en minuscules] = { Description, Id, Name, At }

	function api.ResolveSkin(account)
		local cacheKey = string.lower(tostring(account))
		local cached = skinCache[cacheKey]
		if cached and clock() - cached.At < SKIN_CACHE_SECONDS then
			return cached.Description:Clone(), cached.Id, cached.Name
		end
		local id = tonumber(account)
		if not id then id = resolveName(account) end
		assert(type(id) == "number" and id > 0 and id % 1 == 0 and id < 2 ^ 53, "Unknown Roblox account")
		local description = fetchDescription(id)
		assert(typeof(description) == "Instance" and description:IsA("HumanoidDescription"), "Avatar unavailable")
		local ok, name = pcall(fetchName, id)
		name = ok and name or tostring(id)
		local count, oldestKey, oldestAt = 0, nil, math.huge
		for key, entry in skinCache do
			count += 1
			if entry.At < oldestAt then oldestKey, oldestAt = key, entry.At end
		end
		if count >= SKIN_CACHE_SIZE and oldestKey then
			skinCache[oldestKey].Description:Destroy()
			skinCache[oldestKey] = nil
		end
		if skinCache[cacheKey] then skinCache[cacheKey].Description:Destroy() end
		skinCache[cacheKey] = { Description = description:Clone(), Id = id, Name = name, At = clock() }
		return description, id, name
	end

	local function same(record)
		return record.Target.Parent == players and record.Target.Character == record.Character and record.Character.Parent ~= nil
			and record.Humanoid.Parent == record.Character and record.Humanoid.Health > 0
	end
	local function sameRoot(record)
		local root = record.Root
		return root and root:IsA("BasePart") and root.Parent == record.Character
			and record.Character:FindFirstChild("HumanoidRootPart") == root
	end
	local function own(record, instance)
		record.Owned = record.Owned or {}
		table.insert(record.Owned, instance)
		return instance
	end
	local function save(record, instance, property, value, animated)
		record.Properties = record.Properties or {}
		local item = { Instance = instance, Property = property, Before = instance[property], Applied = value }
		table.insert(record.Properties, item)
		if animated then
			item.Tween = tween(instance, property, value, .45)
		else
			instance[property] = value
		end
	end

	function api.Capture(record)
		assert(same(record) and sameRoot(record) and not record.Cancelled, "Character unavailable")
		record.BeforeDescription = getDescription(record.Humanoid)
		assert(record.BeforeDescription and record.BeforeDescription:IsA("HumanoidDescription"), "No supported avatar description")
	end
	api.CopyPart = Transforms.CopyPart
	function api.ReadDescription(hum)
		return getDescription(hum)
	end

	function api.Apply(record, request)
		assert(same(record) and sameRoot(record) and not record.Cancelled, "Character unavailable")
		if record.Scenario == "Skin" or record.Scenario == "BodyParts" then
			assert(record.NewDescription, "No prepared avatar")
			record.DescriptionChanged = true
			applyDescription(record.Humanoid, record.NewDescription)
			if same(record) then record.Root = assert(record.Character:FindFirstChild("HumanoidRootPart"), "Avatar root missing") end
			return
		end
		if record.Scenario == "BigHead" then
			local scale = record.Humanoid:FindFirstChild("HeadScale")
			if scale and scale:IsA("NumberValue") and record.Humanoid.RigType == Enum.HumanoidRigType.R15 and record.Humanoid.AutomaticScalingEnabled then
				save(record, scale, "Value", scale.Value * request.Scale, true)
			else
				local head = assert(record.Character:FindFirstChild("Head"), "Head missing")
				assert(head:IsA("BasePart"), "Unsupported head")
				save(record, head, "Size", head.Size * request.Scale, true)
				local mesh = head:FindFirstChildOfClass("SpecialMesh")
				if mesh and mesh.MeshType == Enum.MeshType.FileMesh then save(record, mesh, "Scale", mesh.Scale * request.Scale, true) end
				for _, joint in record.Character:GetDescendants() do
					if joint:IsA("JointInstance") and joint.Part1 == head then
						local original = joint.C1
						save(record, joint, "C1", CFrame.new(original.Position * request.Scale) * (original - original.Position), true)
					end
				end
			end
		elseif record.Scenario == "ReverseGravity" then
			-- Le joueur garde le contrôle : pas de PlatformStand ni de prise de la physique par le serveur.
			-- Une force verticale (réglée par Update) le fait monter ; il peut se diriger et se tourner en l'air.
			assert(not record.Root.Anchored and not record.Humanoid.SeatPart, "Unseat or unfreeze this character first")
			record.BeforePivot = record.Character:GetPivot()
			record.PhysicsChanged = true
			local attachment = own(record, Instance.new("Attachment"))
			attachment.Name = "APM_FunnyAttachment"
			attachment.Parent = record.Root
			local force = own(record, Instance.new("VectorForce"))
			force.Name = "APM_FunnyGravity"
			force.Attachment0 = attachment
			force.RelativeTo = Enum.ActuatorRelativeTo.World
			force.ApplyAtCenterOfMass = true
			force.Parent = record.Root
			record.GravityForce = force
			record.GravityFactor = request.GravityFactor
			record.MaxRise = request.MaxRise
			record.MaxRiseSpeed = request.MaxRiseSpeed
			record.OriginY = record.Root.Position.Y
			api.Update(record)
			-- Décollage : au sol (état Running), l'Humanoid plaque le personnage ; un saut le fait passer en chute libre,
			-- où la force prend le relais. Le joueur possède sa physique : seul Jump (répliqué) est pris en compte.
			record.Humanoid.Jump = true
			if ctx.Sentinel and ctx.Sentinel.Exempt then ctx.Sentinel.Exempt(record.Target, record.Duration + 5, "APM Funny " .. record.Scenario) end
		elseif record.Scenario == "UpsideDown" then
			-- Seul l'affichage du corps est retourné (joint racine) : la physique et l'Humanoid restent à l'endroit,
			-- donc le joueur continue à marcher, sauter et tourner normalement... sur la tête.
			-- Joint racine : Motor6D (C0) ou AnimationConstraint des nouveaux avatars (CFrame de son attachement côté racine).
			local joint, property
			for _, item in record.Character:GetDescendants() do
				if item:IsA("Motor6D") and item.Part0 == record.Root then
					joint, property = item, "C0"
					break
				elseif item:IsA("AnimationConstraint") and item.Attachment0 and item.Attachment0.Parent == record.Root then
					joint, property = item.Attachment0, "CFrame"
					break
				end
			end
			assert(joint, "Unsupported rig: no root joint")
			-- Décalage vers le haut pour que la tête retournée ne s'enfonce pas dans le sol.
			local rootY = record.Root.Position.Y
			local headTop, lowest = 0, 0
			for _, item in record.Character:GetDescendants() do
				if item:IsA("BasePart") and item ~= record.Root then
					local half = item.Size.Y / 2
					lowest = math.max(lowest, rootY - (item.Position.Y - half))
					if item.Name == "Head" then headTop = math.max(headTop, item.Position.Y + half - rootY) end
				end
			end
			local lift = math.clamp(headTop - lowest, 0, 8) + .35
			save(record, joint, property, CFrame.new(0, lift, 0) * CFrame.Angles(0, 0, math.pi) * joint[property], true)
		end
	end

	function api.Update(record)
		assert(same(record) and sameRoot(record) and not record.Cancelled, "Character unavailable")
		if record.GravityForce then
			local mass = record.Root.AssemblyMass
			if mass ~= mass or math.abs(mass) == math.huge or mass <= 0 then error("Unsupported assembly mass") end
			local velocity = record.Root.AssemblyLinearVelocity.Y
			local above = record.Root.Position.Y - record.OriginY
			local remaining = record.MaxRise - above
			local maximumAcceleration = world.Gravity * record.GravityFactor
			-- Slow before the ceiling; a damped return corrects small physics overshoots.
			local desiredVelocity = math.min(record.MaxRiseSpeed, math.max(-record.MaxRiseSpeed, remaining * 2))
			local acceleration = math.clamp((desiredVelocity - velocity) * 6, -maximumAcceleration, maximumAcceleration)
			record.GravityForce.Force = Vector3.new(0, mass * (world.Gravity + acceleration), 0)
		end
	end

	function api.Restore(record)
		-- Remove constraints even when the old character is already retired.
		for _, instance in record.Owned or {} do instance:Destroy() end
		for _, item in record.Properties or {} do
			local unfinished = item.Tween and item.Tween.PlaybackState ~= Enum.PlaybackState.Completed
			if item.Tween then item.Tween:Cancel() end
			if item.Instance.Parent then
				-- Retain a property changed by another system after this effect.
				if unfinished or item.Instance[item.Property] == item.Applied then item.Instance[item.Property] = item.Before end
			end
		end
		if record.DescriptionChanged and same(record) then
			local restored = false
			local lastError
			for attempt = 1, 2 do
				if not same(record) then break end
				local ok, err = pcall(applyDescription, record.Humanoid, record.BeforeDescription)
				if ok then
					restored = true
					break
				end
				lastError = err
				if attempt < 2 then task.wait(.25) end
			end
			if not restored and same(record) then error("Avatar restore failed: " .. tostring(lastError)) end
		end
		if record.PhysicsChanged and same(record) and sameRoot(record) then
			-- Gravité inversée : reposer le joueur au sol sous sa position actuelle (pas de retour au point de départ,
			-- pas de chute depuis la hauteur atteinte), en gardant la direction où il regarde.
			if ctx.Sentinel and ctx.Sentinel.Exempt then ctx.Sentinel.Exempt(record.Target, 5, "APM Funny restore") end
			local root = record.Character:FindFirstChild("HumanoidRootPart")
			if root then
				local params = RaycastParams.new()
				params.FilterType = Enum.RaycastFilterType.Exclude
				params.FilterDescendantsInstances = { record.Character }
				local startHeight = record.BeforePivot.Position.Y
				local startHit = world:Raycast(record.BeforePivot.Position, Vector3.new(0, -50, 0), params)
				local standing = startHit and startHeight - startHit.Position.Y or 3
				local here = root.Position
				local drop = math.max(60, here.Y - startHeight + 60)
				local hit = world:Raycast(here, Vector3.new(0, -drop, 0), params)
				local landing = hit and Vector3.new(here.X, hit.Position.Y + standing, here.Z) or record.BeforePivot.Position
				local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
				if look.Magnitude < .01 then look = record.BeforePivot.LookVector * Vector3.new(1, 0, 1) end
				if look.Magnitude < .01 then look = Vector3.new(0, 0, -1) end
				record.Character:PivotTo(CFrame.lookAt(landing, landing + look.Unit))
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
		if record.NetworkBefore and record.Root.Parent then restoreNetwork(record.Root, record.NetworkBefore) end
		for _, description in { record.BeforeDescription, record.NewDescription } do
			if description then description:Destroy() end
		end
	end

	function api.IsSame(record)
		return same(record)
	end
	return api
end

return Transforms
