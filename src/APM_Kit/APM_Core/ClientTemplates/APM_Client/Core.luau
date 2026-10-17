--[[
	Core : état partagé du panneau côté client (remotes, langue, grades, modules, accès, sélection) + cycle de vie du panneau.

	Le panneau n'existe QUE pour un compte qui a un grade : pour un joueur normal, Build() s'arrête avant de créer quoi que ce soit.
	Toutes les actions passent par le serveur, qui les revalide. Le panneau se reconstruit tout seul quand :
	  - le grade du joueur change (donné / retiré depuis un autre panneau, sur n'importe quel serveur) ;
	  - sa langue change (langue du compte Roblox, ou bouton de langue de l'en-tête).
	Les pages enregistrent leurs connexions globales avec Core.On(signal, fn) : elles sont coupées à chaque reconstruction.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("APM_Shared")
local Config = require(Shared:WaitForChild("Config"))
local Lang = require(Shared:WaitForChild("Lang"))
local Root = script.Parent
local Remotes = require(Root:WaitForChild("Remotes"))
local UI = require(Root:WaitForChild("UI"))

local player = Players.LocalPlayer

local Core = {}
Core.Player = player
Core.Config = Config
Core.Lang = Lang
Core.UI = UI
Core.T = Config.Theme
Core.R = Remotes.All()
Core.Enabled = false
Core.Language = Lang.Local()
Core.MyRank = nil
Core.Permissions = {}
Core.ActualOwner = false
local stopped = false
local lifetime = {}
function Core.HasPermission(name) return not stopped and Core.Permissions[name] == true end
function Core.SavePreferences(patch)
 if stopped then return end
 task.spawn(function() pcall(function() Core.R.SetPreferences:InvokeServer(patch) end) end)
end
Core.RankList, Core.RankById = {}, {}
Core.ServerModules = {} -- modules serveur (infos envoyées par GetModules)
Core.ClientModules = {} -- [nom] = outil client (dossier Tools)
Core.ModuleAccess = {} -- [module] = { [grade] = bool }
Core.Options = {} -- listes de choix du serveur
Core.ToolState = {} -- [outil client] = actif ?
Core.Pages, Core.TabButtons = {}, {}
Core.Selected = nil -- Player choisi dans l'onglet Joueurs

local session -- connexions, événements et interfaces de la construction en cours

----------------------------------------------------------------------------------------------------------
-- Langue

function Core.L(key, ...)
	return Lang.Get(Core.Language, key, ...)
end

-- N'importe quel texte affichable (clé, message du serveur, texte multilingue, date, durée)
function Core.Text(value)
	return Lang.Text(Core.Language, value)
end

function Core.FormatDate(timestamp)
	return Core.Text({ d = tonumber(timestamp) or 0 })
end

function Core.FormatDuration(seconds)
	return Core.Text({ s = tonumber(seconds) or 0 })
end

-- Remplacé par Shell (notification en bas de la fenêtre)
function Core.Toast() end

----------------------------------------------------------------------------------------------------------
-- Connexions de la construction en cours

function Core.On(signal, callback)
	if stopped or not session or not session.Alive then return nil end
	local connection = signal:Connect(callback)
	if session then
		table.insert(session.Connections, connection)
	end
	return connection
end

-- Pour les boucles : local mine = Core.Session ; while Core.Alive(mine) do ... end
function Core.Alive(mine)
	return mine ~= nil and mine == session and mine.Alive == true
end

-- Interface hors de la fenêtre principale (détruite à la reconstruction)
function Core.TrackGui(gui)
	if stopped or not session or not session.Alive then gui:Destroy() return gui end
	if session then
		table.insert(session.Guis, gui)
	end
	return gui
end

local function newEvent()
	local event = Instance.new("BindableEvent")
	table.insert(session.Events, event)
	return event
end

----------------------------------------------------------------------------------------------------------
-- Grades

function Core.RankLevel(rankId)
	local rank = rankId and Core.RankById[rankId]
	return rank and rank.Level or 0
end

function Core.RankName(rankId)
	if not rankId then
		return Core.L("Common.NoRank")
	end
	local key = "Rank." .. rankId
	if Lang.Has(key) then
		return Core.L(key)
	end
	local rank = Core.RankById[rankId]
	return rank and rank.Name or rankId
end

function Core.RankColor(rankId)
	local rank = rankId and Core.RankById[rankId]
	return rank and rank.Color or Core.T.sub
end

function Core.HasRankAtLeast(rankId)
	local mine = Core.RankLevel(Core.MyRank)
	return mine > 0 and mine >= Core.RankLevel(rankId)
end

function Core.IsSuper()
	return Core.MyRank ~= nil and Core.MyRank == Core.SuperRank
end

----------------------------------------------------------------------------------------------------------
-- Modules et accès

function Core.CanUse(name)
	if type(Core.Permissions[name]) == "boolean" then return Core.Permissions[name] end
	if not Core.MyRank then
		return false
	end
	local entry = Core.ModuleAccess[name]
	if type(entry) ~= "table" then
		return false
	end
	return entry[Core.MyRank] == true
end

function Core.RefreshAccess(silent)
	local ok, data = pcall(function()
		return Core.R.GetModuleAccess:InvokeServer()
	end)
	if ok and type(data) == "table" then
		Core.ModuleAccess = data
	end
	for name, active in Core.ToolState do
		if active and not Core.CanUse(name) then
			local tool = Core.ClientModules[name]
			if tool then pcall(tool.Set, false) end
			Core.ToolState[name] = false
		end
	end
	if not silent and Core.AccessChanged then
		Core.AccessChanged:Fire()
	end
end

function Core.RefreshOptions()
	local ok, data = pcall(function()
		return Core.R.GetOptions:InvokeServer()
	end)
	if ok and type(data) == "table" then
		Core.Options = data
	end
end

-- Tous les modules (serveur + outils client), triés par Order puis par libellé
function Core.AllModules()
	local list = {}
	for _, module in Core.ServerModules do
		table.insert(list, module)
	end
	for _, tool in Core.ClientModules do
		table.insert(list, tool)
	end
	table.sort(list, function(a, b)
		if (a.Order or 100) == (b.Order or 100) then
			return Core.Text(a.Label) < Core.Text(b.Label)
		end
		return (a.Order or 100) < (b.Order or 100)
	end)
	return list
end

function Core.FindModule(name)
	for _, module in Core.ServerModules do
		if module.Name == name then
			return module
		end
	end
	return Core.ClientModules[name]
end

-- Libellé d'une action du journal (module connu, sinon clé "Action.<nom>")
function Core.ActionLabel(name)
	local module = Core.FindModule(name)
	if module then
		return Core.Text(module.Label)
	end
	return Core.Text("Action." .. tostring(name))
end

-- Demande au serveur d'exécuter un module ; il répond par une notification (toast)
function Core.Action(moduleName, target, value)
	Core.R.Action:FireServer(moduleName, target, value)
end

-- Joueur choisi dans l'onglet Joueurs (cible des modules « sur un joueur » des autres onglets)
function Core.SetSelected(target)
	Core.Selected = target
	if Core.SelectionChanged then
		Core.SelectionChanged:Fire(target)
	end
end

----------------------------------------------------------------------------------------------------------
-- Outils client (dossier Tools), chargés une seule fois

local toolsLoaded, toolsRegistered = false, false
local function loadTools()
	if toolsLoaded then
		return
	end
	toolsLoaded = true
	local folder = Root:FindFirstChild("Tools")
	if not folder then
		return
	end
	for _, source in folder:GetChildren() do
		if source:IsA("ModuleScript") then
			local ok, tool = pcall(require, source)
			if ok and type(tool) == "table" and type(tool.Set) == "function" then
				tool.Name = type(tool.Name) == "string" and tool.Name or source.Name
				if type(tool.Strings) == "table" then
					Lang.AddAll(tool.Strings)
				end
				local prefix = "Tool." .. tool.Name .. "."
				if tool.Label == nil then
					tool.Label = Lang.Has(prefix .. "Label") and prefix .. "Label" or tool.Name
				end
				if tool.Description == nil and Lang.Has(prefix .. "Desc") then
					tool.Description = prefix .. "Desc"
				end
				tool.Category = "Moderation"
				tool.Mode = "toggle"
				tool.Order = tonumber(tool.Order) or 50
				tool.ClientSide = true
				if type(tool.Init) == "function" then
					local okInit, err = pcall(tool.Init, Core)
					if not okInit then
						warn("[APM] Init de l'outil " .. tool.Name .. " : " .. tostring(err))
					end
				end
				Core.ClientModules[tool.Name] = tool
				local originalSet = tool.Set
				-- arguments supplémentaires transmis tels quels à l'outil (ex. Spectator : joueur à observer)
				tool.Set = function(on, ...)
					on = on == true
					if on and (stopped or not Core.CanUse(tool.Name)) then return false end
					local ok, result = pcall(originalSet, on, ...)
					local applied = on and ok and result ~= false
					if not ok or (on and result == false) then pcall(originalSet, false) end
					Core.ToolState[tool.Name] = applied and true or nil
					if not stopped then Core.R.SetClientTool:FireServer(tool.Name, applied) end
					if not ok then error(result, 0) end
					return result
				end
			else
				warn("[APM] Outil client invalide (fonction Set manquante ?) : " .. source.Name .. " " .. tostring(ok and "" or tool))
			end
		end
	end
end

----------------------------------------------------------------------------------------------------------
-- Cycle de vie

local function teardown()
	local old = session
	session = nil
	Core.Session = nil
	Core.Assistant = nil
	Core.Enabled = false
	if not old then
		return
	end
	old.Alive = false
	for name, active in Core.ToolState do
		local tool = Core.ClientModules[name]
		if active and tool then
			if type(tool.Detach) == "function" then
				-- l'interface disparait : on ne coupe que ce que le panneau avait lancé (un effet ordonné par le serveur continue)
				local okDetach, byPanel = pcall(tool.Detach)
				if okDetach and byPanel == true and not stopped then
					pcall(function() Core.R.SetClientTool:FireServer(name, false) end)
				end
			else
				pcall(tool.Set, false)
			end
		end
	end
	table.clear(Core.ToolState)
	for _, connection in old.Connections do
		connection:Disconnect()
	end
	for _, gui in old.Guis do
		gui:Destroy()
	end
	if Core.Gui then
		Core.Gui:Destroy()
		Core.Gui = nil
	end
	for _, event in old.Events do
		event:Destroy()
	end
	Core.Pages, Core.TabButtons = {}, {}
	Core.Selected = nil
end

local function checkAdmin()
	local ok, answer = pcall(function()
		return Core.R.CheckAdmin:InvokeServer()
	end)
	if ok and type(answer) == "table" then
		return answer
	end
	return nil
end

local function buildNow()
	teardown()
	local answer = checkAdmin()
	if stopped then return end
	if not answer or not answer.admin then
		Core.MyRank = nil
		return
	end
	session = { Connections = {}, Events = {}, Guis = {}, Alive = true }
	Core.Session = session
	Core.Language = Lang.Local()
	Core.MyRank = answer.rank
	Core.Permissions = answer.permissions or {}
	Core.ActualOwner = answer.actualOwner == true
	Core.Simulation = answer.simulation
	Core.RankList = type(answer.ranks) == "table" and answer.ranks or {}
	Core.RankById = {}
	for _, rank in Core.RankList do
		Core.RankById[rank.Id] = rank
	end
	Core.SuperRank, Core.ManagerRank, Core.AnnounceRank = answer.super, answer.manager, answer.announcer
	Core.MemoryMode = answer.memory == true
	Core.SelectionChanged = newEvent()
	Core.AccessChanged = newEvent()

	local ok, list = pcall(function()
		return Core.R.GetModules:InvokeServer()
	end)
	Core.ServerModules = ok and type(list) == "table" and list or {}
	for _, module in Core.ServerModules do
		if type(module.Strings) == "table" then
			Lang.AddAll(module.Strings)
		end
	end
	loadTools()
	if not toolsRegistered then
		toolsRegistered = true
		local names = {}
		for name in Core.ClientModules do
			table.insert(names, name)
		end
		pcall(function()
			Core.R.RegisterClientModules:InvokeServer(names)
		end)
	end
	-- un effet déjà actif sur cet appareil (ordonné par le serveur avant la reconstruction du panneau) : les interrupteurs l'affichent
	for name, tool in Core.ClientModules do
		if type(tool.State) == "function" then
			local okState, running = pcall(tool.State)
			if okState and running == true then Core.ToolState[name] = true end
		end
	end
	Core.RefreshAccess(true)
	Core.RefreshOptions()
	if stopped then teardown() return end
	UI.Bind(Core)
	require(Root:WaitForChild("Shell")).Build(Core)
	Core.Enabled = true
end

local building = false
function Core.Build()
	if stopped then return false end
	if building then
		return Core.Enabled
	end
	building = true
	local ok, err = pcall(buildNow)
	building = false
	if stopped then teardown() return false end
	if not ok then
		warn("[APM] Construction du panneau impossible : " .. tostring(err))
		teardown()
	end
	return Core.Enabled
end

-- Reconstruit le panneau (langue ou grade changé) en gardant la fenêtre ouverte et l'onglet choisi
function Core.Rebuild()
	local wasOpen = Core.Gui ~= nil and Core.Gui.Enabled
	local page = Core.CurrentPage
	Core.Build()
	if Core.Enabled and wasOpen then
		Core.SetOpen(true)
		local tab = page and Core.TabButtons[page]
		if tab and tab.Visible then
			Core.SelectPage(page)
		end
	end
end

local started = false
function Core.Stop()
	if stopped then return end
	stopped = true
	teardown()
	for _, connection in lifetime do connection:Disconnect() end
	table.clear(lifetime)
	Core.Permissions = {}
	Core.MyRank = nil
end
function Core.Start()
	if started then
		return
	end
    local gui=player:FindFirstChildOfClass("PlayerGui")
    if not gui then return end
    local owner=gui:FindFirstChild("APM_ClientOwner")
    if owner and owner:IsA("ObjectValue")and owner.Value and owner.Value~=Root and owner.Value:IsDescendantOf(gui)then return end
    if not owner then owner=Instance.new("ObjectValue");owner.Name="APM_ClientOwner";owner.Parent=gui end
    if not owner:IsA("ObjectValue")then return end
    owner.Value=Root
    started = true
	table.insert(lifetime, Core.R.SessionRevoked.OnClientEvent:Connect(Core.Stop))
	table.insert(lifetime, Root.AncestryChanged:Connect(function()
		local gui = player:FindFirstChildOfClass("PlayerGui")
		if not gui or not Root:IsDescendantOf(gui) then Core.Stop() end
	end))
	local ok, prefs = pcall(function() return Core.R.GetPreferences:InvokeServer() end)
	if stopped then return end
	if ok and type(prefs) == "table" then
		if not Config.ForceLanguage and prefs.Language and prefs.Language ~= "auto" then
			Lang.Override = prefs.Language
		else
			Lang.Override = nil
		end
		Core.PreferredPage = prefs.Page == "AutoBridge" and "Home" or prefs.Page
	end
	Core.OpenPreferences = require(Root:WaitForChild("Launcher")).Defaults(Config, ok and prefs or nil)
	-- préférences personnelles complètes (Sentinel y lit son activation, sa position, sa taille et son animation)
	Core.PersonalPreferences = ok and type(prefs) == "table" and prefs or {}
	Core.Build()
	if stopped then return end

	-- droits changés (ici ou sur un autre serveur) : reconstruction si le grade a changé, sinon simple mise à jour de la matrice
	local queued = false
	table.insert(lifetime, Core.R.RankChanged.OnClientEvent:Connect(function()
		if stopped then return end
		if queued then
			return
		end
		queued = true
		task.delay(0.3 + math.random() * 0.7, function()
			queued = false
			if stopped then return end
			local answer = checkAdmin()
			if not answer then
				return
			end
			local rank = answer.admin and answer.rank or nil
			if rank ~= Core.MyRank or (rank ~= nil) ~= Core.Enabled then
				if Core.Enabled and not rank and Core.Gui and Core.Gui.Enabled then
					Core.Toast(Core.L("Shell.AccessRevoked"), false)
					task.wait(1.5)
				end
				Core.Rebuild()
			elseif Core.Enabled then
				Core.Rebuild()
			end
		end)
	end))

	-- langue du compte Roblox changée en cours de partie
	table.insert(lifetime, player:GetPropertyChangedSignal("LocaleId"):Connect(function()
		if Core.Enabled and not Lang.Override and Lang.Local() ~= Core.Language then
			Core.Rebuild()
		end
	end))
end

return Core
