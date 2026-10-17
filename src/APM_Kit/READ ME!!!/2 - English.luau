--[==[

	APM | Admin Panel - Modular — FULL GUIDE (ENGLISH)
	Version 2.10.2 (stable) · MIT license · Free · Made by APM contributors
	=====================================================================================================

	APM is an admin panel that helps developers run their experience: moderation, ranks, security, statistics
	and fun effects. Everything is re-checked by the server, and nothing is sent to players who have no access.

	CONTENTS
		1. Installation
		2. Panel languages
		3. Configuration
		4. Systems
		5. Modules
		6. Extensions (for developers)
		7. Updates and help


	=====================================================================================================
	1. INSTALLATION
	=====================================================================================================

	1) Insert APM_Kit from the Toolbox (Workspace or ServerScriptService both work).
	   Don't put it alone in ServerStorage: scripts don't run there.
	2) Keep the ToolboxBootstrap script enabled (RunContext: Server). On start it automatically moves the kit
	   into ServerStorage and starts a private loader in ServerScriptService.
	   The Installer and APM_Bootstrap scripts stay disabled: they are only for a manual installation.
	3) Give yourself a rank in the active ServerSettings file (see section 3), then add your UserId:
			Settings.Users = { [123456789] = "Owner" }
	   Your UserId is in your profile address: roblox.com/users/<UserId>/profile
	   No account receives a rank by default. Replace 123456789 with your own UserId in this active file.
	4) Press Play. Click the small "APM" button at the top of the screen or press F2 to open the panel.
	   Z recenters the window. In Home you can hide the button and pick another key.
	5) Saving: published games use DataStores. Studio uses memory mode by default (Settings.StudioMemory = true):
	   changes stay in this session. To test DataStores in Studio, set Settings.StudioMemory = false in active ServerSettings
	   AND enable "Enable Studio Access to API Services" in Game Settings > Security. Those tests can write to real saves.

	Good to know
	• The APM button checks 16 spots around the screen so it doesn't hide your UI; if every spot is taken,
	  it sits on top at the bottom left.
	• When the panel is open, it automatically goes in front of every game UI.
	• No code is downloaded, no script is edited while the game runs, nothing is published automatically.


	=====================================================================================================
	2. PANEL LANGUAGES
	=====================================================================================================

	7 languages: français (fr), English (en), español (es), português (pt), Deutsch (de), русский (ru), 中文 (zh).
	• By default, each admin sees the panel in their Roblox account language.
	• The language button at the top of the panel (e.g. "EN v") lets you pick another one; the choice is saved.
	• Players see announcements, warnings and mute messages in their own language.
	• In SharedConfig:
			Config.ForceLanguage = "en"     -- same language for everyone (nil = account language)
			Config.DefaultLanguage = "en"   -- fallback language
	• Translations: APM_Core > Shared > Lang > Tabs (one module per tab, all languages inside). The Lang > <language> and Lang > Phrases modules remain available for your own texts.


	=====================================================================================================
	3. CONFIGURATION
	=====================================================================================================

	Edit only APM_Extensions > Config in the active folder. If ServerStorage.APM_Extensions already exists,
	it takes priority over APM_Kit.APM_Extensions; otherwise start with the kit folder. Home and Diagnostics show the
	active SourcePath and warn about duplicate configurations: edit the indicated file first. Never modify APM_Core;
	updates replace it.
	The defaults, commented line by line, are in APM_Core > Server > Settings and APM_Core > Shared > Config.
	To change a value, copy its line into your file: it replaces the default.
	• a table (e.g. Settings.Funny = { MaxDuration = 30 }) only replaces the keys you write;
	• a list (Ranks, ClientTools, ToolSources) is replaced as a whole;
	• Settings.RemoveKeys = { "Key" } removes a default value.

	ServerSettings (read by the server only)
		Ranks               ranks, highest first (Id, Level, Color, Fixed, Name)
		SuperRank           "Dev": configurable access, nobody can target it
		ManagerRank         "Owner": minimum for the Settings tab
		AnnounceRank        "Staff": can make a server-wide announcement
		CreatorRank         nil by default: no automatic rank. Explicitly enable "Owner" only for the owner of this experience (or its group), never for the APM author.
		                    To enable this option, also remove "CreatorRank" from Settings.RemoveKeys, then set Settings.CreatorRank = "Owner".
		Users               FIXED ranks by UserId (take priority, can't be changed from the panel)
		DefaultUsers        starting ranks (can be changed later in the panel)
		Group               { Id = group, Ranks = { [minimum rank in the group] = "Rank" } }
		StudioRank          optional Studio test rank (nil by default: no automatic rank); no effect online
		DataStoreName       "APM_Data_v1": a single DataStore for all of APM (changing it starts from scratch)
		MessagingTopic      sync of permissions and bans between servers
		MaxLogs / MaxRoster / MaxWarnings   300 / 20000 / 25
		ToolSources         folders searched for Tools by "Give a tool" (ServerStorage by default)
		PermissionDefaults  default minimum rank of each named permission (APM.*, Sentinel.*, Funny.*...)
		Modules             turn off an optional system: { Simulation, AutoBridge, Sentinel, Funny, Assistant }
		Funny               { MaxDuration = 60, MaxActiveScenes = 16, MaxGroupTargets = 8, CrossServerEnabled = true }
		ClientTools         admin player tools: { "Fly", "Noclip", "ESP", "Spectator" }
		DisabledCommands    remove a command: { Kill = true }
		AutoBridge          { Enabled, ScanInterval = 30, MaxScanInstances = 1500, EnableTeamActions = false }
		Sentinel            { Enabled, Mode = "Observation", Interval = 1, CorrectPosition = false, AllowKick = false }
		Assistant           { Enabled, MaxHistory = 40, ReplyStyle = "Short", ConfirmDangerous, AllowAll, MaxAllTargets = 25, RatePerWindow = 8, DefaultDeployed, WaveEnabled, WaveInterval = 30, AnimationSpeed, External = { Enabled = false, Hosts = {}, SecretName, ApiKey, Model } }  -- Sentinel 2.10.2

	SharedConfig (read by the server AND clients: nothing secret)
		ForceLanguage, DefaultLanguage, OpenKey (F2), RecenterKey (Z), Title, Theme (color by color),
		LauncherButton, MobileButton, LanguageButton


	=====================================================================================================
	4. SYSTEMS
	=====================================================================================================

	RANKS
	• Default: Dev (5) > Owner (4) > CoOwner (3) > Staff (2) > StaffTest (1).
	• An admin only acts on a STRICTLY lower rank; Dev can never be targeted.
	• An account's rank is the HIGHEST of its sources: Users, creator, panel / DefaultUsers, group, Studio.
	• "Fixed" ranks are only given in the configuration, never from the panel.
	• The rank list shows its source and the rank that would remain after removing a panel assignment.
	  Removing an assignment does not revoke fixed or group access; the actual owner has a separate Revoke access action.

	FEATURES AND ACCESS (Settings tab)
	• All of APM, by category. The "Active" column turns a feature on or off for the whole game; the rank
	  columns choose who can use it. A category row checks everything at once.
	• Dev follows the default MinRank and saved access choices for its rank, like the other ranks.
	• Orange = mixed; greyed = out of your reach. Panel and Settings access are never removed in bulk.
	• Changes are saved and synced to every server (MessagingService).

	SECURITY (Security tab)
	• Permanent permissions, commands and tools are configured together in Settings > Features and access,
	  with search. Security opens that same editor.
	• Test a lower rank for five minutes. Choose test permissions with checkboxes; JSON is an advanced option.
	  Only permissions held by your real rank can be selected. Restore real rank using the button or /apm-restore;
	  if the panel disappears, use the dedicated recovery button.
	• Rank simulation: test the panel as a lower rank for 5 minutes; /apm-restore in chat gives your real
	  rank back immediately.
	• Security model: each admin gets their own private remotes; the server re-checks rank, access, hierarchy,
	  values and spam on every request. A player without a rank receives neither the panel, nor the button,
	  nor any admin remote: only the public display of announcements, warnings and mutes.

	SAVING
	• A single DataStore (APM_Data_v1): ranks, access matrix, bans, warnings, log and player directory.
	• Writes are limited to save budget: the directory is saved in batches (about every 5 minutes), preferences
	  only when they change.
	• Without DataStores (Studio without API access): memory mode, nothing is saved.

	HOME
	• Server status, performance (depending on your permissions), connected players with search and detailed
	  cards, AutoBridge, Sentinel and diagnostics summaries. Refreshes every 15 s while Home is visible.
	• Opening the panel: show / hide the discreet button, change the key.

	STATISTICS (Statistics tab)
	• Charts: panel usage, players, server performance (heartbeat, memory, network) and the busiest DataStores.
	  One point every 15 s, kept in the server's memory (nothing is saved).
	• To track YOUR game's DataStores (server script):
			local ServerStorage = game:GetService("ServerStorage")
			local core = ServerStorage:WaitForChild("APM_Core", 10)
			local server = core and core:WaitForChild("Server", 10)
			local service = server and server:WaitForChild("APMService", 10)
			assert(service and service:IsA("ModuleScript"), "APMService unavailable.")
			local APM = require(service)
			APM.WaitForReady()
			local DataStoreService = game:GetService("DataStoreService")
			local store = APM.TrackDataStore(DataStoreService:GetDataStore("PlayerData"), "PlayerData")
			-- then use store as usual (GetAsync, SetAsync, UpdateAsync...)

	LOG (Logs tab)     • Every admin action is recorded (300 entries), with category and severity filters.
	BANS               • Ban a connected player or an offline account (exact username or UserId), timed or
	                     permanent, applied on every server; unban in the Bans tab.
	SERVER LOCK        • Stops players without a rank from joining this server; maintenance uses it.

	SENTINEL GUARD (anti-cheat)
	• Watches abnormal speeds and teleports on the server, with tolerances (latency, spawn, seats, physics).
	  Modes: Observation (default), Balanced, Strict.
	• By default it only REPORTS to admins. Position correction: optional. Automatic kick: only if
	  Settings.Sentinel.AllowKick = true. Synthetic diagnostic to test without a real player.
	• Settings source shows the effective value, the script value, and saved or Studio-session overrides.
	  Return to script values removes saved overrides, including panel-added safe zones, and restores script values
	  immediately; script safe zones remain.

	AUTOBRIDGE (integrations)
	• Detects what your game already uses: leaderstats, teams, tools, vehicle seats.
	• Never runs unknown code. Team changes are off by default (EnableTeamActions).
	• In Home > Integrations and settings, inspect each effective value and its source.
	  Return to script values removes saved overrides and immediately restores the script values.

	FUNNY (fun effects, Funny tab)
	• ① Pick an effect in the grid (3D preview next to it), then ▶ START; ② set energy, duration, reach and targets.
	• Scenes: confetti, disco, ducks, bubbles, royal potato, solar system, snow, hearts, fireworks, rainbow.
	• Transformations: big head, Roblox account skin, copy/swap a body part, reverse gravity, upside-down
	  character (the player keeps control of their movement).
	• Reach: Local, Server, Cross-server. Everything is temporary, targets are protected by their rank,
	  the look is restored at the end and a stop button is always available.

	DIAGNOSTICS: Home and Diagnostics show the active configuration and duplicate warning. Extension diagnostics include
	SourcePath, the invalid field, received value, expected value and how to fix it.


	SENTINEL (floating command assistant) and SENTINEL HELPER — new in 2.10.2
	(not to be confused with Sentinel Guard, the anti-cheat above)
	• Sentinel is a small movable window, independent from the panel: it stays on screen when the APM is closed.
	  Type a command (fly, freeze bob, bring bob, speed bob 50, unfly me, kick bob spam...). It is a LOCAL rules-based
	  engine, not a generative AI: no Internet connection is needed. help lists the commands you can use,
	  help <command> shows details, clear empties the history.
	• Commands are the APM's own: every module and client tool of the registry (Players, Moderation, Game, Bans, your extensions).
	  Targets: me, all, an exact username, a UserId or a partial name that matches ONE player (several matches:
	  Sentinel asks you to be more specific). Aliases: tp, vitesse, geler... (English and French).
	• Security: the client only sends text. The server checks identity, rank, permissions, hierarchy (protected ranks stay
	  protected), argument bounds and rate (8 commands / 10 s by default) with the same code as the panel buttons.
	  Sensitive commands (kick, ban, shutdown) ask for confirmation. No code is ever evaluated. "all" is refused for kick / ban.
	• fly / noclip / esp / spectate apply to YOU only (client tools): the server authorizes, your device applies and Sentinel
	  confirms only afterwards. speed / jump accept a player and all: speed bob 50, speed all 20.
	• Window: drag the header or the left grip; two independent arrows retract the discussion zone (top arrow) and the input
	  zone (side arrow); both retracted: a single arrow remains, not draggable, that restores everything.
	  Position and retraction are saved per account. The arrows' shade wave plays every 30 s (configurable, can be turned off).
	• Home: the Sentinel switch turns it on or off for your account (the APM can stay closed).
	• Sentinel Helper tab (Development group): my preferences (local) / server settings (everyone) / custom commands /
	  optional external AI / engine test / storage. Permissions: Assistant.Use (StaffTest), Assistant.Configure,
	  Assistant.Commands, Assistant.External (Owner). Settings are saved in the APM DataStore (SuiteSettings_v2, section
	  SentinelAssistant); Studio memory mode keeps them for the session only.
	• Custom commands are DATA (name, arguments, permission, one allowed action: reply with a text, teleport to a point, run
	  up to 5 existing commands). Never Lua code. Each step runs with the rights of whoever types it.
	• External AI (optional, off by default): requires Settings.Assistant.External in ServerSettings (Hosts = { "api.example.com" },
	  SecretName or ApiKey) and HTTP requests enabled. The key never reaches clients or the DataStore. The AI only sees the typed
	  text and command names; it proposes a command that YOU confirm and that the server validates like any other.
	• ServerSettings: Settings.Assistant = { Enabled, MaxHistory, ReplyStyle, ConfirmDangerous, AllowAll, MaxAllTargets, RatePerWindow,
	  DefaultDeployed, WaveEnabled, WaveInterval, AnimationSpeed, External = {...} }; Settings.Modules.Assistant = false turns it off.

	SENTINEL COMMAND LANGUAGES (7 languages) — multilingual recognition
	• Sentinel understands French, English, Spanish, Portuguese, German, Russian and Chinese at the same time. The language you type in is
	  INDEPENDENT from the panel language: French interface, then a command in Russian, then in Chinese, with no setting to change.
	  Every wording leads to ONE canonical action (the module name: Fly, Freeze, Kick...); permissions, protections, confirmations and
	  the log are exactly those of the English command. A translation never grants anything more.
	• Examples (all = Fly): fly · voler · volar · voar · fliegen · летать · 飞行 (飛行). Stop forms: unfly · arrêter de voler ·
	  dejar de volar · parar de voar · stopp fliegen · перестать летать · 停止飞行. Words can be mixed: "voler all", "fly tous".
	  Case, accents and full-width letters / spaces do not matter (é = e, ß = ss, ё = е, Ｆｌｙ = fly). Simplified and traditional Chinese
	  are listed one by one. No guessing: an unknown command stays unknown (suggestions only).
	• Target, three forms identical in every language:
	    – no target: a command that accepts a target applies to YOU (fly, unfly, noclip, speed 50...);
	    – a username: fly Bob (never translated or altered; a unique partial name is accepted, ambiguity is refused);
	    – all (tous, todos, alle, все, 所有人...): every allowed player, ALWAYS after a confirmation that names the canonical action,
	      the sense (off) and the number of players. An absent target is NEVER "all".
	  "me": me, moi, yo, eu, ich, я, 我... Commands that need a target (kick, freeze, bring...) keep it mandatory;
	  spectate keeps its meaning (watch a player, local); esp stays local.
	• Confirmations: every "all" now asks for confirmation (even with ConfirmDangerous = false). It is tied to the CANONICAL action, its sense
	  and the players actually resolved: another command, another sense, another list of players or an expired token (20 s) asks again.
	• A reserved word that is also the name of a player present (a player named All, Ich, On...) is never guessed: Sentinel asks you to be
	  precise with @UserId (or @name; @me and @all remain the selectors).
	• Replies follow the APM language settings, not the language you typed.
	• Custom commands: their names stay ASCII; a name or alias already used by an official wording of ANY language is refused (the official
	  wording wins; conflicts are listed in Sentinel Helper > Storage). A step such as "fly all" still asks for confirmation.
	• Sentinel Helper > "Command languages": official wordings per language (read-only); the engine test shows the recognized language,
	  the canonical action, the sense, the target and whether a confirmation is required.
	• Developers: wordings live in Server > Core > Assistant > CommandLocalization (one ModuleScript per language: Commands, Off, OffPrefixes,
	  Selectors, Booleans, Units, Local, Choices). Adding an 8th language = adding a child ModuleScript named after its code (same shape as fr / en),
	  nothing else to change. A wording that would designate two actions is excluded and reported (Report().Collisions); a wording shared by two
	  languages for the SAME action is normal.
	• Limits: structured commands only (no free-sentence understanding); in Chinese a space separates the command and its arguments; a word that is a
	  selector or on / off in one language is reserved in all; decimals "1,5" are accepted, "1,000" is refused (ambiguous).

	=====================================================================================================
	5. MODULES
	=====================================================================================================

	Each module can be turned off or limited to some ranks in Settings > Features and access.

	PLAYERS TAB (pick a player, then the action)
		Kick · Ban · Warn · Mute · Freeze · Kill · Heal · Respawn · Bring · Go to (Teleport)
		Send back (Return) · To spawn (ToSpawn)
		Reason and duration (minutes, empty = permanent) for Kick, Ban, Warn, Mute and Freeze.
		"Global" view: directory of every account that has ever joined, even offline.

	MODERATION TAB (on yourself)
		Godmode (infinite health) · Invisible · Walk speed · Jump power
		Tools: Fly, Noclip (walk through walls), ESP (see players through walls), Spectator (watch a player)
		Server-wide announcement.

	GAME TAB
		Give a tool (GiveTool) · Leaderstats (change a value) · Time of day (TimeOfDay)
		Server maintenance (Shutdown): locks, announces and kicks players without a rank after the delay.

	BANS TAB
		Ban list, Unban, ban an account by exact username or UserId.


	=====================================================================================================
	6. EXTENSIONS (FOR DEVELOPERS)
	=====================================================================================================

	Add extensions to the active APM_Extensions folder. APM_DeveloperTemplates is inactive: start with START_HERE
	and copy only the required examples into the matching active folders.
	• Commands.MonJeu.MonJeu_Informer: copy the MonJeu folder into Commands.
	• ClientPages.MonJeu.MonJeuPage: copy MonJeu into ClientPages.
	• Server.MonJeuIntegration and Adapters.MonJeuStatus: copy each ModuleScript into its matching folder.
	Choose a unique command name and namespace. Permissions are never added automatically: declare MonJeu.Page /
	MonJeu.Status explicitly in active ServerSettings.PermissionDefaults with your chosen minimum rank.
	Restart Play after changing source or configuration.

	A) A command: a ModuleScript in APM_Extensions > Commands
		return {
			ApiVersion = 1,
			Name = "Confetti",               -- unique id (letters, digits, _ - .)
			Category = "Players",            -- Players, Moderation, Game... or your own category
			Mode = "target",                 -- "action" | "target" (one player) | "toggle" | "slider"
			MinRank = "Staff",               -- default minimum rank
			Label = { fr = "Confettis", en = "Confetti" },
			Description = { fr = "Lance des confettis.", en = "Throws confetti." },
			-- optional: Group, Order, Color, Confirm, AllowSelf, Min / Max / Default (slider),
			--           Fields = { { Name = "Amount", Type = "number", Min = 1, Max = 100 } },
			--           Inputs = { "Reason", "Minutes" }, Init = function(ctx) end, OnAccessRevoked = function(ctx, player) end
			Execute = function(ctx, admin, target, value)
				-- the server has already checked rank, access, hierarchy and values
				return true, "Confetti thrown!"   -- (success, message shown to the admin)
			end,
		}
		Field types: "number", "choice" (Options), "text", "string". Every run is written to the log.

	B) A server integration: a ModuleScript in APM_Extensions > Server
		return { ApiVersion = 1, Id = "MyGame", Init = function(api)
			-- api.RegisterCommand(command), api.RegisterOptions(name, provider), api.AddProfileProvider(fn),
			-- api.RegisterAdapter(name, adapter), api.HasPermission(player, permission), api.CanTarget(admin, target),
			-- api.Authorize(admin, command, target), api.Notify(player, message, success), api.Log(actor, action, target, detail)
		end }
	Register commands synchronously in Init(api), before any deferred task, and check registration results.
	Do not call APM.WaitForReady() inside Init: APM is already waiting for that initialization to finish.

	C) An AutoBridge adapter: APM_Extensions > Adapters  →  { ApiVersion = 1, Id = "...", Adapter = { Permission, Probe, Actions } }
	D) A panel page: APM_Extensions > ClientPages > MonJeu > MonJeuPage (ModuleScript inside its namespace folder).
	   Keep ModuleScript attributes ApiVersion = 1 and Permission = "MonJeu.Page". Declare
	   Settings.PermissionDefaults = { ["MonJeu.Page"] = "Owner" } explicitly in active ServerSettings; choose your minimum rank.
	   Return a table with ApiVersion = 1, the same Permission, a unique valid Id = "MonJeuPage", and Build(Core, page).
	   Label and Order are optional; Visible(Core) is optional. Handles may list only categories owned by this namespace.
	   Ids use letters, digits, _, . or - and must not collide with APM ids.
	   Use APM_DeveloperTemplates.ClientPages.MonJeu.MonJeuPage as the working example. A page is sent only to authorized
	   admins. Never put secrets in client code. Use Core.On(signal, callback) for connections and
	   Core.Action(command, target, value) for authorized server commands.

	E) From your other server scripts:
		local ServerStorage = game:GetService("ServerStorage")
		local core = ServerStorage:WaitForChild("APM_Core", 10)
		local server = core and core:WaitForChild("Server", 10)
		local service = server and server:WaitForChild("APMService", 10)
		assert(service and service:IsA("ModuleScript"), "APMService unavailable.")
		local APM = require(service)
		APM.WaitForReady()
		APM.IsAdmin(player)  APM.GetRank(player)  APM.HasRankAtLeast(player, "Staff")
		APM.Notify(player, text, success)  APM.Log(actor, action, target, detail, category, "info"|"warning"|"danger")
		APM.AddProfileProvider(fn)  APM.RegisterOptions(name, fn)  APM.TrackDataStore(store, "Name")

	Extension status (loaded / errors) is shown in the Diagnostics tab.


	=====================================================================================================
	7. UPDATES AND HELP
	=====================================================================================================

	• Updating: replace APM_Kit with the new version. Keep your APM_Extensions folder: a compatible external
	  ServerStorage.APM_Extensions configuration is kept and takes priority. Never edit APM_Core.
	• The panel won't open? Check your rank (Settings.Users), that ToolboxBootstrap is enabled and that the kit
	  isn't alone in ServerStorage. The Output shows "[APM] Serveur prêt" (server ready) when everything is fine.
	• Stuck in a rank simulation? Type /apm-restore in chat.
	• "Memory mode" shown? Normal in Studio: nothing is saved during your tests.


	CHANGELOG 2.10.2
	• NEW: Sentinel, floating command assistant (movable, two independent retract arrows, ultra-compact mode).
	• NEW: Sentinel Helper tab (preferences, server settings, custom commands, optional external AI, engine test).
	• NEW: Home switch to turn Sentinel on or off; preferences saved per account (position, retraction, size, animation).
	• NEW: permissions Assistant.Use / Configure / Commands / External; "Sentinel (assistant)" category in Features and access.
	• NEW: speed and jump accept a target (speed bob 50); freeze and mute expose their state (never toggled by mistake).
	• CHANGE: APMService.perform is the shared execution core of panel buttons and Sentinel (same checks, same log).
	• CHANGE: Preferences accept 4 personal fields (AssistantEnabled, AssistantLayout, AssistantWave, AssistantScale); SuiteConfig accepts the SentinelAssistant section.
	• NEW: distributed actions (Dispatcher + ActionExecutor): Fly and Noclip now apply to other players ("fly bob", "fly all", "unfly bob", "noclip bob"), validated by the server, executed on the target's own device and confirmed by it.
	• NEW: every distributed action is checked by the server (rank, tool permission, hierarchy: "all" never bypasses a protection), carries a unique id with expiry, and ends with a figure-based report (affected, protected, failed, unconfirmed). A client reply is a confirmation, never absolute proof: the server verifies what it can (Fly: Humanoid state; Noclip: collisions).
	• NEW: Players tab, "Powers on the player" card (toggle on the selected player, "everyone" buttons with confirmation); "spectate bob" watches a player; "esp bob" is refused on purpose (ESP is a local view, never given to another player).
	• CHANGE: Fly and Noclip share ONE controller (APM_Shared > ActionExecutor > Effects) between the panel switch and the server: no duplicates. New remotes: ActionDispatch / ActionReport (public, replies only), DispatchAction (admin panel).
	• CHANGE: "all" on a server command reports "Freeze: 8 affected, 2 protected, 0 failed, 1 skipped".
	• Developers: adding a distributed action = declare it in ActionCatalog + a controller in ActionExecutor/Effects (+ optional Dispatcher/Hooks); Settings.Modules.Dispatcher = false disables it. Nothing is saved: effects end when the player leaves.
	• No data migration: DataSchemaVersion stays 2; existing configurations and saves are untouched.
	• NEW: multilingual Sentinel: commands in French, English, Spanish, Portuguese, German, Russian and Chinese at the same time, independent from the interface language; one canonical action, same permissions, protections and confirmations.
	• NEW: implicit target: "fly", "unfly", "noclip" act on you; "fly Bob" targets a player; "fly all" (and its translations) always asks for confirmation.
	• CHANGE: any "all" target is confirmed (kill, freeze, mute, heal, respawn, bring, speed, jump, fly, noclip), even with ConfirmDangerous = false; the confirmation is bound to the canonical action and the resolved players.
	• CHANGE: a reserved word that is also the name of a present player (All, Ich, On...) is ambiguous: use @UserId.
	• NEW: "Command languages" card in Sentinel Helper, richer engine test; Unicode normalization (Cyrillic, Chinese, full-width, accents); length in characters (200), not bytes.
	• Developers: CommandLocalization (one ModuleScript per language); an 8th language = one more ModuleScript.

	• NEW: Sentinel "help" now opens an interactive catalog: ALL the commands of the registry in a 3-column grid. A command you may not run shows a padlock (computed by the server; it grants nothing). Touching a command only PREPARES it in the input field (never executed).
	• NEW: autocomplete: commands and aliases (7 languages), players (username, display name, @UserId), selectors, on/off and durations valid for the command; arrows to browse, Tab to complete, Enter submits (or completes a suggestion you selected with the arrows), Esc closes. Only registered commands you may use are suggested; computed locally, no request per keystroke.
	• NEW: durations: 10s · 5m · 2h · 1d (and their translations). A duration a command cannot honour is refused with a message: ban works in whole minutes (30s and 0.5 are refused instead of becoming a permanent ban); an unknown format (1w) is never swallowed into the reason.
	• FIX: Home and Sentinel Helper now read the same state: switching Sentinel off from Home is immediately shown in Sentinel Helper (and the other way round); closing the APM never changes it.
	• CHANGE: the retract arrow of the input zone follows the window position (left half: retracts to the left; right half: to the right); arrows have a discreet dark chip so they stay visible on bright backgrounds.

	MIT license · Free · Made by APM contributors

]==]
return {}
