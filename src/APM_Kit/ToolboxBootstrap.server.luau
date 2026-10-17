-- Toolbox entry: insert APM_Kit, then Play. The server parks the kit in ServerStorage.
-- A private runner survives that move. No Source write, download or permanent Studio installation.
local RunService = game:GetService("RunService")
if not RunService:IsServer() then return end
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local isRunner = script:GetAttribute("APMToolboxRunner") == true
local reference = isRunner and script:FindFirstChild("APMKitRoot")
local bundle = isRunner and reference and reference:IsA("ObjectValue") and reference.Value or script.Parent
local function unique(parent, name)
	local found
	for _, child in parent:GetChildren() do
		if child.Name == name then
			assert(not found, "Duplicate " .. name)
			found = child
		end
	end
	return found
end
local function refuse(reason)
	warn("[APM] Toolbox: " .. reason)
	return { Started = false, Reason = reason }
end
if not bundle or not bundle:IsA("Model") or bundle:GetAttribute("APM_Kit") ~= true
		or bundle:GetAttribute("APMDistributionSchema") ~= 3 or bundle:GetAttribute("APMToolboxApi") ~= 1 then
	return refuse("Unsupported Toolbox kit. No installation changed.")
end
if not isRunner then
	if script:IsDescendantOf(SS) then
		return refuse("ServerStorage does not run scripts. Insert APM_Kit in Workspace or ServerScriptService to start it.")
	end
	-- Remember the editable kit path before parking the bundle in ServerStorage.
 bundle:SetAttribute("APMEditKitPath", bundle:GetFullName())
	-- Elect exactly one entry before cloning or requiring anything that can yield.
	local registry = SS:FindFirstChild("APM_RuntimeRegistry")
	if not registry then
		registry = Instance.new("Folder")
		registry.Name = "APM_RuntimeRegistry"
		registry:SetAttribute("APMRuntimeRegistry", true)
		registry.Parent = SS
	end
	assert(registry:GetAttribute("APMRuntimeRegistry") == true, "APM registry collision")
	local owner = registry:FindFirstChild("Runner")
	if owner and owner.Value then
		local canonical = owner.Value:FindFirstChild("APMKitRoot")
		if canonical and canonical:IsA("ObjectValue") and canonical.Value == bundle then
			script.Disabled = true
			return { Started = false, Duplicate = true }
		end
		bundle:SetAttribute("APMRuntimeState", "Inactive")
		script.Disabled = true
		local quarantine = SS:FindFirstChild("APM_InactiveCopies")
		if not quarantine then
			quarantine = Instance.new("Folder")
			quarantine.Name = "APM_InactiveCopies"
			quarantine:SetAttribute("APMInactiveCopies", true)
			quarantine.Parent = SS
		end
		assert(quarantine:GetAttribute("APMInactiveCopies") == true, "APM quarantine collision")
		for _, node in bundle:GetDescendants() do if node:IsA("BaseScript") then node.Disabled = true end end
		bundle:SetAttribute("APMInactiveCopy", true)
		bundle.Parent = quarantine
		return { Started = false, Duplicate = true }
	end
	-- Publish an independent, server-only runner before moving the script's original ancestor.
	-- Scripts stored in ServerStorage stop executing, so the entry must hand off first.
	local runner = script:Clone()
	assert(runner, "ToolboxBootstrap must be Archivable")
	runner.Disabled = true
	runner.Name = "APM_ToolboxBootstrap"
	runner:SetAttribute("APMToolboxRunner", true)
	runner:SetAttribute("APMRuntimeCopy", true)
	if not owner then
		owner = Instance.new("ObjectValue")
		owner.Name = "Runner"
		owner.Parent = registry
	end
	owner.Value = runner
	local target = Instance.new("ObjectValue")
	target.Name = "APMKitRoot"
	target.Value = bundle
	target.Parent = runner
	runner.Disabled = false
	runner.Parent = SSS
	return { Started = false, HandedOff = true }
end
assert(script.Parent == SSS, "Toolbox runner must be private in ServerScriptService")
-- Park before requiring any module, yielding or starting services. Never move unrelated objects.
if bundle.Parent ~= SS then
	local name, suffix = bundle.Name, 1
	while SS:FindFirstChild(bundle.Name) and SS:FindFirstChild(bundle.Name) ~= bundle do
		suffix += 1
		bundle.Name = name .. "_" .. suffix
	end
	bundle.Parent = SS
end
local entryTemplate = bundle:FindFirstChild("ToolboxBootstrap")
if entryTemplate and entryTemplate:IsA("Script") then entryTemplate.Disabled = true end
bundle:SetAttribute("APMRuntimePlacement", "ServerStorage")
local function retireRunner()
	task.defer(function()
		script:Destroy()
	end)
