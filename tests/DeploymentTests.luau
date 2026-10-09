-- Run in Studio Edit against an installed Core. Real cloned instance trees, mocked service destinations.
-- Does not validate XML import, PackageLink publication, DataStores or published servers.
local Tests={}
function Tests.Run(installSource,bootstrapSource)
	assert(not game:GetService("RunService"):IsRunning(),"Edit only")
	local SS=game:GetService("ServerStorage")
	local root=Instance.new("Folder") root.Name="APM_IsolatedInstallerTest" root:SetAttribute("APMValidationFixture",true) root.Parent=SS
	local ok,result=pcall(function()
		local services={}
		for _,name in {"ServerStorage","ServerScriptService","ReplicatedStorage","StarterPlayerScripts"} do
			local folder=Instance.new("Folder") folder.Name=name folder.Parent=root services[name]=folder
		end
		services.Players={GetPlayers=function()return {} end}
		services.RunService={IsRunning=function()return false end,IsServer=function()return true end}
		services.ChangeHistoryService={SetWaypoint=function()end}
		services.StarterPlayer={StarterPlayerScripts=services.StarterPlayerScripts}
		local mockGame={GetService=function(_,name)return assert(services[name],name) end}
		local bundle=Instance.new("Model") bundle.Name="APM_Distribution" bundle:SetAttribute("APMDistributionSchema",3)
		SS.APM_Core:Clone().Parent=bundle SS.APM_Extensions:Clone().Parent=bundle
		local entry=game.ServerScriptService.APM_Bootstrap:Clone() entry.Disabled=true entry.Parent=bundle bundle.Parent=services.ServerStorage
		local env=setmetatable({game=mockGame},{__index=getfenv()})
		local install=assert(loadstring(installSource)) setfenv(install,env) install()
		assert(services.ServerStorage.APM_Core and services.ServerStorage.APM_Extensions and services.ServerScriptService.APM_Bootstrap)
		assert(not services.ServerScriptService.APM_Bootstrap.Disabled and services.ServerScriptService.APM_Bootstrap:GetAttribute("APMBootstrapApi")==1)
		local core=services.ServerStorage.APM_Core
		assert(not core.ClientTemplates.APM_Client.APM_Boot.Disabled and not core.ClientTemplates.APM_Notices.Disabled)
		assert(not pcall(install),"Duplicate installer accepted")
		local bootstrap=assert(loadstring(bootstrapSource))
		setfenv(bootstrap,setmetatable({game=mockGame,script={Parent=core}},{__index=getfenv()}))
		local gate=bootstrap()
		assert(not pcall(gate.Start,{ApiVersion=1,AllowExperimental=false}),"Experimental release accepted without opt-in")
		assert(not services.ReplicatedStorage:FindFirstChild("APM_Shared"),"Gate published shared code before validation")
		assert(not pcall(gate.Start,{ApiVersion=2,AllowExperimental=true}),"Future bootstrap API accepted")
		local release=table.clone(require(core.Release)) release.DataSchemaVersion=3
		assert(require(core.Migrations).ValidateRelease(release)==false,"Future data schema accepted")
		return {Passed=true,FreshInstallerIsolated=true,EntryAndTemplatesEnabled=true,DuplicateRejected=true,
			ExperimentalGate=true,FutureApiRejected=true,FutureDataSchemaRejected=true,
			Scope="Isolated cloned Studio trees and mocked service boundary; no XML import or runtime deployment"}
	end)
	root:Destroy() assert(ok,result) return result
end
return Tests
