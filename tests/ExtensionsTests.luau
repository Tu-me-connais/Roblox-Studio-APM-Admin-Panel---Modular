-- Pure loader/contract tests. No Instances, DataStores, remotes or live experience mutation.
local Tests={}
function Tests.Run(extensionSource)
	local assertions=0
	local function check(condition,message) assertions+=1 assert(condition,message) end
	local function node(name,className,descendants,manifest,requireError)
		local object={Name=name,ClassName=className,Children=descendants or {},Manifest=manifest,RequireError=requireError}
		function object:IsA(class) return self.ClassName==class end
		function object:GetChildren() return table.clone(self.Children) end
		function object:FindFirstChild(childName)
			for _,child in self.Children do if child.Name==childName then return child end end
		end
		return object
	end
	local function fresh(root)
		local serverStorage=node("ServerStorage","Folder",root and {root} or {})
		local warnings={}
		local environment=setmetatable({game={GetService=function(_,name) assert(name=="ServerStorage") return serverStorage end},
			require=function(source) if source.RequireError then error(source.RequireError) end return source.Manifest end,
			warn=function(message) table.insert(warnings,tostring(message)) end},{__index=getfenv(0)})
		local chunk,problem=loadstring(extensionSource,"APM_Extensions_tests")
		assert(chunk,problem) setfenv(chunk,environment)
		return chunk(),warnings
	end
	local ranks={ById={Owner={},Staff={}},Defaults={["AutoBridge.View"]={},["Examples.Inventory.View"]={}}}
	local function command(name)
		return {ApiVersion=1,Name=name or "DemoCommand",Category="Examples",Mode="action",MinRank="Owner",Execute=function() return true,"OK" end}
	end
	local empty=fresh()
	check(empty.ApiVersion==1,"Expected extension API v1")
	local duplicateRecords=fresh()
	duplicateRecords.Record("Commands","Example:SameName","Error","DuplicateCommand")
	duplicateRecords.Record("Commands","Example:SameName","Loaded")
	check(duplicateRecords.Snapshot().Loaded==1 and duplicateRecords.Snapshot().Errors==1,"Rejected duplicate must not hide the successful registration or its error")
	check(empty.ValidateCommand(command(),"Demo",ranks),"Valid command rejected")
	local invalid=command() invalid.ApiVersion=2
	local ok,code=empty.ValidateCommand(invalid,"Demo",ranks)
	check(not ok and code=="UnsupportedApi","Unknown API accepted")
	invalid=command() invalid.MinRank="MissingRank"
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Unknown rank accepted")
	invalid=command() invalid.Order=0/0
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Nonfinite order accepted")
	invalid=command() invalid.Label=function() return "secret" end
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Executable public metadata accepted")
	invalid=command() invalid.Fields={{Name="Amount",Type="number",Min=5,Max=1}}
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Reversed numeric bounds accepted")
	invalid=command() invalid.Fields={["hidden"]={Name="Amount",Type="number"}}
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Nondense Fields accepted")
	invalid=command() invalid.Fields={{Name="Value",Type="number"},{Name="Value",Type="number"}}
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Duplicate field name accepted")
	invalid=command() invalid.Inputs={"UnvalidatedField"}
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Unvalidated input accepted")
	invalid=command() invalid.Strings={fr="not a dictionary"}
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Invalid Strings accepted")
	invalid=command() invalid.Default={}
	for _=1,7 do invalid.Default={child=invalid.Default} end
	check(not empty.ValidateCommand(invalid,"Demo",ranks),"Unbounded public metadata accepted")
	local sourceRoot=node("APM_Extensions","Folder",{node("Commands","Folder",{
		node("Zulu","ModuleScript"),node("Alpha","Folder",{node("Second","ModuleScript"),node("First","ModuleScript"),node("Nested","Folder",{node("Third","ModuleScript")})})})})
	local discovery=fresh(sourceRoot)
	local sources=discovery.CommandSources()
	check(#sources==4,"Command discovery count")
	check(sources[1].Source.Name=="First" and sources[2].Source.Name=="Third" and sources[3].Source.Name=="Second" and sources[4].Source.Name=="Zulu","Command discovery must be deterministic")
	check(sources[1].ExtensionId=="Alpha" and sources[4].ExtensionId=="Zulu","Command namespace provenance")
	local many={}
	for index=1,205 do table.insert(many,node(string.format("Command%03d",index),"ModuleScript")) end
	local limited=fresh(node("APM_Extensions","Folder",{node("Commands","Folder",many)}))
	check(#limited.CommandSources()==200 and limited.Snapshot().Errors==1,"Command discovery must be bounded")
	local function adapter(permission)
		return {Permission=permission,Probe=function() return {Status="Detected",Name="Actual fixture",Count=1} end,Actions={}}
	end
	local integrationCalls=0
	local initSecret="PRIVATE_TEST_MARKER_DO_NOT_LEAK"
	local root=node("APM_Extensions","Folder",{
		node("Adapters","Folder",{
			node("AValid","ModuleScript",nil,{ApiVersion=1,Id="valid_adapter",Adapter=adapter("Examples.Inventory.View")}),
			node("BUnknownPermission","ModuleScript",nil,{ApiVersion=1,Id="unknown_permission",Adapter=adapter("Secret.Unknown")}),
			node("CCollision","ModuleScript",nil,{ApiVersion=1,Id="teams",Adapter=adapter("AutoBridge.View")}),
			node("DFuture","ModuleScript",nil,{ApiVersion=2,Id="future",Adapter=adapter("AutoBridge.View")}),
			node("ERequireFailure","ModuleScript",nil,nil,initSecret),
			node("FUnknownActionPermission","ModuleScript",nil,{ApiVersion=1,Id="bad_action",Adapter={Permission="AutoBridge.View",Probe=function() return {} end,
				Actions={Mutate={Permission="Secret.Unknown",Validate=function() return {} end,Execute=function() return true end}}}}),
		}),
		node("Server","Folder",{
			node("AIntegration","ModuleScript",nil,{ApiVersion=1,Id="demo_server",Init=function(api)
				integrationCalls+=1
				check(api.ApiVersion==1 and api.Id=="demo_server" and table.isfrozen(api),"Integration API contract")
				check(api.Remotes==nil and api.Ranks==nil and api.Exempt==nil,"Sensitive implementation API exposed")
				local loaded=api.RegisterCommand(command("DemoIntegrationCommand"))
				check(loaded,"Integration command rejected")
				local collision=api.RegisterCommand(command("Kick"))
				check(not collision,"Integration replaced official command")
				local future=command("FutureCommand") future.ApiVersion=99
				check(not api.RegisterCommand(future),"Integration loaded unknown command API")
				local key=api.RegisterOptions("teams",function() return {{"actual_team","Actual team"}} end)
				check(key=="demo_server.teams","Options must use extension namespace")
				check(api.AddProfileProvider(function(userId) return {{Label="UserId",Value=userId}} end),"Profile hook not registered")
				check(api.RegisterAdapter("secondary",adapter("Examples.Inventory.View")),"Integration adapter not registered")
				check(api.HasPermission({Allowed=true},"AutoBridge.View"),"Known effective permission rejected")
				check(not api.HasPermission({Allowed=true},"Secret.Unknown"),"Unknown effective permission accepted")
				check(api.Authorize({Allowed=true},"DemoIntegrationCommand"),"Authorization wrapper failed")
			end}),
			node("BCollision","ModuleScript",nil,{ApiVersion=1,Id="valid_adapter",Init=function() error("Duplicate manifest must never initialize") end}),
			node("CInitFailure","ModuleScript",nil,{ApiVersion=1,Id="init_failure",Init=function() error(initSecret) end}),
		}),
	})
	local module,warnings=fresh(root)
	local registered={teams=true}
	local commands={Kick={Official=true}}
	local optionProviders,profileProviders={},{}
	local service={RegisterOptions=function(name,provider) optionProviders[name]=provider end,AddProfileProvider=function(provider) table.insert(profileProviders,provider) end}
	local context={Ranks={ById=ranks.ById,Defaults=ranks.Defaults,CanUse=function(player,permission) return player.Allowed==true and ranks.Defaults[permission]~=nil end,
		CanTarget=function() return false end},AutoBridge={RegisterAdapter=function(id,value)
		if registered[id] then return false,"Adapter already registered" end registered[id]=value return true
	end},Notify=function() end,Log=function() end,Authorize=function(player,name) return player.Allowed==true and commands[name]~=nil end}
	function context.RegisterExtensionCommand(value,namespace)
		local valid,why=module.ValidateCommand(value,namespace,context.Ranks)
		if not valid then return false,why end
		if commands[value.Name] then return false,"DuplicateCommand" end
		commands[value.Name]=value return true
	end
	local booted,problem=pcall(module.Init,context,service)
	check(booted,"Rejected extension must not crash loader: "..tostring(problem))
	check(context.Extensions==module,"Context extension registry absent")
	check(registered.valid_adapter~=nil and registered.demo_server_secondary~=nil,"Valid adapters were not loaded")
	check(registered.unknown_permission==nil and registered.future==nil and registered.bad_action==nil,"Rejected adapter was loaded")
	check(commands.Kick.Official==true and commands.DemoIntegrationCommand~=nil and commands.FutureCommand==nil,"Command registry collision/version handling")
	check(optionProviders["demo_server.teams"]()[1][1]=="actual_team","Real options provider not called")
	check(#profileProviders==1 and profileProviders[1](123)[1].Value==123,"Profile provider arguments changed")
	local snapshot=module.Snapshot()
	check(snapshot.Present and snapshot.Loaded==2 and snapshot.Errors==7,"Expected loaded/error diagnostics")
	local fields={Kind=true,Id=true,Status=true,Code=true}
	for _,entry in snapshot.Entries do
		for key,value in entry do check(fields[key] and (type(value)~="string" or not string.find(value,initSecret,1,true)),"Diagnostics leaked private details") end
	end
	check(#warnings>=2,"Complete errors should remain available in server console")
	snapshot.Entries[1].Status="ChangedByConsumer"
	check(module.Snapshot().Entries[1].Status~="ChangedByConsumer","Diagnostic snapshot aliases internal records")
	module.Init(context,service)
	check(integrationCalls==1,"Init must be idempotent")
	local absent=fresh()
	check(pcall(absent.Init,context,service) and not absent.Snapshot().Present,"Absent optional root should boot")
	return {Passed=true,Assertions=assertions,Scope="Pure mocked loader/contract tests; native APM pipeline needs separate Studio integration tests"}
end
return Tests
