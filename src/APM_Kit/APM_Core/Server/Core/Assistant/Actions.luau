--[[
	Actions : REGISTRE FERMÉ des actions que peut déclencher une commande personnalisée de Sentinel Helper.
	Une commande personnalisée n'est jamais du code : c'est une fiche de données (nom, arguments, permission, action) validée ici,
	au moment de l'enregistrement ET à chaque chargement. Ni loadstring, ni require, ni chemin d'instance venant d'un DataStore ou d'un client.
	  Reply     répond un texte court à l'admin (aide-mémoire, rappel de procédure)
	  Teleport  téléporte l'admin (ou un joueur visé qu'il a le droit de cibler) vers un point fixe, coordonnées bornées
	  Run       enchaîne jusqu'à 5 commandes EXISTANTES de l'APM ; chaque étape repasse par le moteur normal avec les droits de celui qui tape
	            (une commande personnalisée n'élève donc jamais un grade : elle ne peut rien que l'admin ne puisse déjà faire à la main).
]]
local Actions = {}

Actions.Types = { Reply = true, Teleport = true, Run = true }
Actions.COORDINATE_LIMIT = 100000
Actions.MAX_STEPS = 5
Actions.MAX_ARGS = 3

-- Texte simple : UTF-8 valide, sans caractères de contrôle, tronqué à `limit` caractères ; nil si ce n'est pas un texte
function Actions.CleanText(value, limit)
	if type(value) ~= "string" or #value > limit * 4 or not utf8.len(value) then return nil end
	value = string.gsub(value, "%c", " ")
	value = string.gsub(string.gsub(value, "^%s+", ""), "%s+$", "")
	if utf8.len(value) > limit then
		value = string.sub(value, 1, utf8.offset(value, limit + 1) - 1)
	end
	return value
end

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- « {nom} » dans un modèle d'étape : doit référencer un argument déclaré de la commande (ou {me})
local function placeholdersValid(template, declared)
	for name in string.gmatch(template, "{([^{}]*)}") do
		if name ~= "me" and not declared[name] then return false end
	end
	local stripped = string.gsub(template, "{[^{}]*}", "")
	return not string.find(stripped, "[{}]")
end

-- Valide l'action d'une fiche. args : arguments déjà validés de la fiche. Renvoie l'action propre, ou nil + code d'erreur.
function Actions.Validate(action, args)
	if type(action) ~= "table" or type(action.Type) ~= "string" or not Actions.Types[action.Type] then return nil, "ActionType" end
	local declared, hasTarget = {}, false
	for _, arg in args or {} do
		declared[arg.Name] = arg
		if arg.Type == "target" then hasTarget = true end
	end
	if action.Type == "Reply" then
		local text = Actions.CleanText(action.Text, 120)
		if not text or text == "" then return nil, "ActionText" end
		return { Type = "Reply", Text = text }
	elseif action.Type == "Teleport" then
		local who = action.Who == "Target" and "Target" or "Self"
		if who == "Target" and not hasTarget then return nil, "ActionTarget" end
		local point = {}
		for _, axis in { "X", "Y", "Z" } do
			local value = action[axis]
			if not finite(value) or math.abs(value) > Actions.COORDINATE_LIMIT then return nil, "ActionPoint" end
			point[axis] = math.floor(value * 100 + .5) / 100
		end
		return { Type = "Teleport", Who = who, X = point.X, Y = point.Y, Z = point.Z }
	else
		if type(action.Steps) ~= "table" or #action.Steps < 1 or #action.Steps > Actions.MAX_STEPS then return nil, "ActionSteps" end
		local steps = {}
		for index, step in action.Steps do
			local command = type(step) == "table" and Actions.CleanText(step.Command, 100) or nil
			if type(index) ~= "number" or not command or command == "" or not placeholdersValid(command, declared) then return nil, "ActionStep" end
			table.insert(steps, { Command = command })
		end
		return { Type = "Run", Steps = steps }
	end
end

-- Remplace {argument} par la valeur tapée, en UN SEUL mot : une valeur ne peut pas ajouter de mots ni changer de commande
function Actions.Expand(template, values, selfName)
	return (string.gsub(template, "{([^{}]*)}", function(name)
		local value = name == "me" and (selfName or "me") or values[name]
		if value == nil then return "" end
		value = string.gsub(tostring(value), "[\"'%c]", "")
		if value == "" then return "" end
		if string.find(value, "%s") then return '"' .. value .. '"' end
		return value
	end))
end

--[[
	Exécute Reply et Teleport. host : { Msg, CanTarget(admin, joueur), NotifyTeleport(joueur), Character(joueur) }.
	values : valeurs des arguments ; target : joueur déjé résolu (ou nil). Renvoie ok, code, message traduisible.
]]
function Actions.Execute(host, admin, action, values, target)
	if action.Type == "Reply" then
		return true, "Done", host.Msg("Assistant.CustomReply", action.Text)
	elseif action.Type == "Teleport" then
		local subject = admin
		if action.Who == "Target" then
			if not target then return false, "NotFound", host.Msg("Assistant.NotFound") end
			subject = target
			if target ~= admin and not host.CanTarget(admin, target) then return false, "Protected", host.Msg("Assistant.Protected", target.Name) end
		end
		local character = host.Character(subject)
		if not character then return false, "Unavailable", host.Msg("Srv.CharacterNotFound") end
		host.NotifyTeleport(subject)
		character:PivotTo(CFrame.new(action.X, action.Y, action.Z))
		return true, "Done", host.Msg("Assistant.Teleported", subject.Name)
	end
	return false, "Unavailable", host.Msg("Assistant.Unavailable")
end

return Actions
