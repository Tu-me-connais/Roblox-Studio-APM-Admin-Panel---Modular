--[==[

	APM | Admin Panel - Modular — GUIA COMPLETO (PORTUGUÊS)
	Versão 2.10.2 (estável) · Licença MIT · Grátis · Criado por APM contributors
	=====================================================================================================

	O APM é um painel de administração que ajuda os desenvolvedores a gerenciar sua experiência: moderação,
	cargos, segurança, estatísticas e efeitos divertidos. O servidor confere tudo de novo e nada é enviado
	aos jogadores sem acesso.

	ÍNDICE
		1. Instalação
		2. Idiomas do painel
		3. Configuração
		4. Sistemas
		5. Módulos
		6. Extensões (para desenvolvedores)
		7. Atualizações e ajuda


	=====================================================================================================
	1. INSTALAÇÃO
	=====================================================================================================

	1) Insira o APM_Kit pela Toolbox (Workspace ou ServerScriptService funcionam).
	   Não o deixe sozinho no ServerStorage: os scripts não rodam lá.
	2) Mantenha o script ToolboxBootstrap ativado (RunContext: Server). Ao iniciar, ele move o kit automaticamente
	   para o ServerStorage e inicia um carregador privado no ServerScriptService.
	   Os scripts Installer e APM_Bootstrap continuam desativados: servem apenas para uma instalação manual.
	3) Dê a si mesmo um cargo no arquivo ServerSettings ativo (veja a seção 3) e adicione seu UserId:
			Settings.Users = { [123456789] = "Owner" }
	   Seu UserId está no endereço do seu perfil: roblox.com/users/<UserId>/profile
	   Nenhuma conta recebe um cargo por padrão. Substitua 123456789 pelo seu próprio UserId neste arquivo ativo.
	4) Aperte Play. Clique no pequeno botão "APM" no topo da tela ou aperte F2 para abrir o painel.
	   Z centraliza a janela. Em Início você pode esconder o botão e escolher outra tecla.
	5) Salvamento: o jogo publicado usa DataStores. O Studio usa o modo memória por padrão (Settings.StudioMemory = true):
	   as mudanças ficam nesta sessão. Para testar DataStores no Studio, defina Settings.StudioMemory = false no
	   ServerSettings ativo E ative "Enable Studio Access to API Services" em Configurações do jogo > Segurança.
	   Esses testes podem gravar nos salvamentos reais.

	Bom saber
	• O botão APM verifica 16 posições na tela para não esconder sua interface; se todas estiverem ocupadas,
	  ele fica por cima, no canto inferior esquerdo.
	• Com o painel aberto, ele passa automaticamente na frente de todas as interfaces do jogo.
	• Nenhum código é baixado, nenhum script é alterado durante o jogo e nada é publicado automaticamente.


	=====================================================================================================
	2. IDIOMAS DO PAINEL
	=====================================================================================================

	7 idiomas: français (fr), English (en), español (es), português (pt), Deutsch (de), русский (ru), 中文 (zh).
	• Por padrão, cada admin vê o painel no idioma da sua conta Roblox.
	• O botão de idioma no topo do painel (ex. "PT v") permite escolher outro; a escolha fica salva.
	• Os jogadores veem anúncios, avisos e mensagens de silenciamento no próprio idioma.
	• No SharedConfig:
			Config.ForceLanguage = "pt"     -- mesmo idioma para todos (nil = idioma da conta)
			Config.DefaultLanguage = "en"   -- idioma reserva
	• Traduções: APM_Core > Shared > Lang > Tabs (um módulo por aba, com todos os idiomas). Os módulos Lang > <idioma> e Lang > Phrases continuam disponíveis para seus próprios textos.


	=====================================================================================================
	3. CONFIGURAÇÃO
	=====================================================================================================

	Edite somente APM_Extensions > Config na pasta ativa. Se ServerStorage.APM_Extensions já existir,
	ela tem prioridade sobre APM_Kit.APM_Extensions; caso contrário, comece na pasta do kit. Início e Diagnósticos mostram
	o SourcePath ativo e avisam quando há configurações duplicadas: edite primeiro o arquivo indicado.
	Não modifique APM_Core: ele é substituído a cada atualização.
	Os valores padrão, comentados linha por linha, estão em APM_Core > Server > Settings e APM_Core > Shared > Config.
	Para mudar um valor, copie a linha dele no seu arquivo: ela substitui o padrão.
	• uma tabela (ex. Settings.Funny = { MaxDuration = 30 }) só substitui as chaves escritas;
	• uma lista (Ranks, ClientTools, ToolSources) é substituída inteira;
	• Settings.RemoveKeys = { "Chave" } remove um valor padrão.

	ServerSettings (lido apenas pelo servidor)
		Ranks               cargos, do mais alto ao mais baixo (Id, Level, Color, Fixed, Name)
		SuperRank           "Dev": acesso configurável, ninguém pode mirá-lo
		ManagerRank         "Owner": mínimo para a aba Configurações
		AnnounceRank        "Staff": pode fazer um anúncio para todo o servidor
		CreatorRank         nil por padrão: sem cargo automático. Ative "Owner" explicitamente apenas para o proprietário desta experiência (ou do seu grupo), nunca para o autor do APM.
		                    Para ativar esta opção, remova também "CreatorRank" de Settings.RemoveKeys e defina Settings.CreatorRank = "Owner".
		Users               cargos FIXOS por UserId (prioritários, não mudam pelo painel)
		DefaultUsers        cargos iniciais (podem mudar depois no painel)
		Group               { Id = grupo, Ranks = { [cargo mínimo no grupo] = "Cargo" } }
		StudioRank          cargo de teste opcional no Studio (nil por padrão: nenhum cargo automático); sem efeito online
		DataStoreName       "APM_Data_v1": um único DataStore para todo o APM (mudar recomeça do zero)
		MessagingTopic      sincronização de permissões e banimentos entre servidores
		MaxLogs / MaxRoster / MaxWarnings   300 / 20000 / 25
		ToolSources         pastas onde "Dar uma ferramenta" procura Tools (ServerStorage por padrão)
		PermissionDefaults  cargo mínimo padrão de cada permissão nomeada (APM.*, Sentinel.*, Funny.*...)
		Modules             desligar um sistema opcional: { Simulation, AutoBridge, Sentinel, Funny, Assistant }
		Funny               { MaxDuration = 60, MaxActiveScenes = 16, MaxGroupTargets = 8, CrossServerEnabled = true }
		ClientTools         ferramentas do admin: { "Fly", "Noclip", "ESP", "Spectator" }
		DisabledCommands    remover um comando: { Kill = true }
		AutoBridge          { Enabled, ScanInterval = 30, MaxScanInstances = 1500, EnableTeamActions = false }
		Sentinel            { Enabled, Mode = "Observation", Interval = 1, CorrectPosition = false, AllowKick = false }
		Assistant           { Enabled, MaxHistory = 40, ReplyStyle = "Short", ConfirmDangerous, AllowAll, MaxAllTargets = 25, RatePerWindow = 8, DefaultDeployed, WaveEnabled, WaveInterval = 30, AnimationSpeed, External = { Enabled = false, Hosts = {}, SecretName, ApiKey, Model } }  -- Sentinel 2.10.2

	SharedConfig (lido pelo servidor E pelos clientes: nada secreto)
		ForceLanguage, DefaultLanguage, OpenKey (F2), RecenterKey (Z), Title, Theme (cor por cor),
		LauncherButton, MobileButton, LanguageButton


	=====================================================================================================
	4. SISTEMAS
	=====================================================================================================

	CARGOS
	• Padrão: Dev (5) > Owner (4) > CoOwner (3) > Staff (2) > StaffTest (1).
	• Um admin só age sobre um cargo ESTRITAMENTE inferior; o Dev nunca pode ser alvo.
	• O cargo de uma conta é o MAIS ALTO de suas fontes: Users, criador, painel / DefaultUsers, grupo, Studio.
	• Cargos "Fixed" só são dados na configuração, nunca pelo painel.
	• A lista de cargos mostra sua origem e o cargo que ficará após remover uma atribuição do painel.
	  Isso não revoga o acesso fixo ou de grupo; o dono real possui uma ação separada para revogar o acesso.

	FUNÇÕES E ACESSO (aba Configurações)
	• Todo o APM, por categoria. A coluna "Ativo" liga ou desliga uma função para o jogo inteiro; as colunas
	  de cargos escolhem quem pode usá-la. Uma linha de categoria marca tudo de uma vez.
	• Dev segue o MinRank padrão e as escolhas de acesso salvas para seu cargo, como os outros cargos.
	• Laranja = misto; cinza = fora do seu alcance. O acesso ao painel e às Configurações nunca é removido em massa.
	• As mudanças são salvas e sincronizadas em todos os servidores (MessagingService).

	SEGURANÇA (aba Segurança)
	• Permissões permanentes, comandos e ferramentas são configurados juntos em Configurações > Funções e acesso,
	  com busca. Segurança abre esse mesmo editor.
	• Teste um cargo inferior por cinco minutos. Escolha as permissões do teste pelas caixas de seleção;
	  o JSON é uma opção avançada. Só podem ser selecionados direitos que você já possui. Volte ao cargo real pelo botão
	  ou /apm-restore; se o painel desaparecer, use o botão de recuperação.
	• Simulação de cargo: teste o painel como um cargo inferior por 5 minutos; /apm-restore no chat
	  devolve seu cargo real na hora.
	• Modelo de segurança: cada admin recebe seus próprios remotes privados; o servidor confere cargo, acesso,
	  hierarquia, valores e anti-spam a cada pedido. Um jogador sem cargo não recebe nem o painel, nem o botão,
	  nem nenhum remote de admin: só a exibição pública de anúncios, avisos e silenciamentos.

	SALVAMENTO
	• Um único DataStore (APM_Data_v1): cargos, matriz de acesso, banimentos, avisos, registro e diretório de jogadores.
	• Gravações limitadas para economizar orçamento: o diretório é salvo em lotes (cerca de 5 minutos), as
	  preferências só quando mudam.
	• Sem DataStores (Studio sem acesso à API): modo memória, nada é salvo.

	INÍCIO
	• Estado do servidor, desempenho (conforme suas permissões), jogadores conectados com busca e fichas
	  detalhadas, resumos do AutoBridge, Sentinel e diagnósticos. Atualiza a cada 15 s quando Início está visível.
	• Abertura do painel: mostrar / esconder o botão discreto, trocar a tecla.

	ESTATÍSTICAS (aba Estatísticas)
	• Gráficos: uso do painel, jogadores, desempenho do servidor (ciclo, memória, rede) e DataStores mais usados.
	  Um ponto a cada 15 s, guardado na memória do servidor (nada é gravado).
	• Para acompanhar os DataStores do SEU jogo (script de servidor):
			local ServerStorage = game:GetService("ServerStorage")
			local core = ServerStorage:WaitForChild("APM_Core", 10)
			local server = core and core:WaitForChild("Server", 10)
			local service = server and server:WaitForChild("APMService", 10)
			assert(service and service:IsA("ModuleScript"), "APMService indisponível.")
			local APM = require(service)
			APM.WaitForReady()
			local DataStoreService = game:GetService("DataStoreService")
			local store = APM.TrackDataStore(DataStoreService:GetDataStore("PlayerData"), "PlayerData")
			-- depois use store normalmente (GetAsync, SetAsync, UpdateAsync...)

	REGISTRO (aba Logs)  • Toda ação de admin é registrada (300 entradas), com filtros por categoria e gravidade.
	BANIMENTOS           • Banir um jogador conectado ou uma conta offline (nome exato ou UserId), temporário ou
	                       permanente, aplicado em todos os servidores; desbanir na aba Banimentos.
	TRAVA DO SERVIDOR    • Impede jogadores sem cargo de entrar neste servidor; a manutenção usa isso.

	SENTINEL GUARD (anti-trapaça)
	• Observa no servidor velocidades e teletransportes anormais, com tolerâncias (latência, spawn, assentos,
	  física). Modos: Observação (padrão), Equilibrado, Rigoroso.
	• Por padrão ele só AVISA os admins. Correção de posição: opcional. Expulsão automática: só se
	  Settings.Sentinel.AllowKick = true. Diagnóstico sintético para testar sem um jogador real.
	• A origem dos ajustes mostra o valor efetivo, o do script e as alterações salvas ou da sessão Studio.
	  Voltar aos valores do script remove as alterações salvas, incluindo as zonas seguras adicionadas pelo painel,
	  e aplica o script imediatamente; as zonas seguras do script são mantidas.

	AUTOBRIDGE (integrações)
	• Detecta o que seu jogo já usa: leaderstats, times, ferramentas, assentos de veículo.
	• Nunca executa código desconhecido. Troca de time desativada por padrão (EnableTeamActions).
	• Em Início > Integrações e ajustes, consulte cada valor efetivo e sua origem.
	  Voltar aos valores do script remove as alterações salvas e aplica imediatamente os valores do script.

	FUNNY (efeitos divertidos, aba Funny)
	• ① Escolha um efeito na grade (prévia 3D ao lado) e ▶ INICIAR; ② ajuste energia, duração, alcance e alvos.
	• Cenários: confete, disco, patos, bolhas, batata real, sistema solar, neve, corações, fogos de artifício, arco-íris.
	• Transformações: cabeça grande, skin de uma conta Roblox, copiar/trocar uma parte do corpo, gravidade
	  invertida, personagem de cabeça para baixo (o jogador continua controlando seus movimentos).
	• Alcance: Local, Servidor, Entre servidores. Tudo é temporário, os alvos são protegidos pelo cargo,
	  a aparência é restaurada no final e sempre há um botão para parar.

	DIAGNÓSTICOS: Início e Diagnósticos mostram a configuração ativa e as duplicatas. Os diagnósticos das extensões
	indicam SourcePath, o campo inválido, o valor recebido, o esperado e como corrigir.


	SENTINEL (assistente de comandos flutuante) e SENTINEL HELPER — novidade da 2.10.2
	(não confundir com o Sentinel Guard, o antitrapaça acima)
	• O Sentinel é uma pequena janela móvel, independente do painel: continua na tela quando o APM está fechado.
	  Digite um comando (fly, freeze bob, bring bob, speed bob 50, unfly me, kick bob spam...). É um motor LOCAL baseado em regras,
	  não uma IA generativa: não precisa de conexão com a Internet. help lista os comandos que você pode usar,
	  help <comando> mostra os detalhes, clear esvazia o histórico.
	• Os comandos são os do APM: cada módulo e ferramenta de cliente do registro (Jogadores, Moderação, Jogo, Banimentos, suas extensões).
	  Alvos: me, all, um nome exato, um UserId ou um nome parcial que corresponda a UM só jogador (várias correspondências:
	  o Sentinel pede para especificar). Aliases: tp, vitesse, geler... (inglês e francês).
	• Segurança: o cliente só envia texto. O servidor verifica identidade, cargo, permissões, hierarquia (cargos protegidos
	  continuam protegidos), limites dos argumentos e frequência (8 comandos / 10 s por padrão) com o mesmo código dos botões do painel.
	  Comandos sensíveis (kick, ban, shutdown) pedem confirmação. Nenhum código é avaliado. all é recusado para kick / ban.
	• fly / noclip / esp / spectate afetam só VOCÊ (ferramentas de cliente): o servidor autoriza, seu dispositivo aplica e o Sentinel
	  confirma só depois. speed / jump aceitam um jogador e all: speed bob 50, speed all 20.
	• Janela: arraste o cabeçalho ou a alça esquerda; duas setas independentes recolhem a zona de conversa (seta superior)
	  e a de entrada (seta lateral); com as duas recolhidas resta uma única seta, não móvel, que restaura tudo.
	  Posição e recolhimento são salvos por conta. A onda de tons das setas passa a cada 30 s (configurável, desativável).
	• Início: o interruptor do Sentinel o ativa ou desativa para a sua conta (o APM pode ficar fechado).
	• Aba Sentinel Helper (grupo Desenvolvimento): minhas preferências (locais) / configurações do servidor (todos) / comandos
	  personalizados / IA externa opcional / teste do motor / armazenamento. Permissões: Assistant.Use (StaffTest), Assistant.Configure,
	  Assistant.Commands, Assistant.External (Owner). As configurações ficam no DataStore do APM (SuiteSettings_v2, seção
	  SentinelAssistant); o modo memória do Studio só as mantém durante a sessão.
	• Comandos personalizados são DADOS (nome, argumentos, permissão, uma ação permitida: responder com um texto, teletransportar
	  para um ponto, executar até 5 comandos existentes). Nunca código Lua. Cada etapa roda com os direitos de quem a digita.
	• IA externa (opcional, desativada por padrão): exige Settings.Assistant.External no ServerSettings (Hosts = { "api.exemplo.com" },
	  SecretName ou ApiKey) e solicitações HTTP ativadas. A chave nunca chega aos clientes nem ao DataStore. A IA só vê o texto digitado
	  e os nomes dos comandos; ela propõe um comando que VOCÊ confirma e que o servidor valida como qualquer outro.
	• ServerSettings: Settings.Assistant = { Enabled, MaxHistory, ReplyStyle, ConfirmDangerous, AllowAll, MaxAllTargets, RatePerWindow,
	  DefaultDeployed, WaveEnabled, WaveInterval, AnimationSpeed, External = {...} }; Settings.Modules.Assistant = false o desativa.

	IDIOMAS DOS COMANDOS DO SENTINEL (7 idiomas) — reconhecimento multilíngue
	• O Sentinel entende ao mesmo tempo português, inglês, francês, espanhol, alemão, russo e chinês. O idioma em que você digita é INDEPENDENTE do
	  idioma do painel: interface em português, comando em russo e depois em chinês, sem mudar nada. Todas as fórmulas levam a UMA ação canônica
	  (o nome do módulo: Fly, Freeze, Kick...); permissões, proteções, confirmações e registro são exatamente os do comando em inglês. Uma tradução
	  nunca concede nada a mais.
	• Exemplos (todos = Fly): fly · voler · volar · voar · fliegen · летать · 飞行 (飛行). Formas de parada: unfly · arrêter de voler ·
	  dejar de volar · parar de voar · stopp fliegen · перестать летать · 停止飞行. Dá para misturar: «voar all», «fly todos».
	  Maiúsculas, acentos e letras / espaços de largura total não importam (é = e, ß = ss, ё = е, Ｆｌｙ = fly). O chinês simplificado e o tradicional
	  são listados um a um. Sem adivinhação: um comando desconhecido continua desconhecido (apenas sugestões).
	• Alvo, três formas idênticas em todos os idiomas:
	    – sem alvo: um comando que aceita alvo se aplica a VOCÊ (fly, unfly, noclip, speed 50...);
	    – um nome de usuário: fly Bob (nunca traduzido nem alterado; um início de nome único é aceito, a ambiguidade é recusada);
	    – all (todos, todas, tous, alle, все, 所有人...): todos os jogadores permitidos, SEMPRE após uma confirmação que nomeia a ação canônica,
	      o sentido (parada) e o número de jogadores. Um alvo ausente NUNCA é «all».
	  «me»: eu, me, moi, yo, ich, я, 我... Os comandos que exigem alvo (kick, freeze, bring...) continuam exigindo;
	  spectate mantém seu sentido (observar um jogador, local); esp continua local.
	• Confirmações: todo «all» agora pede confirmação (mesmo com ConfirmDangerous = false). Ela é ligada à ação CANÔNICA, ao seu sentido e aos
	  jogadores realmente resolvidos: outro comando, outro sentido, outra lista de jogadores ou um token expirado (20 s) pergunta de novo.
	• Uma palavra reservada que também é o nome de um jogador presente (um jogador chamado All, Ich, On...) nunca é adivinhada: o Sentinel pede
	  precisão com @UserId (ou @nome; @me e @all continuam sendo os seletores).
	• As respostas seguem o idioma das configurações do APM, não o idioma digitado.
	• Comandos personalizados: os nomes continuam ASCII; um nome ou alias já usado por uma fórmula oficial de QUALQUER idioma é recusado (a fórmula
	  oficial vence; conflitos listados em Sentinel Helper > Armazenamento). Uma etapa «fly all» continua pedindo confirmação.
	• Sentinel Helper > «Idiomas dos comandos»: fórmulas oficiais por idioma (somente leitura); o teste do motor mostra o idioma reconhecido, a ação
	  canônica, o sentido, o alvo e se há confirmação.
	• Desenvolvedores: as fórmulas ficam em Server > Core > Assistant > CommandLocalization (um ModuleScript por idioma: Commands, Off, OffPrefixes,
	  Selectors, Booleans, Units, Local, Choices). Adicionar um 8.º idioma = adicionar um ModuleScript filho com o nome do seu código (mesma forma que
	  fr / en), sem mudar mais nada. Uma fórmula que designasse duas ações é descartada e sinalizada (Report().Collisions); uma fórmula compartilhada
	  por dois idiomas para a MESMA ação é normal.
	• Limites: apenas comandos estruturados (sem compreensão de frases livres); em chinês um espaço separa o comando e os argumentos; uma palavra que é
	  seletor ou on / off em um idioma fica reservada em todos; decimais «1,5» são aceitos, «1,000» é recusado (ambíguo).

	=====================================================================================================
	5. MÓDULOS
	=====================================================================================================

	Cada módulo pode ser desligado ou reservado a certos cargos em Configurações > Funções e acesso.

	ABA JOGADORES (escolha um jogador e depois a ação)
		Expulsar (Kick) · Banir (Ban) · Avisar (Warn) · Silenciar (Mute) · Congelar (Freeze) · Matar (Kill)
		Curar (Heal) · Renascer (Respawn) · Trazer (Bring) · Ir até ele (Teleport)
		Devolver (Return) · Ao spawn (ToSpawn)
		Motivo e duração (minutos, vazio = permanente) para Kick, Ban, Warn, Mute e Freeze.
		Visão "Global": diretório de todas as contas que já entraram, mesmo offline.

	ABA MODERAÇÃO (em você mesmo)
		Godmode (vida infinita) · Invisível · Velocidade · Pulo
		Ferramentas: Fly (voar), Noclip (atravessar paredes), ESP (ver jogadores através das paredes), Spectator (observar)
		Anúncio para todo o servidor.

	ABA JOGO
		Dar uma ferramenta (GiveTool) · Leaderstats (alterar um valor) · Hora do jogo (TimeOfDay)
		Manutenção do servidor (Shutdown): trava, anuncia e expulsa os jogadores sem cargo após o prazo.

	ABA BANIMENTOS
		Lista de banimentos, desbanir (Unban), banir uma conta por nome exato ou UserId.


	=====================================================================================================
	6. EXTENSÕES (PARA DESENVOLVEDORES)
	=====================================================================================================

	Adicione extensões à pasta APM_Extensions ativa. APM_DeveloperTemplates está inativo: comece pelo START_HERE
	e copie somente os exemplos necessários para as pastas ativas correspondentes.
	• Commands.MonJeu.MonJeu_Informer: copie a pasta MonJeu para Commands.
	• ClientPages.MonJeu.MonJeuPage: copie MonJeu para ClientPages.
	• Server.MonJeuIntegration e Adapters.MonJeuStatus: copie cada ModuleScript para sua pasta correspondente.
	Escolha um nome de comando e um namespace únicos. Nenhuma permissão é adicionada automaticamente: declare
	MonJeu.Page / MonJeu.Status em Settings.PermissionDefaults do ServerSettings ativo, com o cargo mínimo escolhido.
	Reinicie Play após modificar o código ou a configuração.

	A) Um comando: um ModuleScript em APM_Extensions > Commands
		return {
			ApiVersion = 1,
			Name = "Confete",                -- identificador único (letras, números, _ - .)
			Category = "Players",            -- Players, Moderation, Game... ou sua própria categoria
			Mode = "target",                 -- "action" | "target" (um jogador) | "toggle" | "slider"
			MinRank = "Staff",               -- cargo mínimo padrão
			Label = { pt = "Confete", en = "Confetti" },
			Description = { pt = "Joga confete.", en = "Throws confetti." },
			-- opcional: Group, Order, Color, Confirm, AllowSelf, Min / Max / Default (slider),
			--           Fields = { { Name = "Quantidade", Type = "number", Min = 1, Max = 100 } },
			--           Inputs = { "Reason", "Minutes" }, Init = function(ctx) end, OnAccessRevoked = function(ctx, player) end
			Execute = function(ctx, admin, target, value)
				-- o servidor já conferiu cargo, acesso, hierarquia e valores
				return true, "Confete jogado!"   -- (sucesso, mensagem mostrada ao admin)
			end,
		}
		Tipos de campo: "number", "choice" (Options), "text", "string". Cada execução vai para o registro.

	B) Uma integração de servidor: um ModuleScript em APM_Extensions > Server
		return { ApiVersion = 1, Id = "MeuJogo", Init = function(api)
			-- api.RegisterCommand(comando), api.RegisterOptions(nome, provedor), api.AddProfileProvider(fn),
			-- api.RegisterAdapter(nome, adaptador), api.HasPermission(jogador, permissão), api.CanTarget(admin, alvo),
			-- api.Authorize(admin, comando, alvo), api.Notify(jogador, mensagem, sucesso), api.Log(ator, ação, alvo, detalhe)
		end }
	Registre os comandos diretamente em Init(api), antes de qualquer tarefa adiada, e confira os resultados.
	Não chame APM.WaitForReady() dentro de Init: o APM já está esperando essa inicialização terminar.

	C) Um adaptador AutoBridge: APM_Extensions > Adapters  →  { ApiVersion = 1, Id = "...", Adapter = { Permission, Probe, Actions } }
	D) Uma página do painel: APM_Extensions > ClientPages > MonJeu > MonJeuPage (ModuleScript dentro de sua pasta de namespace).
	   Mantenha os atributos ApiVersion = 1 e Permission = "MonJeu.Page" do ModuleScript. Declare explicitamente
	   Settings.PermissionDefaults = { ["MonJeu.Page"] = "Owner" } no ServerSettings ativo; escolha seu cargo mínimo.
	   Retorne uma tabela com ApiVersion = 1, a mesma Permission, um Id válido e único = "MonJeuPage" e Build(Core, page).
	   Label, Order e Visible(Core) são opcionais. Handles só pode listar categorias deste namespace.
	   Os Id usam letras, números, _, . ou - e não podem repetir os Id do APM.
	   Use APM_DeveloperTemplates.ClientPages.MonJeu.MonJeuPage como exemplo funcional. A página só é enviada a admins
	   autorizados. Não coloque segredos no código cliente. Use Core.On(signal, callback) para as conexões e
	   Core.Action(command, target, value) para comandos autorizados do servidor.

	E) A partir dos seus outros scripts de servidor:
		local ServerStorage = game:GetService("ServerStorage")
		local core = ServerStorage:WaitForChild("APM_Core", 10)
		local server = core and core:WaitForChild("Server", 10)
		local service = server and server:WaitForChild("APMService", 10)
		assert(service and service:IsA("ModuleScript"), "APMService indisponível.")
		local APM = require(service)
		APM.WaitForReady()
		APM.IsAdmin(jogador)  APM.GetRank(jogador)  APM.HasRankAtLeast(jogador, "Staff")
		APM.Notify(jogador, texto, sucesso)  APM.Log(ator, ação, alvo, detalhe, categoria, "info"|"warning"|"danger")
		APM.AddProfileProvider(fn)  APM.RegisterOptions(nome, fn)  APM.TrackDataStore(store, "Nome")

	O estado das extensões (carregadas / erros) aparece na aba Diagnósticos.


	=====================================================================================================
	7. ATUALIZAÇÕES E AJUDA
	=====================================================================================================

	• Atualizar: substitua o APM_Kit pela nova versão. Mantenha sua pasta APM_Extensions: uma configuração
	  externa ServerStorage.APM_Extensions compatível é mantida e tem prioridade. Nunca altere o APM_Core.
	• O painel não abre? Confira seu cargo (Settings.Users), se o ToolboxBootstrap está ativado e se o kit
	  não está sozinho no ServerStorage. A saída (Output) mostra "[APM] Serveur prêt" (servidor pronto) se tudo estiver certo.
	• Preso numa simulação de cargo? Digite /apm-restore no chat.
	• Aparece "modo memória"? Normal no Studio: nada é salvo durante seus testes.


	REGISTRO DE ALTERAÇÕES 2.10.2
	• NOVO: Sentinel, assistente de comandos flutuante (móvel, duas setas de recolhimento independentes, modo ultracompacto).
	• NOVO: aba Sentinel Helper (preferências, configurações do servidor, comandos personalizados, IA externa opcional, teste do motor).
	• NOVO: interruptor do Sentinel no Início; preferências por conta (posição, recolhimento, tamanho, animação).
	• NOVO: permissões Assistant.Use / Configure / Commands / External; categoria Sentinel (assistente) em Funções e acesso.
	• NOVO: speed e jump aceitam um alvo (speed bob 50); freeze e mute expõem seu estado (nunca alternados por engano).
	• ALTERADO: APMService.perform é o núcleo de execução comum dos botões do painel e do Sentinel (mesmas verificações, mesmo registro).
	• ALTERADO: Preferences aceita 4 campos pessoais (AssistantEnabled, AssistantLayout, AssistantWave, AssistantScale); SuiteConfig aceita a seção SentinelAssistant.
	• NOVO: ações distribuídas (Dispatcher + ActionExecutor): Fly e Noclip também se aplicam a outros jogadores ("fly bob", "fly all", "unfly bob", "noclip bob"), validadas pelo servidor, executadas no dispositivo do alvo e confirmadas por ele.
	• NOVO: cada ação distribuída é controlada pelo servidor (cargo, permissão da ferramenta, hierarquia: "all" nunca contorna uma proteção), traz um identificador único com expiração e termina com um balanço em números (afetados, protegidos, falhas, não confirmados). A resposta de um cliente é uma confirmação, nunca uma prova absoluta: o servidor verifica o que pode (Fly: estado do Humanoid; Noclip: colisões).
	• NOVO: aba Jogadores, cartão "Poderes sobre o jogador" (interruptor no jogador escolhido, botões "todos" com confirmação); "spectate bob" observa um jogador; "esp bob" é recusado de propósito (o ESP é uma visão local, nunca dada a outro jogador).
	• MUDANÇA: Fly e Noclip compartilham UM único controlador (APM_Shared > ActionExecutor > Effects) entre o interruptor do painel e o servidor: sem duplicatas. Novos remotes: ActionDispatch / ActionReport (públicos, somente respostas), DispatchAction (painel do administrador).
	• MUDANÇA: "all" em um comando de servidor dá um balanço "Freeze: 8 afetados, 2 protegidos, 0 falhas, 1 ignorado".
	• Desenvolvedores: adicionar uma ação distribuída = declará-la em ActionCatalog + um controlador em ActionExecutor/Effects (+ Dispatcher/Hooks opcional); Settings.Modules.Dispatcher = false a desativa. Nada é salvo: os efeitos terminam quando o jogador sai.
	• Sem migração de dados: DataSchemaVersion continua 2; configurações e salvamentos existentes intactos.
	• NEW: Sentinel multilíngue: comandos em português, inglês, francês, espanhol, alemão, russo e chinês ao mesmo tempo, independentes do idioma da interface; uma única ação canônica, mesmas permissões, proteções e confirmações.
	• NEW: alvo implícito: «fly», «unfly», «noclip» agem sobre você; «fly Bob» mira um jogador; «fly all» (e suas traduções) sempre pede confirmação.
	• CHANGE: todo alvo «all» é confirmado (kill, freeze, mute, heal, respawn, bring, speed, jump, fly, noclip), mesmo com ConfirmDangerous = false; a confirmação é ligada à ação canônica e aos jogadores resolvidos.
	• CHANGE: uma palavra reservada que também é o nome de um jogador presente (All, Ich, On...) é ambígua: use @UserId.
	• NEW: cartão «Idiomas dos comandos» no Sentinel Helper, teste do motor ampliado; normalização Unicode (cirílico, chinês, largura total, acentos); comprimento em caracteres (200), não em bytes.
	• Desenvolvedores: CommandLocalization (um ModuleScript por idioma); um 8.º idioma = um ModuleScript a mais.

	• NOVO: «help» abre um catálogo interativo: TODOS os comandos do registro em uma grade de 3 colunas. Um comando que você não pode executar mostra um cadeado (calculado pelo servidor; não concede nada). Tocar em um comando apenas o PREPARA no campo de digitação (nunca é executado).
	• NOVO: preenchimento automático: comandos e aliases (7 idiomas), jogadores (usuário, nome de exibição, @UserId), seletores, on/off e durações válidas para o comando; setas para percorrer, Tab para completar, Enter envia (ou completa uma sugestão escolhida com as setas), Esc fecha. Só comandos registrados e permitidos são sugeridos; cálculo local, nenhuma requisição por tecla.
	• NOVO: durações: 10s · 5m · 2h · 1d (e suas traduções). Uma duração que um comando não consegue cumprir é recusada com uma mensagem: ban trabalha em minutos inteiros (30s e 0,5 são recusados em vez de virar um banimento permanente); um formato desconhecido (1w) nunca é engolido pelo motivo.
	• CORREÇÃO: Início e Sentinel Helper leem o mesmo estado: desligar o Sentinel pelo Início aparece na hora no Sentinel Helper (e vice-versa); fechar o APM nunca o altera.
	• MUDANÇA: a seta da área de digitação segue a posição da janela (metade esquerda: recolhe para a esquerda; metade direita: para a direita); as setas têm uma discreta pastilha escura para continuar visíveis em fundos claros.

	Licença MIT · Grátis · Criado por APM contributors

]==]
return {}
