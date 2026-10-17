--[==[

	APM | Admin Panel - Modular — VOLLSTÄNDIGE ANLEITUNG (DEUTSCH)
	Version 2.10.2 (stabil) · MIT-Lizenz · Kostenlos · Erstellt von APM contributors
	=====================================================================================================

	APM ist ein Admin-Panel, das Entwicklern hilft, ihre Experience zu verwalten: Moderation, Ränge, Sicherheit,
	Statistiken und lustige Effekte. Der Server prüft alles erneut, und Spieler ohne Zugriff erhalten nichts.

	INHALT
		1. Installation
		2. Sprachen des Panels
		3. Konfiguration
		4. Systeme
		5. Module
		6. Erweiterungen (für Entwickler)
		7. Updates und Hilfe


	=====================================================================================================
	1. INSTALLATION
	=====================================================================================================

	1) Füge APM_Kit aus der Toolbox ein (Workspace oder ServerScriptService funktionieren beide).
	   Lege es nicht allein in ServerStorage: Dort starten keine Skripte.
	2) Lass das Skript ToolboxBootstrap aktiviert (RunContext: Server). Beim Start verschiebt es das Kit automatisch
	   nach ServerStorage und startet einen privaten Lader in ServerScriptService.
	   Die Skripte Installer und APM_Bootstrap bleiben deaktiviert: Sie dienen nur einer manuellen Installation.
	3) Gib dir in der aktiven ServerSettings-Datei einen Rang (siehe Abschnitt 3) und füge dann deine UserId hinzu:
			Settings.Users = { [123456789] = "Owner" }
	   Deine UserId steht in der Adresse deines Profils: roblox.com/users/<UserId>/profile
	   Standardmäßig erhält kein Konto einen Rang. Ersetze 123456789 durch deine eigene UserId in dieser aktiven Datei.
	4) Drücke Play. Klicke oben auf den kleinen „APM“-Knopf oder drücke F2, um das Panel zu öffnen.
	   Z zentriert das Fenster. Unter Start kannst du den Knopf ausblenden und eine andere Taste wählen.
	5) Speicherung: Veröffentlichte Spiele verwenden DataStores. Studio verwendet standardmäßig den Arbeitsspeichermodus
	   (Settings.StudioMemory = true): Änderungen bleiben nur in dieser Sitzung. Um DataStores in Studio zu testen,
	   setze Settings.StudioMemory = false in der aktiven ServerSettings-Datei UND aktiviere "Enable Studio Access to API Services"
	   unter Spieleinstellungen > Sicherheit. Diese Tests können in echte gespeicherte Daten schreiben.

	Gut zu wissen
	• Der APM-Knopf prüft 16 Stellen am Bildschirmrand, um deine Oberfläche nicht zu verdecken; sind alle belegt,
	  liegt er unten links darüber.
	• Ist das Panel geöffnet, liegt es automatisch vor allen Oberflächen des Spiels.
	• Es wird kein Code heruntergeladen, kein Skript während des Spiels geändert und nichts automatisch veröffentlicht.


	=====================================================================================================
	2. SPRACHEN DES PANELS
	=====================================================================================================

	7 Sprachen: français (fr), English (en), español (es), português (pt), Deutsch (de), русский (ru), 中文 (zh).
	• Standardmäßig sieht jeder Admin das Panel in der Sprache seines Roblox-Kontos.
	• Mit dem Sprachknopf oben im Panel (z. B. „DE v“) wählst du eine andere; die Wahl wird gespeichert.
	• Spieler sehen Ankündigungen, Verwarnungen und Stummschaltungen in ihrer eigenen Sprache.
	• In SharedConfig:
			Config.ForceLanguage = "de"     -- gleiche Sprache für alle (nil = Sprache des Kontos)
			Config.DefaultLanguage = "en"   -- Ersatzsprache
	• Übersetzungen: APM_Core > Shared > Lang > Tabs (ein Modul pro Tab, alle Sprachen darin). Die Module Lang > <Sprache> und Lang > Phrases bleiben für eigene Texte verfügbar.


	=====================================================================================================
	3. KONFIGURATION
	=====================================================================================================

	Bearbeite nur APM_Extensions > Config im aktiven Ordner. Wenn ServerStorage.APM_Extensions bereits existiert,
	hat er Vorrang vor APM_Kit.APM_Extensions. Verwende andernfalls den Ordner aus dem Kit. Start und Diagnose zeigen den
	aktiven SourcePath und warnen vor mehrfach vorhandenen Konfigurationen: Bearbeite zuerst die angegebene Datei.
	Ändere niemals APM_Core; Updates ersetzen diesen Ordner.
	Die Standardwerte, Zeile für Zeile kommentiert, stehen in APM_Core > Server > Settings und APM_Core > Shared > Config.
	Um einen Wert zu ändern, kopiere seine Zeile in deine Datei: Sie ersetzt den Standardwert.
	• eine Tabelle (z. B. Settings.Funny = { MaxDuration = 30 }) ersetzt nur die angegebenen Schlüssel;
	• eine Liste (Ranks, ClientTools, ToolSources) wird komplett ersetzt;
	• Settings.RemoveKeys = { "Schlüssel" } entfernt einen Standardwert.

	ServerSettings (nur vom Server gelesen)
		Ranks               Ränge, vom höchsten zum niedrigsten (Id, Level, Color, Fixed, Name)
		SuperRank           "Dev": konfigurierbarer Zugriff, niemand kann ihn als Ziel wählen
		ManagerRank         "Owner": Minimum für den Tab Einstellungen
		AnnounceRank        "Staff": darf eine Ankündigung an den ganzen Server senden
		CreatorRank         standardmäßig nil: kein automatischer Rang. Aktiviere "Owner" ausdrücklich nur für den Besitzer dieser Experience (oder ihrer Gruppe), niemals für den APM-Autor.
		                    Entferne dazu auch "CreatorRank" aus Settings.RemoveKeys und setze Settings.CreatorRank = "Owner".
		Users               FESTE Ränge pro UserId (haben Vorrang, im Panel nicht änderbar)
		DefaultUsers        Start-Ränge (später im Panel änderbar)
		Group               { Id = Gruppe, Ranks = { [Mindestrang in der Gruppe] = "Rang" } }
		StudioRank          optionaler Studio-Testrang (standardmäßig nil: kein automatischer Rang); online ohne Wirkung
		DataStoreName       "APM_Data_v1": ein einziger DataStore für ganz APM (Ändern beginnt bei null)
		MessagingTopic      Synchronisierung von Rechten und Banns zwischen Servern
		MaxLogs / MaxRoster / MaxWarnings   300 / 20000 / 25
		ToolSources         Ordner, in denen „Werkzeug geben“ nach Tools sucht (standardmäßig ServerStorage)
		PermissionDefaults  Standard-Mindestrang jeder benannten Berechtigung (APM.*, Sentinel.*, Funny.*...)
		Modules             ein optionales System abschalten: { Simulation, AutoBridge, Sentinel, Funny, Assistant }
		Funny               { MaxDuration = 60, MaxActiveScenes = 16, MaxGroupTargets = 8, CrossServerEnabled = true }
		ClientTools         Werkzeuge des Admins: { "Fly", "Noclip", "ESP", "Spectator" }
		DisabledCommands    einen Befehl entfernen: { Kill = true }
		AutoBridge          { Enabled, ScanInterval = 30, MaxScanInstances = 1500, EnableTeamActions = false }
		Sentinel            { Enabled, Mode = "Observation", Interval = 1, CorrectPosition = false, AllowKick = false }
		Assistant           { Enabled, MaxHistory = 40, ReplyStyle = "Short", ConfirmDangerous, AllowAll, MaxAllTargets = 25, RatePerWindow = 8, DefaultDeployed, WaveEnabled, WaveInterval = 30, AnimationSpeed, External = { Enabled = false, Hosts = {}, SecretName, ApiKey, Model } }  -- Sentinel 2.10.2

	SharedConfig (vom Server UND den Clients gelesen: nichts Geheimes)
		ForceLanguage, DefaultLanguage, OpenKey (F2), RecenterKey (Z), Title, Theme (Farbe für Farbe),
		LauncherButton, MobileButton, LanguageButton


	=====================================================================================================
	4. SYSTEME
	=====================================================================================================

	RÄNGE
	• Standard: Dev (5) > Owner (4) > CoOwner (3) > Staff (2) > StaffTest (1).
	• Ein Admin wirkt nur auf einen STRIKT niedrigeren Rang; Dev kann nie Ziel sein.
	• Der Rang eines Kontos ist der HÖCHSTE seiner Quellen: Users, Ersteller, Panel / DefaultUsers, Gruppe, Studio.
	• „Fixed“-Ränge werden nur in der Konfiguration vergeben, nie im Panel.
	• Die Rangliste zeigt die Quelle und den Rang, der nach dem Entfernen einer Panel-Zuweisung bestehen bleibt.
	  Dies entzieht keine festen oder gruppenbasierten Rechte; der tatsächliche Eigentümer hat eine separate Aktion zum Entziehen des Zugriffs.

	FUNKTIONEN UND ZUGRIFF (Tab Einstellungen)
	• Ganz APM, nach Kategorie. Die Spalte „Aktiv“ schaltet eine Funktion für das ganze Spiel ein oder aus; die
	  Rangspalten legen fest, wer sie nutzen darf. Eine Kategoriezeile hakt alles auf einmal an.
	• Für Dev gelten der voreingestellte MinRank und die gespeicherten Zugriffsentscheidungen für seinen Rang, wie für andere Ränge.
	• Orange = gemischt; grau = außerhalb deiner Reichweite. Panel- und Einstellungszugriff werden nie gesammelt entfernt.
	• Änderungen werden gespeichert und auf allen Servern synchronisiert (MessagingService).

	SICHERHEIT (Tab Sicherheit)
	• Dauerhafte Berechtigungen, Befehle und Werkzeuge werden gemeinsam unter Einstellungen > Funktionen und Zugriff
	  mit Suchfunktion konfiguriert. Sicherheit öffnet denselben Editor.
	• Teste einen niedrigeren Rang für fünf Minuten. Wähle die Testberechtigungen über Kontrollkästchen;
	  JSON ist eine erweiterte Option. Du kannst nur Rechte auswählen, die du tatsächlich besitzt. Stelle deinen echten
	  Rang über die Schaltfläche oder /apm-restore wieder her; verschwindet das Panel, nutze die Wiederherstellungsschaltfläche.
	• Rangsimulation: Teste das Panel 5 Minuten lang als niedrigerer Rang; /apm-restore im Chat gibt dir
	  sofort deinen echten Rang zurück.
	• Sicherheitsmodell: Jeder Admin erhält eigene private Remotes; der Server prüft bei jeder Anfrage Rang, Zugriff,
	  Hierarchie, Werte und Spam. Ein Spieler ohne Rang erhält weder das Panel noch den Knopf noch ein Admin-Remote:
	  nur die öffentliche Anzeige von Ankündigungen, Verwarnungen und Stummschaltungen.

	SPEICHERN
	• Ein einziger DataStore (APM_Data_v1): Ränge, Zugriffsmatrix, Banns, Verwarnungen, Protokoll und Spielerverzeichnis.
	• Schreibvorgänge sind begrenzt, um Budget zu sparen: Das Verzeichnis wird gebündelt gespeichert (etwa alle 5 Minuten),
	  Einstellungen nur, wenn sie sich ändern.
	• Ohne DataStores (Studio ohne API-Zugriff): Speichermodus, nichts wird gespeichert.

	START
	• Serverstatus, Leistung (je nach Rechten), verbundene Spieler mit Suche und Detailkarten, Zusammenfassungen von
	  AutoBridge, Sentinel und Diagnose. Aktualisiert sich alle 15 s, wenn Start sichtbar ist.
	• Öffnen des Panels: unauffälligen Knopf zeigen / ausblenden, Taste ändern.

	STATISTIKEN (Tab Statistiken)
	• Diagramme: Panel-Nutzung, Spieler, Serverleistung (Takt, Speicher, Netzwerk) und die meistgenutzten DataStores.
	  Ein Messpunkt alle 15 s, im Speicher des Servers gehalten (nichts wird gespeichert).
	• Um die DataStores DEINES Spiels zu verfolgen (Server-Skript):
			local ServerStorage = game:GetService("ServerStorage")
			local core = ServerStorage:WaitForChild("APM_Core", 10)
			local server = core and core:WaitForChild("Server", 10)
			local service = server and server:WaitForChild("APMService", 10)
			assert(service and service:IsA("ModuleScript"), "APMService nicht verfügbar.")
			local APM = require(service)
			APM.WaitForReady()
			local DataStoreService = game:GetService("DataStoreService")
			local store = APM.TrackDataStore(DataStoreService:GetDataStore("PlayerData"), "PlayerData")
			-- dann store wie gewohnt benutzen (GetAsync, SetAsync, UpdateAsync...)

	PROTOKOLL (Tab Logs)  • Jede Admin-Aktion wird festgehalten (300 Einträge), mit Filtern nach Kategorie und Schwere.
	BANNS                 • Bann eines verbundenen Spielers oder eines Offline-Kontos (genauer Name oder UserId), befristet
	                        oder dauerhaft, auf allen Servern; Entbannen im Tab Banns.
	SERVERSPERRE          • Verhindert, dass Spieler ohne Rang diesem Server beitreten; die Wartung nutzt sie.

	SENTINEL GUARD (Anti-Cheat)
	• Beobachtet auf dem Server ungewöhnliche Geschwindigkeiten und Teleports, mit Toleranzen (Latenz, Spawn,
	  Sitze, Physik). Modi: Beobachtung (Standard), Ausgewogen, Streng.
	• Standardmäßig MELDET er nur an Admins. Positionskorrektur: optional. Automatischer Kick: nur wenn
	  Settings.Sentinel.AllowKick = true. Synthetische Diagnose zum Testen ohne echten Spieler.
	• Die Einstellungsquelle zeigt wirksame Werte, Skriptwerte und gespeicherte oder auf die Studio-Sitzung begrenzte Überschreibungen.
	  Die Rückkehr zu Skriptwerten entfernt gespeicherte Überschreibungen, einschließlich sicherer Zonen aus dem Panel,
	  und stellt die Skriptwerte sofort wieder her. Im Skript definierte sichere Zonen bleiben erhalten.

	AUTOBRIDGE (Integrationen)
	• Erkennt, was dein Spiel schon nutzt: leaderstats, Teams, Werkzeuge, Fahrzeugsitze.
	• Führt nie unbekannten Code aus. Teamwechsel ist standardmäßig aus (EnableTeamActions).
	• Prüfe unter Start > Integrationen und Einstellungen jeden wirksamen Wert und seine Quelle.
	  Die Rückkehr zu Skriptwerten entfernt gespeicherte Überschreibungen und stellt die Skriptwerte sofort wieder her.

	FUNNY (lustige Effekte, Tab Funny)
	• ① Wähle einen Effekt im Raster (3D-Vorschau daneben), dann ▶ STARTEN; ② stelle Energie, Dauer, Reichweite und Ziele ein.
	• Szenen: Konfetti, Disco, Enten, Blasen, königliche Kartoffel, Sonnensystem, Schnee, Herzen, Feuerwerk, Regenbogen.
	• Verwandlungen: großer Kopf, Skin eines Roblox-Kontos, Körperteil kopieren/tauschen, umgekehrte Schwerkraft,
	  Figur auf dem Kopf (der Spieler behält die Kontrolle über seine Bewegungen).
	• Reichweite: Lokal, Server, Serverübergreifend. Alles ist vorübergehend, Ziele sind durch ihren Rang geschützt,
	  das Aussehen wird am Ende wiederhergestellt und es gibt immer einen Stopp-Knopf.

	DIAGNOSE: Start und Diagnose zeigen die aktive Konfiguration und eine Warnung bei Duplikaten. Die Erweiterungsdiagnose
	enthält SourcePath, das ungültige Feld, den erhaltenen Wert, den erwarteten Wert und Hinweise zur Korrektur.


	SENTINEL (schwebender Befehlsassistent) und SENTINEL HELPER — neu in 2.10.2
	(nicht zu verwechseln mit Sentinel Guard, dem Anti-Cheat oben)
	• Sentinel ist ein kleines, verschiebbares Fenster, unabhängig vom Panel: Es bleibt sichtbar, wenn das APM geschlossen ist.
	  Gib einen Befehl ein (fly, freeze bob, bring bob, speed bob 50, unfly me, kick bob spam...). Es ist eine LOKALE regelbasierte
	  Engine, keine generative KI: Eine Internetverbindung ist nicht nötig. help listet die nutzbaren Befehle auf,
	  help <Befehl> zeigt Details, clear leert den Verlauf.
	• Die Befehle sind die des APM: jedes Modul und jedes Client-Werkzeug des Registers (Spieler, Moderation, Spiel, Banns, deine Erweiterungen).
	  Ziele: me, all, ein exakter Benutzername, eine UserId oder ein Teilname, der auf GENAU EINEN Spieler passt (mehrere Treffer:
	  Sentinel bittet um Präzisierung). Aliasse: tp, vitesse, geler... (Englisch und Französisch).
	• Sicherheit: Der Client sendet nur Text. Der Server prüft Identität, Rang, Berechtigungen, Hierarchie (geschützte Ränge bleiben
	  geschützt), Argumentgrenzen und Rate (standardmäßig 8 Befehle / 10 s) mit demselben Code wie die Panel-Schaltflächen.
	  Sensible Befehle (kick, ban, shutdown) verlangen eine Bestätigung. Es wird nie Code ausgewertet. all wird für kick / ban abgelehnt.
	• fly / noclip / esp / spectate betreffen nur DICH (Client-Werkzeuge): Der Server erlaubt, dein Gerät wendet an und Sentinel
	  bestätigt erst danach. speed / jump akzeptieren einen Spieler und all: speed bob 50, speed all 20.
	• Fenster: Kopfzeile oder linken Griff ziehen; zwei unabhängige Pfeile klappen den Gesprächsbereich (oberer Pfeil) und den
	  Eingabebereich (seitlicher Pfeil) ein; sind beide eingeklappt, bleibt ein einziger, nicht verschiebbarer Pfeil, der alles wiederherstellt.
	  Position und Einklappzustand werden pro Konto gespeichert. Die Schattierungswelle der Pfeile läuft alle 30 s (einstellbar, abschaltbar).
	• Start: Der Sentinel-Schalter aktiviert oder deaktiviert ihn für dein Konto (das APM kann geschlossen bleiben).
	• Reiter Sentinel Helper (Gruppe Entwicklung): meine Einstellungen (lokal) / Servereinstellungen (alle) / eigene Befehle /
	  optionale externe KI / Engine-Test / Speicher. Berechtigungen: Assistant.Use (StaffTest), Assistant.Configure,
	  Assistant.Commands, Assistant.External (Owner). Einstellungen liegen im APM-DataStore (SuiteSettings_v2, Abschnitt
	  SentinelAssistant); der Speichermodus von Studio behält sie nur für die Sitzung.
	• Eigene Befehle sind DATEN (Name, Argumente, Berechtigung, eine erlaubte Aktion: mit Text antworten, zu einem Punkt teleportieren,
	  bis zu 5 vorhandene Befehle ausführen). Nie Lua-Code. Jeder Schritt läuft mit den Rechten dessen, der ihn eingibt.
	• Externe KI (optional, standardmäßig aus): erfordert Settings.Assistant.External in ServerSettings (Hosts = { "api.beispiel.com" },
	  SecretName oder ApiKey) und aktivierte HTTP-Anfragen. Der Schlüssel erreicht nie Clients oder den DataStore. Die KI sieht nur den
	  eingegebenen Text und die Befehlsnamen; sie schlägt einen Befehl vor, den DU bestätigst und den der Server wie jeden anderen prüft.
	• ServerSettings: Settings.Assistant = { Enabled, MaxHistory, ReplyStyle, ConfirmDangerous, AllowAll, MaxAllTargets, RatePerWindow,
	  DefaultDeployed, WaveEnabled, WaveInterval, AnimationSpeed, External = {...} }; Settings.Modules.Assistant = false schaltet ihn ab.

	BEFEHLSSPRACHEN VON SENTINEL (7 Sprachen) — mehrsprachige Erkennung
	• Sentinel versteht gleichzeitig Deutsch, Englisch, Französisch, Spanisch, Portugiesisch, Russisch und Chinesisch. Die Sprache, in der du tippst, ist
	  UNABHÄNGIG von der Panelsprache: deutsche Oberfläche, Befehl auf Russisch und dann auf Chinesisch, ohne etwas umzustellen. Jede Formulierung führt zu
	  EINER kanonischen Aktion (dem Modulnamen: Fly, Freeze, Kick...); Berechtigungen, Schutzregeln, Bestätigungen und Protokoll sind genau die des englischen
	  Befehls. Eine Übersetzung gewährt nie etwas zusätzlich.
	• Beispiele (alle = Fly): fly · voler · volar · voar · fliegen · летать · 飞行 (飛行). Stopp-Formen: unfly · arrêter de voler · dejar de volar ·
	  parar de voar · stopp fliegen · перестать летать · 停止飞行. Mischen ist möglich: „fliegen all“, „fly alle“. Groß-/Kleinschreibung, Akzente und
	  Voll­breiten-Zeichen sind egal (é = e, ß = ss, ё = е, Ｆｌｙ = fly). Vereinfachtes und traditionelles Chinesisch werden einzeln aufgeführt.
	  Kein Raten: ein unbekannter Befehl bleibt unbekannt (nur Vorschläge).
	• Ziel, drei Formen, in allen Sprachen gleich:
	    – ohne Ziel: ein Befehl, der ein Ziel erlaubt, gilt für DICH (fly, unfly, noclip, speed 50...);
	    – ein Benutzername: fly Bob (nie übersetzt oder verändert; ein eindeutiger Namensanfang wird akzeptiert, Mehrdeutigkeit wird abgelehnt);
	    – all (alle, tous, todos, все, 所有人...): alle erlaubten Spieler, IMMER nach einer Bestätigung, die die kanonische Aktion, die Richtung (aus) und die
	      Anzahl der Spieler nennt. Ein fehlendes Ziel ist NIEMALS „all“.
	  „me“: ich, me, moi, yo, eu, я, 我... Befehle, die ein Ziel verlangen (kick, freeze, bring...), behalten diese Pflicht; spectate behält seine Bedeutung
	  (einen Spieler beobachten, lokal); esp bleibt lokal.
	• Bestätigungen: jedes „all“ verlangt jetzt eine Bestätigung (auch mit ConfirmDangerous = false). Sie ist an die KANONISCHE Aktion, ihre Richtung und die
	  tatsächlich aufgelösten Spieler gebunden: anderer Befehl, andere Richtung, andere Spielerliste oder abgelaufener Token (20 s) fragt erneut.
	• Ein reserviertes Wort, das zugleich der Name eines anwesenden Spielers ist (ein Spieler namens All, Ich, On...), wird nie erraten: Sentinel verlangt
	  Präzision mit @UserId (oder @Name; @me und @all bleiben die Selektoren).
	• Antworten folgen der Spracheinstellung des APM, nicht der getippten Sprache.
	• Eigene Befehle: ihre Namen bleiben ASCII; ein Name oder Alias, der schon von einer offiziellen Formulierung IRGENDEINER Sprache belegt ist, wird abgelehnt
	  (die offizielle Formulierung gewinnt; Konflikte stehen in Sentinel Helper > Speicher). Ein Schritt „fly all“ verlangt weiterhin eine Bestätigung.
	• Sentinel Helper > „Befehlssprachen“: offizielle Formulierungen je Sprache (nur lesen); der Engine-Test zeigt die erkannte Sprache, die kanonische Aktion,
	  die Richtung, das Ziel und ob eine Bestätigung nötig ist.
	• Entwickler: die Formulierungen liegen in Server > Core > Assistant > CommandLocalization (ein ModuleScript je Sprache: Commands, Off, OffPrefixes, Selectors,
	  Booleans, Units, Local, Choices). Eine 8. Sprache = ein weiteres ModuleScript mit dem Sprachcode als Namen (gleiche Form wie fr / en), sonst nichts ändern.
	  Eine Formulierung, die zwei Aktionen bezeichnen würde, wird ausgeschlossen und gemeldet (Report().Collisions); eine von zwei Sprachen für DIESELBE Aktion
	  geteilte Formulierung ist normal.
	• Grenzen: nur strukturierte Befehle (kein Verstehen freier Sätze); im Chinesischen trennt ein Leerzeichen Befehl und Argumente; ein Wort, das in einer Sprache
	  Selektor oder on / off ist, ist in allen reserviert; Dezimalzahlen „1,5“ werden akzeptiert, „1,000“ abgelehnt (mehrdeutig).

	=====================================================================================================
	5. MODULE
	=====================================================================================================

	Jedes Modul kann unter Einstellungen > Funktionen und Zugriff abgeschaltet oder bestimmten Rängen vorbehalten werden.

	TAB SPIELER (Spieler wählen, dann die Aktion)
		Kicken (Kick) · Bannen (Ban) · Verwarnen (Warn) · Stummschalten (Mute) · Einfrieren (Freeze) · Töten (Kill)
		Heilen (Heal) · Neu spawnen (Respawn) · Herholen (Bring) · Hingehen (Teleport)
		Zurücksenden (Return) · Zum Spawn (ToSpawn)
		Grund und Dauer (Minuten, leer = dauerhaft) für Kick, Ban, Warn, Mute und Freeze.
		Ansicht „Global“: Verzeichnis aller Konten, die schon einmal da waren, auch offline.

	TAB MODERATION (auf dich selbst)
		Godmode (unendliche Gesundheit) · Unsichtbar · Laufgeschwindigkeit · Sprungkraft
		Werkzeuge: Fly (fliegen), Noclip (durch Wände gehen), ESP (Spieler durch Wände sehen), Spectator (zuschauen)
		Ankündigung an den ganzen Server.

	TAB SPIEL
		Werkzeug geben (GiveTool) · Leaderstats (Wert ändern) · Tageszeit (TimeOfDay)
		Serverwartung (Shutdown): sperrt, kündigt an und kickt Spieler ohne Rang nach Ablauf der Frist.

	TAB BANNS
		Bannliste, Entbannen (Unban), ein Konto per genauem Namen oder UserId bannen.


	=====================================================================================================
	6. ERWEITERUNGEN (FÜR ENTWICKLER)
	=====================================================================================================

	Füge Erweiterungen zum aktiven Ordner APM_Extensions hinzu. APM_DeveloperTemplates ist inaktiv: Beginne mit START_HERE
	und kopiere nur benötigte Beispiele in die passenden aktiven Ordner.
	• Commands.MonJeu.MonJeu_Informer: Kopiere den Ordner MonJeu nach Commands.
	• ClientPages.MonJeu.MonJeuPage: Kopiere MonJeu nach ClientPages.
	• Server.MonJeuIntegration und Adapters.MonJeuStatus: Kopiere jedes ModuleScript in den passenden Ordner.
	Wähle eindeutige Befehlsnamen und Namespaces. Rechte werden nie automatisch hinzugefügt: Deklariere MonJeu.Page /
	MonJeu.Status in Settings.PermissionDefaults der aktiven ServerSettings-Datei mit dem gewählten Mindestrang.
	Starte Play nach Änderungen am Quellcode oder an der Konfiguration neu.

	A) Ein Befehl: ein ModuleScript in APM_Extensions > Commands
		return {
			ApiVersion = 1,
			Name = "Konfetti",               -- eindeutige Kennung (Buchstaben, Ziffern, _ - .)
			Category = "Players",            -- Players, Moderation, Game... oder eine eigene Kategorie
			Mode = "target",                 -- "action" | "target" (ein Spieler) | "toggle" | "slider"
			MinRank = "Staff",               -- Standard-Mindestrang
			Label = { de = "Konfetti", en = "Confetti" },
			Description = { de = "Wirft Konfetti.", en = "Throws confetti." },
			-- optional: Group, Order, Color, Confirm, AllowSelf, Min / Max / Default (slider),
			--           Fields = { { Name = "Menge", Type = "number", Min = 1, Max = 100 } },
			--           Inputs = { "Reason", "Minutes" }, Init = function(ctx) end, OnAccessRevoked = function(ctx, player) end
			Execute = function(ctx, admin, target, value)
				-- der Server hat Rang, Zugriff, Hierarchie und Werte bereits geprüft
				return true, "Konfetti geworfen!"   -- (Erfolg, Nachricht an den Admin)
			end,
		}
		Feldtypen: "number", "choice" (Options), "text", "string". Jede Ausführung wird protokolliert.

	B) Eine Server-Integration: ein ModuleScript in APM_Extensions > Server
		return { ApiVersion = 1, Id = "MeinSpiel", Init = function(api)
			-- api.RegisterCommand(befehl), api.RegisterOptions(name, anbieter), api.AddProfileProvider(fn),
			-- api.RegisterAdapter(name, adapter), api.HasPermission(spieler, berechtigung), api.CanTarget(admin, ziel),
			-- api.Authorize(admin, befehl, ziel), api.Notify(spieler, nachricht, erfolg), api.Log(akteur, aktion, ziel, detail)
		end }
	Registriere Befehle synchron in Init(api), vor verzögerten Aufgaben, und prüfe die Ergebnisse.
	Rufe APM.WaitForReady() nicht in Init auf: APM wartet bereits auf das Ende dieser Initialisierung.

	C) Ein AutoBridge-Adapter: APM_Extensions > Adapters  →  { ApiVersion = 1, Id = "...", Adapter = { Permission, Probe, Actions } }
	D) Eine Panel-Seite: APM_Extensions > ClientPages > MonJeu > MonJeuPage (ModuleScript im Namespace-Ordner).
	   Behalte die ModuleScript-Attribute ApiVersion = 1 und Permission = "MonJeu.Page". Deklariere ausdrücklich
	   Settings.PermissionDefaults = { ["MonJeu.Page"] = "Owner" } in der aktiven ServerSettings-Datei mit deinem Mindestrang.
	   Gib eine Tabelle mit ApiVersion = 1, derselben Permission, einer gültigen eindeutigen Id = "MonJeuPage" und Build(Core, page) zurück.
	   Label, Order und Visible(Core) sind optional. Handles darf nur Kategorien dieses Namespace auflisten.
	   Ids dürfen Buchstaben, Ziffern, _, . oder - enthalten und nicht mit APM-Ids kollidieren.
	   Verwende APM_DeveloperTemplates.ClientPages.MonJeu.MonJeuPage als funktionierendes Beispiel. Nur berechtigte Admins
	   bekommen die Seite. Keine Geheimnisse im Client-Code. Nutze Core.On(signal, callback) für Verbindungen und
	   Core.Action(command, target, value) für autorisierte Serverbefehle.

	E) Aus deinen anderen Server-Skripten:
		local ServerStorage = game:GetService("ServerStorage")
		local core = ServerStorage:WaitForChild("APM_Core", 10)
		local server = core and core:WaitForChild("Server", 10)
		local service = server and server:WaitForChild("APMService", 10)
		assert(service and service:IsA("ModuleScript"), "APMService nicht verfügbar.")
		local APM = require(service)
		APM.WaitForReady()
		APM.IsAdmin(spieler)  APM.GetRank(spieler)  APM.HasRankAtLeast(spieler, "Staff")
		APM.Notify(spieler, text, erfolg)  APM.Log(akteur, aktion, ziel, detail, kategorie, "info"|"warning"|"danger")
		APM.AddProfileProvider(fn)  APM.RegisterOptions(name, fn)  APM.TrackDataStore(store, "Name")

	Der Zustand der Erweiterungen (geladen / Fehler) wird im Tab Diagnose angezeigt.


	=====================================================================================================
	7. UPDATES UND HILFE
	=====================================================================================================

	• Aktualisieren: Ersetze APM_Kit durch die neue Version. Behalte deinen Ordner APM_Extensions: Eine kompatible
	  externe Konfiguration ServerStorage.APM_Extensions bleibt erhalten und hat Vorrang. Ändere niemals APM_Core.
	• Das Panel öffnet sich nicht? Prüfe deinen Rang (Settings.Users), ob ToolboxBootstrap aktiviert ist und ob das
	  Kit nicht allein in ServerStorage liegt. Die Ausgabe (Output) zeigt „[APM] Serveur prêt“ (Server bereit), wenn alles passt.
	• In einer Rangsimulation festgesteckt? Tippe /apm-restore in den Chat.
	• „Speichermodus“ angezeigt? In Studio normal: Während deiner Tests wird nichts gespeichert.


	ÄNDERUNGSPROTOKOLL 2.10.2
	• NEU: Sentinel, schwebender Befehlsassistent (verschiebbar, zwei unabhängige Einklapp-Pfeile, Ultrakompaktmodus).
	• NEU: Reiter Sentinel Helper (Einstellungen, Servereinstellungen, eigene Befehle, optionale externe KI, Engine-Test).
	• NEU: Sentinel-Schalter im Start; Einstellungen pro Konto (Position, Einklappen, Größe, Animation).
	• NEU: Berechtigungen Assistant.Use / Configure / Commands / External; Kategorie Sentinel (Assistent) in Funktionen und Zugriff.
	• NEU: speed und jump akzeptieren ein Ziel (speed bob 50); freeze und mute machen ihren Zustand lesbar (nie versehentlich umgeschaltet).
	• ÄNDERUNG: APMService.perform ist der gemeinsame Ausführungskern von Panel-Schaltflächen und Sentinel (gleiche Prüfungen, gleiches Protokoll).
	• ÄNDERUNG: Preferences akzeptiert 4 persönliche Felder (AssistantEnabled, AssistantLayout, AssistantWave, AssistantScale); SuiteConfig akzeptiert den Abschnitt SentinelAssistant.
	• NEU: verteilte Aktionen (Dispatcher + ActionExecutor): Fly und Noclip gelten jetzt auch für andere Spieler („fly bob“, „fly all“, „unfly bob“, „noclip bob“), vom Server geprüft, auf dem Gerät des Ziels ausgeführt und von ihm bestätigt.
	• NEU: Jede verteilte Aktion wird vom Server kontrolliert (Rang, Werkzeugrecht, Hierarchie: „all“ umgeht nie einen Schutz), trägt eine eindeutige ID mit Ablaufzeit und endet mit einer Zahlenbilanz (betroffen, geschützt, fehlgeschlagen, unbestätigt). Die Antwort eines Clients ist eine Bestätigung, nie ein absoluter Beweis: Der Server prüft, was er kann (Fly: Humanoid-Zustand; Noclip: Kollisionen).
	• NEU: Tab Spieler, Karte „Kräfte auf den Spieler“ (Schalter für den gewählten Spieler, „alle“-Knöpfe mit Bestätigung); „spectate bob“ beobachtet einen Spieler; „esp bob“ wird absichtlich abgelehnt (ESP ist eine lokale Ansicht und wird nie an andere Spieler vergeben).
	• ÄNDERUNG: Fly und Noclip teilen sich EINEN Controller (APM_Shared > ActionExecutor > Effects) zwischen Panel-Schalter und Server: keine Doppelungen. Neue Remotes: ActionDispatch / ActionReport (öffentlich, nur Antworten), DispatchAction (Admin-Panel).
	• ÄNDERUNG: „all“ bei einem Serverbefehl liefert eine Bilanz „Freeze: 8 betroffen, 2 geschützt, 0 fehlgeschlagen, 1 übersprungen“.
	• Entwickler: Eine verteilte Aktion hinzufügen = in ActionCatalog deklarieren + ein Controller in ActionExecutor/Effects (+ optional Dispatcher/Hooks); Settings.Modules.Dispatcher = false deaktiviert sie. Nichts wird gespeichert: Effekte enden, wenn der Spieler geht.
	• Keine Datenmigration: DataSchemaVersion bleibt 2; bestehende Konfigurationen und Speicherstände bleiben unberührt.
	• NEW: mehrsprachiges Sentinel: Befehle auf Deutsch, Englisch, Französisch, Spanisch, Portugiesisch, Russisch und Chinesisch gleichzeitig, unabhängig von der Oberflächensprache; eine kanonische Aktion, gleiche Berechtigungen, Schutzregeln und Bestätigungen.
	• NEW: implizites Ziel: „fly“, „unfly“, „noclip“ wirken auf dich; „fly Bob“ zielt auf einen Spieler; „fly all“ (und seine Übersetzungen) verlangt immer eine Bestätigung.
	• CHANGE: jedes Ziel „all“ wird bestätigt (kill, freeze, mute, heal, respawn, bring, speed, jump, fly, noclip), auch mit ConfirmDangerous = false; die Bestätigung ist an die kanonische Aktion und die aufgelösten Spieler gebunden.
	• CHANGE: ein reserviertes Wort, das zugleich Name eines anwesenden Spielers ist (All, Ich, On...), ist mehrdeutig: @UserId verwenden.
	• NEW: Karte „Befehlssprachen“ im Sentinel Helper, erweiterter Engine-Test; Unicode-Normalisierung (Kyrillisch, Chinesisch, Vollbreite, Akzente); Länge in Zeichen (200), nicht in Bytes.
	• Entwickler: CommandLocalization (ein ModuleScript je Sprache); eine 8. Sprache = ein weiteres ModuleScript.

	• NEU: „help“ öffnet einen interaktiven Katalog: ALLE Befehle des Registers in einem Raster mit 3 Spalten. Ein Befehl, den du nicht ausführen darfst, zeigt ein Schloss (vom Server berechnet; es gewährt nichts). Antippen bereitet einen Befehl nur im Eingabefeld VOR (wird nie ausgeführt).
	• NEU: Autovervollständigung: Befehle und Aliase (7 Sprachen), Spieler (Benutzername, Anzeigename, @UserId), Selektoren, on/off und für den Befehl gültige Dauern; Pfeile zum Blättern, Tab zum Vervollständigen, Enter sendet (oder vervollständigt einen mit den Pfeilen gewählten Vorschlag), Esc schließt. Vorgeschlagen werden nur registrierte, erlaubte Befehle; lokale Berechnung, keine Anfrage pro Tastendruck.
	• NEU: Dauern: 10s · 5m · 2h · 1d (und Übersetzungen). Eine Dauer, die ein Befehl nicht einhalten kann, wird mit einer Meldung abgelehnt: ban arbeitet in ganzen Minuten (30s und 0,5 werden abgelehnt, statt zu einem dauerhaften Bann zu werden); ein unbekanntes Format (1w) landet nie im Grund.
	• FIX: Startseite und Sentinel Helper lesen denselben Zustand: Sentinel auf der Startseite auszuschalten erscheint sofort im Sentinel Helper (und umgekehrt); das Schließen des APM ändert nichts daran.
	• ÄNDERUNG: Der Pfeil des Eingabebereichs folgt der Fensterposition (linke Hälfte: klappt nach links ein; rechte Hälfte: nach rechts); die Pfeile haben ein dezentes dunkles Plättchen und bleiben auf hellem Hintergrund sichtbar.

	MIT-Lizenz · Kostenlos · Erstellt von APM contributors

]==]
return {}
