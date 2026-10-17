--[==[

	APM | Admin Panel - Modular — GUÍA COMPLETA (ESPAÑOL)
	Versión 2.10.2 (estable) · Licencia MIT · Gratis · Creado por APM contributors
	=====================================================================================================

	APM es un panel de administración que ayuda a los desarrolladores a gestionar su experiencia: moderación,
	rangos, seguridad, estadísticas y efectos divertidos. El servidor vuelve a comprobarlo todo y no se envía
	nada a los jugadores que no tienen acceso.

	ÍNDICE
		1. Instalación
		2. Idiomas del panel
		3. Configuración
		4. Sistemas
		5. Módulos
		6. Extensiones (para desarrolladores)
		7. Actualizaciones y ayuda


	=====================================================================================================
	1. INSTALACIÓN
	=====================================================================================================

	1) Inserta APM_Kit desde la Toolbox (sirven Workspace o ServerScriptService).
	   No lo pongas solo en ServerStorage: ahí los scripts no se ejecutan.
	2) Deja activado el script ToolboxBootstrap (RunContext: Server). Al iniciar, mueve el kit automáticamente
	   a ServerStorage y arranca un cargador privado en ServerScriptService.
	   Los scripts Installer y APM_Bootstrap siguen desactivados: solo sirven para una instalación manual.
	3) Date un rango en el archivo ServerSettings activo (ver sección 3) y añade tu UserId:
			Settings.Users = { [123456789] = "Owner" }
	   Tu UserId está en la dirección de tu perfil: roblox.com/users/<UserId>/profile
	   Ninguna cuenta recibe un rango por defecto. Sustituye 123456789 por tu propio UserId en este archivo activo.
	4) Pulsa Play. Haz clic en el botón "APM" arriba de la pantalla o pulsa F2 para abrir el panel.
	   Z centra la ventana. En Inicio puedes ocultar el botón y elegir otra tecla.
	5) Guardado: el juego publicado usa DataStores. Studio usa el modo memoria por defecto (Settings.StudioMemory = true):
	   los cambios quedan en esta sesión. Para probar DataStores en Studio, pon Settings.StudioMemory = false en el
	   ServerSettings activo Y activa "Enable Studio Access to API Services" en Configuración del juego > Seguridad.
	   Estas pruebas pueden escribir en los guardados reales.

	Bueno saber
	• El botón APM revisa 16 posiciones de la pantalla para no tapar tu interfaz; si todas están ocupadas,
	  se coloca encima, abajo a la izquierda.
	• Cuando el panel está abierto, pasa automáticamente delante de todas las interfaces del juego.
	• No se descarga código, no se modifica ningún script durante el juego y nada se publica automáticamente.


	=====================================================================================================
	2. IDIOMAS DEL PANEL
	=====================================================================================================

	7 idiomas: français (fr), English (en), español (es), português (pt), Deutsch (de), русский (ru), 中文 (zh).
	• Por defecto, cada admin ve el panel en el idioma de su cuenta de Roblox.
	• El botón de idioma arriba del panel (p. ej. "ES v") permite elegir otro; la elección se guarda.
	• Los jugadores ven los anuncios, advertencias y mensajes de silencio en su propio idioma.
	• En SharedConfig:
			Config.ForceLanguage = "es"     -- mismo idioma para todos (nil = idioma de la cuenta)
			Config.DefaultLanguage = "en"   -- idioma de reserva
	• Traducciones: APM_Core > Shared > Lang > Tabs (un módulo por pestaña, con todos los idiomas). Los módulos Lang > <idioma> y Lang > Phrases siguen disponibles para tus propios textos.


	=====================================================================================================
	3. CONFIGURACIÓN
	=====================================================================================================

	Modifica solo APM_Extensions > Config en la carpeta activa. Si ya existe ServerStorage.APM_Extensions,
	tiene prioridad sobre APM_Kit.APM_Extensions; si no, empieza en la carpeta del kit. Inicio y Diagnósticos muestran
	el SourcePath activo y avisan si hay configuraciones duplicadas: modifica primero el archivo indicado.
	No modifiques APM_Core: se reemplaza con cada actualización.
	Los valores por defecto, comentados línea a línea, están en APM_Core > Server > Settings y APM_Core > Shared > Config.
	Para cambiar un valor, copia su línea en tu archivo: reemplaza el valor por defecto.
	• una tabla (p. ej. Settings.Funny = { MaxDuration = 30 }) solo reemplaza las claves escritas;
	• una lista (Ranks, ClientTools, ToolSources) se reemplaza entera;
	• Settings.RemoveKeys = { "Clave" } elimina un valor por defecto.

	ServerSettings (solo lo lee el servidor)
		Ranks               rangos, del más alto al más bajo (Id, Level, Color, Fixed, Name)
		SuperRank           "Dev": acceso configurable, nadie puede apuntarle
		ManagerRank         "Owner": mínimo para la pestaña Ajustes
		AnnounceRank        "Staff": puede hacer un anuncio a todo el servidor
		CreatorRank         nil por defecto: sin rango automático. Activa "Owner" explícitamente solo para el propietario de esta experiencia (o su grupo), nunca para el autor de APM.
		                    Para activar esta opción, elimina también "CreatorRank" de Settings.RemoveKeys y establece Settings.CreatorRank = "Owner".
		Users               rangos FIJOS por UserId (prioritarios, no se cambian desde el panel)
		DefaultUsers        rangos iniciales (se pueden cambiar después en el panel)
		Group               { Id = grupo, Ranks = { [rango mínimo en el grupo] = "Rango" } }
		StudioRank          rango de prueba opcional en Studio (nil por defecto: ningún rango automático); sin efecto en línea
		DataStoreName       "APM_Data_v1": un solo DataStore para todo APM (cambiarlo empieza de cero)
		MessagingTopic      sincronización de permisos y baneos entre servidores
		MaxLogs / MaxRoster / MaxWarnings   300 / 20000 / 25
		ToolSources         carpetas donde "Dar una herramienta" busca los Tool (ServerStorage por defecto)
		PermissionDefaults  rango mínimo por defecto de cada permiso con nombre (APM.*, Sentinel.*, Funny.*...)
		Modules             desactivar un sistema opcional: { Simulation, AutoBridge, Sentinel, Funny, Assistant }
		Funny               { MaxDuration = 60, MaxActiveScenes = 16, MaxGroupTargets = 8, CrossServerEnabled = true }
		ClientTools         herramientas del admin: { "Fly", "Noclip", "ESP", "Spectator" }
		DisabledCommands    quitar un comando: { Kill = true }
		AutoBridge          { Enabled, ScanInterval = 30, MaxScanInstances = 1500, EnableTeamActions = false }
		Sentinel            { Enabled, Mode = "Observation", Interval = 1, CorrectPosition = false, AllowKick = false }
		Assistant           { Enabled, MaxHistory = 40, ReplyStyle = "Short", ConfirmDangerous, AllowAll, MaxAllTargets = 25, RatePerWindow = 8, DefaultDeployed, WaveEnabled, WaveInterval = 30, AnimationSpeed, External = { Enabled = false, Hosts = {}, SecretName, ApiKey, Model } }  -- Sentinel 2.10.2

	SharedConfig (lo leen el servidor Y los clientes: nada secreto)
		ForceLanguage, DefaultLanguage, OpenKey (F2), RecenterKey (Z), Title, Theme (color por color),
		LauncherButton, MobileButton, LanguageButton


	=====================================================================================================
	4. SISTEMAS
	=====================================================================================================

	RANGOS
	• Por defecto: Dev (5) > Owner (4) > CoOwner (3) > Staff (2) > StaffTest (1).
	• Un admin solo actúa sobre un rango ESTRICTAMENTE inferior; a Dev nunca se le puede apuntar.
	• El rango de una cuenta es el MÁS ALTO de sus fuentes: Users, creador, panel / DefaultUsers, grupo, Studio.
	• Los rangos "Fixed" solo se dan en la configuración, nunca desde el panel.
	• La lista de rangos muestra su origen y el rango que quedará al quitar una asignación del panel.
	  Esto no revoca el acceso fijo ni de grupo; el dueño real tiene una acción separada para revocar el acceso.

	FUNCIONES Y ACCESO (pestaña Ajustes)
	• Todo APM, por categoría. La columna "Activo" enciende o apaga una función para todo el juego; las columnas
	  de rangos eligen quién puede usarla. Una fila de categoría marca todo de una vez.
	• Dev respeta el MinRank por defecto y las opciones de acceso guardadas para su rango, como los demás rangos.
	• Naranja = mezcla; gris = fuera de tu alcance. El acceso al panel y a Ajustes nunca se quita en bloque.
	• Los cambios se guardan y se sincronizan en todos los servidores (MessagingService).

	SEGURIDAD (pestaña Seguridad)
	• Los permisos permanentes, comandos y herramientas se configuran juntos en Ajustes > Funciones y acceso,
	  con búsqueda. Seguridad abre ese mismo editor.
	• Prueba un rango inferior durante cinco minutos. Elige los permisos de prueba con las casillas;
	  el JSON es una opción avanzada. Solo puedes seleccionar derechos que ya tienes. Vuelve al rango real con el botón
	  o /apm-restore; si desaparece el panel, usa el botón de recuperación.
	• Simulación de rango: prueba el panel como un rango inferior durante 5 minutos; /apm-restore en el chat
	  devuelve tu rango real al instante.
	• Modelo de seguridad: cada admin recibe sus propios remotes privados; el servidor vuelve a comprobar rango,
	  acceso, jerarquía, valores y anti-spam en cada petición. Un jugador sin rango no recibe ni el panel, ni el
	  botón, ni ningún remote de admin: solo la visualización pública de anuncios, advertencias y silencios.

	GUARDADO
	• Un solo DataStore (APM_Data_v1): rangos, matriz de acceso, baneos, advertencias, registro y directorio de jugadores.
	• Escrituras limitadas para ahorrar presupuesto: el directorio se guarda por lotes (unos 5 minutos), las
	  preferencias solo cuando cambian.
	• Sin DataStores (Studio sin acceso a la API): modo memoria, no se guarda nada.

	INICIO
	• Estado del servidor, rendimiento (según tus permisos), jugadores conectados con búsqueda y fichas
	  detalladas, resúmenes de AutoBridge, Sentinel y diagnósticos. Se actualiza cada 15 s si Inicio está visible.
	• Apertura del panel: mostrar / ocultar el botón discreto, cambiar la tecla.

	ESTADÍSTICAS (pestaña Estadísticas)
	• Gráficos: uso del panel, jugadores, rendimiento del servidor (ciclo, memoria, red) y DataStores más usados.
	  Un punto cada 15 s, guardado en la memoria del servidor (no se escribe nada).
	• Para seguir los DataStores de TU juego (script de servidor):
			local ServerStorage = game:GetService("ServerStorage")
			local core = ServerStorage:WaitForChild("APM_Core", 10)
			local server = core and core:WaitForChild("Server", 10)
			local service = server and server:WaitForChild("APMService", 10)
			assert(service and service:IsA("ModuleScript"), "APMService no disponible.")
			local APM = require(service)
			APM.WaitForReady()
			local DataStoreService = game:GetService("DataStoreService")
			local store = APM.TrackDataStore(DataStoreService:GetDataStore("PlayerData"), "PlayerData")
			-- y luego usa store como siempre (GetAsync, SetAsync, UpdateAsync...)

	REGISTRO (pestaña Logs)  • Cada acción de admin queda registrada (300 entradas), con filtros por categoría y gravedad.
	BANEOS                    • Banea a un jugador conectado o una cuenta desconectada (nombre exacto o UserId), temporal o
	                            permanente, aplicado en todos los servidores; desbanea en la pestaña Baneos.
	BLOQUEO DEL SERVIDOR      • Impide que los jugadores sin rango entren a este servidor; el mantenimiento lo usa.

	SENTINEL GUARD (anti-trampas)
	• Vigila en el servidor velocidades y teletransportes anormales, con tolerancias (latencia, aparición, asientos,
	  física). Modos: Observación (por defecto), Equilibrado, Estricto.
	• Por defecto solo AVISA a los admins. Corrección de posición: opcional. Expulsión automática: solo si
	  Settings.Sentinel.AllowKick = true. Diagnóstico sintético para probar sin un jugador real.
	• El origen de los ajustes muestra el valor efectivo, el del script y los cambios guardados o de la sesión Studio.
	  Volver a los valores del script elimina los cambios guardados, incluidas las zonas seguras añadidas desde el panel,
	  y aplica el script al instante; las zonas seguras del script se conservan.

	AUTOBRIDGE (integraciones)
	• Detecta lo que tu juego ya usa: leaderstats, equipos, herramientas, asientos de vehículo.
	• Nunca ejecuta código desconocido. Cambio de equipo desactivado por defecto (EnableTeamActions).
	• En Inicio > Integraciones y ajustes, consulta cada valor efectivo y su origen.
	  Volver a los valores del script elimina los cambios guardados y aplica al instante los valores del script.

	FUNNY (efectos divertidos, pestaña Funny)
	• ① Elige un efecto en la cuadrícula (vista previa 3D al lado) y ▶ LANZAR; ② ajusta energía, duración, alcance y objetivos.
	• Escenas: confeti, disco, patos, burbujas, patata real, sistema solar, nieve, corazones, fuegos artificiales, arcoíris.
	• Transformaciones: cabeza grande, skin de una cuenta de Roblox, copiar/intercambiar una parte del cuerpo,
	  gravedad invertida, personaje boca abajo (el jugador sigue controlando sus movimientos).
	• Alcance: Local, Servidor, Entre servidores. Todo es temporal, los objetivos están protegidos por su rango,
	  la apariencia se restaura al final y siempre hay un botón para detener.

	DIAGNÓSTICOS: Inicio y Diagnósticos muestran la configuración activa y los duplicados. Los diagnósticos de extensiones
	indican SourcePath, el campo inválido, el valor recibido, el esperado y cómo corregirlo.


	SENTINEL (asistente de comandos flotante) y SENTINEL HELPER — novedad de 2.10.2
	(no confundir con Sentinel Guard, el antitrampas de arriba)
	• Sentinel es una pequeña ventana movible, independiente del panel: sigue en pantalla cuando el APM está cerrado.
	  Escribe un comando (fly, freeze bob, bring bob, speed bob 50, unfly me, kick bob spam...). Es un motor LOCAL basado en reglas,
	  no una IA generativa: no necesita conexión a Internet. help lista los comandos que puedes usar,
	  help <comando> da el detalle, clear vacía el historial.
	• Los comandos son los del APM: cada módulo y herramienta de cliente del registro (Jugadores, Moderación, Juego, Baneos, tus extensiones).
	  Objetivos: me, all, un nombre exacto, un UserId o un nombre parcial que coincida con UN solo jugador (varias coincidencias:
	  Sentinel pide precisar). Alias: tp, vitesse, geler... (inglés y francés).
	• Seguridad: el cliente solo envía texto. El servidor comprueba identidad, rango, permisos, jerarquía (los rangos protegidos
	  siguen protegidos), límites de los argumentos y frecuencia (8 comandos / 10 s por defecto) con el mismo código que los botones del panel.
	  Los comandos sensibles (kick, ban, shutdown) piden confirmación. Nunca se evalúa código. all se rechaza para kick / ban.
	• fly / noclip / esp / spectate solo te afectan a TI (herramientas de cliente): el servidor autoriza, tu dispositivo aplica y Sentinel
	  confirma solo después. speed / jump aceptan un jugador y all: speed bob 50, speed all 20.
	• Ventana: arrastra la cabecera o el asa izquierda; dos flechas independientes repliegan la zona de conversación (flecha superior)
	  y la de entrada (flecha lateral); con ambas replegadas queda una sola flecha, no movible, que lo restaura todo.
	  La posición y el repliegue se guardan por cuenta. La onda de matices de las flechas pasa cada 30 s (configurable, desactivable).
	• Inicio: el interruptor Sentinel lo activa o desactiva para tu cuenta (el APM puede seguir cerrado).
	• Pestaña Sentinel Helper (grupo Desarrollo): mis preferencias (locales) / ajustes del servidor (todos) / comandos
	  personalizados / IA externa opcional / prueba del motor / almacenamiento. Permisos: Assistant.Use (StaffTest), Assistant.Configure,
	  Assistant.Commands, Assistant.External (Owner). Los ajustes se guardan en el DataStore del APM (SuiteSettings_v2, sección
	  SentinelAssistant); el modo memoria de Studio solo los conserva durante la sesión.
	• Los comandos personalizados son DATOS (nombre, argumentos, permiso, una acción permitida: responder con un texto, teletransportar
	  a un punto, ejecutar hasta 5 comandos existentes). Nunca código Lua. Cada paso se ejecuta con los derechos de quien lo escribe.
	• IA externa (opcional, desactivada por defecto): exige Settings.Assistant.External en ServerSettings (Hosts = { "api.ejemplo.com" },
	  SecretName o ApiKey) y las solicitudes HTTP activadas. La clave nunca llega a los clientes ni al DataStore. La IA solo ve el texto escrito
	  y los nombres de comandos; propone un comando que TÚ confirmas y que el servidor valida como cualquier otro.
	• ServerSettings: Settings.Assistant = { Enabled, MaxHistory, ReplyStyle, ConfirmDangerous, AllowAll, MaxAllTargets, RatePerWindow,
	  DefaultDeployed, WaveEnabled, WaveInterval, AnimationSpeed, External = {...} }; Settings.Modules.Assistant = false lo desactiva.

	IDIOMAS DE LOS COMANDOS DE SENTINEL (7 idiomas) — reconocimiento multilingüe
	• Sentinel entiende a la vez español, inglés, francés, portugués, alemán, ruso y chino. El idioma en que escribes es INDEPENDIENTE del
	  idioma del panel: interfaz en español, comando en ruso y luego en chino, sin cambiar nada. Todas las fórmulas llevan a UNA acción
	  canónica (el nombre del módulo: Fly, Freeze, Kick...); permisos, protecciones, confirmaciones y registro son exactamente los del comando
	  en inglés. Una traducción nunca concede nada más.
	• Ejemplos (todos = Fly): fly · voler · volar · voar · fliegen · летать · 飞行 (飛行). Formas de parada: unfly · arrêter de voler ·
	  dejar de volar · parar de voar · stopp fliegen · перестать летать · 停止飞行. Se pueden mezclar: «volar all», «fly todos».
	  Mayúsculas, tildes y letras / espacios de ancho completo no importan (é = e, ß = ss, ё = е, Ｆｌｙ = fly). El chino simplificado y el
	  tradicional se listan uno por uno. Sin adivinar: un comando desconocido sigue siendo desconocido (solo sugerencias).
	• Destino, tres formas idénticas en todos los idiomas:
	    – sin destino: un comando que admite destino se aplica a TI (fly, unfly, noclip, speed 50...);
	    – un nombre de usuario: fly Bob (nunca se traduce ni se altera; se acepta un inicio de nombre único, la ambigüedad se rechaza);
	    – all (todos, todas, tous, alle, все, 所有人...): todos los jugadores permitidos, SIEMPRE tras una confirmación que nombra la acción
	      canónica, el sentido (parada) y el número de jugadores. Un destino ausente NUNCA es «all».
	  «me»: yo, me, moi, eu, ich, я, 我... Los comandos que exigen destino (kick, freeze, bring...) lo siguen exigiendo;
	  spectate conserva su sentido (observar a un jugador, en local); esp sigue siendo local.
	• Confirmaciones: todo «all» pide ahora confirmación (incluso con ConfirmDangerous = false). Va ligada a la acción CANÓNICA, a su sentido y a
	  los jugadores realmente resueltos: otro comando, otro sentido, otra lista de jugadores o un token caducado (20 s) vuelve a preguntar.
	• Una palabra reservada que es también el nombre de un jugador presente (un jugador llamado All, Ich, On...) nunca se adivina: Sentinel pide
	  precisión con @UserId (o @nombre; @me y @all siguen siendo los selectores).
	• Las respuestas siguen el idioma de los ajustes del APM, no el idioma escrito.
	• Comandos personalizados: sus nombres siguen siendo ASCII; un nombre o alias ya usado por una fórmula oficial de CUALQUIER idioma se rechaza
	  (la fórmula oficial gana; los conflictos aparecen en Sentinel Helper > Almacenamiento). Un paso «fly all» sigue pidiendo confirmación.
	• Sentinel Helper > «Idiomas de los comandos»: fórmulas oficiales por idioma (solo lectura); la prueba del motor muestra el idioma reconocido,
	  la acción canónica, el sentido, el destino y si hace falta confirmación.
	• Desarrolladores: las fórmulas están en Server > Core > Assistant > CommandLocalization (un ModuleScript por idioma: Commands, Off, OffPrefixes,
	  Selectors, Booleans, Units, Local, Choices). Añadir un 8.º idioma = añadir un ModuleScript hijo con el nombre de su código (misma forma que
	  fr / en), sin tocar nada más. Una fórmula que designara dos acciones se descarta y se señala (Report().Collisions); una fórmula compartida por
	  dos idiomas para la MISMA acción es normal.
	• Límites: solo comandos estructurados (sin comprensión de frases libres); en chino un espacio separa el comando y sus argumentos; una palabra que
	  es selector o on / off en un idioma queda reservada en todos; los decimales «1,5» se aceptan, «1,000» se rechaza (ambiguo).

	=====================================================================================================
	5. MÓDULOS
	=====================================================================================================

	Cada módulo se puede desactivar o reservar a ciertos rangos en Ajustes > Funciones y acceso.

	PESTAÑA JUGADORES (elige un jugador y luego la acción)
		Expulsar (Kick) · Banear (Ban) · Advertir (Warn) · Silenciar (Mute) · Congelar (Freeze) · Matar (Kill)
		Curar (Heal) · Reaparecer (Respawn) · Traer (Bring) · Ir hacia él (Teleport)
		Devolver (Return) · Al spawn (ToSpawn)
		Motivo y duración (minutos, vacío = permanente) para Kick, Ban, Warn, Mute y Freeze.
		Vista "Global": directorio de todas las cuentas que ya han entrado, incluso desconectadas.

	PESTAÑA MODERACIÓN (sobre ti mismo)
		Godmode (salud infinita) · Invisible · Velocidad · Salto
		Herramientas: Fly (volar), Noclip (atravesar paredes), ESP (ver jugadores a través de paredes), Spectator (observar)
		Anuncio a todo el servidor.

	PESTAÑA JUEGO
		Dar una herramienta (GiveTool) · Leaderstats (cambiar un valor) · Hora del juego (TimeOfDay)
		Mantenimiento del servidor (Shutdown): bloquea, anuncia y expulsa a los jugadores sin rango tras el plazo.

	PESTAÑA BANEOS
		Lista de baneos, desbanear (Unban), banear una cuenta por nombre exacto o UserId.


	=====================================================================================================
	6. EXTENSIONES (PARA DESARROLLADORES)
	=====================================================================================================

	Añade las extensiones a APM_Extensions activo. APM_DeveloperTemplates está inactivo: empieza por START_HERE
	y copia solo los ejemplos necesarios a las carpetas activas correspondientes.
	• Commands.MonJeu.MonJeu_Informer: copia la carpeta MonJeu a Commands.
	• ClientPages.MonJeu.MonJeuPage: copia MonJeu a ClientPages.
	• Server.MonJeuIntegration y Adapters.MonJeuStatus: copia cada ModuleScript a su carpeta correspondiente.
	Elige un nombre de comando y un namespace únicos. Nunca se añaden permisos automáticamente: declara MonJeu.Page /
	MonJeu.Status en Settings.PermissionDefaults del ServerSettings activo con el rango mínimo que elijas.
	Reinicia Play después de modificar el código o la configuración.

	A) Un comando: un ModuleScript en APM_Extensions > Commands
		return {
			ApiVersion = 1,
			Name = "Confeti",                -- identificador único (letras, cifras, _ - .)
			Category = "Players",            -- Players, Moderation, Game... o tu propia categoría
			Mode = "target",                 -- "action" | "target" (un jugador) | "toggle" | "slider"
			MinRank = "Staff",               -- rango mínimo por defecto
			Label = { es = "Confeti", en = "Confetti" },
			Description = { es = "Lanza confeti.", en = "Throws confetti." },
			-- opcional: Group, Order, Color, Confirm, AllowSelf, Min / Max / Default (slider),
			--           Fields = { { Name = "Cantidad", Type = "number", Min = 1, Max = 100 } },
			--           Inputs = { "Reason", "Minutes" }, Init = function(ctx) end, OnAccessRevoked = function(ctx, player) end
			Execute = function(ctx, admin, target, value)
				-- el servidor ya comprobó rango, acceso, jerarquía y valores
				return true, "¡Confeti lanzado!"   -- (éxito, mensaje mostrado al admin)
			end,
		}
		Tipos de campo: "number", "choice" (Options), "text", "string". Cada ejecución queda en el registro.

	B) Una integración de servidor: un ModuleScript en APM_Extensions > Server
		return { ApiVersion = 1, Id = "MiJuego", Init = function(api)
			-- api.RegisterCommand(comando), api.RegisterOptions(nombre, proveedor), api.AddProfileProvider(fn),
			-- api.RegisterAdapter(nombre, adaptador), api.HasPermission(jugador, permiso), api.CanTarget(admin, objetivo),
			-- api.Authorize(admin, comando, objetivo), api.Notify(jugador, mensaje, éxito), api.Log(actor, acción, objetivo, detalle)
		end }
	Registra los comandos directamente en Init(api), antes de cualquier tarea diferida, y comprueba los resultados.
	No llames a APM.WaitForReady() dentro de Init: APM ya está esperando a que termine esa inicialización.

	C) Un adaptador AutoBridge: APM_Extensions > Adapters  →  { ApiVersion = 1, Id = "...", Adapter = { Permission, Probe, Actions } }
	D) Una página del panel: APM_Extensions > ClientPages > MonJeu > MonJeuPage (ModuleScript dentro de su carpeta de namespace).
	   Conserva los atributos ApiVersion = 1 y Permission = "MonJeu.Page" del ModuleScript. Declara expresamente
	   Settings.PermissionDefaults = { ["MonJeu.Page"] = "Owner" } en el ServerSettings activo; elige tu rango mínimo.
	   Devuelve una tabla con ApiVersion = 1, la misma Permission, un Id válido y único = "MonJeuPage" y Build(Core, page).
	   Label, Order y Visible(Core) son opcionales. Handles solo puede listar categorías de este namespace.
	   Los Id usan letras, cifras, _, . o - y no deben coincidir con los Id de APM.
	   Usa APM_DeveloperTemplates.ClientPages.MonJeu.MonJeuPage como ejemplo funcional. Solo los admins autorizados reciben
	   la página. No incluyas secretos en código cliente. Usa Core.On(signal, callback) para las conexiones y
	   Core.Action(command, target, value) para comandos de servidor autorizados.

	E) Desde tus otros scripts de servidor:
		local ServerStorage = game:GetService("ServerStorage")
		local core = ServerStorage:WaitForChild("APM_Core", 10)
		local server = core and core:WaitForChild("Server", 10)
		local service = server and server:WaitForChild("APMService", 10)
		assert(service and service:IsA("ModuleScript"), "APMService no disponible.")
		local APM = require(service)
		APM.WaitForReady()
		APM.IsAdmin(jugador)  APM.GetRank(jugador)  APM.HasRankAtLeast(jugador, "Staff")
		APM.Notify(jugador, texto, éxito)  APM.Log(actor, acción, objetivo, detalle, categoría, "info"|"warning"|"danger")
		APM.AddProfileProvider(fn)  APM.RegisterOptions(nombre, fn)  APM.TrackDataStore(store, "Nombre")

	El estado de las extensiones (cargadas / errores) aparece en la pestaña Diagnósticos.


	=====================================================================================================
	7. ACTUALIZACIONES Y AYUDA
	=====================================================================================================

	• Actualizar: reemplaza APM_Kit por la nueva versión. Conserva tu carpeta APM_Extensions: una configuración
	  externa ServerStorage.APM_Extensions compatible se conserva y tiene prioridad. Nunca modifiques APM_Core.
	• ¿El panel no se abre? Comprueba tu rango (Settings.Users), que ToolboxBootstrap esté activado y que el kit
	  no esté solo en ServerStorage. La salida (Output) muestra "[APM] Serveur prêt" (servidor listo) si todo va bien.
	• ¿Atascado en una simulación de rango? Escribe /apm-restore en el chat.
	• ¿Aparece "modo memoria"? Es normal en Studio: no se guarda nada durante tus pruebas.


	REGISTRO DE CAMBIOS 2.10.2
	• NUEVO: Sentinel, asistente de comandos flotante (movible, dos flechas de repliegue independientes, modo ultracompacto).
	• NUEVO: pestaña Sentinel Helper (preferencias, ajustes del servidor, comandos personalizados, IA externa opcional, prueba del motor).
	• NUEVO: interruptor de Sentinel en Inicio; preferencias por cuenta (posición, repliegue, tamaño, animación).
	• NUEVO: permisos Assistant.Use / Configure / Commands / External; categoría Sentinel (asistente) en Funciones y acceso.
	• NUEVO: speed y jump aceptan un objetivo (speed bob 50); freeze y mute exponen su estado (nunca se invierten por error).
	• CAMBIO: APMService.perform es el núcleo de ejecución común de los botones del panel y de Sentinel (mismas comprobaciones, mismo registro).
	• CAMBIO: Preferences admite 4 campos personales (AssistantEnabled, AssistantLayout, AssistantWave, AssistantScale); SuiteConfig admite la sección SentinelAssistant.
	• NUEVO: acciones distribuidas (Dispatcher + ActionExecutor): Fly y Noclip también se aplican a otros jugadores («fly bob», «fly all», «unfly bob», «noclip bob»), validadas por el servidor, ejecutadas en el dispositivo del objetivo y confirmadas por él.
	• NUEVO: cada acción distribuida la controla el servidor (rango, permiso sobre la herramienta, jerarquía: «all» nunca esquiva una protección), lleva un identificador único con caducidad y termina con un balance en cifras (afectados, protegidos, fallos, sin confirmar). La respuesta de un cliente es una confirmación, nunca una prueba absoluta: el servidor verifica lo que puede (Fly: estado del Humanoid; Noclip: colisiones).
	• NUEVO: pestaña Jugadores, tarjeta «Poderes sobre el jugador» (interruptor sobre el jugador elegido, botones «todos» con confirmación); «spectate bob» observa a un jugador; «esp bob» se rechaza a propósito (el ESP es una vista local, nunca se da a otro jugador).
	• CAMBIO: Fly y Noclip comparten UN solo controlador (APM_Shared > ActionExecutor > Effects) entre el interruptor del panel y el servidor: sin duplicados. Nuevos remotes: ActionDispatch / ActionReport (públicos, solo respuestas), DispatchAction (panel de administración).
	• CAMBIO: «all» en un comando de servidor da un balance «Freeze: 8 afectados, 2 protegidos, 0 fallos, 1 omitido».
	• Desarrolladores: añadir una acción distribuida = declararla en ActionCatalog + un controlador en ActionExecutor/Effects (+ Dispatcher/Hooks opcional); Settings.Modules.Dispatcher = false la desactiva. No se guarda nada: los efectos terminan cuando el jugador se va.
	• Sin migración de datos: DataSchemaVersion sigue en 2; configuraciones y guardados existentes intactos.
	• NEW: Sentinel multilingüe: comandos en español, inglés, francés, portugués, alemán, ruso y chino a la vez, independientes del idioma de la interfaz; una sola acción canónica, mismos permisos, protecciones y confirmaciones.
	• NEW: destino implícito: «fly», «unfly», «noclip» actúan sobre ti; «fly Bob» apunta a un jugador; «fly all» (y sus traducciones) siempre pide confirmación.
	• CHANGE: todo destino «all» se confirma (kill, freeze, mute, heal, respawn, bring, speed, jump, fly, noclip), incluso con ConfirmDangerous = false; la confirmación va ligada a la acción canónica y a los jugadores resueltos.
	• CHANGE: una palabra reservada que es también el nombre de un jugador presente (All, Ich, On...) es ambigua: usa @UserId.
	• NEW: tarjeta «Idiomas de los comandos» en Sentinel Helper, prueba del motor ampliada; normalización Unicode (cirílico, chino, ancho completo, tildes); longitud en caracteres (200), no en bytes.
	• Desarrolladores: CommandLocalization (un ModuleScript por idioma); un 8.º idioma = un ModuleScript más.

	• NUEVO: «help» abre un catálogo interactivo: TODOS los comandos del registro en una cuadrícula de 3 columnas. Un comando que no puedes ejecutar muestra un candado (lo calcula el servidor; no concede nada). Tocar un comando solo lo PREPARA en el campo de escritura (nunca se ejecuta).
	• NUEVO: autocompletado: comandos y alias (7 idiomas), jugadores (usuario, nombre visible, @UserId), selectores, on/off y duraciones válidas para el comando; flechas para recorrer, Tab para completar, Intro envía (o completa una sugerencia elegida con las flechas), Esc cierra. Solo se sugieren comandos registrados y permitidos; cálculo local, ninguna petición por pulsación.
	• NUEVO: duraciones: 10s · 5m · 2h · 1d (y sus traducciones). Una duración que un comando no puede cumplir se rechaza con un mensaje: ban trabaja en minutos enteros (30s y 0,5 se rechazan en lugar de convertirse en un baneo permanente); un formato desconocido (1w) nunca se cuela en el motivo.
	• CORRECCIÓN: Inicio y Sentinel Helper leen el mismo estado: apagar Sentinel desde Inicio se refleja al instante en Sentinel Helper (y al revés); cerrar el APM nunca lo cambia.
	• CAMBIO: la flecha de la zona de escritura sigue la posición de la ventana (mitad izquierda: se repliega a la izquierda; mitad derecha: a la derecha); las flechas llevan una discreta pastilla oscura para verse sobre fondos claros.

	Licencia MIT · Gratis · Creado por APM contributors

]==]
return {}
