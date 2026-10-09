-- Stable entry point outside the Package. Updating Core never replaces this Script.
local RunService = game:GetService("RunService")
if not script:IsDescendantOf(game:GetService("ServerScriptService")) then return end
assert(RunService:IsServer(), "APM bootstrap is server-only")
local core = game:GetService("ServerStorage"):WaitForChild("APM_Core", 10)
assert(core and core:IsA("Model"), "[APM] Private APM_Core model missing")
require(core:WaitForChild("Bootstrap")).Start({
	ApiVersion = 1,
	AllowExperimental = script:GetAttribute("AllowExperimental") == true,
})
