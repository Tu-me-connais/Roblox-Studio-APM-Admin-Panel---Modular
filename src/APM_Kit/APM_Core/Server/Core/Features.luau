--[[
	Features : catalogue de TOUTES les fonctionnalités de l'APM, rangées par catégorie, pour l'onglet Paramètres.
	  - « accès » : commandes (modules serveur), outils client, permissions dédiées -> matrice fonctionnalité x grade ;
	  - « globale » : effets Funny -> seulement actif / coupé.
	« Actif » coupe une fonctionnalité pour TOUT le jeu, Dev compris (Ranks.IsFeatureEnabled). Réservé au SuperRank et au
	propriétaire réel de l'expérience (hors simulation). APM.AccessPanel et APM.ManagePermissions restent toujours actifs.
	Une catégorie entière se change par SetAccessBulk : une seule écriture, revalidée nom par nom.
	Une extension peut ranger ses permissions : ctx.Features.Describe("MonExt.Use", { Category = "MonExt", Label = { fr = "...", en = "..." } }).
]]
local Lang = require(game:GetService("ReplicatedStorage"):WaitForChild("APM_Shared"):WaitForChild("Lang"))

local Features = {}

local MAX_BULK = 60

local function text(fr, en, es, pt, de)
	return { fr = fr, en = en, es = es, pt = pt, de = de }
end

