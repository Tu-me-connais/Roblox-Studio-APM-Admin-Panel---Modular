-- Distribué uniquement durant une simulation sans accès au panneau.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lang = require(ReplicatedStorage:WaitForChild("APM_Shared"):WaitForChild("Lang"))
local function text(fr, en)
	return Lang.Text(Lang.Local(), { fr = fr, en = en })
end
local holder = script.Parent
local button = Instance.new("TextButton")
button.Name = "RestoreRealRank"
button.Text = text("Simulation : revenir au grade réel", "Simulation: back to my real rank")
button.Size = UDim2.fromOffset(300, 44)
button.Position = UDim2.new(0.5, -150, 0, 12)
button.BackgroundColor3 = Color3.fromRGB(40, 48, 68)
button.TextColor3 = Color3.new(1, 1, 1)
button.TextSize = 15
button.Parent = holder
button.Activated:Connect(function()
	button.Text = text("Restauration…", "Restoring…")
	local ok, success, message = pcall(function()
		return holder.APM_Remotes.RestoreSimulation:InvokeServer()
	end)
	if button.Parent and (not ok or not success) then
		button.Text = message ~= nil and Lang.Text(Lang.Local(), message) or text("Réessayer ou écrire /apm-restore", "Retry or type /apm-restore")
	end
end)
