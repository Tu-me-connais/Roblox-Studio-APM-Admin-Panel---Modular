local HttpService = game:GetService("HttpService")
local Page = { Id = "Security", Order = 8, Label = { fr = "Tests et sécurité", en = "Tests and security" } }
function Page.Visible(Core)
 return Core.ActualOwner == true or Core.HasPermission("APM.Simulate") or Core.HasPermission("APM.ManagePermissions") or (type(Core.Simulation)=="table" and Core.Simulation.active==true)
end
function Page.Build(Core, page)
 local UI,T,R = Core.UI,Core.T,Core.R
 local mine=Core.Session
 local function text(fr,en) return Core.Text({fr=fr,en=en}) end
 local function alive() return Core.Alive(mine) and page.Parent~=nil end
 local scroll=UI.scroll({Name="SecurityScroll",Size=UDim2.fromScale(1,1)},page)
 UI.list(scroll,10)
 local function hint(card,order,value)
  return UI.label({Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,Text=value,TextWrapped=true,TextSize=12,TextColor3=T.sub,LayoutOrder=order},card)
 end
 local function row(card,order,height)
  return UI.new("Frame",{Size=UDim2.new(1,0,0,height or 34),BackgroundTransparency=1,LayoutOrder=order},card)
 end
 local function invoke(remote,...)
  local args=table.pack(...)
  local ok,success,message=pcall(function() return remote:InvokeServer(table.unpack(args,1,args.n)) end)
  return ok and success==true, ok and message or text("Le serveur est indisponible.","Server unavailable.")
 end
 if Core.HasPermission("APM.ManagePermissions") then
  local card=UI.card(scroll,0)
  UI.sectionHeader(text("CONFIGURER LES ACCÈS","CONFIGURE ACCESS"),T.accent,card,1)
  hint(card,2,text("Toutes les permissions, commandes et outils se règlent au même endroit, dans Paramètres.","All permissions, commands and tools are configured together in Settings."))
  local open=UI.button({Name="OpenPermissionEditor",Size=UDim2.new(1,0,0,34),Text=text("Ouvrir les permissions","Open permissions"),BackgroundColor3=T.accent,LayoutOrder=3},card)
  open.Activated:Connect(function()
   if Core.OpenPermissionEditor then Core.OpenPermissionEditor("")
   elseif Core.TabButtons.Settings and Core.TabButtons.Settings.Visible then Core.SelectPage("Settings") end
  end)
 end
 if (Core.HasPermission("APM.Simulate") or (type(Core.Simulation)=="table" and Core.Simulation.active==true)) and (type(Core.Simulation)~="table" or Core.Simulation.enabled~=false) then
  local state=type(Core.Simulation)=="table" and Core.Simulation or {}
  local ok,data=pcall(function() return R.GetSimulation:InvokeServer() end)
  if ok and type(data)=="table" then state=data end
  local realRank=state.realRank or Core.RealRank or Core.MyRank
  local allowed=state.realPermissions or Core.Permissions or {}
  local card=UI.card(scroll,1)
  card.Name="PermissionSimulationCard"
  UI.sectionHeader(text("TESTER LES PERMISSIONS","TEST PERMISSIONS"),T.accent,card,1)
  local summary=hint(card,2,"")
  local observedAt=os.clock()
  local function summaryText()
   if state.active then
    local remaining=math.max(0,(state.remaining or 0)-math.floor(os.clock()-observedAt))
    summary.Text=text("Test actif : ","Active test: ")..Core.RankName(state.rank)..text(" · retour automatique dans "," · automatic restore in ")..remaining.." s."
   else summary.Text=text("Contexte réel : ","Real context: ")..Core.RankName(realRank)..text(" · aucun test actif."," · no active test.") end
  end
  summaryText()
  hint(card,3,text("Le test dure au maximum cinq minutes. Si le panneau disparaît, utilise « Revenir au grade réel » à l’écran ou tape /apm-restore dans le chat.","Tests last up to five minutes. If the panel disappears, use the on-screen restore button or type /apm-restore in chat."))
  local presets=row(card,4)
  local ordinary=UI.button({Name="PresetOrdinary",Size=UDim2.new(.5,-4,1,0),Text=text("Joueur ordinaire","Ordinary player"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=12},presets)
  local own=UI.button({Name="PresetRealRank",Size=UDim2.new(.5,-4,1,0),Position=UDim2.new(.5,4,0,0),Text=text("Mon grade réel","My real rank"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=12},presets)
  local choices={{"None",text("Joueur ordinaire","Ordinary player")}}
  for _,rank in Core.RankList do if rank.Level<=Core.RankLevel(realRank) then table.insert(choices,{rank.Id,Core.RankName(rank.Id)}) end end
  local rankRow=row(card,5)
  UI.label({Size=UDim2.new(.4,0,1,0),Text=text("Grade à tester","Rank to test"),TextSize=13},rankRow)
  local picker=UI.picker(rankRow,choices,state.active and (state.rank or "None") or "None",UDim2.new(.6,0,0,32),UDim2.fromScale(.4,0))
  local custom=state.custom==true
  local selected={}
  for name,value in allowed do
   if value==true and (not custom or state.permissions and state.permissions[name]==true) then selected[name]=true end
  end
  local customRow=row(card,6)
  customRow.Name="SimulationModeRow"
  UI.label({Size=UDim2.new(1,-60,1,0),Text=text("Choisir les permissions du test","Choose test permissions"),TextSize=12},customRow)
  local body=UI.new("Frame",{Name="SimulationPermissions",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,BackgroundTransparency=1,LayoutOrder=7,Visible=custom},card)
  UI.list(body,8)
  local search=UI.input({Name="SimulationSearch",Size=UDim2.new(1,0,0,30),PlaceholderText=text("Rechercher une permission ou une commande","Find a permission or command"),TextSize=12,LayoutOrder=1},body)
  local selectionStatus=hint(body,2,"")
  local bulk=row(body,3,30)
  local all=UI.button({Name="SelectAllSimulationPermissions",Size=UDim2.new(.5,-4,1,0),Text=text("Tout sélectionner","Select all"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=12},bulk)
  local none=UI.button({Name="ClearSimulationPermissions",Size=UDim2.new(.5,-4,1,0),Position=UDim2.new(.5,4,0,0),Text=text("Tout décocher","Clear all"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=12},bulk)
  local list=UI.scroll({Name="SimulationPermissionList",Size=UDim2.new(1,0,0,210),LayoutOrder=4},body)
  UI.list(list,5)
  local advanced=UI.button({Name="ToggleSimulationJSON",Size=UDim2.new(1,0,0,28),Text=text("Avancé : éditer le JSON","Advanced: edit JSON"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=11,LayoutOrder=5},body)
  local editor=UI.input({Name="SimulationJSON",Size=UDim2.new(1,0,0,130),MultiLine=true,TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,TextSize=12,Font=Enum.Font.Code,LayoutOrder=6,Visible=false,ClearTextOnFocus=false},body)
  local rows={}
  local labels={}
  local catalogue=Core.FeatureCatalogue
  if not catalogue and Core.HasPermission("APM.ManagePermissions") then
   local good,value=pcall(function() return R.GetFeatures:InvokeServer() end)
   if good and type(value)=="table" then catalogue=value end
  end
  for _,category in catalogue and catalogue.Categories or {} do
   for _,item in category.Items or {} do labels[item.Name]=Core.Text(item.Label or item.Name) end
  end
  for _,module in Core.AllModules() do if not labels[module.Name] then labels[module.Name]=Core.Text(module.Label or module.Name) end end
  local names={}
  for name,value in allowed do if type(name)=="string" and type(value)=="boolean" then table.insert(names,name) end end
  table.sort(names,function(a,b) return string.lower(labels[a] or a)<string.lower(labels[b] or b) end)
  local function sync()
   local count=0
   for name in selected do if allowed[name]==true then count+=1 end end
   selectionStatus.Text=count..text(" permission(s) sélectionnée(s). Les droits absents de ton grade réel restent verrouillés."," permission(s) selected. Permissions absent from your real rank stay locked.")
   for name,entry in rows do if entry.Switch then entry.Switch.Set(selected[name]==true) end end
   if not editor.Visible then local good,json=pcall(HttpService.JSONEncode,HttpService,selected);if good then editor.Text=json end end
  end
  for index,name in names do
   local item=UI.new("Frame",{Name="Permission_"..name:gsub("[^%w_]","_"),Size=UDim2.new(1,-6,0,48),BackgroundColor3=T.panel2,LayoutOrder=index,Corner=6},list)
   UI.label({Size=UDim2.new(1,-72,0,24),Position=UDim2.fromOffset(8,2),Text=labels[name] or name,TextSize=12,TextTruncate=Enum.TextTruncate.AtEnd},item)
   UI.label({Size=UDim2.new(1,-72,0,16),Position=UDim2.fromOffset(8,26),Text=name,TextSize=10,TextColor3=T.sub,TextTruncate=Enum.TextTruncate.AtEnd},item)
   local entry={Frame=item}
   rows[name]=entry
   if allowed[name]==true then
    entry.Switch=UI.Switch(item,selected[name]==true,function(value) selected[name]=value and true or nil;sync() end,UDim2.new(1,-54,0,12))
   else UI.label({Size=UDim2.fromOffset(60,48),Position=UDim2.new(1,-64,0,0),Text=text("Verrouillé","Locked"),TextSize=10,TextColor3=T.sub,TextXAlignment=Enum.TextXAlignment.Center},item) end
  end
  local function readJSON()
   if #editor.Text>20000 then return nil,text("Liste trop longue.","List too long.") end
   local good,map=pcall(HttpService.JSONDecode,HttpService,editor.Text)
   if not good or type(map)~="table" then return nil,text("JSON invalide : utilise un objet permission: true/false.","Invalid JSON: use a permission: true/false object.") end
   local clean,count={},0
   for name,value in map do
    count+=1
    if count>200 or type(name)~="string" or type(value)~="boolean" or allowed[name]==nil then return nil,text("Permission inconnue ou format invalide.","Unknown permission or invalid format.") end
    if value and allowed[name]~=true then return nil,text("Ce droit n'est pas disponible dans ton grade réel.","This permission is unavailable in your real rank.") end
    if value then clean[name]=true end
   end
   return clean
  end
  local toggle=UI.Switch(customRow,custom,function(value)
   custom=value;body.Visible=value
   if value and picker.Get()=="None" then picker.Set(realRank) end
  end,UDim2.new(1,-46,0,4))
  toggle.Frame.Name="ToggleCustomSimulationPermissions"
  ordinary.Activated:Connect(function() custom=false;toggle.Set(false);body.Visible=false;picker.Set("None") end)
  own.Activated:Connect(function() custom=false;toggle.Set(false);body.Visible=false;picker.Set(realRank) end)
  all.Activated:Connect(function() for name,value in allowed do selected[name]=value==true and true or nil end;editor.Visible=false;sync() end)
  none.Activated:Connect(function() table.clear(selected);editor.Visible=false;sync() end)
  advanced.Activated:Connect(function()
   if editor.Visible then
    local map,errorText=readJSON()
    if not map then Core.Toast(errorText,false);return end
    selected=map;editor.Visible=false;sync()
   else sync();editor.Visible=true end
  end)
  search:GetPropertyChangedSignal("Text"):Connect(function()
   local q=string.lower(search.Text)
   for name,entry in rows do entry.Frame.Visible=q=="" or string.find(string.lower((labels[name] or name).." "..name),q,1,true)~=nil end
  end)
  sync()
  local buttons=row(card,8)
  local start=UI.button({Name="StartPermissionTest",Size=UDim2.new(.5,-4,1,0),Text=text("Démarrer le test","Start test"),BackgroundColor3=T.accent,TextSize=12},buttons)
  local restore=UI.button({Name="RestoreRealPermissions",Size=UDim2.new(.5,-4,1,0),Position=UDim2.new(.5,4,0,0),Text=text("Revenir au grade réel","Restore real rank"),BackgroundColor3=T.panel,Stroke=T.stroke,TextSize=12},buttons)
  local canStart=Core.HasPermission("APM.Simulate")
  start.Visible=canStart
  if not canStart then restore.Size=UDim2.new(1,0,1,0);restore.Position=UDim2.new() end
  local busy=false
  start.Activated:Connect(function()
   if busy or not Core.HasPermission("APM.Simulate") then return end
   local permissions
   if custom then
    if picker.Get()=="None" then Core.Toast(text("Choisis un grade pour personnaliser ses permissions.","Choose a rank before customizing permissions."),false);return end
    if editor.Visible then local map,errorText=readJSON();if not map then Core.Toast(errorText,false);return end;selected=map end
    permissions=table.clone(selected)
   end
   busy=true
   task.spawn(function()
    local success,message=invoke(R.SetSimulation,picker.Get(),permissions)
    busy=false
    if alive() then Core.Toast(message or "",success) end
   end)
  end)
  restore.Activated:Connect(function()
   if busy then return end
   busy=true
   task.spawn(function() local success,message=invoke(R.RestoreSimulation);busy=false;if alive() then Core.Toast(message or "",success) end end)
  end)
  task.spawn(function() while alive() do task.wait(1);if alive() then summaryText() end end end)
 end
	if Core.ActualOwner then
		local card = UI.card(scroll, 3)
		UI.sectionHeader(text("AUTORITÉ DU PROPRIÉTAIRE", "EXPERIENCE OWNER AUTHORITY"), T.warn, card, 1)
		hint(card, 2, text("Cette attribution prioritaire peut révoquer un accès fixe ou de groupe. Hériter rétablit les sources originales. En simulation, toute modification de cette attribution est refusée.",
			"This priority override can revoke fixed or group access. Inherit restores original sources. Overrides cannot be changed while simulating."))
		local account = UI.input({ Size = UDim2.new(1, 0, 0, 32), PlaceholderText = "UserId", TextSize = 13, LayoutOrder = 3 }, card)
		local choices = { { "Inherit", text("Hériter des sources", "Inherit sources") }, { "None", text("Aucun accès", "No access") } }
		for _, rank in Core.RankList do table.insert(choices, { rank.Id, Core.RankName(rank.Id) }) end
		local choiceRow = row(card, 4)
		local ownerPicker = UI.picker(choiceRow, choices, "Inherit", UDim2.new(1, 0, 0, 32), UDim2.fromOffset(0, 0))
		local save = UI.button({ Size = UDim2.new(1, 0, 0, 34), Text = text("Appliquer l'attribution", "Apply override"), BackgroundColor3 = T.warn, TextColor3 = T.bg,
			TextSize = 13, LayoutOrder = 5 }, card)
		UI.Confirmable(save, true, function()
			local userId = tonumber(account.Text)
			if not userId or userId % 1 ~= 0 then
				Core.Toast(text("UserId invalide.", "Invalid UserId."), false)
				return
			end
			task.spawn(function()
				local success, message = invoke(R.SetOwnerAccessOverride, userId, ownerPicker.Get())
				Core.Toast(message or "", success)
			end)
		end)
	end
end
return Page
