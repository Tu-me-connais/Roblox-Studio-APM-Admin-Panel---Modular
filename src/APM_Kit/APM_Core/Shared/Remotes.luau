-- APM 2 : façade serveur compatible ; seuls les événements de notices sont publics.
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Remotes = {}
Remotes.Functions = {
	"CheckAdmin", "GetModules", "GetOptions", "GetLogs", "GetBanned", "GetModuleAccess", "SetModuleAccess", "SetRank", "GetRank",
	"GetStaff", "RegisterClientModules", "GlobalSearch", "GetRoster", "GetProfile", "BanUserId", "SetServerLock", "GetServerLock", "GetWarnings",
	"GetSimulation", "SetSimulation", "RestoreSimulation", "SetOwnerAccessOverride", "GetAutoBridge", "RefreshAutoBridge", "ConfigureAutoBridge",
	"AutoBridgeAction",
	"GetSentinel", "ConfigureSentinel", "TestSentinel", "GetDiagnostics", "GetPreferences", "SetPreferences", "GetHomeSnapshot",
	"GetFunny", "StartFunny", "StopFunny", "GetFeatures", "SetAccessBulk", "GetStats",
	"GetAnnounceState", "AnnounceDraft", "SetAnnounceStyle",
	"SentinelAction",
	-- Sentinel (assistant flottant) et Sentinel Helper : distincts de Sentinel Guard (GetSentinel / ConfigureSentinel / ...)
	"RunAssistant", "GetAssistant", "ConfigureAssistant",
	-- Actions distribuées (panneau classique, admins seulement) : le serveur reste l'autorité, voir Core/Dispatcher
	"DispatchAction",
}
Remotes.Events = { "Action", "Notify", "LogAdded", "Announce", "RankChanged", "SessionRevoked", "SetClientTool", "AnnounceState", "AssistantChanged" }
-- ActionDispatch (serveur -> client de la cible) et ActionReport (réponses du client) : publics car les cibles n'ont pas forcément de grade ;
-- le client n'y envoie que des réponses validées par le serveur, jamais une demande (Core/Dispatcher, Shared/ActionExecutor)
local publicNames = { Announcement = true, Warned = true, Muted = true, ActionDispatch = true, ActionReport = true }
local server = RunService:IsServer()
local publicFolder
if server then
	publicFolder = RS:FindFirstChild("APM_Public") or Instance.new("Folder")
	publicFolder.Name = "APM_Public"
	publicFolder.Parent = RS
	publicFolder:SetAttribute("APMRuntimeCopy", true)
	publicFolder:SetAttribute("APMComponentId", "APM_Transport.Public")
	for name in publicNames do
		if not publicFolder:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e:SetAttribute("APMComponentId", "APM_Transport.Public." .. name)
			e.Parent = publicFolder
		end
	end
else
	publicFolder = RS:WaitForChild("APM_Public")
end
local gateway, proxies, signals, claims = nil, {}, {}, {}
function Remotes.Configure(value)
	assert(server, "Serveur seulement")
	gateway = value
end
function Remotes.Claim(name)
	if claims[name] then return false end
	claims[name] = true
	return true
end
function Remotes.Get(name, className)
	if publicNames[name] then return publicFolder:WaitForChild(name) end
	assert(server, "Le transport administratif doit venir de la session privée")
	if proxies[name] then return proxies[name] end
	local proxy = {}
	if className == "RemoteEvent" then
		local signal = Instance.new("BindableEvent")
		signals[name] = signal
		proxy.OnServerEvent = signal.Event
		function proxy:FireClient(player, ...)
			if gateway then gateway.Send(player, name, ...) end
		end
		function proxy:FireAllClients(...)
			for _, player in Players:GetPlayers() do self:FireClient(player, ...) end
		end
	end
	proxies[name] = proxy
	return proxy
end
function Remotes.All()
	assert(server, "Transport client privé requis")
	local result = {}
	for _, name in Remotes.Functions do result[name] = Remotes.Get(name, "RemoteFunction") end
	for _, name in Remotes.Events do result[name] = Remotes.Get(name, "RemoteEvent") end
	for name in publicNames do result[name] = Remotes.Get(name, "RemoteEvent") end
	return result
end
function Remotes.Dispatch(name, player, ...)
	assert(server, "Serveur seulement")
	local proxy = proxies[name]
	if not proxy then return nil end
	if signals[name] then
		signals[name]:Fire(player, ...)
		return nil
	end
	if type(proxy.OnServerInvoke) == "function" then return proxy.OnServerInvoke(player, ...) end
	return nil
end
return Remotes
