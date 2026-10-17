--[[
	Announcements (serveur) : annonces à tout le serveur.

	- Envoi (remote Announce) : permission APM.Announce ; message + titre facultatif, filtrés par Roblox (un échec du filtrage
	  ne diffuse jamais le texte brut).
	- Verrou de rédaction : un seul admin rédige à la fois sur ce serveur (AnnounceDraft : claim / ping / release). Les autres
	  voient « X rédige une annonce » et ne peuvent pas envoyer. Libéré à l'envoi, quand le rédacteur vide ses champs ou quitte,
	  s'il perd la permission, ou après DRAFT_TIMEOUT secondes sans signe de vie (panneau fermé, déconnexion réseau...).
	- Verrou d'affichage : tant qu'une annonce est à l'écran des joueurs, aucune autre ne part (pas de chevauchement).
	  La place est réservée AVANT le filtrage (qui attend Roblox) : deux envois simultanés ne peuvent pas passer tous les deux.
	- Style (permission APM.AnnounceStyle, Owner par défaut) : validé par APM_Shared.Announcements, enregistré dans le
	  DataStore de l'APM (clé AnnounceStyle), publié à tous les clients par l'attribut APM_Public.AnnounceStyle et
	  synchronisé entre serveurs (MessagingService).
	L'état (rédacteur, annonce à l'écran, version du style) est poussé aux admins concernés par l'événement AnnounceState.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MessagingService = game:GetService("MessagingService")

local Style = require(ReplicatedStorage:WaitForChild("APM_Shared"):WaitForChild("Announcements"))

local Announcements = {}

local DRAFT_TIMEOUT = 15 -- secondes sans signe de vie avant de libérer la rédaction
local SEND_COOLDOWN = 3 -- secondes entre deux annonces d'un même admin
local STORE_KEY = "AnnounceStyle"

local ctx, Ranks, Guard, Msg, R
local style = Style.Default()
local styleVersion = 1
local holder -- rédacteur actuel : { Player, UserId, Name, Expires }
local showing -- annonce à l'écran (ou en cours de filtrage) : { Name, Until }
local lastSent = {}
local topic

local function canAnnounce(player)
	return player.Parent == Players and Ranks.IsAdmin(player) and Ranks.HasPermission(player, "APM.Announce")
end
local function canStyle(player)
	return player.Parent == Players and Ranks.IsAdmin(player) and Ranks.HasPermission(player, "APM.AnnounceStyle")
end

local function publishStyle()
	local folder = ReplicatedStorage:FindFirstChild("APM_Public")
	if folder then
		folder:SetAttribute("AnnounceStyle", Style.Encode(style))
	end
end

-- Rédacteur encore valable ? (présent, toujours autorisé, signe de vie récent)
local function currentHolder()
	if holder and (os.clock() > holder.Expires or not canAnnounce(holder.Player)) then
		holder = nil
	end
	return holder
end

-- Secondes restantes de l'annonce à l'écran (0 = aucune)
local function showingLeft()
	if showing and os.clock() >= showing.Until then
		showing = nil
	end
	return showing and math.max(1, math.ceil(showing.Until - os.clock())) or 0
end

local function stateFor(player)
	local current = currentHolder()
	local left = showingLeft()
	return {
		Holder = current and current.Name or nil,
		Mine = current ~= nil and current.UserId == player.UserId,
		ShowingBy = left > 0 and showing.Name or nil,
		ShowingLeft = left,
		CanStyle = canStyle(player),
		StyleVersion = styleVersion,
	}
end

-- Pousse l'état à chaque admin qui peut annoncer ou régler le style
local function broadcast()
	for _, player in Players:GetPlayers() do
		if Ranks.IsAdmin(player) and (Ranks.HasPermission(player, "APM.Announce") or Ranks.HasPermission(player, "APM.AnnounceStyle")) then
			R.AnnounceState:FireClient(player, stateFor(player))
		end
	end
end

local function releaseHolder(player)
	if holder and holder.UserId == player.UserId then
		holder = nil
		broadcast()
	end
end

----------------------------------------------------------------------------------------------------------
-- Style : lecture / écriture

local function loadStyle()
	local store = Ranks.GetStore()
	if not store then
		return -- mode mémoire : style de la session
	end
	local ok, data = pcall(store.GetAsync, store, STORE_KEY)
	if not ok then
		warn("[APM] Style des annonces illisible (DataStore) : style par défaut conservé. " .. tostring(data))
		return
	end
	if type(data) == "table" then
		local loaded = Style.Sanitize(data)
		if not Style.Equal(loaded, style) then
			style = loaded
			styleVersion += 1
			publishStyle()
			broadcast()
		end
	end
end

local function saveStyle(newStyle)
	local store = Ranks.GetStore()
	if not store then
		return Ranks.Memory == true -- en Studio sans DataStore : valable pour la session ; une panne publiée refuse
	end
	local ok, err = pcall(store.SetAsync, store, STORE_KEY, newStyle)
	if not ok then
		warn("[APM] Enregistrement du style des annonces impossible : " .. tostring(err))
		return false
	end
	if topic then
		task.spawn(function()
			pcall(MessagingService.PublishAsync, MessagingService, topic, game.JobId)
		end)
	end
	return true
end

function Announcements.GetStyle()
	return Style.Copy(style)
end

----------------------------------------------------------------------------------------------------------

local function trim(text)
	text = string.gsub(text, "^%s+", "")
	return (string.gsub(text, "%s+$", ""))
end

function Announcements.Init(context)
	ctx = context
	Ranks, Guard, Msg, R = ctx.Ranks, ctx.Guard, ctx.Msg, ctx.Remotes
	ctx.Announcements = Announcements
	publishStyle()
	task.spawn(loadStyle)

	-- État courant + style enregistré (ouverture de l'onglet)
	R.GetAnnounceState.OnServerInvoke = function(player)
		if not Ranks.IsAdmin(player) or not Guard.Allow(player, "GetAnnounceState", 20, 10) then
			return nil
		end
		local state = stateFor(player)
		state.Style = Style.Copy(style)
		return state
	end

	-- Rédaction : action = "claim" (je commence) | "ping" (je rédige toujours) | "release" (j'abandonne)
	R.AnnounceDraft.OnServerInvoke = function(player, action)
		if not canAnnounce(player) then
			return false, stateFor(player)
		end
		if not Guard.Allow(player, "AnnounceDraft", 40, 10) or (action ~= "claim" and action ~= "ping" and action ~= "release") then
			return false, stateFor(player)
		end
		local current = currentHolder()
		if action == "release" then
			releaseHolder(player)
			return true, stateFor(player)
		end
		if current and current.UserId ~= player.UserId then
			return false, stateFor(player) -- quelqu'un rédige déjà
		end
		local fresh = current == nil
		if fresh then
			holder = { Player = player, UserId = player.UserId, Name = player.Name }
		end
		local mine = holder
		mine.Expires = os.clock() + DRAFT_TIMEOUT
		task.delay(DRAFT_TIMEOUT + 0.5, function()
			if holder == mine and os.clock() > mine.Expires then
				holder = nil
				broadcast()
			end
		end)
		if fresh then
			broadcast()
		end
		return true, stateFor(player)
	end

	-- Style (Owner par défaut) : validé, enregistré, publié à tous
	R.SetAnnounceStyle.OnServerInvoke = function(player, raw)
		if not canStyle(player) then
			return false, Msg("Srv.AccessDenied")
		end
		if not Guard.Allow(player, "SetAnnounceStyle", 6, 30) then
			return false, Msg("Srv.TooManyChanges")
		end
		if type(raw) ~= "table" then
			return false, Msg("Srv.InvalidParams")
		end
		local clean = Style.Sanitize(raw)
		if not saveStyle(clean) then
			return false, Msg("Srv.AnnounceStyleWriteFailed")
		end
		if not canStyle(player) then
			return false, Msg("Srv.AccessChanged")
		end
		style = clean
		styleVersion += 1
		publishStyle()
		broadcast()
		ctx.Log(player.Name, "AnnounceStyle", nil, Msg("Log.AnnounceStyle", "Announce.Preset." .. clean.Preset), "System", "info")
		return true, Msg("Srv.AnnounceStyleSaved"), Style.Copy(clean)
	end

	-- Envoi d'une annonce
	R.Announce.OnServerEvent:Connect(function(admin, text, title)
		if not canAnnounce(admin) then
			ctx.Notify(admin, Msg("Srv.AccessDenied"), false)
			return
		end
		if type(text) ~= "string" or (title ~= nil and type(title) ~= "string") then
			return
		end
		text = ctx.Filter.Clamp(text, Style.MaxMessage)
		title = title and ctx.Filter.Clamp(title, Style.MaxTitle) or ""
		if not text or not title then
			return
		end
		text, title = trim(text), trim(title)
		if text == "" then
			ctx.Notify(admin, Msg("Srv.EmptyMessage"), false)
			return
		end
		local current = currentHolder()
		if current and current.UserId ~= admin.UserId then
			ctx.Notify(admin, Msg("Srv.AnnounceBusy", current.Name), false)
			return
		end
		local left = showingLeft()
		if left > 0 then
			ctx.Notify(admin, Msg("Srv.AnnounceShowing", left), false)
			return
		end
		local now = os.clock()
		if lastSent[admin.UserId] and now - lastSent[admin.UserId] < SEND_COOLDOWN then
			ctx.Notify(admin, Msg("Srv.AnnounceWait"), false)
			return
		end
		lastSent[admin.UserId] = now

		-- réserve l'écran avant d'attendre le filtrage : un second envoi simultané est refusé
		local slot = { Name = admin.Name, Until = os.clock() + 30 }
		showing = slot
		local filtered = ctx.Filter.Strings(text, admin.UserId)
		local filteredTitle = title ~= "" and ctx.Filter.Strings(title, admin.UserId) or nil
		if not filtered or (title ~= "" and not filteredTitle) or not canAnnounce(admin) then
			if showing == slot then
				showing = nil
			end
			if not filtered or (title ~= "" and not filteredTitle) then
				ctx.Notify(admin, Msg("Srv.AnnounceFilterDown"), false)
			end
			return
		end

		local duration = Style.Duration(style, filtered.Broadcast) + Style.AnimationTime + 0.5
		slot.Until = os.clock() + duration
		if holder and holder.UserId == admin.UserId then
			holder = nil
		end
		R.Announcement:FireAllClients(filtered.Broadcast, admin.Name, {
			Title = filteredTitle and filteredTitle.Broadcast or nil,
			Time = os.time(),
		})
		ctx.Notify(admin, Msg("Srv.AnnounceSent"), true)
		local detail = filteredTitle and (filteredTitle.Broadcast .. " : " .. filtered.Broadcast) or filtered.Broadcast
		ctx.Log(admin.Name, "Announce", nil, detail, "System", "info")
		broadcast()
		task.delay(duration, function()
			if showing == slot then
				showing = nil
				broadcast()
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastSent[player.UserId] = nil
		if holder and holder.UserId == player.UserId then
			holder = nil
			broadcast()
		end
	end)

	-- synchronisation du style entre serveurs
	topic = tostring(ctx.Settings.MessagingTopic or "APM_Sync_v1") .. "_AnnounceStyle"
	if Ranks.GetStore() then
		task.spawn(function()
			pcall(function()
				MessagingService:SubscribeAsync(topic, function(message)
					if message.Data ~= game.JobId then
						task.spawn(loadStyle)
					end
				end)
			end)
		end)
	end
end

return Announcements
