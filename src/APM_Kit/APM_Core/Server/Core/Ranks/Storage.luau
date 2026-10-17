-- Ranks.Storage : DataStore de l'APM (ou mode mémoire), lecture prudente d'une clé et annonce des changements aux autres serveurs.
local MessagingService = game:GetService("MessagingService")
local DataStoreService = game:GetService("DataStoreService")

return function(Ranks, S)
	local Settings, IS_STUDIO = S.Settings, S.IS_STUDIO

	-- Sauvegarde (DataStore de l'APM, partagé avec le journal, les bans, les avertissements et l'annuaire)

	S.store = nil
	Ranks.Memory = false

	local function enterMemory(reason)
		if Ranks.Memory then
			return
		end
		Ranks.Memory = true
		S.store = nil
		if reason == "Settings.StudioMemory" then
			print("[APM] Tests Studio isolés : mode mémoire demandé, aucune écriture dans les sauvegardes publiées.")
		else
			warn(("[APM] DataStore inaccessible (%s) : MODE MÉMOIRE, rien n'est enregistré. En Studio : Paramètres du jeu > Sécurité > "
				.. "Activer l'accès de Studio aux services API."):format(tostring(reason)))
		end
	end

	do
		if IS_STUDIO and Settings.StudioMemory == true then
			enterMemory("Settings.StudioMemory")
		else
			local ok, result = pcall(DataStoreService.GetDataStore, DataStoreService, Settings.DataStoreName or "APM_Data_v1")
			if ok then
				-- appels comptés pour l'onglet Stats (DataStores les plus sollicités)
				S.store = require(script.Parent.Parent.Statistics).WrapDataStore(result, Settings.DataStoreName or "APM_Data_v1")
			elseif IS_STUDIO then
				enterMemory(result)
			else
				warn("[APM] DataStore unavailable: privileged access remains closed. " .. tostring(result))
			end
		end
	end

	-- Le DataStore de l'APM (nil en mode mémoire)
	function Ranks.GetStore()
		return S.store
	end

	-- Lit une clé : valeur, ok (ok = false : lecture impossible, on reste prudent)
	function S.load(key)
		if not S.store then
			return nil, Ranks.Memory
		end
		local attempts = IS_STUDIO and 1 or 3
		local lastError
		for attempt = 1, attempts do
			local ok, value = pcall(S.store.GetAsync, S.store, key)
			if ok then
				return value, true
			end
			lastError = value
			if attempt < attempts then
				task.wait(attempt)
			end
		end
		if IS_STUDIO then
			enterMemory(lastError)
			return nil, true
		end
		warn(("[APM] Lecture impossible (%s) : %s"):format(key, tostring(lastError)))
		return nil, false
	end

	S.TOPIC = Settings.MessagingTopic or "APM_Sync_v1"
	function S.publish()
		if S.reconcileSimulations then
			S.reconcileSimulations()
		end
		if Ranks.OnChanged then
			-- Rights and private sessions are invalidated before the mutation returns.
			local ok, err = pcall(Ranks.OnChanged)
			if not ok then
				warn("[APM] Rights refresh failed: " .. tostring(err))
			end
		end
		if S.store then
			task.spawn(function()
				pcall(MessagingService.PublishAsync, MessagingService, S.TOPIC, game.JobId)
			end)
		end
	end
end
