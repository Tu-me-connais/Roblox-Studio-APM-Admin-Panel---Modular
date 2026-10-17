-- This module uses the currently installed Core. No Source write, asset download or runtime code update.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local Bootstrap = {}
local started, context, starting = false, nil, false
local root = script.Parent
local function unique(parent, name)
	local result
	for _, child in parent:GetChildren() do
		if child.Name == name then assert(not result, "[APM] Duplicate " .. name) result = child end
	end
	return result
end
function Bootstrap.Start(options)
	assert(game:GetService("RunService"):IsServer(), "Server only")
	assert(root.Parent == SS and root.Name == "APM_Core", "[APM] Core must be private in ServerStorage")
	if started then return context end
	assert(not starting,"[APM] Initialization already in progress")
	starting=true
	local installation=require(root.Server.Core.InstallationGuard).Create()
	installation.Register("Core",root)
	installation.Normalize(root)
	local release = require(root.Release)
	assert(require(root.Migrations).ValidateRelease(release), "[APM] Unknown data/API schema: review migration in Edit")
	assert(type(options) == "table" and options.ApiVersion == release.BootstrapApiVersion, "[APM] Bootstrap API incompatible")
	assert(release.ExtensionApiVersion == 1 and release.InstallationSchema == 3, "[APM] Unsupported Core installation")
	assert(release.Channel == "stable" or (release.Channel == "experimental" and options.AllowExperimental == true), "[APM] Experimental release requires explicit bootstrap opt-in")
	local extensions = unique(SS, "APM_Extensions")
	assert(extensions and extensions:IsA("Folder") and extensions:GetAttribute("APMExtensionsSchema") == release.ExtensionsSchema, "[APM] Extensions schema incompatible; no migration performed at runtime")
	installation.Register("Extensions",extensions)
	installation.Normalize(extensions)
	installation.Sweep(root,extensions)
	assert(unique(SS,"APM_Core")==root,"[APM] Core ambiguous")
assert(not SSS:FindFirstChild("APM_Server") and not SS:FindFirstChild("APM_ClientTemplates")
		and not game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("APM_Notices"), "[APM] Legacy installation present: migrate in Edit before starting")
	-- Fail on unknown public code instead of deleting developer content.
	assert(not unique(RS, "APM_Shared") and not RS:FindFirstChild("APM_Remotes") and not RS:FindFirstChild("APM_Public"), "[APM] Existing transport/shared installation; stop and resolve in Edit")
	local shared = root.Shared:Clone()
	shared.Name = "APM_Shared"
	shared:SetAttribute("APMRuntimeCopy", true)
	shared:SetAttribute("APMVersion", release.Version)
	local config = extensions:FindFirstChild("Config")
	local custom = config and config:FindFirstChild("SharedConfig")
	assert(custom and custom:IsA("ModuleScript"), "[APM] SharedConfig missing")
	local copy = custom:Clone() copy.Name = "CustomConfig" copy.Parent = shared
	-- Validate developer configuration before publishing its clone to clients.
	assert(type(require(copy)) == "table", "[APM] SharedConfig must return a table")
	installation.Register("Shared",shared)
	shared.Parent = RS
	started = true -- fail closed on a partial initialization; no duplicate services/retry loop.
	local remotes = require(shared.Remotes)
	installation.Register("Public",RS.APM_Public)
	assert(remotes.Claim("Server"), "[APM] Duplicate server initialization")
	local service = require(root.Server.APMService)
	context = service.Init()
	-- Public notices only; privileged UI continues to be delivered by Sessions.
	local noticeTemplate = root.ClientTemplates:FindFirstChild("APM_Notices")
	assert(noticeTemplate and noticeTemplate:IsA("LocalScript"), "[APM] Public notice template missing")
	local pending = {}
	local function notices(player)
		if pending[player] then return end
		pending[player] = true
		task.spawn(function()
			local gui = player:WaitForChild("PlayerGui", 10)
			pending[player] = nil
			if not gui or player.Parent ~= Players or gui:FindFirstChild("APM_PublicClient") then return end
			local holder=Instance.new("ScreenGui") holder.Name="APM_PublicClient" holder.ResetOnSpawn=false holder.Enabled=false
			holder:SetAttribute("APMRuntimeCopy",true) holder:SetAttribute("APMVersion",release.Version)
			local scriptCopy = noticeTemplate:Clone()
			scriptCopy.Name = "APM_PublicNoticeClient"
			scriptCopy:SetAttribute("APMRuntimeCopy", true) scriptCopy:SetAttribute("APMVersion", release.Version)
			scriptCopy.Parent = holder
			holder.Parent = gui
			gui.ChildAdded:Connect(function(node)
				if node~=holder and node.Name==holder.Name and node:GetAttribute("APMRuntimeCopy")==true then node:Destroy()end
			end)
		end)
	end
	Players.PlayerAdded:Connect(notices)
	Players.PlayerRemoving:Connect(function(player) pending[player] = nil end)
	for _, player in Players:GetPlayers() do notices(player) end
	installation.Watch(root,extensions)
	print("[APM] Core " .. release.Version .. " (" .. release.Channel .. ") loaded from private Core")
	return context
end
return Bootstrap
