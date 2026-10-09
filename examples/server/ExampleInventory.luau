-- Optional: APM_Extensions.Adapters.ExampleInventory. Read-only structural diagnostic.
-- Configure the Examples.Inventory.View permission in developer ServerSettings before installing this manifest.
local ServerStorage=game:GetService("ServerStorage")
return {
	ApiVersion=1,
	Id="example_inventory",
	Adapter={
		Permission="Examples.Inventory.View",
		Actions={},
		Probe=function()
			local folder=ServerStorage:FindFirstChild("ExampleInventory")
			if not folder or not folder:IsA("Folder") then
				return {Name="ExampleInventory",Status="Unsupported",Count=0,Detail="Dossier serveur ExampleInventory absent ; aucune API métier supposée."}
			end
			local tools,scanned=0,0
			local entries=folder:GetChildren()
			for _,item in entries do
				if scanned>=500 then break end
				scanned+=1
				if item:IsA("Tool") then tools+=1 end
			end
			return {Name="ExampleInventory",Status="Detected",Count=tools,
				Detail=string.format("Dossier réel présent ; %d outils parmi %d enfants examinés%s. Une API du jeu est requise pour toute action.",
					tools,scanned,#entries>500 and " (limite 500 atteinte)" or "")}
		end,
	},
}
