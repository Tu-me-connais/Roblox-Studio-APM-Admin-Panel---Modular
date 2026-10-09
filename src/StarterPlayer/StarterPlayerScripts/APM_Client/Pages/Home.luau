-- Central dashboard; optional sections use the same private, permission-filtered transport.
local Page={Id="Home",Order=0,Label={fr="Accueil",en="Home",es="Inicio",pt="Início",de="Start"}}
function Page.Visible(Core) return Core.HasPermission("APM.AccessPanel") end
function Page.Build(Core,page)
 local UI,T,R=Core.UI,Core.T,Core.R
 local mine=Core.Session
 local function text(fr,en) return Core.Text({fr=fr,en=en}) end
 local function alive() return Core.Alive(mine) and page.Parent~=nil end
 local function diagnosticsAllowed() return Core.ActualOwner or Core.HasPermission("APM.Simulate") end
 local scroll=UI.scroll({Name="HomeScroll",Size=UDim2.fromScale(1,1)},page) UI.list(scroll,10)
 local heading=UI.card(scroll,1) heading.Name="DashboardHeader"
 UI.sectionHeader(text("TABLEAU DE BORD","DASHBOARD"),T.accent,heading,1)
 local status=UI.label({Name="DashboardStatus",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextWrapped=true,TextSize=12,TextColor3=T.sub,LayoutOrder=2,Text=Core.L("Common.Loading")},heading)
 local refreshButton=UI.button({Name="RefreshDashboard",Size=UDim2.new(1,0,0,32),Text=Core.L("Common.Refresh"),LayoutOrder=3},heading)
 local grid=UI.new("Frame",{Name="SummaryCards",Size=UDim2.new(1,-6,0,224),BackgroundTransparency=1,LayoutOrder=2},scroll)
 local layout=UI.new("UIGridLayout",{CellPadding=UDim2.fromOffset(8,8),SortOrder=Enum.SortOrder.LayoutOrder},grid)
 local metrics={}
 local function metric(name,title,color,order)
  local card=UI.card(grid,order) card.Name=name card.AutomaticSize=Enum.AutomaticSize.None
  UI.sectionHeader(title,color,card,1)
  local value=UI.label({Name="Value",Size=UDim2.new(1,0,0,30),Font=T.fontBold,TextSize=25,TextColor3=color,Text="—",LayoutOrder=2},card)
  local detail=UI.label({Name="Detail",Size=UDim2.new(1,0,0,28),TextSize=11,TextWrapped=true,TextColor3=T.sub,Text="",LayoutOrder=3},card)
  metrics[name]={Card=card,Value=value,Detail=detail} return metrics[name]
 end
 local serverMetric=metric("ServerSummary",text("SERVEUR","SERVER"),T.accent,1)
 local systemsMetric=metric("SystemsSummary",text("SYSTÈMES DÉTECTÉS","DETECTED SYSTEMS"),T.accent,2)
 local operationalMetric=metric("OperationsSummary",text("OPÉRATIONNELS","OPERATIONAL"),T.good,3)
 local sentinelMetric=metric("SentinelSummary","SENTINEL GUARD",T.warn,4) sentinelMetric.Value.TextSize=20
 local function reflow()
  if not alive() then return end
  local count=0 for _,entry in metrics do if entry.Card.Visible then count+=1 end end
  local cols=grid.AbsoluteSize.X>=480 and 2 or 1
  layout.CellSize=UDim2.new(1/cols,-(cols==2 and 4 or 0),0,112)
  grid.Size=UDim2.new(1,-6,0,math.ceil(count/cols)*120-8)
 end
 Core.On(grid:GetPropertyChangedSignal("AbsoluteSize"),reflow)
 local serverCard=UI.card(scroll,3) serverCard.Name="ServerDetails"
 UI.sectionHeader(text("INFORMATIONS DU SERVEUR","SERVER INFORMATION"),T.accent,serverCard,1)
 local serverInfo=UI.label({Name="ServerInfo",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextSize=12,TextWrapped=true,TextColor3=T.sub,Text=Core.L("Common.Loading"),LayoutOrder=2},serverCard)
 local bridgeCard=UI.card(scroll,4) bridgeCard.Name="AutoBridgeOverview"
 UI.sectionHeader("AUTOBRIDGE",T.accent,bridgeCard,1)
 local bridgeInfo=UI.label({Name="IntegrationStatus",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextSize=12,TextWrapped=true,TextColor3=T.sub,LayoutOrder=2},bridgeCard)
 local systems=UI.label({Name="DetectedSystems",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextSize=12,TextWrapped=true,LayoutOrder=3},bridgeCard)
 local bridgeErrors=UI.label({Name="IntegrationErrors",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextSize=12,TextWrapped=true,TextColor3=T.bad,LayoutOrder=4,Visible=false},bridgeCard)
 local detailsButton=UI.button({Name="OpenAutoBridgeDetails",Size=UDim2.new(1,0,0,34),BackgroundColor3=T.accent,Text=text("INTÉGRATIONS ET RÉGLAGES","INTEGRATIONS AND SETTINGS"),LayoutOrder=5},bridgeCard)
 local rescan=UI.button({Name="RefreshAutoBridge",Size=UDim2.new(1,0,0,32),Text=text("Actualiser la découverte","Refresh discovery"),LayoutOrder=6},bridgeCard)
 local detailFrame=UI.new("Frame",{Name="AutoBridgeDetails",Size=UDim2.new(1,0,0,540),BackgroundTransparency=1,LayoutOrder=7,Visible=false},bridgeCard)
 local sentinelCard=UI.card(scroll,5) sentinelCard.Name="SentinelOverview"
 UI.sectionHeader("SENTINEL GUARD",T.warn,sentinelCard,1)
 local sentinelInfo=UI.label({Name="SentinelStatus",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextSize=12,TextWrapped=true,TextColor3=T.sub,LayoutOrder=2},sentinelCard)
 local alerts=UI.label({Name="RecentAlerts",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextSize=12,TextWrapped=true,LayoutOrder=3},sentinelCard)
 local sentinelOpen=UI.button({Name="OpenSentinel",Size=UDim2.new(1,0,0,32),Text=text("Consulter Sentinel Guard","Open Sentinel Guard"),LayoutOrder=4},sentinelCard)
 local diagnosticCard=UI.card(scroll,6) diagnosticCard.Name="HomeDiagnostics"
 UI.sectionHeader(text("DIAGNOSTICS","DIAGNOSTICS"),T.accent,diagnosticCard,1)
 local diagnosticInfo=UI.label({Name="DiagnosticsStatus",Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,TextSize=12,TextWrapped=true,TextColor3=T.sub,LayoutOrder=2},diagnosticCard)
 local diagnosticOpen=UI.button({Name="OpenDiagnostics",Size=UDim2.new(1,0,0,32),Text=text("Diagnostics détaillés","Detailed diagnostics"),LayoutOrder=3},diagnosticCard)
 local STATUS={Detected={"Détecté","Detected"},Compatible={"Compatible","Compatible"},Operational={"Opérationnel","Operational"},Unsupported={"Non pris en charge","Unsupported"},Error={"Erreur d'intégration","Integration error"}}
 local function permissions()
  if not alive() then return end
  local bridge=Core.HasPermission("AutoBridge.View") local sentinel=Core.HasPermission("Sentinel.View")
  systemsMetric.Card.Visible=bridge operationalMetric.Card.Visible=bridge bridgeCard.Visible=bridge
  sentinelMetric.Card.Visible=sentinel sentinelCard.Visible=sentinel diagnosticCard.Visible=diagnosticsAllowed()
  if not bridge then
   detailFrame.Visible=false systems.Text="" bridgeInfo.Text="" bridgeErrors.Text="" bridgeErrors.Visible=false
   systemsMetric.Value.Text="—" operationalMetric.Value.Text="—"
  end
  if not sentinel then alerts.Text="" sentinelInfo.Text="" sentinelMetric.Value.Text="—" end
  if not diagnosticsAllowed() then diagnosticInfo.Text="" end
  reflow()
 end
 local function renderBridge(data)
  if not alive() or not Core.HasPermission("AutoBridge.View") then return end
  if type(data)~="table" or data.Allowed~=true or data.Unavailable then
   systemsMetric.Value.Text="—" systemsMetric.Detail.Text=text("Données indisponibles","Data unavailable")
   operationalMetric.Value.Text="—" operationalMetric.Detail.Text=""
   bridgeInfo.Text=text("AutoBridge indisponible. Réessayez l'actualisation.","AutoBridge unavailable. Try refreshing.") systems.Text="" bridgeErrors.Visible=false return
  end
  if data.Disabled or not data.Enabled then
   systemsMetric.Value.Text="—" systemsMetric.Detail.Text=text("AutoBridge désactivé","AutoBridge disabled")
   operationalMetric.Value.Text="—" operationalMetric.Detail.Text=""
   bridgeInfo.Text=text("Découverte désactivée ; aucun comptage courant disponible.","Discovery disabled; current counts unavailable.") systems.Text="" bridgeErrors.Visible=false return
  end
  local detected,compatible,operational,errors=0,0,0,0 local rows,errorRows={},{}
  for _,entry in data.Systems or {} do
   local state=entry.Status
   if (entry.Count or 0)>0 or state=="Detected" or state=="Compatible" or state=="Operational" then detected+=1 end
   if state=="Compatible" or state=="Operational" then compatible+=1 end
   if state=="Operational" then operational+=1 end
   if state=="Error" then errors+=1 table.insert(errorRows,tostring(entry.Name or entry.Id).." : "..tostring(entry.Detail or "")) end
   local labels=STATUS[state] or STATUS.Detected
   if #rows<6 then table.insert(rows,tostring(entry.Name or entry.Id).." · "..text(labels[1],labels[2])) end
  end
  systemsMetric.Value.Text=tostring(detected)
  systemsMetric.Detail.Text=tostring(compatible)..text(" compatible(s)"," compatible")..(data.Truncated and text(" · partiel"," · partial") or "")
  operationalMetric.Value.Text=tostring(operational)
  operationalMetric.Detail.Text=tostring(errors)..text(" erreur(s) d'intégration"," integration error(s)")
  bridgeInfo.Text=tostring(#(data.Systems or {}))..text(" systèmes examinés. "," systems checked. ")
   ..text("Les états concernent les fonctionnalités déclarées par les adaptateurs.","States describe the features declared by adapters.")
  if data.ScanAge~=nil then bridgeInfo.Text..=text(" Scan datant de "," Scan age: ")..tostring(data.ScanAge).." s." end
  if data.Truncated then bridgeInfo.Text..=text(" Analyse partielle : limite de parcours atteinte."," Partial scan: traversal limit reached.") end
  systems.Text=table.concat(rows,"\n")
  if #(data.Systems or {})>6 then systems.Text..=text("\nVoir les intégrations pour la liste complète.","\nOpen integrations for the full list.") end
  bridgeErrors.Text=table.concat(errorRows,"\n") bridgeErrors.Visible=#errorRows>0
 end
 local function render(data)
  if not alive() then return end permissions()
  if type(data)~="table" or type(data.Server)~="table" then status.Text=text("Données indisponibles. Réessayez l'actualisation.","Data unavailable. Try refreshing.") return end
  status.Text=text("Dernier relevé serveur : ","Last server snapshot: ")..os.date("%H:%M:%S",data.GeneratedAt)
  local s=data.Server
  serverMetric.Value.Text=tostring(s.Players).." / "..tostring(s.MaxPlayers)
  serverMetric.Detail.Text=text("joueurs connectés","players connected")
  local minutes=math.floor(s.UptimeSeconds/60)
  serverInfo.Text=(s.Studio and "Studio" or text("Serveur publié","Published server")).." · Place "..tostring(s.PlaceId)
   ..text("\nDurée de session : ","\nSession uptime: ")..string.format("%dh %02dm %02ds",math.floor(minutes/60),minutes%60,s.UptimeSeconds%60)
   .." · "..text(s.Locked and "Entrées verrouillées" or "Entrées ouvertes",s.Locked and "Joining locked" or "Joining open")
   .."\n"..text(s.MemoryMode and "Mode mémoire : changements non enregistrés." or "Stockage persistant configuré.",s.MemoryMode and "Memory mode: changes are not saved." or "Persistent storage configured.")
  if Core.HasPermission("AutoBridge.View") then renderBridge(data.AutoBridge) end
  if Core.HasPermission("Sentinel.View") then
   local guard=data.Sentinel
   if type(guard)~="table" or guard.Unavailable then
    sentinelMetric.Value.Text="—" sentinelMetric.Detail.Text=text("Données indisponibles","Data unavailable") sentinelInfo.Text=text("Sentinel indisponible.","Sentinel unavailable.") alerts.Text=""
   else
    local enabled=guard.Enabled and not guard.Disabled
    local mode=guard.Mode=="Balanced" and text("Équilibré","Balanced") or guard.Mode=="Strict" and text("Strict","Strict") or text("Observation","Observation")
    sentinelMetric.Value.Text=enabled and mode or text("Désactivé","Disabled")
    sentinelMetric.Detail.Text=tostring(guard.TotalAlerts)..text(" alerte(s), tests inclus"," alert(s), tests included")
    sentinelInfo.Text=text("Historique conservé : ","Retained history: ")..tostring(guard.HistoryCount)
     ..text(" · joueurs suivis : "," · tracked players: ")..tostring(guard.TrackedPlayers)
     ..text("\nUn signal heuristique demande une vérification des mécaniques du jeu.","\nA heuristic signal needs review against game mechanics.")
    local lines={} for _,alert in guard.RecentAlerts or {} do
     table.insert(lines,os.date("%H:%M:%S",alert.Time).." · "..(alert.Test and text("TEST · ","TEST · ") or "")..tostring(alert.Name).." · "..tostring(alert.Kind).."\n"..tostring(alert.Detail))
    end
    alerts.Text=#lines>0 and table.concat(lines,"\n\n") or text("Aucune alerte dans l'historique courant.","No alerts in the current history.")
   end
  end
  if diagnosticsAllowed() then
   local d=data.Diagnostics
   diagnosticInfo.Text=type(d)=="table" and text(d.sessionActive and "Session privée active" or "Session privée inactive",d.sessionActive and "Private session active" or "Private session inactive")
    .." · "..text(d.globalAdminRemotes and "Transport administratif global détecté" or "Transport privé",d.globalAdminRemotes and "Global administrative transport detected" or "Private transport")
    .."\n"..text(d.simulation and d.simulation.active and "Simulation en cours" or "Contexte réel",d.simulation and d.simulation.active and "Simulation in progress" or "Real context")
    ..(type(d.core)=="table" and ("\nAPM "..tostring(d.core.Version).." · "..tostring(d.core.Channel).." · API "..tostring(d.core.ApiVersion)) or "")
    ..(type(d.extensions)=="table" and ("\n"..text("Extensions : consulter les diagnostics détaillés.","Extensions: see detailed diagnostics.")) or "")
    or text("Diagnostics indisponibles.","Diagnostics unavailable.")
  end
 end
 local loading=false local lastRefresh=-math.huge local panel
 local function refresh()
  if not alive() or loading or not Core.HasPermission("APM.AccessPanel") or os.clock()-lastRefresh<2 then return end
  loading=true lastRefresh=os.clock() refreshButton.Active=false refreshButton.Text=Core.L("Common.Loading")
  task.spawn(function()
   local ok,data=pcall(function()return R.GetHomeSnapshot:InvokeServer()end)
   loading=false if not alive() then return end
   refreshButton.Active=true refreshButton.Text=Core.L("Common.Refresh")
   render(ok and data or nil)
  end)
 end
 local bridgeLoading=false
 rescan.Activated:Connect(function()
  if bridgeLoading or not alive() or not Core.HasPermission("AutoBridge.View") then return end
  bridgeLoading=true rescan.Active=false rescan.Text=Core.L("Common.Loading")
  task.spawn(function()
   local ok,success,data=pcall(function()return R.RefreshAutoBridge:InvokeServer()end)
   bridgeLoading=false if not alive() then return end rescan.Active=true rescan.Text=text("Actualiser la découverte","Refresh discovery")
   if not Core.HasPermission("AutoBridge.View") then permissions() return end
   if ok and success then renderBridge(data) if panel and detailFrame.Visible then panel.Refresh(false) end
   else Core.Toast(ok and data or Core.L("Common.ServerError"),false) end
  end)
 end)
 detailsButton.Activated:Connect(function()
  if not alive() or not Core.HasPermission("AutoBridge.View") then return end
  detailFrame.Visible=not detailFrame.Visible
  detailsButton.Text=detailFrame.Visible and text("FERMER LES INTÉGRATIONS","CLOSE INTEGRATIONS") or text("INTÉGRATIONS ET RÉGLAGES","INTEGRATIONS AND SETTINGS")
  if detailFrame.Visible then
   if not panel then panel=require(script.Parent.Parent.Components.AutoBridgePanel).Build(Core,detailFrame,renderBridge) end
   panel.Refresh(false)
  end
 end)
 local function openTab(name,allowed)
  if not alive() or not allowed then return end
  local tab=Core.TabButtons[name] if tab and tab.Visible then Core.SelectPage(name) end
 end
 sentinelOpen.Activated:Connect(function()openTab("Sentinel",Core.HasPermission("Sentinel.View"))end)
 diagnosticOpen.Activated:Connect(function()openTab("Diagnostics",diagnosticsAllowed())end)
 refreshButton.Activated:Connect(refresh)
 Core.On(Core.AccessChanged.Event,function()permissions() if page.Visible then refresh()end end)
 page:GetPropertyChangedSignal("Visible"):Connect(function()if page.Visible then refresh()end end)
 permissions() refresh()
 task.spawn(function()
  while alive() do task.wait(15) if alive() and page.Visible and Core.Gui and Core.Gui.Enabled then refresh()end end
 end)
end
return Page
