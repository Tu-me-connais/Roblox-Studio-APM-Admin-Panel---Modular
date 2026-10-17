--[[
	Noclip (contrôleur client) : le personnage du joueur traverse les murs. À combiner avec Fly pour ne pas tomber dans le vide.
	C'est LE contrôleur de Noclip (voir Fly). Côté serveur, le Dispatcher coupe aussi les collisions du personnage (soutien « Hybrid ») pour que
	les autres joueurs voient le même résultat : le Humanoid local remet CanCollide à vrai à chaque image, d'où la boucle Stepped ci-dessous.
]]
local Noclip = {}

function Noclip.Create(env)
	local controller = {}
	local connection
	local original = {} -- [pièce] = true : collision coupée par ce contrôleur
	local activeCharacter

	local function restore()
		for part in original do
			if part.Parent then
				part.CanCollide = true
			end
		end
		table.clear(original)
	end

	local function stop()
		if connection then
			connection:Disconnect()
			connection = nil
		end
		restore()
		activeCharacter = nil
	end

	function controller.Start()
		stop()
		-- comme l'ancien outil : sans personnage prêt, la boucle attend simplement le prochain (le moteur relance Start à chaque réapparition)
		connection = env.Stepped:Connect(function()
			local character = env.Character()
			if not character then
				return
			end
			if activeCharacter ~= character then
				restore()
				activeCharacter = character
			end
			for _, part in character:GetDescendants() do
				if part:IsA("BasePart") and part.CanCollide then
					original[part] = true
					part.CanCollide = false
				end
			end
		end)
		return true
	end

	function controller.Stop()
		stop()
	end

	return controller
end

return Noclip