end
local stagedCore, stagedExtensions, started, claimed
local ok, result = pcall(function()
	if SS:GetAttribute("APMToolboxBootClaim") ~= nil then
		return refuse("An APM Core or startup already exists. Duplicate kit ignored; existing installation retained.")
	end
	local core = assert(bundle:FindFirstChild("APM_Core"), "Kit Core missing")
	assert(core:IsA("Model") and core:GetAttribute("APMCore") == true, "Invalid Core")
	assert(not core:FindFirstChildOfClass("PackageLink"), "Toolbox Core must be standalone")
	local installation = require(core.Server.Core.InstallationGuard).Create()
	installation.Normalize(bundle)
	local currentExtensions = SS:FindFirstChild("APM_Extensions") or bundle:FindFirstChild("APM_Extensions")
	assert(currentExtensions, "Extensions missing")
	installation.Register("SourceKit", bundle)
	installation.Register("SourceCore", core)
	installation.Register(currentExtensions.Parent == SS and "Extensions" or "SourceExtensions", currentExtensions)
	installation.Sweep(core, currentExtensions, bundle)
	assert(not SS:FindFirstChild("APM_ClientTemplates") and not SSS:FindFirstChild("APM_Server")
			and not RS:FindFirstChild("APM_Shared") and not RS:FindFirstChild("APM_Remotes") and not RS:FindFirstChild("APM_Public")
			and not game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("APM_Notices"), "Unknown conflicting transport retained; startup closed")
	local releaseModule = assert(core:FindFirstChild("Release"), "Release missing")
	local migrations = assert(core:FindFirstChild("Migrations"), "Migrations missing")
	assert(releaseModule:IsA("ModuleScript") and migrations:IsA("ModuleScript"), "Invalid release modules")
	local release = require(releaseModule)
	assert(require(migrations).ValidateRelease(release), "Unsupported release")
	assert(core:FindFirstChild("Bootstrap") and core.Bootstrap:IsA("ModuleScript"), "Core Bootstrap missing")
	assert(release.CoreApiVersion == 1 and release.BootstrapApiVersion == 1 and release.InstallationSchema == 3,
		"Unsupported Toolbox/Core contract")
	assert(release.Channel == "stable" or bundle:GetAttribute("AllowExperimental") == true,
		"Experimental kit needs explicit AllowExperimental=true")
	local externalEntry = unique(SSS, "APM_Bootstrap")
	assert(not externalEntry or (externalEntry:IsA("Script") and externalEntry.Disabled and externalEntry:GetAttribute("APMBootstrapApi") == 1),
		"Active or incompatible external bootstrap: review installation")
	local existingExtensions = unique(SS, "APM_Extensions")
	local extensions = existingExtensions or assert(unique(bundle, "APM_Extensions"), "Kit Extensions missing")
	assert(extensions:IsA("Folder") and extensions:GetAttribute("APMExtensionsSchema") == release.ExtensionsSchema,
		"Extensions schema incompatible; configuration retained")
	local config = assert(extensions:FindFirstChild("Config"), "Extensions Config missing")
 local kitExtensions = unique(bundle, "APM_Extensions")
 local duplicateConfiguration = existingExtensions ~= nil and kitExtensions ~= nil and kitExtensions ~= existingExtensions
 local editKitPath = bundle:GetAttribute("APMEditKitPath") or bundle:GetFullName()
 local kitSettingsPath = editKitPath .. ".APM_Extensions.Config.ServerSettings"
 local activeSettingsPath = existingExtensions and (existingExtensions:GetFullName() .. ".Config.ServerSettings") or kitSettingsPath
 extensions:SetAttribute("APMConfigurationSourcePath", activeSettingsPath)
 extensions:SetAttribute("APMDuplicateConfigurations", duplicateConfiguration)
 extensions:SetAttribute("APMAlternateConfigurationPath", duplicateConfiguration and kitSettingsPath or nil)
 print("[APM] Configuration active : " .. activeSettingsPath)
 if duplicateConfiguration then
  warn("[APM] Deux configurations présentes : ServerStorage.APM_Extensions est prioritaire. Les réglages du kit ne sont pas utilisés : " .. kitSettingsPath)
 end
	for _, name in { "ServerSettings", "SharedConfig" } do
		assert(config:FindFirstChild(name) and config[name]:IsA("ModuleScript"), "Config module missing: " .. name)
	end
	-- Claim before publishing copies or yielding in the actual Core initialization.
	if unique(SS, "APM_Core") or SS:GetAttribute("APMToolboxBootClaim") ~= nil then
		return refuse("Another APM startup won the claim; this copy remains inactive.")
	end
	SS:SetAttribute("APMToolboxBootClaim", bundle:GetFullName())
	claimed = true
	stagedCore = core:Clone()
	stagedCore:SetAttribute("APMRuntimeCopy", true)
	if not existingExtensions then
		stagedExtensions = extensions:Clone()
		stagedExtensions:SetAttribute("APMRuntimeCopy", true)
		stagedExtensions.Parent = SS
		installation.Register("Extensions", stagedExtensions)
	end
	stagedCore.Parent = SS
	installation.Register("Core", stagedCore)
	started = true -- Initialization may create services; do not retry or pretend it is transactional.
	local context = require(stagedCore:WaitForChild("Bootstrap")).Start({
		ApiVersion = release.BootstrapApiVersion,
		AllowExperimental = bundle:GetAttribute("AllowExperimental") == true,
	})
	bundle:SetAttribute("APMRuntimeState", "Ready")
	print("[APM] Toolbox kit " .. release.Version .. " ready; kit in ServerStorage, private runner, developer extensions preserved.")
	return { Started = true, ReusedExtensions = existingExtensions ~= nil }
end)
if not ok then
	if not started then
		if stagedCore then stagedCore:Destroy() end
		if stagedExtensions then stagedExtensions:Destroy() end
		if claimed and SS:GetAttribute("APMToolboxBootClaim") == bundle:GetFullName() then SS:SetAttribute("APMToolboxBootClaim", nil) end
	end
	bundle:SetAttribute("APMRuntimeState", "Failed")
	if not started then retireRunner() end
	return refuse(tostring(result))
end
if not result.Started then
	bundle:SetAttribute("APMRuntimeState", "Inactive")
	retireRunner()
end
return result
