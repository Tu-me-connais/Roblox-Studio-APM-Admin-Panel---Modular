local Page={Id="Diagnostics",Order=7.8,Label={fr="Diagnostics",en="Diagnostics"}}
function Page.Visible(Core) return Core.HasPermission("APM.Simulate") or Core.ActualOwner end
function Page.Build(Core,page)
 local UI,T=Core.UI,Core.T local mine=Core.Session
 local scroll=UI.scroll({Size=UDim2.fromScale(1,1)},page) UI.list(scroll,10)
 local card=UI.card(scroll,1)
 UI.sectionHeader("Distribution privée et session",T.accent,card,1)
 local info=UI.label({Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true,TextSize=13,LayoutOrder=2,Text="Chargement…"},card)
 local refresh=UI.button({Size=UDim2.new(1,0,0,36),LayoutOrder=3,Text="Inspecter ce client",BackgroundColor3=T.accent},card)
 UI.label({Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true,TextSize=12,TextColor3=T.sub,LayoutOrder=4,
  Text="Cette vue décrit les objets présents maintenant. Une simulation après connexion ne prouve pas l'absence de réplication initiale. Tester une première connexion avec StudioRank=nil ou un second client sans grade."},card)
 local busy=false
 local function inspect()
  if busy then return end busy=true refresh.Text="Inspection…"
  task.spawn(function()
   local found,seen={},{} local count=0
   local names={APM_Client=true,APM_Private=true,APM_Recovery=true,APM_Remotes=true,APM_Gui=true,APM_Launcher=true}
   local roots={Core.Player:FindFirstChildOfClass("PlayerGui"),Core.Player:FindFirstChild("PlayerScripts"),game:GetService("ReplicatedStorage"),workspace}
   for _,root in roots do if root then
    local queue={root} local index=1
    while index<=#queue and count<5000 do
     local node=queue[index] index+=1 count+=1
     if names[node.Name] or node:GetAttribute("APMPrivate") then
      if not seen[node] then seen[node]=true table.insert(found,node:GetFullName()) end
     end
     for _,child in node:GetChildren() do if #queue<5000 then table.insert(queue,child) end end
     if count%200==0 then task.wait() end
    end
   end end
   local ok,data=pcall(function() return Core.R.GetDiagnostics:InvokeServer() end)
   if not Core.Alive(mine) then return end
   info.Text=("Client actuel : %d objet(s) APM privé(s), %d objets inspectés%s\n%s\n\nServeur : session=%s, autorisation=%s, remotes admin globaux=%s")
    :format(#found,count,count>=5000 and " (limite atteinte)" or "",table.concat(found,"\n"),
    tostring(ok and type(data)=="table" and data.sessionActive),tostring(ok and type(data)=="table" and data.authorized),tostring(ok and type(data)=="table" and data.globalAdminRemotes))
   if ok and type(data)=="table" then
    if type(data.core)=="table" then
     info.Text..="\n\nCore : "..tostring(data.core.Version).." · "..tostring(data.core.Channel).." · API "..tostring(data.core.ApiVersion).." · données "..tostring(data.core.DataSchemaVersion)
    end
    if type(data.extensions)=="table" then
     info.Text..="\nExtensions chargées : "..tostring(data.extensions.Loaded).." · erreurs : "..tostring(data.extensions.Errors)
     for _,entry in data.extensions.Entries or {} do
      info.Text..="\n"..tostring(entry.Kind).." / "..tostring(entry.Id).." : "..tostring(entry.Status)..(entry.Code and (" · "..tostring(entry.Code)) or "")
     end
    end
   end
   refresh.Text="Inspecter ce client" busy=false
  end)
 end
 refresh.Activated:Connect(inspect) inspect()
end
return Page
