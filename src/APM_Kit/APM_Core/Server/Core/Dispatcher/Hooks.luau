--[[
	Hooks : soutiens SERVEUR facultatifs des actions distribuées (le contrôleur principal reste sur le client de la cible).
	Un soutien peut définir : Apply(player) · Clear(player) · OnCharacter(player, character) · Verify(player) -> true | false | nil
	Verify renvoie une PREUVE côté serveur quand il en existe une (true : constaté, false : contredit), nil quand le serveur ne peut pas savoir.

	  Fly     Verify : le Humanoid de la cible est en état PlatformStanding (état répliqué par son client).
	  Noclip  le serveur coupe lui aussi CanCollide sur le personnage (répliqué à tous les clients : les autres joueurs voient la même chose que la cible,
	          sans groupe de collision global, donc sans toucher aux réglages physiques du jeu) et restaure les valeurs d'origine à l'arrêt.
]]
local Hooks = {}

function Hooks.Create(ctx, services)
	services = services or {}
	local hooks = {}

	-- Fly ---------------------------------------------------------------------------------------------------
	hooks.Fly = {
		Verify = function(player)
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not humanoid then return nil end
			return humanoid:GetState() == Enum.HumanoidStateType.PlatformStanding
		end,
	}

	-- Noclip ------------------------------------------------------------------------------------------------
	local assists = setmetatable({}, { __mode = "k" }) -- [Player] = { Character, Originals, Connection }

	local function release(player)
		local record = assists[player]
		if not record then return end
		assists[player] = nil
		if record.Connection then record.Connection:Disconnect() end
		for part, was in record.Originals do
			if part.Parent then part.CanCollide = was end
		end
	end

	local function assist(player)
		release(player)
		local character = player.Character
		if not character then return false end
		local record = { Character = character, Originals = {} }
		local function take(part)
			if part:IsA("BasePart") and record.Originals[part] == nil then
				record.Originals[part] = part.CanCollide
				part.CanCollide = false
			end
		end
		for _, descendant in character:GetDescendants() do take(descendant) end
		record.Connection = character.DescendantAdded:Connect(take)
		assists[player] = record
		return true
	end

	hooks.Noclip = {
		Apply = assist,
		Clear = release,
		OnCharacter = function(player) assist(player) end,
		Verify = function(player)
			local record = assists[player]
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not record or record.Character ~= character or not root then return nil end
			return root.CanCollide == false
		end,
	}

	return hooks
end

return Hooks
