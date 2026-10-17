--[[
	Shell : la fenêtre de l'APM (ScreenGui), son en-tête déplaçable, la barre d'onglets, les notifications (toasts) et les raccourcis.
	  Config.OpenKey (F2)       ouvre / ferme le panneau (téléphone / tablette : bouton « APM » à l'écran)
	  Config.RecenterKey (Z)    recentre la fenêtre
	Les onglets viennent du dossier Pages officiel, des pages ExtensionPages autorisées + un onglet automatique pour chaque catégorie de module
	qu'aucune page ne gère (voir CategoryPage). Le bouton de langue de l'en-tête change la langue pour la session.
]]
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")

local Shell = {}

local Root = script.Parent

-- Les modules officiels restent privés au Core. Les pages personnalisées sont uniquement
-- celles validées par le serveur et clonées dans ExtensionPages/<ExtensionId>.
local function validId(value)
	return type(value) == "string" and #value > 0 and #value <= 64 and value:match("^[%w_%.%-]+$") ~= nil
end

local function pageOrder(def)
	local order = def.Order
	return type(order) == "number" and order == order and math.abs(order) < math.huge and order or 100
end

local function sortedChildren(folder)
	local children = folder:GetChildren()
	table.sort(children, function(a, b)
		return a.Name < b.Name
	end)
	return children
end

local function pageDefinitions(Core)
	local defs, handled, ids, reserved = {}, {}, {}, {}
	local discoverySession = Core.Session
 Core.ExtensionDiagnostics={}
 local function diagnostic(source,code,field,received,expected,fr,en)
  if #Core.ExtensionDiagnostics>=30 then return end
  table.insert(Core.ExtensionDiagnostics,{Kind="ClientPages",Id=source.Name,Status="Error",Code=code,
   SourcePath=source:GetFullName(),Field=field,Received=string.sub(tostring(received),1,200),Expected=expected,
   Message={fr=fr,en=en},Hint={fr="Corrige la page dans APM_Extensions > ClientPages, puis relance le test.",en="Fix the page in APM_Extensions > ClientPages, then restart the test."}})
 end
	-- Réserver aussi les pages cachées et les identifiants retirés : une extension
	-- ne doit pas réintroduire un second onglet AutoBridge ou remplacer Accueil.
	for _, id in { "Home", "Players", "Game", "Moderation", "Bans", "Logs", "Settings", "Diagnostics", "Security", "Sentinel", "SentinelHelper", "Profile", "AutoBridge" } do
		reserved[id] = true
	end
	local categoryOwners = {}
	for _, module in Core.ServerModules do
		local category = module.Category
		if type(category) == "string" then
			local owner = type(module.ExtensionId) == "string" and module.ExtensionId or false
			if categoryOwners[category] == nil then
				categoryOwners[category] = owner
			elseif categoryOwners[category] ~= owner then
				categoryOwners[category] = false
			end
			if not owner then reserved[category] = true end
		end
	end
	local folder = Root:FindFirstChild("Pages")
	for _, source in folder and sortedChildren(folder) or {} do
		if not Core.Alive(discoverySession) then return defs end
		if source:IsA("ModuleScript") then
			reserved[source.Name] = true
			local ok, def = pcall(require, source)
			if ok and type(def) == "table" and type(def.Build) == "function" then
				def.Id = def.Id or source.Name
				reserved[def.Id] = true
				if not ids[def.Id] then
					ids[def.Id] = true
					table.insert(defs, def)
					for _, category in def.Handles or {} do
						handled[category] = true
						reserved[category] = true
					end
				else
					warn("[APM] Identifiant de page officiel dupliqué : " .. tostring(def.Id))
				end
			else
				warn("[APM] Page invalide : " .. source.Name .. " (" .. tostring(def) .. ")")
			end
		end
	end

	local extensions = Root:FindFirstChild("ExtensionPages")
	local function discover(folder, extensionId)
		for _, source in sortedChildren(folder) do
			if not Core.Alive(discoverySession) then return end
			if source:IsA("Folder") then
				discover(source, extensionId)
			elseif source:IsA("ModuleScript") then
				local permission = source:GetAttribute("Permission")
				-- Cet attribut vient du manifest serveur : aucun require avant son contrôle.
				if type(permission) ~= "string" or permission == "" or source:GetAttribute("ApiVersion") ~= 1 then
					warn("[APM] Métadonnées de page extension invalides : " .. source:GetFullName())
     diagnostic(source,"InvalidPageManifest","ApiVersion / Permission",tostring(source:GetAttribute("ApiVersion")).." / "..tostring(permission),{fr="ApiVersion=1; Permission non vide",en="ApiVersion=1; non-empty Permission"},"Attributs de page incomplets : ApiVersion=1 et Permission sont requis.","Page attributes incomplete: ApiVersion=1 and Permission are required.")
				elseif Core.HasPermission(permission) then
					local ok, definition = pcall(require, source)
					if not Core.Alive(discoverySession) then return end
					if not ok or type(definition) ~= "table" or type(definition.Build) ~= "function"
							or definition.ApiVersion ~= 1 or definition.Permission ~= permission or not validId(definition.Id) then
						warn("[APM] Page extension invalide : " .. source:GetFullName())
     local field,received,expected="return",type(definition),"table"
     if not ok then field,received,expected="require",definition,{fr="module sans erreur",en="module without errors"}
     elseif type(definition)=="table" then
      if type(definition.Build)~="function" then field,received,expected="Build",type(definition.Build),"function(Core, page)"
      elseif definition.ApiVersion~=1 then field,received,expected="ApiVersion",definition.ApiVersion,"1"
      elseif definition.Permission~=permission then field,received,expected="Permission",definition.Permission,permission
      else field,received,expected="Id",definition.Id,{fr="identifiant unique : lettres, chiffres, _, . ou -",en="unique identifier: letters, digits, _, . or -"} end
     end
     diagnostic(source,"InvalidPage",field,received,expected,"Le contrat de la page ne correspond pas au modèle attendu.","The page contract does not match the expected template.")
					elseif string.lower(definition.Id) == "autobridge" or reserved[definition.Id] or ids[definition.Id]
							or (categoryOwners[definition.Id] ~= nil and categoryOwners[definition.Id] ~= extensionId) then
						warn("[APM] Identifiant de page extension réservé ou dupliqué : " .. definition.Id)
     diagnostic(source,"ReservedPageId","Id",definition.Id,{fr="identifiant unique de l'extension",en="unique extension identifier"},"Cet identifiant est déjà utilisé ou réservé par l'APM.","This identifier is already used or reserved by APM.")
					elseif definition.Handles ~= nil and type(definition.Handles) ~= "table" then
						warn("[APM] Handles de page extension invalide : " .. definition.Id)
     diagnostic(source,"InvalidPageHandles","Handles",type(definition.Handles),"table","Handles doit être une liste de catégories.","Handles must be a list of categories.")
					elseif Core.HasPermission(permission) then
						-- Copier les métadonnées : ne pas modifier la valeur mise en cache par require.
						local def = table.clone(definition)
						def.Order = math.max(1, pageOrder(def)) -- Home remains the initial central dashboard.
						def.ExtensionId = extensionId
      def.SourcePath=source:GetFullName()
						def.Handles = {}
						for _, category in definition.Handles or {} do
							if type(category) == "string" and not reserved[category] and categoryOwners[category] == extensionId then
								table.insert(def.Handles, category)
								handled[category] = true
							else
								warn("[APM] Une extension ne peut gérer cette catégorie : " .. tostring(category))
        diagnostic(source,"ReservedCategory","Handles",category,{fr="catégorie appartenant à cette extension",en="category belonging to this extension"},"La catégorie est réservée ou appartient à une autre extension.","The category is reserved or belongs to another extension.")
							end
						end
						ids[def.Id] = true
						table.insert(defs, def)
					end
				end
			end
		end
	end
	if extensions and extensions:IsA("Folder") then
		for _, folder in sortedChildren(extensions) do
			if folder:IsA("Folder") and validId(folder.Name) then discover(folder, folder.Name) end
		end
	end

	local CategoryPage = require(Root:WaitForChild("CategoryPage"))
	local order = 3
	for _, module in Core.ServerModules do
		local category = module.Category
		if type(category) == "string" and string.lower(category) ~= "autobridge" and not handled[category] and not ids[category] and module.Mode ~= "toggle" and module.Mode ~= "slider" then
			handled[category], ids[category] = true, true
			order += 0.01
			table.insert(defs, {
				Id = category,
				Order = order,
				Label = "Tab." .. category,
				Build = function(core, page)
					CategoryPage.Build(core, page, category)
				end,
			})
		end
	end
	table.sort(defs, function(a, b)
		local left, right = pageOrder(a), pageOrder(b)
		return left < right or (left == right and a.Id < b.Id)
	end)
	return defs
end

function Shell.Build(Core)
	local buildSession = Core.Session
	local UI, T, L, Lang, Config = Core.UI, Core.T, Core.L, Core.Lang, Core.Config
	local player = Core.Player
	local playerGui = player:WaitForChild("PlayerGui")

	local old = playerGui:FindFirstChild("APM_Gui")
	if old then
		old:Destroy()
	end
	local gui = UI.new("ScreenGui", { Name = "APM_Gui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 80, Enabled = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, playerGui)
	Core.Gui = gui
	gui:SetAttribute("APMPrivateSession", Root.Parent:GetAttribute("SessionId"))

	local main = UI.new("Frame", { Name = "Main", Size = UDim2.fromOffset(820, 480), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = T.bg, Corner = 14, Stroke = T.stroke, StrokeThickness = 1.5 }, gui)
	local mainCorner = main:FindFirstChildOfClass("UICorner")
	mainCorner.BottomLeftRadius = UDim.new(0, 0)
	Core.main = main
	local scale = UI.new("UIScale", {}, main)
	local function rescale()
		local camera = workspace.CurrentCamera
		local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(viewport.X / 860, viewport.Y / 520), 0.25, 1.15)
	end
	rescale()
	if workspace.CurrentCamera then
		Core.On(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"), rescale)
	end

	-- En-tête --------------------------------------------------------------------------------------------------
	local header = UI.new("Frame", { Name = "Header", Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = T.panel, Corner = 14 }, main)
	UI.new("Frame", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -16), BackgroundColor3 = T.panel }, header)
	-- logo à la place du texte « APM » (Config.LogoImage) ; un titre personnalisé garde le texte
	local logo = Config.LogoImage
	local useLogo = type(logo) == "string" and logo ~= "" and (Config.Title == nil or Config.Title == "APM")
	local titleX = 18
	if useLogo then
		UI.new("ImageLabel", { Name = "Logo", Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(12, 6), BackgroundTransparency = 1, Image = logo,
			ScaleType = Enum.ScaleType.Fit, ZIndex = 2, Corner = 20 }, header)
		titleX = 58
	end
	UI.label({ Size = UDim2.new(1, -(420 + titleX), 1, 0), Position = UDim2.fromOffset(titleX, 0), Font = T.fontBold, TextSize = 19, TextTruncate = Enum.TextTruncate.AtEnd,
		Text = useLogo and L("Shell.Subtitle") or (tostring(Config.Title or "APM") .. "  -  " .. L("Shell.Subtitle")), ZIndex = 2 }, header)
	UI.label({ Size = UDim2.fromOffset(150, 22), Position = UDim2.new(1, -184, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 0,
		BackgroundColor3 = Core.RankColor(Core.MyRank), Font = T.fontBold, TextSize = 12, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd, Text = L("Shell.Rank", Core.RankName(Core.MyRank)), ZIndex = 3, Corner = 11 }, header)
	local clock = UI.label({ Name = "LocalClock", Size = UDim2.fromOffset(88, 24), Position = UDim2.new(1, -88, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundTransparency = 0, BackgroundColor3 = T.panel2, Font = T.fontBold, TextSize = 13, TextColor3 = T.text,
		TextXAlignment = Enum.TextXAlignment.Center, Text = "", ZIndex = 3, Corner = 8 }, header)
	local function updateClock()
		local now = DateTime.now():ToLocalTime()
		clock.Text = string.format("%02d:%02d:%02d", now.Hour, now.Minute, now.Second)
	end
	updateClock()
	task.spawn(function()
		while Core.Alive(buildSession) and clock.Parent ~= nil do
			task.wait(1)
			if Core.Alive(buildSession) and clock.Parent ~= nil then updateClock() end
		end
	end)
	UI.label({ Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -64, 0.5, 0), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 0,
		BackgroundColor3 = T.panel2, Font = T.fontBold, TextSize = 13, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Center,
		Text = Config.RecenterKey and Config.RecenterKey.Name or "", Visible = Config.RecenterKey ~= nil, ZIndex = 3, Corner = 6 }, header)
	local closeButton = UI.button({ Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -44, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(58, 44, 48), Text = "X", TextSize = 16, ZIndex = 3 }, header)

	-- bouton de langue : Auto (langue du compte Roblox) ou une langue choisie pour la session
	if Config.LanguageButton ~= false and not Config.ForceLanguage then
		local options = { { "auto", L("Language.Auto") } }
		for _, code in Lang.Codes() do
			local dict = Lang.Dictionaries[code]
			table.insert(options, { code, (dict and dict["Language.Name"] or code) .. "  (" .. string.upper(code) .. ")" })
		end
		local picker = UI.picker(header, options, Lang.Override or "auto", UDim2.fromOffset(62, 26), UDim2.new(1, -404, 0.5, -13), function()
			return string.upper(Core.Language) .. " v"
		end)
		picker.Frame.ZIndex = 3
		picker.Changed = function(id)
			Lang.Override = id ~= "auto" and id or nil
			Core.SavePreferences({ Language = id })
			task.defer(Core.Rebuild)
		end
	end

	-- déplacement par l'en-tête + recentrage
	do
		local dragging, dragInput, dragStart, startPosition
		local function viewport()
			local camera = workspace.CurrentCamera
			return camera and camera.ViewportSize or Vector2.new(1280, 720)
		end
		header.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragging, dragStart, startPosition = true, input.Position, main.Position
				local changed
				changed = input:GetPropertyChangedSignal("UserInputState"):Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
						changed:Disconnect()
					end
				end)
			end
		end)
		header.InputChanged:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
				dragInput = input
			end
		end)
		Core.On(UserInputService.InputChanged, function(input)
			if dragging and input == dragInput then
				local vp, delta = viewport(), input.Position - dragStart
				main.Position = UDim2.new(startPosition.X.Scale + delta.X / vp.X, 0, startPosition.Y.Scale + delta.Y / vp.Y, 0)
			end
		end)
		Core.On(UserInputService.InputBegan, function(input, processed)
			if not processed and not UserInputService:GetFocusedTextBox() and gui.Enabled and Config.RecenterKey and input.KeyCode == Config.RecenterKey and input.KeyCode.Name ~= Core.OpenPreferences.OpenKey and not (Core.Launcher and (Core.Launcher.Capturing or os.clock() < (Core.Launcher.SuppressUntil or 0))) then
				main.Position = UDim2.fromScale(0.5, 0.5)
			end
		end)
	end

	-- Barre latérale et contenu ------------------------------------------------------------------------------------
	local sidebar = UI.scroll({ Name = "Sidebar", Size = UDim2.new(0, 190, 1, -52), Position = UDim2.fromOffset(0, 52), BackgroundTransparency = 0,
		BackgroundColor3 = T.panel }, main)
	UI.list(sidebar, 5)
	UI.padding(sidebar, 12)
	local content = UI.new("Frame", { Name = "Content", Size = UDim2.new(1, -190, 1, -52), Position = UDim2.fromOffset(190, 52), BackgroundTransparency = 1 }, main)
	UI.padding(content, 14)
	Core.sidebar, Core.content = sidebar, content

	-- Notification (toast) -------------------------------------------------------------------------------------------
	local toast = UI.label({ Name = "Toast", Size = UDim2.new(1, -28, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1, BackgroundColor3 = T.panel2, TextTransparency = 1, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		ZIndex = 60, Corner = 8 }, main)
	UI.padding(toast, 8, 12, 12)
	local toastToken = 0
	function Core.Toast(text, success)
		toastToken += 1
		local token = toastToken
		toast.Text = Core.Text(text)
		toast.TextColor3 = success == false and T.bad or T.good
		toast.BackgroundTransparency, toast.TextTransparency = 0.05, 0
		task.delay(3.4, function()
			if token == toastToken and toast.Parent then
				TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
			end
		end)
	end
	Core.On(Core.R.Notify.OnClientEvent, function(text, success)
		Core.Toast(text, success)
	end)

	-- Pages ---------------------------------------------------------------------------------------------------------
	Core.Pages, Core.TabButtons = {}, {}
 local groups={
  [1]={fr="DÉVELOPPEMENT",en="DEVELOPMENT"},[2]={fr="SURVEILLANCE",en="MONITORING"},
  [3]={fr="ADMINISTRATION",en="ADMINISTRATION"},[4]={fr="EXTENSIONS",en="EXTENSIONS"},
 }
 local nav={
  Home={0,1},Settings={1,1},Security={1,2},Diagnostics={1,3},SentinelHelper={1,4},
  Stats={2,1},Sentinel={2,2},Logs={2,3},
  Players={3,1},Moderation={3,2},Bans={3,3},Game={3,4},Funny={3,5},
 }
 local groupHeaders={}
 local function updateGroups()
  for group,label in groupHeaders do
   local any=false
   for _,tab in Core.TabButtons do if tab.Visible and tab:GetAttribute("NavigationGroup")==group then any=true;break end end
   label.Visible=any
  end
 end
	function Core.SelectPage(name)
		Core.CurrentPage = name
		Core.PreferredPage = name
		Core.SavePreferences({ Page = name })
		for pageName, frame in Core.Pages do
			frame.Visible = pageName == name
		end
		for tabName, button in Core.TabButtons do
			local active = tabName == name
			button.BackgroundColor3 = active and T.accent or T.panel2
			button.TextColor3 = active and Color3.new(1, 1, 1) or T.sub
		end
	end
	function Core.MakeTab(name, label, order)
		local position=nav[name] or {4,math.floor(order or 100)}
  local button = UI.button({ Name = name, Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.panel2, TextSize = 13, TextColor3 = T.sub, TextWrapped = true,
   Text = Core.Text(label), LayoutOrder = position[1]*100+position[2], Corner = 8 }, sidebar)
  button:SetAttribute("NavigationGroup",position[1])
		local page = UI.new("Frame", { Name = name .. "Page", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
		page:SetAttribute("TabId", name)
		Core.Pages[name], Core.TabButtons[name] = page, button
		button.Activated:Connect(function()
			Core.SelectPage(name)
		end)
		return page
	end
	-- Cache / montre un onglet (si l'onglet affiché disparaît, on revient au premier visible)
	function Core.SetTabVisible(name, visible)
		local button = Core.TabButtons[name]
		if not button then
			return
		end
		button.Visible = visible
  updateGroups()
		if not visible and Core.CurrentPage == name then
			local best
			for tabName, other in Core.TabButtons do
				if other.Visible and (not best or other.LayoutOrder < Core.TabButtons[best].LayoutOrder) then
					best = tabName
				end
			end
			if best then
				Core.SelectPage(best)
			end
		end
	end

	Core.Launcher = require(Root:WaitForChild("Launcher")).Create(Core, gui)
	-- Sentinel (assistant flottant) : interface indépendante de cette fenêtre ; une erreur ici ne doit jamais empêcher le panneau de s'ouvrir
	local assistantOk, assistantProblem = pcall(function()
		require(Root:WaitForChild("Assistant")).Attach(Core)
	end)
	if not assistantOk then warn("[APM] Sentinel indisponible : " .. tostring(assistantProblem)) end
	local first
	for index, def in pageDefinitions(Core) do
		if not Core.Alive(buildSession) then return end
		local visible = not def.ExtensionId or Core.HasPermission(def.Permission)
		if visible and type(def.Visible) == "function" then
			local ok, result = pcall(def.Visible, Core)
			visible = ok and result == true
		end
		if not Core.Alive(buildSession) then return end
		if visible and (not def.ExtensionId or Core.HasPermission(def.Permission)) then
			local page
			if def.Tab ~= false then
				page = Core.MakeTab(def.Id, def.Label or ("Tab." .. def.Id), pageOrder(def))
				-- Navigation groups keep developer tasks near the top.
				first = first or def.Id
			end
			local ok, err = pcall(def.Build, Core, page)
			if not Core.Alive(buildSession) then return end
			if not ok then
				warn(("[APM] Page %s en erreur : %s"):format(tostring(def.Id), tostring(err)))
    if #Core.ExtensionDiagnostics<30 then table.insert(Core.ExtensionDiagnostics,{Kind="ClientPages",Id=tostring(def.Id),Status="Error",Code="PageBuildFailed",SourcePath=def.SourcePath or (Root:GetFullName()..".Pages."..tostring(def.Id)),Field="Build",Received=string.sub(tostring(err),1,300),Expected={fr="Build(Core,page) sans erreur",en="Build(Core,page) without errors"},Message={fr="La page n'a pas pu construire son interface.",en="The page could not build its interface."},Hint={fr="Vérifie Build(Core, page) et le modèle de page.",en="Check Build(Core, page) against the page template."}}) end
			end
		end
	end

 for group,label in groups do
  groupHeaders[group]=UI.label({Name="NavigationGroup"..group,Size=UDim2.new(1,0,0,20),Text=Core.Text(label),Font=T.fontBold,TextSize=10,TextColor3=T.sub,LayoutOrder=group*100},sidebar)
 end
 updateGroups()
	-- Ouverture / fermeture -------------------------------------------------------------------------------------------
	local memoryWarned = false
	function Core.SetOpen(open)
		gui.Enabled = open == true
		if not open and GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(gui) then
			GuiService.SelectedObject = nil
		end
		if not open and Core.ProfileOverlay then
			Core.ProfileOverlay.Visible = false
		end
		if open and Core.MemoryMode and not memoryWarned then
			memoryWarned = true
			Core.Toast(L("Shell.MemoryMode"), false)
		end
	end
	closeButton.Activated:Connect(function()
		Core.SetOpen(false)
	end)
	Core.On(UserInputService.InputBegan, function(input, processed)
		local launcher = Core.Launcher
		if launcher.Capturing or os.clock() < (launcher.SuppressUntil or 0) or UserInputService:GetFocusedTextBox() then return end
		if not processed and (input.KeyCode.Name == Core.OpenPreferences.OpenKey or input.KeyCode == Enum.KeyCode.ButtonY) then
			Core.SetOpen(not gui.Enabled)
			if gui.Enabled and input.KeyCode == Enum.KeyCode.ButtonY then
				GuiService.SelectedObject = Core.TabButtons[Core.CurrentPage] or Core.TabButtons[first]
			end
		end
	end)

	local preferred = Core.PreferredPage and Core.TabButtons[Core.PreferredPage]
	if preferred and preferred.Visible then
		Core.SelectPage(Core.PreferredPage)
	elseif first then
		Core.SelectPage(first)
	end
	print(("[APM] Panneau prêt (%s, %s)"):format(tostring(Core.MyRank), Core.Language))
end

return Shell
