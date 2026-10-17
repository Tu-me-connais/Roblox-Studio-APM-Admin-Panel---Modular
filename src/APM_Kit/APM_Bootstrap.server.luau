-- Stable entry point outside the Package. Updating Core never replaces this Script.
local RunService = game:GetService("RunService")
if not script:IsDescendantOf(game:GetService("ServerScriptService")) then return end
assert(RunService:IsServer(), "APM bootstrap is server-only")
local storage = game:GetService("ServerStorage")
local core = storage:FindFirstChild("APM_Core")
if not core or core:GetAttribute("APMCore") ~= true then return end
local registry = storage:FindFirstChild("APM_RuntimeRegistry")
if not registry then
	registry = Instance.new("Folder")
	registry.Name = "APM_RuntimeRegistry"
	registry:SetAttribute("APMRuntimeRegistry", true)
	registry.Parent = storage
end
assert(registry:GetAttribute("APMRuntimeRegistry") == true, "APM registry collision")
local owner = registry:FindFirstChild("Runner")
if owner and owner.Value and owner.Value ~= script then return end
if not owner then
	owner = Instance.new("ObjectValue")
	owner.Name = "Runner"
	owner.Parent = registry
end
owner.Value = script
assert(core and core:IsA("Model"), "[APM] Private APM_Core model missing")
require(core:WaitForChild("Bootstrap")).Start({
	ApiVersion = 1,
	AllowExperimental = script:GetAttribute("AllowExperimental") == true,
})
