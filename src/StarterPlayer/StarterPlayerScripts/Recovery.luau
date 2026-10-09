-- Distribué uniquement durant une simulation sans accès au panneau.
local holder = script.Parent
local button = Instance.new("TextButton") button.Name="RestoreRealRank" button.Text="Simulation : revenir au grade réel"
button.Size=UDim2.fromOffset(300,44) button.Position=UDim2.new(0.5,-150,0,12)
button.BackgroundColor3=Color3.fromRGB(40,48,68) button.TextColor3=Color3.new(1,1,1) button.TextSize=15 button.Parent=holder
button.Activated:Connect(function()
 button.Text="Restauration…"
 local ok,success,message=pcall(function() return holder.APM_Remotes.RestoreSimulation:InvokeServer() end)
 if button.Parent and (not ok or not success) then button.Text=tostring(message or "Réessayer ou écrire /apm-restore") end
end)
