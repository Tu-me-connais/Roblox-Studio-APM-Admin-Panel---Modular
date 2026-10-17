-- ESP (outil client) : pseudo, distance et contour des autres joueurs à travers les murs (visible que par toi).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local M = {}
M.Name, M.Order = "ESP", 22

local Core
local folder, connection
local marks = {} -- [Player] = { billboard, highlight, label, character }

local function mark(player)
	if marks[player] or player == Players.LocalPlayer then
		return
	end
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return
	end
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "APM_ESP_" .. player.UserId
	billboard.Adornee = head
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(170, 40)
	billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	billboard.Parent = folder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(255, 220, 90)
	label.TextStrokeTransparency = 0.3
	label.Text = player.DisplayName
	label.Parent = billboard
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = Color3.fromRGB(255, 220, 90)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Adornee = character
	highlight.Parent = folder
	marks[player] = { billboard = billboard, highlight = highlight, label = label, character = character }
end

local function unmark(player)
	local entry = marks[player]
	if entry then
		entry.billboard:Destroy()
		entry.highlight:Destroy()
		marks[player] = nil
	end
end

function M.Init(core)
	Core = core
end

function M.Set(on)
	if connection then
		connection:Disconnect()
		connection = nil
	end
	for player in marks do
		unmark(player)
	end
	if folder then
		folder:Destroy()
		folder = nil
	end
	if not on then
		return
	end
	folder = Instance.new("Folder")
	folder.Name = "APM_ESP"
	folder.Parent = workspace.CurrentCamera
	local elapsed = 0
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		if elapsed < 0.2 then return end
		elapsed = 0
		local camera = workspace.CurrentCamera
		for _, player in Players:GetPlayers() do
			local entry = marks[player]
			if entry and entry.character ~= player.Character then -- il a réapparu
				unmark(player)
				entry = nil
			end
			if not entry then
				mark(player)
				entry = marks[player]
			end
			if entry then
				local head = entry.billboard.Adornee
				if head and camera then
					local distance = math.floor((camera.CFrame.Position - head.Position).Magnitude)
					entry.label.Text = Core and Core.L("Tool.ESP.Studs", player.DisplayName, distance) or ("%s\n%d"):format(player.DisplayName, distance)
				end
			end
		end
		for player in marks do
			if not player.Parent then
				unmark(player)
			end
		end
	end)
end

return M
