-- Trusted developer sources live outside APM_Core. Nothing is downloaded or discovered in game systems.
local ServerStorage = game:GetService("ServerStorage")
local Extensions = { ApiVersion = 1 }
local records, initialized = {}, false
local function identifier(value, limit)
	return type(value)=="string" and #value>0 and #value<=(limit or 40) and string.match(value,"^[%w_%-%.]+$")~=nil
end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
local function publicData(value,depth,budget)
	budget.n+=1
	if budget.n>1000 or depth>5 then return false end
	local kind=typeof(value)
	if kind=="nil" or kind=="boolean" or kind=="Color3" then return true end
	if kind=="number" then return finite(value) end
	if kind=="string" then return #value<=4096 and utf8.len(value)~=nil end
	if kind~="table" then return false end
	for key,item in value do
		if (type(key)~="string" and type(key)~="number") or not publicData(key,depth+1,budget) or not publicData(item,depth+1,budget) then return false end
	end
	return true
end
local function children(folder)
	local list=folder:GetChildren()
	table.sort(list,function(a,b) return a.Name<b.Name end)
	return list
end
function Extensions.Root()
	local root=ServerStorage:FindFirstChild("APM_Extensions")
	if root and (root:IsA("Folder") or root:IsA("Model")) then return root end
	return nil
end
function Extensions.Record(kind,id,status,code)
	-- Retain a successful registration and its rejected duplicate as separate facts.
	local key=kind..":"..tostring(id)..":"..tostring(status)..":"..tostring(code)
	records[key]={Kind=kind,Id=string.sub(tostring(id),1,100),Status=status,Code=code}
