-- Known APM copies are retired privately, never deleted or merged over developer settings.
local Guard = {}
function Guard.Create(services)
	services = services or {}
	local storage = services.ServerStorage or game:GetService("ServerStorage")
	local quarantine = storage:FindFirstChild("APM_InactiveCopies")
	if quarantine then
		assert(quarantine:GetAttribute("APMInactiveCopies") == true, "APM quarantine name collision")
	else
		quarantine = Instance.new("Folder")
		quarantine.Name = "APM_InactiveCopies"
		quarantine:SetAttribute("APMInactiveCopies", true)
		quarantine.Parent = storage
	end
	local api = { Count = 0 }
	function api.Register(role, node)
		local registry = storage:FindFirstChild("APM_RuntimeRegistry")
		if not registry then
			registry = Instance.new("Folder")
			registry.Name = "APM_RuntimeRegistry"
			registry:SetAttribute("APMRuntimeRegistry", true)
			registry.Parent = storage
		end
		assert(registry:GetAttribute("APMRuntimeRegistry") == true, "APM registry collision")
		local reference = registry:FindFirstChild(role)
		if not reference then
			reference = Instance.new("ObjectValue")
			reference.Name = role
			reference.Parent = registry
		end
		assert(reference:IsA("ObjectValue") and (not reference.Value or reference.Value == node), "Canonical component already registered: " .. role)
		reference.Value = node
	end
	function api.Retire(node, reason)
		if not node or node == quarantine or node:IsDescendantOf(quarantine) then return end
		for _, v in node:GetDescendants() do if v:IsA("BaseScript") then v.Disabled = true elseif v:IsA("ScreenGui") then v.Enabled = false end end
		if node:IsA("BaseScript") then node.Disabled = true elseif node:IsA("ScreenGui") then node.Enabled = false end
		node:SetAttribute("APMInactiveReason", reason)
		node:SetAttribute("APMInactiveCopy", true)
		node.Parent = quarantine
		api.Count += 1
	end
	function api.Normalize(root)
		local owners = {}
		local function collect(parent, path)
			for _, child in parent:GetChildren() do
				local childPath = path .. "." .. child.Name
				local id = child:GetAttribute("APMComponentId")
				if child.Name == "APM_Core" and child:GetAttribute("APMCore") == true or child.Name == "APM_Extensions" and child:GetAttribute("APMExtensionsSchema") ~= nil then childPath = child.Name end
				local preferred = childPath == id
				if type(id) == "string" and (not owners[id] or preferred and not owners[id].Preferred) then owners[id] = { Node = child, Preferred = preferred } end
				if child:IsA("Folder") or child:IsA("Model") or child:IsA("LuaSourceContainer") then collect(child, childPath) end
			end
		end
		collect(root, root:GetAttribute("APMComponentId") or root.Name)
		local function visit(parent)
			local seen = {}
			for _, child in parent:GetChildren() do
				local id = child:GetAttribute("APMComponentId")
				if seen[child.Name] or (type(id) == "string" and owners[id].Node ~= child) then
					api.Retire(child, "Duplicate component: " .. tostring(id or child.Name))
				else
					seen[child.Name] = child
					if child:IsA("Folder") or child:IsA("Model") or child:IsA("LuaSourceContainer") then visit(child) end
				end
			end
		end
		visit(root)
	end
	function api.Sweep(core, extensions, bundle)
		local roots = services.Roots or { workspace, game:GetService("ReplicatedStorage"), game:GetService("ServerScriptService"), storage,
			game:GetService("StarterPlayer").StarterPlayerScripts, game:GetService("StarterGui") }
		local function protected(node)
			local registry = storage:FindFirstChild("APM_RuntimeRegistry")
			if registry then for _, reference in registry:GetChildren() do if reference:IsA("ObjectValue") and reference.Value and (node == reference.Value or node:IsDescendantOf(reference.Value)) then return true end end end
			return node == core or node == extensions or node == bundle or node == quarantine or node:IsDescendantOf(core)
				or node:IsDescendantOf(extensions) or (bundle and node:IsDescendantOf(bundle)) or node:IsDescendantOf(quarantine)
				or node.Name == "APM_RestorePoints" or node:GetAttribute("APMValidationFixture") == true
		end
		local reserved = { APM_Server = true, APM_Shared = true, APM_ClientTemplates = true, APM_Client = true, APM_Remotes = true, APM_Public = true,
			APM_Notices = true, APM_Gui = true, APM_Launcher = true, APM_Bootstrap = true }
		local visited = 0
		local function visit(parent)
			for _, node in parent:GetChildren() do
				visited += 1
				if visited % 400 == 0 then task.wait() end
				if not protected(node) then
					local id = node:GetAttribute("APMComponentId")
					local owned = type(id) == "string" and (id:sub(1, 9) == "APM_Core." or id:sub(1, 15) == "APM_Extensions.")
					local fullCore = node.Name == "APM_Core" and node:GetAttribute("APMCore") == true
					local kit = node:GetAttribute("APM_Kit") == true and node:GetAttribute("APMDistributionSchema") == 3
					local extensionsCopy = node.Name == "APM_Extensions" and node:GetAttribute("APMExtensionsSchema") ~= nil
					local legacy = reserved[node.Name] and (node:GetAttribute("APMRuntimeCopy") == true or node:GetAttribute("APMComponentId") ~= nil
							or (node.Name == "APM_Server" and node:FindFirstChild("APMService") and node:FindFirstChild("Core"))
							or (node.Name == "APM_Bootstrap" and node:GetAttribute("APMBootstrapApi") == 1)
							or (node.Name == "APM_Shared" and node:FindFirstChild("Remotes") and node:FindFirstChild("Lang") and node:FindFirstChild("Config")))
					if owned or fullCore or kit or legacy or extensionsCopy then api.Retire(node, "Isolated or duplicate APM component")
					elseif node:IsA("Folder") or node:IsA("Model") then visit(node) end
				end
			end
		end
		for _, parent in roots do visit(parent) end
		api.Normalize(core)
		api.Normalize(extensions)
		local registry = storage:FindFirstChild("APM_RuntimeRegistry")
		if registry then
			for _, role in { "Shared", "Public" } do
				local ref = registry:FindFirstChild(role)
				if ref and ref.Value then api.Normalize(ref.Value) end
			end
		end
		return api.Count
	end
	function api.Watch(core, extensions, bundle)
		local pending = false
		local connections = {}
		for _, root in services.Roots or { workspace, game:GetService("ReplicatedStorage"), game:GetService("ServerScriptService"), storage, game:GetService("StarterPlayer").StarterPlayerScripts,
			game:GetService("StarterGui") } do
			table.insert(connections, root.DescendantAdded:Connect(function(node)
				if node:GetAttribute("APMInactiveCopy") == true or pending then return end
				local id = node:GetAttribute("APMComponentId")
				if node:GetAttribute("APM_Kit") == true or node:GetAttribute("APMCore") == true or type(id) == "string" or node.Name == "APM_Extensions" or node.Name == "APM_Bootstrap" then
					pending = true
					task.defer(function()
						api.Sweep(core, extensions, bundle)
						pending = false
					end)
				end
			end))
		end
		return connections
	end
	return api
end
return Guard
