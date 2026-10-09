-- Manual local update in Studio Edit; actual linked Packages use Studio's Get Latest workflow.
-- Insert the reviewed new APM_Distribution in ServerStorage. Extensions/bootstrap are never overwritten.
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before Core update")
local SS=game:GetService("ServerStorage") local SSS=game:GetService("ServerScriptService")
local function unique(parent,name) local found for _,v in parent:GetChildren() do if v.Name==name then assert(not found,"Duplicate "..name) found=v end end return found end
local bundle=unique(SS,"APM_Distribution") local current=unique(SS,"APM_Core") local extensions=unique(SS,"APM_Extensions") local bootstrap=unique(SSS,"APM_Bootstrap")
assert(bundle and current and extensions and bootstrap,"Reviewed bundle and installed architecture required")
local candidate=assert(bundle:FindFirstChild("APM_Core"),"Candidate Core missing") local nextRelease=require(candidate.Release) local oldRelease=require(current.Release)
assert(require(candidate.Migrations).ValidateRelease(nextRelease,oldRelease),"Unsupported migration")
assert(extensions:GetAttribute("APMExtensionsSchema")==nextRelease.ExtensionsSchema and bootstrap:GetAttribute("APMBootstrapApi")==nextRelease.BootstrapApiVersion,"External contracts incompatible")
assert(nextRelease.Channel=="stable" or bootstrap:GetAttribute("AllowExperimental")==true,"Experimental update requires explicit opt-in")
assert(not current:FindFirstChildWhichIsA("PackageLink") and not candidate:FindFirstChildWhichIsA("PackageLink"),"Linked Package: use Studio version management to preserve the real PackageLink")
local history=game:GetService("ChangeHistoryService") history:SetWaypoint("Before manual APM Core update")
local points=SS:FindFirstChild("APM_RestorePoints") if not points then points=Instance.new("Folder") points.Name="APM_RestorePoints" points.Parent=SS end
local backup=Instance.new("Model") backup.Name="APM_CoreUpdate_"..game:GetService("HttpService"):GenerateGUID(false)
backup:SetAttribute("CreatedAt",os.time()) backup:SetAttribute("APMRestoreSchema",3)
-- Preserve private template Disabled flags exactly. Only the external entry Script is disabled in its backup.
for _,v in {current,extensions,bootstrap} do
	local c=v:Clone()
	if c:IsA("BaseScript") then c:SetAttribute("APMPreviousDisabled",c.Disabled) c.Disabled=true end
	c.Parent=backup
end
backup.Parent=points
local staged=candidate:Clone()
current.Parent=nil local ok,problem=pcall(function()staged.Parent=SS end)
if not ok then staged:Destroy() current.Parent=SS error(problem) end
current:Destroy()
history:SetWaypoint("APM Core updated; extensions preserved")
print("[APM] Core "..nextRelease.Version.."; restore point "..backup:GetFullName()..". Test before publication.")
