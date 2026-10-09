-- Edit-only code rollback, retaining current extensions. Does not roll back DataStores.
-- Select one APM_CoreUpdate_* restore model in Explorer before executing.
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before restore")
local SS=game:GetService("ServerStorage") local selected=game:GetService("Selection"):Get() assert(#selected==1,"Select one restore point")
local point=selected[1] assert(point.Parent==SS:FindFirstChild("APM_RestorePoints") and point:GetAttribute("APMRestoreSchema")==3,"Independent Core restore point required")
local current=assert(SS:FindFirstChild("APM_Core"),"Current Core missing") local saved=assert(point:FindFirstChild("APM_Core"),"Saved Core missing")
assert(not current:FindFirstChildWhichIsA("PackageLink") and not saved:FindFirstChildWhichIsA("PackageLink"),"Linked Package: restore the supported revision using Studio Package Details")
assert(require(saved.Migrations).ValidateRelease(require(saved.Release),require(current.Release)),"Data/API incompatible; review separate migration")
local release=require(saved.Release) local bootstrap=assert(game.ServerScriptService:FindFirstChild("APM_Bootstrap"),"Bootstrap missing")
assert(bootstrap:GetAttribute("APMBootstrapApi")==release.BootstrapApiVersion and SS.APM_Extensions:GetAttribute("APMExtensionsSchema")==release.ExtensionsSchema,"External contracts incompatible")
assert(release.Channel=="stable" or bootstrap:GetAttribute("AllowExperimental")==true,"Experimental rollback requires explicit opt-in")
local staged=saved:Clone() local history=game:GetService("ChangeHistoryService") history:SetWaypoint("Before APM Core rollback")
local replaced=Instance.new("Model") replaced.Name="APM_BeforeRollback_"..game:GetService("HttpService"):GenerateGUID(false) replaced:SetAttribute("APMRestoreSchema",3)
current.Parent=replaced replaced.Parent=point.Parent
local ok,problem=pcall(function()staged.Parent=SS end) if not ok then staged:Destroy() current.Parent=SS replaced:Destroy() error(problem) end
history:SetWaypoint("APM Core rolled back; extensions retained")
print("[APM] Code restored; current extensions and DataStores retained. Test before publishing.")
