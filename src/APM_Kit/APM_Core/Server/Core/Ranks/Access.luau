-- Ranks.Access : matrice d'accès module x grade, permissions nommées et interrupteur « Actif » (clé "Access").

return function(Ranks, S)
	local Settings, Msg, BUILTIN_PERMISSIONS = S.Settings, S.Msg, S.BUILTIN_PERMISSIONS

	-- Matrice d'accès (clé "Access") : valeurs enregistrées par-dessus les valeurs par défaut des modules

	Ranks.Access = {} -- [module] = { [Id du grade] = true / false } (choix faits dans le panneau)
	Ranks.Defaults = {} -- [module] = { [Id du grade] = true / false } (d'après le MinRank du module)
	Ranks.AccessReady = false
	S.accessRevision = -1

	-- Interrupteur « Actif » : entrée réservée de la clé "Access" (même révision, même synchronisation entre serveurs).
	-- Access["$Disabled"] = { [fonctionnalité] = true }. Les noms qui commencent par « $ » ne sont jamais des modules.
	local DISABLED = "$Disabled"
	Ranks.FeatureColumn = "*" -- colonne « Actif » des changements groupés
	Ranks.ProtectedFeatures = { ["APM.AccessPanel"] = true, ["APM.ManagePermissions"] = true }
	Ranks.FeatureNames = {} -- fonctionnalités sans colonne de grade (ex. effets Funny), déclarées par DeclareFeature

	local function reservedName(name)
		return string.sub(name, 1, 1) == "$"
	end

	function Ranks.IsFeatureEnabled(name)
		if Ranks.ProtectedFeatures[name] then
			return true
		end
		local disabled = Ranks.Access[DISABLED]
		return not (type(disabled) == "table" and disabled[name] == true)
	end

	function Ranks.DeclareFeature(name)
		if type(name) == "string" and name ~= "" and #name <= 64 and not reservedName(name) then
			Ranks.FeatureNames[name] = true
		end
	end

	-- Fonctionnalité connue (matrice ou déclarée) ?
	function Ranks.IsFeature(name)
		return type(name) == "string" and (Ranks.Defaults[name] ~= nil or Ranks.FeatureNames[name] == true)
	end

	function Ranks.LoadAccess()
		local data, ok = S.load("Access")
		if not ok then
			Ranks.AccessReady = false
			return false
		end
		Ranks.AccessReady = true
		if type(data) ~= "table" then
			if data ~= nil then Ranks.AccessReady = false; return false end
			Ranks.Access = {}
			S.accessRevision = 0
			return true
		end
		local revision = tonumber(data._Revision) or 0
		if revision < S.accessRevision then
			return true
		end
		S.accessRevision = revision
		data._Revision = nil
		Ranks.Access = data
		return true
	end

	-- Déclare des modules dans la matrice : list = { module, ... } (MinRank lu) ou { "Nom", ... } ; allowAll : tous les grades par défaut
	function Ranks.InitModuleAccess(list, allowAll)
		for _, info in list do
			local name = type(info) == "table" and info.Name or info
			if type(name) == "string" and name ~= "" and not reservedName(name) then
				local minimum = type(info) == "table" and Ranks.Level(info.MinRank) or 0
				local entry = Ranks.Defaults[name] or {}
				Ranks.Defaults[name] = entry
				for _, rank in Ranks.List do
					if entry[rank.Id] == nil then
						entry[rank.Id] = allowAll == true or rank.Level >= minimum
					end
				end
			end
		end
		-- Named permissions share the existing Access key and revision protocol.
		local permissionDefaults = table.clone(type(Settings.PermissionDefaults) == "table" and Settings.PermissionDefaults or {})
		for name, minimum in BUILTIN_PERMISSIONS do
			if permissionDefaults[name] == nil then
				permissionDefaults[name] = minimum
			end
		end
		for name, config in permissionDefaults do
			if type(name) == "string" and #name <= 64 and name ~= "" and not reservedName(name) then
				Ranks.PermissionNames[name] = true
				local minimum = type(config) == "table" and config.MinRank or config
				local entry = Ranks.Defaults[name] or {}
				Ranks.Defaults[name] = entry
				for _, rank in Ranks.List do
					entry[rank.Id] = minimum == true or (type(minimum) == "string" and Ranks.ById[minimum] ~= nil and rank.Level >= Ranks.Level(minimum))
				end
			end
		end
	end

	-- Choix du grade seul, sans l'interrupteur « Actif » (ce que montre la matrice des Paramètres)
	function Ranks.RawAllowed(name, rankId)
		local stored = Ranks.Access[name]
		if type(stored) == "table" and type(stored[rankId]) == "boolean" then
			return stored[rankId]
		end
		local default = Ranks.Defaults[name]
		return default ~= nil and default[rankId] == true
	end

	-- Ce grade a-t-il accès à ce module ? (fonctionnalité active, puis choix enregistré, sinon valeur par défaut ; module inconnu : non)
	function Ranks.Allowed(name, rankId)
		return Ranks.IsFeatureEnabled(name) and Ranks.RawAllowed(name, rankId)
	end

	-- Matrice complète pour le client : { [module] = { [grade] = bool } }
	function Ranks.GetModuleAccess()
		local view = {}
		for name in Ranks.Defaults do
			local entry = {}
			for _, rank in Ranks.List do
				entry[rank.Id] = Ranks.Allowed(name, rank.Id)
			end
			view[name] = entry
		end
		return view
	end

	function Ranks.SetModuleAccess(name, rankId, allowed, validate)
		if typeof(validate) == "Instance" and validate:IsA("Player") then
			local actor = validate
			if not Ranks.PreparePermissionChange(actor, name) then return false, Msg("Srv.AccessChanged") end
			validate = function() return Ranks.CanManagePermissionColumn(actor, name, rankId) end
		elseif validate ~= nil and type(validate) ~= "function" then
			return false, Msg("Srv.InvalidParams")
		end
		if type(name) ~= "string" or not Ranks.Defaults[name] or not Ranks.ById[rankId] or type(allowed) ~= "boolean" then
			return false, Msg("Srv.InvalidParams")
		end
		if validate and not validate() then
			return false, Msg("Srv.AccessChanged")
		end
		if not S.store and not Ranks.Memory then
			return false, Msg("Srv.AccessSaveFailed")
		end
		if not S.store then
			Ranks.Access[name] = type(Ranks.Access[name]) == "table" and Ranks.Access[name] or {}
			Ranks.Access[name][rankId] = allowed
			Ranks.AccessReady = true
			S.publish()
			return true, Msg("Srv.AccessSaved")
		end
		local cancelled = false
		local ok, result = pcall(S.store.UpdateAsync, S.store, "Access", function(old)
			if validate and not validate() then
				cancelled = true
				return nil
			end
			local map = type(old) == "table" and old or {}
			map[name] = type(map[name]) == "table" and map[name] or {}
			map[name][rankId] = allowed
			map._Revision = (tonumber(map._Revision) or 0) + 1
			return map
		end)
		if not ok or cancelled or type(result) ~= "table" then
			return false, Msg("Srv.AccessSaveFailed")
		end
		local revision = tonumber(result._Revision) or 0
		if revision >= S.accessRevision then
			S.accessRevision = revision
			result._Revision = nil
			Ranks.Access = result
		end
		Ranks.AccessReady = true
		S.publish()
		return true, Msg("Srv.AccessSaved")
	end

	-- Changement groupé (une catégorie, tout l'APM) en UNE écriture. column = Id d'un grade, ou Ranks.FeatureColumn (« Actif »).
	-- validate(name) est rappelé dans la transaction : un nom qui n'est plus autorisé est ignoré. Renvoie ok, message, nombre changé.
	function Ranks.SetAccessBulk(names, column, allowed, validate)
		local global = column == Ranks.FeatureColumn
		if type(names) ~= "table" or type(allowed) ~= "boolean" or type(validate) ~= "function" or (not global and not Ranks.ById[column]) then
			return false, Msg("Srv.InvalidParams"), 0
		end
		local function apply(map)
			local count = 0
			for _, name in names do
				if type(name) == "string" and not reservedName(name) and validate(name) then
					if global then
						local disabled = type(map[DISABLED]) == "table" and map[DISABLED] or {}
						map[DISABLED] = disabled
						disabled[name] = (not allowed) or nil
					else
						map[name] = type(map[name]) == "table" and map[name] or {}
						map[name][column] = allowed
					end
					count += 1
				end
			end
			return count
		end
		if not S.store and not Ranks.Memory then
			return false, Msg("Srv.AccessSaveFailed"), 0
		end
		if not S.store then
			local count = apply(Ranks.Access)
			if count == 0 then
				return false, Msg("Srv.AccessChanged"), 0
			end
			Ranks.AccessReady = true
			S.publish()
			return true, Msg("Srv.AccessSaved"), count
		end
		local count = 0
		local ok, result = pcall(S.store.UpdateAsync, S.store, "Access", function(old)
			local map = type(old) == "table" and old or {}
			count = apply(map)
			if count == 0 then
				return nil
			end
			map._Revision = (tonumber(map._Revision) or 0) + 1
			return map
		end)
		if ok and count == 0 then
			return false, Msg("Srv.AccessChanged"), 0
		end
		if not ok or type(result) ~= "table" then
			return false, Msg("Srv.AccessSaveFailed"), 0
		end
		local revision = tonumber(result._Revision) or 0
		if revision >= S.accessRevision then
			S.accessRevision = revision
			result._Revision = nil
			Ranks.Access = result
		end
		Ranks.AccessReady = true
		S.publish()
		return true, Msg("Srv.AccessSaved"), count
	end
end
