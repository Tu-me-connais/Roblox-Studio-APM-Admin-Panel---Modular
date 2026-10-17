-- Copy into Studio Command Bar, in Edit. Insert APM_Distribution or APM_Kit (schema 3) into ServerStorage first.
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before installation")
local SS=game:GetService("ServerStorage") local SSS=game:GetService("ServerScriptService") local RS=game:GetService("ReplicatedStorage")
local function unique(parent,name)
	local found for _,v in parent:GetChildren() do if v.Name==name then assert(not found,"Duplicate "..name) found=v end end return found
end
local bundle
for _,candidate in SS:GetChildren() do
	if candidate.Name=="APM_Distribution" or candidate.Name=="APM_Kit" then
		assert(candidate:IsA("Model") and candidate:GetAttribute("APMDistributionSchema")==3,"Legacy or incompatible bundle: review migration")
		assert(not bundle,"Duplicate APM installation bundles")
		bundle=candidate
	end
end
assert(bundle,"Compatible private bundle missing")
assert(not unique(SS,"APM_Core") and not unique(SS,"APM_Extensions") and not unique(SSS,"APM_Bootstrap"),"Existing installation: use reviewed migration or UpdateCore")
assert(not SS:FindFirstChild("APM_ClientTemplates") and not SSS:FindFirstChild("APM_Server")
	and not RS:FindFirstChild("APM_Shared") and not RS:FindFirstChild("APM_Remotes")
	and not game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("APM_Notices"),"Legacy installation: review and migrate, do not install a second APM")
local core=assert(bundle:FindFirstChild("APM_Core"),"Core missing") local release=require(core.Release)
assert(require(core.Migrations).ValidateRelease(release),"Unsupported release")
local extensions=assert(bundle:FindFirstChild("APM_Extensions"),"Extensions missing")
assert(extensions:GetAttribute("APMExtensionsSchema")==release.ExtensionsSchema,"Extensions incompatible")
local bootstrap=assert(bundle:FindFirstChild("APM_Bootstrap"),"Bootstrap missing") assert(bootstrap:IsA("Script") and bootstrap.Disabled,"Bootstrap must be disabled in bundle")
local staged={core:Clone(),extensions:Clone(),bootstrap:Clone()}
local history=game:GetService("ChangeHistoryService") history:SetWaypoint("Before APM Core installation")
local ok,problem=pcall(function()
	staged[1].Parent=SS staged[2].Parent=SS
	staged[3]:SetAttribute("APMBootstrapApi",release.BootstrapApiVersion)
	staged[3]:SetAttribute("AllowExperimental",release.Channel=="experimental") staged[3].Parent=SSS staged[3].Disabled=false
end)
if not ok then for _,v in staged do v:Destroy() end error(problem) end
history:SetWaypoint("APM Core and Extensions installed")
print("[APM] Installed "..release.Version.."; extensions are outside Core. Test before publishing. Imported bundle retained.")