-- Catégories officielles : ordre, titre, couleur. Une catégorie inconnue (module d'extension) prend le titre "Cat.<Id>".
local CATEGORIES = {
	Panel = { Order = 1, Label = text("Panneau et sécurité", "Panel and security", "Panel y seguridad", "Painel e segurança", "Panel und Sicherheit"),
		Color = Color3.fromRGB(205, 95, 95) },
	Players = { Order = 2, Label = "Cat.Players", Color = Color3.fromRGB(88, 128, 232) },
	Bans = { Order = 3, Label = "Cat.Bans", Color = Color3.fromRGB(190, 60, 60) },
	Moderation = { Order = 4, Label = "Cat.Moderation", Color = Color3.fromRGB(80, 175, 110) },
	Game = { Order = 5, Label = "Cat.Game", Color = Color3.fromRGB(220, 170, 70) },
	Funny = { Order = 6, Label = text("Amusement", "Funny"), Color = Color3.fromRGB(235, 120, 200) },
	Sentinel = { Order = 7, Label = text("Sentinel Guard", "Sentinel Guard"), Color = Color3.fromRGB(150, 110, 230) },
	AutoBridge = { Order = 8, Label = text("AutoBridge", "AutoBridge"), Color = Color3.fromRGB(70, 180, 200) },
	Assistant = { Order = 9, Label = text("Sentinel (assistant)", "Sentinel (assistant)", "Sentinel (asistente)", "Sentinel (assistente)", "Sentinel (Assistent)"), Color = Color3.fromRGB(190, 190, 196) },
	Extensions = { Order = 50, Label = text("Extensions", "Extensions"), Color = Color3.fromRGB(150, 157, 172) },
}

-- Permissions dédiées officielles : { catégorie, ordre, libellé }
local PERMISSIONS = {
	["APM.AccessPanel"] = { "Panel", 1, text("Ouvrir le panneau", "Open the panel", "Abrir el panel", "Abrir o painel", "Panel öffnen") },
	["APM.ManagePermissions"] = { "Panel", 2, text("Paramètres : grades et accès", "Settings: ranks and access", "Ajustes: rangos y acceso", "Configurações: cargos e acesso", "Einstellungen: Ränge und Zugriff") },
	["APM.ServerLock"] = { "Panel", 3, text("Verrouiller le serveur", "Lock the server", "Bloquear el servidor", "Trancar o servidor", "Server sperren") },
	["APM.Announce"] = { "Panel", 4, text("Annonce à tout le serveur", "Server-wide announcement", "Anuncio a todo el servidor", "Anúncio para o servidor", "Ankündigung an den Server") },
	["APM.AnnounceStyle"] = { "Panel", 4.5, text("Réglages des annonces (style, disposition, textes)", "Announcement settings (style, layout, texts)",
		"Ajustes de anuncios (estilo, disposición, textos)", "Ajustes dos anúncios (estilo, layout, textos)", "Ankündigungseinstellungen (Stil, Layout, Texte)") },
	["APM.ViewLogs"] = { "Panel", 5, text("Voir le journal", "View the log (Logs)", "Ver el registro (Logs)", "Ver o registro (Logs)", "Protokoll ansehen (Logs)") },
	["APM.Simulate"] = { "Panel", 6, text("Simulation de grade et diagnostics", "Rank simulation and diagnostics", "Simulación de rango y diagnóstico", "Simulação de cargo e diagnóstico", "Rangsimulation und Diagnose") },
	["Funny.View"] = { "Funny", 1, text("Voir l'onglet Amusement", "View the Funny tab") },
	["Funny.Use"] = { "Funny", 2, text("Lancer des scènes", "Start scenes") },
	["Funny.Group"] = { "Funny", 3, text("Viser un groupe de joueurs", "Target a group of players") },
	["Funny.Server"] = { "Funny", 4, text("Viser tout le serveur", "Target the whole server") },
	["Funny.CrossServer"] = { "Funny", 5, text("Diffuser sur tous les serveurs", "Broadcast to every server") },
	["Funny.Transform"] = { "Funny", 6, text("Transformations d'avatar", "Avatar transformations") },
	["Funny.Physics"] = { "Funny", 7, text("Effets physiques", "Physics effects") },
	["Funny.StopAll"] = { "Funny", 8, text("Arrêter les scènes des autres", "Stop other admins' scenes") },
	["Sentinel.View"] = { "Sentinel", 1, text("Voir Sentinel", "View Sentinel") },
	["Sentinel.Configure"] = { "Sentinel", 2, text("Configurer Sentinel", "Configure Sentinel") },
	["Sentinel.Test"] = { "Sentinel", 3, text("Tester Sentinel", "Test Sentinel") },
	["AutoBridge.View"] = { "AutoBridge", 1, text("Voir AutoBridge", "View AutoBridge") },
	["AutoBridge.Configure"] = { "AutoBridge", 2, text("Configurer AutoBridge", "Configure AutoBridge") },
	["Assistant.Use"] = { "Assistant", 1, text("Utiliser Sentinel (assistant flottant)", "Use Sentinel (floating assistant)", "Usar Sentinel (asistente flotante)", "Usar o Sentinel (assistente flutuante)", "Sentinel verwenden (schwebender Assistent)") },
	["Assistant.Configure"] = { "Assistant", 2, text("Sentinel Helper : réglages généraux", "Sentinel Helper: general settings", "Sentinel Helper: ajustes generales", "Sentinel Helper: configurações gerais", "Sentinel Helper: Allgemeine Einstellungen") },
	["Assistant.Commands"] = { "Assistant", 3, text("Sentinel Helper : commandes personnalisées", "Sentinel Helper: custom commands", "Sentinel Helper: comandos personalizados", "Sentinel Helper: comandos personalizados", "Sentinel Helper: eigene Befehle") },
	["Assistant.External"] = { "Assistant", 4, text("Sentinel Helper : IA externe (facultative)", "Sentinel Helper: external AI (optional)", "Sentinel Helper: IA externa (opcional)", "Sentinel Helper: IA externa (opcional)", "Sentinel Helper: externe KI (optional)") },
}

-- Rang d'affichage dans une catégorie : commandes, outils client, permissions, effets
local KIND_RANK = { Command = 0, Tool = 1, Permission = 2, Effect = 3 }

function Features.Init(ctx, Grades)
	local Ranks, Guard, R, Msg = ctx.Ranks, ctx.Guard, ctx.Remotes, ctx.Msg
	local api = {}
	local described = {} -- [permission] = { Category, Order, Label, Description } (extensions)
	local effects = {} -- effets Funny : { Name, Order, Label, Description }
	local tools, toolOrder = {}, {}

	for index, config in ctx.Settings.ClientTools or {} do
		local name = type(config) == "string" and config or (type(config) == "table" and config.Name) or (type(index) == "string" and index)
		if type(name) == "string" then
			tools[name] = true
			toolOrder[name] = type(index) == "number" and index or 50
		end
	end

	local funnySource = script.Parent:FindFirstChild("Funny")
	local ok, Funny = pcall(require, funnySource)
	if ok and type(Funny) == "table" and type(Funny.Effects) == "function" then
		for _, effect in Funny.Effects() do
			local name = Funny.EffectFeature(effect.Id)
			Ranks.DeclareFeature(name)
			table.insert(effects, { Name = name, Order = effect.Order, Label = effect.Label, Description = effect.Description })
		end
	end

	function api.Describe(name, info)
		if type(name) == "string" and #name <= 64 and type(info) == "table" then
			described[name] = {
				Category = type(info.Category) == "string" and info.Category ~= "" and string.sub(info.Category, 1, 32) or nil,
				Order = tonumber(info.Order) or 100,
				Label = info.Label,
				Description = info.Description,
			}
		end
	end

	-- Le SuperRank et le propriétaire réel (hors simulation) allument / coupent les fonctionnalités pour tout le jeu
	local function canToggle(player)
		if not Grades.CanManage(player) then
			return false
		end
		return Ranks.IsSuper(player) or (Ranks.IsExperienceOwner(player) and not Ranks.GetSimulation(player).active)
	end
	api.CanToggle = canToggle

	-- Fiche d'une fonctionnalité de la matrice (commande, outil client ou permission)
	local function describe(name)
		local module = ctx.Modules and ctx.Modules[name]
		if module then
			return { Kind = "Command", Category = module.Category, Order = module.Order, Label = module.Label, Description = module.Description, ExtensionId = module.ExtensionId }
		end
		if tools[name] then
			local prefix = "Tool." .. name .. "."
			return { Kind = "Tool", Category = "Moderation", Order = toolOrder[name], ClientSide = true,
				Label = Lang.Has(prefix .. "Label") and prefix .. "Label" or name, Description = Lang.Has(prefix .. "Desc") and prefix .. "Desc" or nil }
		end
		local official, custom = PERMISSIONS[name], described[name]
		local prefix = string.match(name, "^([%w_]+)%.")
		local category = custom and custom.Category or official and official[1] or (prefix and CATEGORIES[prefix] and prefix) or "Extensions"
		return { Kind = "Permission", Category = category, Order = custom and custom.Order or official and official[2] or 100,
			Label = custom and custom.Label or official and official[3] or name, Description = custom and custom.Description or nil }
	end

	local function editability(player, name, globalOnly)
		local editable, reasons = {}, {}
		local global = Ranks.FeatureColumn
		editable[global] = canToggle(player) and not Ranks.ProtectedFeatures[name]
		if not editable[global] then
			reasons[global] = Ranks.ProtectedFeatures[name]
				and text("Cet accès reste toujours actif. Modifie la colonne d'un grade pour régler qui peut l'utiliser.", "This access always stays active. Change a rank column to choose who can use it.")
				or text("Seuls le grade le plus haut et le propriétaire du jeu peuvent activer ou couper une fonctionnalité.", "Only the highest rank and the game owner can switch a feature on or off.")
		end
		for _, rank in Ranks.List do
			if globalOnly then
				editable[rank.Id] = false
				reasons[rank.Id] = text("Cet effet se règle uniquement avec la colonne Actif.", "This effect is controlled only by the Active column.")
			else
				local allowed, reason = Grades.CanChangeColumn(player, name, rank.Id)
				editable[rank.Id] = allowed == true
				reasons[rank.Id] = reason
			end
		end
		return editable, reasons
	end

	-- Tout le catalogue, avec l'état actuel (valeurs brutes des grades + interrupteur « Actif »)
	function api.Snapshot(player)
		local categories, byId = {}, {}
		local function add(info)
			local id = type(info.Category) == "string" and info.Category or "Extensions"
			local category = byId[id]
			if not category then
				local def = CATEGORIES[id]
				category = { Id = id, Order = def and def.Order or 20, Label = def and def.Label or ("Cat." .. id), Color = def and def.Color or nil, Items = {} }
				byId[id] = category
				table.insert(categories, category)
			end
			info.Category = nil
			table.insert(category.Items, info)
		end
		for name in Ranks.Defaults do
			local info = describe(name)
			info.Name = name
			info.Access = {}
			for _, rank in Ranks.List do
				info.Access[rank.Id] = Ranks.RawAllowed(name, rank.Id)
			end
			info.Permission = Ranks.PermissionNames[name] == true
			info.Protected = Ranks.ProtectedFeatures[name] == true
			info.Enabled = Ranks.IsFeatureEnabled(name)
			info.CanEdit, info.LockReason = editability(player, name, false)
			add(info)
		end
		for _, effect in effects do
			local editable, reasons = editability(player, effect.Name, true)
			add({ Kind = "Effect", Category = "Funny", Name = effect.Name, Order = effect.Order, Label = effect.Label, Description = effect.Description,
				Global = true, Enabled = Ranks.IsFeatureEnabled(effect.Name), CanEdit = editable, LockReason = reasons })
		end
		for _, category in categories do
			table.sort(category.Items, function(a, b)
				local ka, kb = KIND_RANK[a.Kind] or 9, KIND_RANK[b.Kind] or 9
				if ka ~= kb then
					return ka < kb
				end
				local oa, ob = tonumber(a.Order) or 100, tonumber(b.Order) or 100
				if oa ~= ob then
					return oa < ob
				end
				return a.Name < b.Name
			end)
		end
		table.sort(categories, function(a, b)
			if a.Order ~= b.Order then
				return a.Order < b.Order
			end
			return a.Id < b.Id
		end)
		return {
			Categories = categories,
			Column = Ranks.FeatureColumn,
			CanToggle = canToggle(player),
			Owner = Ranks.IsExperienceOwner(player) and not Ranks.GetSimulation(player).active,
			MaxBulk = MAX_BULK,
		}
	end

	R.GetFeatures.OnServerInvoke = function(player)
		if not Grades.CanManage(player) or not Guard.Allow(player, "GetFeatures", 10, 10) then
			return nil
		end
		Ranks.PreparePermissionChange(player, "APM.AccessPanel")
		if not Grades.CanManage(player) then return nil end
		return api.Snapshot(player)
	end

	local function toggleOnly()
		return Lang.Phrase({fr="Seuls le grade %s et le propriétaire du jeu peuvent couper une fonctionnalité.",en="Only the %s rank and the game owner can switch features off."}, "Rank." .. Ranks.Super)
	end

	-- names : liste de fonctionnalités (MAX_BULK au plus) ; column : Id d'un grade ou "*" (« Actif ») ; allowed : booléen
	R.SetAccessBulk.OnServerInvoke = function(admin, names, column, allowed)
		if not Grades.CanManage(admin) then
			return false, Msg("Srv.ManageOnly", "Rank." .. Ranks.Manager)
		end
		if not Guard.Allow(admin, "SetAccessBulk", 20, 30) then
			return false, Msg("Srv.TooManyChanges")
		end
		if type(names) ~= "table" or type(column) ~= "string" or type(allowed) ~= "boolean" then
			return false, Msg("Srv.InvalidParams")
		end
		local list, seen = {}, {}
		for index, name in names do
			if type(index) ~= "number" or index < 1 or index > MAX_BULK or index % 1 ~= 0 or type(name) ~= "string" or #name > 64 then
				return false, Msg("Srv.InvalidParams")
			end
			if not seen[name] then
				seen[name] = true
				table.insert(list, name)
			end
		end
		if #list == 0 then
			return false, Msg("Srv.InvalidParams")
		end
		local global = column == Ranks.FeatureColumn
		if not global and not Ranks.ById[column] then
			return false, Msg("Srv.UnknownRank")
		end
		if global and not canToggle(admin) then
			return false, toggleOnly()
		end
		-- un décochage groupé ne retire jamais l'accès au panneau ni aux Paramètres (à faire ligne par ligne)
		local bulkOff = #list > 1 and not allowed
		-- Warm only the owner sources needed by critical columns; validation below never yields.
		if not global and not bulkOff then
			for _, name in list do
				if name == "APM.AccessPanel" or name == "APM.ManagePermissions" then Ranks.PreparePermissionChange(admin, name) end
			end
		end
		local function permitted(name)
			if Ranks.ProtectedFeatures[name] and (global or bulkOff) then
				return false
			end
			if global then
				return canToggle(admin) and Ranks.IsFeature(name)
			end
			return Ranks.Defaults[name] ~= nil and Grades.CanChangeColumn(admin, name, column)
		end
		local accepted = {}
		for _, name in list do
			if permitted(name) then
				table.insert(accepted, name)
			end
		end
		if #accepted == 0 then
			return false, global and text("Rien à changer : fonctionnalités protégées ou inconnues.", "Nothing to change: protected or unknown features.") or Msg("Srv.ColumnTooHigh")
		end
		local success, message, count = Ranks.SetAccessBulk(accepted, column, allowed, permitted)
		if not success then
			return false, message
		end
		local target = #accepted == 1 and accepted[1] or ("%s +%d"):format(accepted[1], #accepted - 1)
		ctx.Log(admin.Name, global and "SetFeature" or "SetModuleAccess", target,
			Msg("Log.AccessSet", global and "Settings.Active" or ("Rank." .. column), allowed and "Common.Yes" or "Common.No"), "Access", "danger")
		local skipped = #list - count
		local saved = Lang.Phrase({fr="%d réglage(s) enregistré(s).",en="%d setting(s) saved."}, count)
		local ignored = skipped > 0 and Lang.Phrase({fr=" %d ignoré(s) : protégé(s) ou hors de ta portée.",en=" %d skipped: protected or out of your reach."}, skipped) or ""
		return true, Lang.Phrase({fr="%s%s",en="%s%s"}, saved, ignored), count
	end

	return api
end

return Features