end
function Extensions.Snapshot()
	local entries,loaded,errors={},{},0
	for _,record in records do
		table.insert(entries,table.clone(record))
		if record.Status=="Error" then errors+=1 elseif record.Status=="Loaded" then table.insert(loaded,record.Id) end
	end
	table.sort(entries,function(a,b) if a.Kind==b.Kind then return a.Id<b.Id end return a.Kind<b.Kind end)
	return {ApiVersion=Extensions.ApiVersion,Present=Extensions.Root()~=nil,Loaded=#loaded,Errors=errors,Entries=entries}
end
-- Namespace is the top Commands folder, or the source name for a direct ModuleScript.
function Extensions.CommandSources()
	local root=Extensions.Root()
	local folder=root and root:FindFirstChild("Commands")
	local sources={}
	if not folder or not folder:IsA("Folder") then return sources end
	local function visit(node,namespace,depth)
		if depth>8 or #sources>=200 then Extensions.Record("Commands",namespace,"Error","SourceLimit") return end
		for _,child in children(node) do
			if #sources>=200 then Extensions.Record("Commands",namespace,"Error","SourceLimit") return end
			if child:IsA("ModuleScript") then table.insert(sources,{Source=child,ExtensionId=namespace})
			elseif child:IsA("Folder") then visit(child,namespace,depth+1) end
		end
	end
	for _,child in children(folder) do
		if #sources>=200 then Extensions.Record("Commands","limit","Error","SourceLimit") break end
		if not identifier(child.Name) then Extensions.Record("Commands",child.Name,"Error","InvalidNamespace")
		elseif child:IsA("ModuleScript") then table.insert(sources,{Source=child,ExtensionId=child.Name})
		elseif child:IsA("Folder") then visit(child,child.Name,1) end
	end
	return sources
end
function Extensions.ValidateCommand(command,namespace,ranks)
	if not identifier(namespace) or type(command)~="table" or command.ApiVersion~=Extensions.ApiVersion then return false,"UnsupportedApi" end
	if not identifier(command.Name,64) or type(command.Execute)~="function" or not identifier(command.Category,64)
		or type(command.MinRank)~="string" or not ranks.ById[command.MinRank] then return false,"InvalidCommand" end
	if command.Mode~=nil and command.Mode~="action" and command.Mode~="target" and command.Mode~="toggle" and command.Mode~="slider" then return false,"InvalidMode" end
	if command.Order~=nil and not finite(command.Order) then return false,"InvalidOrder" end
	if command.Init~=nil and type(command.Init)~="function" then return false,"InvalidInit" end
	if command.OnAccessRevoked~=nil and type(command.OnAccessRevoked)~="function" then return false,"InvalidCleanup" end
	if command.Color~=nil and typeof(command.Color)~="Color3" then return false,"InvalidColor" end
	if command.Confirm~=nil and type(command.Confirm)~="boolean" then return false,"InvalidConfirmation" end
	if command.AllowSelf~=nil and type(command.AllowSelf)~="boolean" then return false,"InvalidTargetPolicy" end
	for _,key in {"Min","Max","Default"} do
		if command[key]~=nil and (key~="Default" or command.Mode=="slider") and not finite(command[key]) then return false,"InvalidNumber" end
	end
	if command.Min~=nil and command.Max~=nil and command.Min>command.Max then return false,"InvalidRange" end
	local budget={n=0}
	for _,key in {"Name","Label","Description","Category","Mode","Group","Order","Color","Min","Max","Default","Confirm","Fields","Inputs","Strings"} do
		if not publicData(command[key],0,budget) then return false,"InvalidPublicData" end
	end
	if command.Fields~=nil then
		if type(command.Fields)~="table" or #command.Fields>40 then return false,"InvalidFields" end
		local names,count={},0
		for index,field in command.Fields do
			count+=1
			if count>40 or type(index)~="number" or index%1~=0 or index<1 or index>#command.Fields then return false,"InvalidFields" end
			if type(field)~="table" or not identifier(field.Name,64) or names[field.Name]
				or (field.Type~="number" and field.Type~="choice" and field.Type~="text" and field.Type~="string") then return false,"InvalidField" end
			names[field.Name]=true
			for _,key in {"Min","Max","Default","MaxLength"} do
				if field[key]~=nil and (key~="Default" or field.Type=="number") and not finite(field[key]) then return false,"InvalidFieldNumber" end
			end
			if field.Min~=nil and field.Max~=nil and field.Min>field.Max then return false,"InvalidFieldRange" end
			if field.Type=="choice" and type(field.Options)~="table" and type(field.Options)~="string" then return false,"InvalidOptions" end
		end
	end
	if command.Inputs~=nil then
		if type(command.Inputs)~="table" or #command.Inputs>2 then return false,"InvalidInputs" end
		local count=0
		for index,input in command.Inputs do
			count+=1
			if count>2 or type(index)~="number" or index%1~=0 or index<1 or index>#command.Inputs or (input~="Reason" and input~="Minutes") then return false,"InvalidInput" end
		end
	end
	if command.Strings~=nil then
		if type(command.Strings)~="table" then return false,"InvalidStrings" end
		for code,dictionary in command.Strings do
			if type(code)~="string" or type(dictionary)~="table" then return false,"InvalidStrings" end
			for key,value in dictionary do if type(key)~="string" or type(value)~="string" then return false,"InvalidStrings" end end
		end
	end
	return true
end
local function adapterValid(adapter,ctx)
	if type(adapter)~="table" or type(adapter.Permission)~="string" or not ctx.Ranks.Defaults[adapter.Permission]
		or type(adapter.Probe)~="function" or type(adapter.Actions)~="table" then return false end
	local count=0
	for _,action in adapter.Actions do
		count+=1 if count>40 then return false end
		if type(action)~="table" or type(action.Permission)~="string" or not ctx.Ranks.Defaults[action.Permission] then return false end
	end
	return true
end
function Extensions.Init(ctx,service)
	if initialized then return Extensions end
	initialized=true
	ctx.Extensions=Extensions
	local root=Extensions.Root()
	if not root then return Extensions end
	local ids={}
	local function makeApi(namespace)
		local api={ApiVersion=Extensions.ApiVersion,Id=namespace}
		function api.RegisterCommand(command) return ctx.RegisterExtensionCommand(command,namespace) end
		function api.RegisterOptions(name,provider)
			if not identifier(name,20) or type(provider)~="function" then return nil,"InvalidOptionsProvider" end
			local key=namespace.."."..name
			service.RegisterOptions(key,provider)
			return key
		end
		-- Profile rows follow the existing contract: every administrator can view them.
		function api.AddProfileProvider(provider)
			if type(provider)~="function" then return false,"InvalidProfileProvider" end
			service.AddProfileProvider(provider) return true
		end
		function api.RegisterAdapter(name,adapter)
			if not identifier(name,20) or not adapterValid(adapter,ctx) or not ctx.AutoBridge then return false,"InvalidAdapter" end
			local id=namespace.."_"..name
			if #id>40 then return false,"AdapterIdTooLong" end
			return ctx.AutoBridge.RegisterAdapter(id,adapter)
		end
		function api.HasPermission(player,permission) return ctx.Ranks.CanUse(player,permission) end
		function api.CanTarget(player,target) return ctx.Ranks.CanTarget(player,target) end
		function api.Authorize(player,command,target) return ctx.Authorize(player,command,target) end
		function api.Notify(player,message,success) ctx.Notify(player,message,success) end
		function api.Log(actor,action,target,detail,level) ctx.Log(actor,namespace.."."..tostring(action),target,detail,"Extensions",level or "info") end
		return table.freeze(api)
	end
	for _,kind in {"Adapters","Server"} do
		local folder=root:FindFirstChild(kind)
		if folder and folder:IsA("Folder") then
			local count=0
			for _,source in children(folder) do
				if source:IsA("ModuleScript") then
					count+=1
					if count>100 then Extensions.Record(kind,"limit","Error","SourceLimit") break end
					local ok,manifest=pcall(require,source)
					local id=ok and type(manifest)=="table" and manifest.Id or source.Name
					local code
					if not ok then code="RequireFailed" warn("[APM] Extension "..kind.." "..source.Name.." : "..tostring(manifest))
					elseif type(manifest)~="table" or manifest.ApiVersion~=Extensions.ApiVersion or not identifier(id) then code="InvalidManifest"
					elseif ids[id] then code="DuplicateId"
					elseif kind=="Adapters" then
						if not adapterValid(manifest.Adapter,ctx) or not ctx.AutoBridge then code="InvalidAdapter"
						else
							local registered,problem=ctx.AutoBridge.RegisterAdapter(id,manifest.Adapter)
							if not registered then code="AdapterRejected" warn("[APM] Adaptateur "..id.." : "..tostring(problem)) end
						end
					elseif type(manifest.Init)~="function" then code="InvalidInit"
					else
						local ready,problem=pcall(manifest.Init,makeApi(id))
						if not ready or problem==false then code="InitFailed" warn("[APM] Intégration "..id.." : "..tostring(problem)) end
					end
					if not code then ids[id]=true end
					Extensions.Record(kind,id,code and "Error" or "Loaded",code)
				end
			end
		end
	end
	return Extensions
end
return Extensions
