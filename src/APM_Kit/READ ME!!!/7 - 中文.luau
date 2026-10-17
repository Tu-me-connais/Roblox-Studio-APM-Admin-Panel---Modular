--[==[

	APM | Admin Panel - Modular — 完整指南（简体中文）
	版本 2.10.2（稳定版）· MIT 许可 · 免费 · 作者：APM contributors
	=====================================================================================================

	APM 是一个帮助开发者管理体验的管理面板：管理玩家、等级、安全、统计和趣味效果。
	所有操作都会由服务器重新验证，没有权限的玩家不会收到任何东西。

	目录
		1. 安装
		2. 面板语言
		3. 配置
		4. 系统
		5. 模块
		6. 扩展（面向开发者）
		7. 更新与帮助


	=====================================================================================================
	1. 安装
	=====================================================================================================

	1) 从 Toolbox 插入 APM_Kit（放在 Workspace 或 ServerScriptService 都可以）。
	   不要只放在 ServerStorage 里：那里的脚本不会运行。
	2) 保持 ToolboxBootstrap 脚本启用（RunContext：Server）。启动时它会自动把套件移到 ServerStorage，
	   并在 ServerScriptService 中启动一个私有加载器。
	   Installer 和 APM_Bootstrap 脚本保持禁用：它们只用于手动安装。
	3) 在生效的 ServerSettings 文件中为自己分配等级（见第 3 节），然后添加你的 UserId：
			Settings.Users = { [123456789] = "Owner" }
	   UserId 在你的个人资料网址中：roblox.com/users/<UserId>/profile
	   默认不授予任何账户等级。在这个当前生效的文件中，将 123456789 替换为你自己的 UserId。
	4) 点击 Play。点击屏幕上方的小“APM”按钮或按 F2 打开面板。
	   Z 将窗口居中。在“首页”中可以隐藏按钮并更换按键。
	5) 保存：已发布的游戏使用 DataStores。Studio 默认使用内存模式（Settings.StudioMemory = true），更改仅保留在当前会话中。
	   要在 Studio 中测试 DataStores，请在生效的 ServerSettings 中设置 Settings.StudioMemory = false，并在游戏设置 > 安全中
	   启用 "Enable Studio Access to API Services"。这些测试可能会写入真实存档。

	小贴士
	• APM 按钮会检查屏幕上的 16 个位置，避免遮挡你的界面；如果全部被占用，它会叠加在左下角。
	• 面板打开时，会自动显示在所有游戏界面的前面。
	• 不下载任何代码，游戏运行时不修改任何脚本，也不会自动发布任何内容。


	=====================================================================================================
	2. 面板语言
	=====================================================================================================

	7 种语言：français (fr)、English (en)、español (es)、português (pt)、Deutsch (de)、русский (ru)、中文 (zh)。
	• 默认情况下，每位管理员看到的是自己 Roblox 账号的语言。
	• 面板顶部的语言按钮（例如“ZH v”）可以切换语言；选择会被保存。
	• 玩家看到的公告、警告和禁言提示也是他们自己的语言。
	• 在 SharedConfig 中：
			Config.ForceLanguage = "zh"     -- 所有人使用同一种语言（nil = 账号语言）
			Config.DefaultLanguage = "en"   -- 备用语言
	• 翻译：APM_Core > Shared > Lang > Tabs（每个标签页一个模块，包含所有语言）。Lang > <语言> 和 Lang > Phrases 模块仍可用于您自己的文本。


	=====================================================================================================
	3. 配置
	=====================================================================================================

	只编辑生效的 APM_Extensions > Config 文件夹。如果 ServerStorage.APM_Extensions 已存在，它的优先级高于 APM_Kit.APM_Extensions。
	否则，先使用套件中的文件夹。首页和诊断显示生效的 SourcePath，并提示重复配置：请先编辑所指示的文件。
	切勿修改 APM_Core；更新会替换它。
	默认值（逐行注释）位于 APM_Core > Server > Settings 和 APM_Core > Shared > Config。
	要修改某个值，把那一行复制到你的文件中：它会替换默认值。
	• 表（例如 Settings.Funny = { MaxDuration = 30 }）只替换你写出的键；
	• 列表（Ranks、ClientTools、ToolSources）会被整体替换；
	• Settings.RemoveKeys = { "键名" } 会删除一个默认值。

	ServerSettings（仅服务器读取）
		Ranks               等级，从高到低（Id、Level、Color、Fixed、Name）
		SuperRank           "Dev"：访问权限可配置，任何人都不能以其为目标
		ManagerRank         "Owner"：使用“设置”标签页的最低等级
		AnnounceRank        "Staff"：可以向整个服务器发布公告
		CreatorRank         默认为 nil：不自动授予等级。只有明确需要时，才为本体验（或所属群组）的所有者启用 "Owner"，绝不授予 APM 作者。
		                    要启用此选项，还需从 Settings.RemoveKeys 中移除 "CreatorRank"，然后设置 Settings.CreatorRank = "Owner"。
		Users               按 UserId 设置的固定等级（优先，不能在面板中修改）
		DefaultUsers        初始等级（之后可在面板中修改）
		Group               { Id = 群组, Ranks = { [群组内最低等级] = "等级" } }
		StudioRank          可选的 Studio 测试等级（默认为 nil：不自动授予等级）；对线上游戏无效
		DataStoreName       "APM_Data_v1"：整个 APM 只用一个 DataStore（更改后从零开始）
		MessagingTopic      在服务器之间同步权限和封禁
		MaxLogs / MaxRoster / MaxWarnings   300 / 20000 / 25
		ToolSources         “给予工具”查找 Tool 的文件夹（默认 ServerStorage）
		PermissionDefaults  每个命名权限的默认最低等级（APM.*、Sentinel.*、Funny.*...）
		Modules             关闭可选系统：{ Simulation, AutoBridge, Sentinel, Funny, Assistant }
		Funny               { MaxDuration = 60, MaxActiveScenes = 16, MaxGroupTargets = 8, CrossServerEnabled = true }
		ClientTools         管理员工具：{ "Fly", "Noclip", "ESP", "Spectator" }
		DisabledCommands    移除某个命令：{ Kill = true }
		AutoBridge          { Enabled, ScanInterval = 30, MaxScanInstances = 1500, EnableTeamActions = false }
		Sentinel            { Enabled, Mode = "Observation", Interval = 1, CorrectPosition = false, AllowKick = false }
		Assistant           { Enabled, MaxHistory = 40, ReplyStyle = "Short", ConfirmDangerous, AllowAll, MaxAllTargets = 25, RatePerWindow = 8, DefaultDeployed, WaveEnabled, WaveInterval = 30, AnimationSpeed, External = { Enabled = false, Hosts = {}, SecretName, ApiKey, Model } }  -- Sentinel 2.10.2

	SharedConfig（服务器和客户端都会读取：不要放任何秘密）
		ForceLanguage、DefaultLanguage、OpenKey（F2）、RecenterKey（Z）、Title、Theme（逐个颜色）、
		LauncherButton、MobileButton、LanguageButton


	=====================================================================================================
	4. 系统
	=====================================================================================================

	等级
	• 默认：Dev (5) > Owner (4) > CoOwner (3) > Staff (2) > StaffTest (1)。
	• 管理员只能对等级严格低于自己的人操作；Dev 永远不能被当作目标。
	• 账号的等级取各来源中最高的一个：Users、创建者、面板 / DefaultUsers、群组、Studio。
	• “Fixed”等级只能在配置中给予，不能在面板中给予。
	• 等级列表显示等级来源，以及移除面板分配后仍会保留的等级。
	  移除分配不会撤销固定来源或群组授予的访问权限；实际所有者可使用单独的撤销访问操作。

	功能与权限（“设置”标签页）
	• 按类别列出整个 APM。“启用”列为整个游戏开启或关闭某功能；等级列决定谁可以使用。
	  类别行可一次勾选整个类别。
	• Dev 和其他等级一样，遵循默认 MinRank 和为其等级保存的访问权限设置。
	• 橙色 = 部分选中；灰色 = 超出你的权限。面板和设置的访问权限永远不会被批量移除。
	• 修改会被保存，并同步到所有服务器（MessagingService）。

	安全（“安全”标签页）
	• 永久权限、命令和工具统一在设置 > 功能与权限中配置，并支持搜索。安全会打开同一个编辑器。
	• 以较低等级进行五分钟测试。通过复选框选择测试权限；JSON 是高级选项。只能选择你真实拥有的权限。
	  使用按钮或 /apm-restore 恢复真实等级；如果面板消失，请使用专用恢复按钮。
	• 等级模拟：以较低等级测试面板 5 分钟；在聊天中输入 /apm-restore 可立即恢复真实等级。
	• 安全模型：每位管理员都有自己的私有 remote；服务器在每次请求时重新检查等级、权限、
	  层级、数值和防刷。没有等级的玩家不会收到面板、按钮或任何管理 remote：
	  只会看到公开显示的公告、警告和禁言提示。

	保存
	• 只用一个 DataStore（APM_Data_v1）：等级、权限矩阵、封禁、警告、日志和玩家名录。
	• 限制写入以节省配额：名录分批保存（约每 5 分钟一次），偏好设置仅在改变时保存。
	• 没有 DataStore 时（Studio 未开启 API 访问）：内存模式，不保存任何内容。

	首页
	• 服务器状态、性能（取决于你的权限）、可搜索的在线玩家及详细资料，以及 AutoBridge、Sentinel 和诊断摘要。
	  首页可见时每 15 秒刷新一次。
	• 打开面板：显示 / 隐藏低调按钮，更换按键。

	统计（“统计”标签页）
	• 图表：面板使用情况、玩家、服务器性能（心跳、内存、网络）以及最繁忙的 DataStore。
	  每 15 秒一个数据点，保存在服务器内存中（不写入任何内容）。
	• 要统计你自己游戏的 DataStore（服务器脚本）：
			local ServerStorage = game:GetService("ServerStorage")
			local core = ServerStorage:WaitForChild("APM_Core", 10)
			local server = core and core:WaitForChild("Server", 10)
			local service = server and server:WaitForChild("APMService", 10)
			assert(service and service:IsA("ModuleScript"), "APMService 不可用。")
			local APM = require(service)
			APM.WaitForReady()
			local DataStoreService = game:GetService("DataStoreService")
			local store = APM.TrackDataStore(DataStoreService:GetDataStore("PlayerData"), "PlayerData")
			-- 然后照常使用 store（GetAsync、SetAsync、UpdateAsync...）

	日志（Logs 标签页）  • 每个管理操作都会被记录（300 条），可按类别和严重程度筛选。
	封禁                • 封禁在线玩家或离线账号（准确用户名或 UserId），可限时或永久，在所有服务器生效；
	                      在“封禁”标签页解封。
	服务器锁定          • 阻止没有等级的玩家加入本服务器；维护功能会用到它。

	SENTINEL GUARD（反作弊）
	• 在服务器端监测异常速度和传送，并考虑容差（延迟、出生、座位、物理）。
	  模式：观察（默认）、平衡、严格。
	• 默认只向管理员报告。位置修正：可选。自动踢出：仅当 Settings.Sentinel.AllowKick = true 时。
	  提供模拟数据诊断，无需真实玩家即可测试。
	• 设置来源显示实际生效的值、脚本值，以及已保存的覆盖设置或当前 Studio 会话的覆盖设置。
	  恢复脚本值会移除已保存的覆盖设置，包括通过面板添加的安全区，并立即恢复脚本值；脚本中定义的安全区会保留。

	AUTOBRIDGE（集成）
	• 检测你的游戏已使用的内容：leaderstats、队伍、工具、载具座位。
	• 绝不执行未知代码。队伍更换默认关闭（EnableTeamActions）。
	• 在首页 > 集成与设置中查看每个实际生效的值及其来源。
	  恢复脚本值会移除已保存的覆盖设置，并立即恢复脚本值。

	FUNNY（趣味效果，Funny 标签页）
	• ① 在网格中选择一个效果（旁边有 3D 预览），然后 ▶ 启动；② 调整活力、时长、范围和目标。
	• 场景：彩纸、迪斯科、鸭子、泡泡、土豆陫下、太阳系、雪花、爱心、烟花、彩虹。
	• 变形：大头、Roblox 账号外观、复制/交换身体部位、反重力、倒立角色（玩家仍可控制移动）。
	• 范围：本地、服务器、跨服。一切都是临时的，目标受等级保护，结束时恢复外观，并始终有停止按钮。

	诊断： 首页和诊断显示生效的配置和重复配置提示。扩展诊断包括 SourcePath、无效字段、收到的值、预期值和修复方法。


	SENTINEL（悬浮命令助手）与 SENTINEL HELPER — 2.10.2 新增
	（请勿与上方的反作弊 Sentinel Guard 混淆）
	• Sentinel 是一个可移动的小窗口，独立于面板：APM 关闭后它仍留在屏幕上。
	  输入命令（fly、freeze bob、bring bob、speed bob 50、unfly me、kick bob spam……）。它是本地规则引擎，
	  不是生成式 AI：无需联网。help 列出您可用的命令，help <命令> 显示详情，clear 清空历史。
	• 命令就是 APM 自己的命令：注册表中的每个模块和客户端工具（玩家、管理、游戏、封禁、您的扩展）。
	  目标：me、all、精确的用户名、UserId，或只匹配一名玩家的部分名称（匹配多名时 Sentinel 会要求更具体）。
	  别名：tp、vitesse、geler……（英文和法文）。
	• 安全：客户端只发送文本。服务器用与面板按钮相同的代码检查身份、等级、权限、层级（受保护的等级依然受保护）、
	  参数范围和频率（默认每 10 秒 8 条命令）。敏感命令（kick、ban、shutdown）需要确认。绝不会执行任何代码。kick / ban 不接受 all。
	• fly / noclip / esp / spectate 只作用于您自己（客户端工具）：服务器授权，您的设备应用，Sentinel 在确实生效后才确认。
	  speed / jump 接受玩家和 all：speed bob 50、speed all 20。
	• 窗口：拖动标题栏或左侧手柄；两个独立箭头分别收起对话区（上方箭头）和输入区（侧边箭头）；两者都收起时只剩一个
	  不可拖动的箭头，点击即可全部恢复。位置和收起状态按账号保存。箭头的明暗波每 30 秒经过一次（可调整、可关闭）。
	• 主页：Sentinel 开关可为您的账号启用或停用它（APM 可以保持关闭）。
	• Sentinel Helper 标签页（开发组）：我的偏好（本地）/ 服务器设置（所有人）/ 自定义命令 / 可选的外部 AI / 引擎测试 / 存储。
	  权限：Assistant.Use（StaffTest）、Assistant.Configure、Assistant.Commands、Assistant.External（Owner）。设置保存在
	  APM 的 DataStore（SuiteSettings_v2，SentinelAssistant 部分）；Studio 内存模式只在本次会话中保留它们。
	• 自定义命令是数据（名称、参数、权限和一个允许的操作：回复文本、传送到某点、运行最多 5 条现有命令），绝不是 Lua 代码。
	  每一步都以输入者的权限运行。
	• 外部 AI（可选，默认关闭）：需要在 ServerSettings 中设置 Settings.Assistant.External（Hosts = { "api.example.com" }、
	  SecretName 或 ApiKey）并启用 HTTP 请求。密钥绝不会到达客户端或 DataStore。AI 只看到输入的文本和命令名称；
	  它提出的命令需要您确认，服务器会像检查其他命令一样检查它。
	• ServerSettings：Settings.Assistant = { Enabled, MaxHistory, ReplyStyle, ConfirmDangerous, AllowAll, MaxAllTargets, RatePerWindow,
	  DefaultDeployed, WaveEnabled, WaveInterval, AnimationSpeed, External = {...} }；Settings.Modules.Assistant = false 可将其关闭。

	SENTINEL 命令语言（7 种语言）— 多语言识别
	• Sentinel 同时理解中文、英语、法语、西班牙语、葡萄牙语、德语和俄语。你输入命令所用的语言与面板界面语言无关：界面是中文，也可以先用俄语、再用法语输入命令，无需更改任何设置。
	  所有表述都对应同一个规范动作（模块名：Fly、Freeze、Kick……）；权限、保护、确认和日志与英文命令完全相同。翻译绝不会多给任何权限。
	• 示例（都等于 Fly）：fly · voler · volar · voar · fliegen · летать · 飞行（飛行）。停止形式：unfly · arrêter de voler · dejar de volar · parar de voar ·
	  stopp fliegen · перестать летать · 停止飞行。可以混用：“飞行 all”、“fly 所有人”。大小写、重音以及全角字母 / 空格都不影响（é = e、ß = ss、ё = е、Ｆｌｙ = fly）。
	  简体与繁体中文逐一列出。不做猜测：未知命令仍然是未知命令（只给出建议）。
	• 目标，三种形式在所有语言中一致：
	    – 不写目标：支持目标的命令作用于你自己（fly、unfly、noclip、speed 50……）；
	    – 用户名：fly Bob（不会被翻译或改动；唯一的名称前缀可以接受，有歧义则拒绝）；
	    – all（所有人、tous、todos、alle、все……）：所有被允许的玩家，并且始终先经过确认，确认中会写明规范动作、方向（关）和玩家人数。缺少目标绝不等于“all”。
	  “me”：我、me、moi、yo、eu、ich、я……需要目标的命令（kick、freeze、bring……）仍然必须写目标；spectate 保持原意（观察某个玩家，仅限本地）；esp 仍然只在本地。
	• 确认：现在所有“all”都需要确认（即使 ConfirmDangerous = false）。确认绑定到规范动作、方向和实际解析出的玩家：换命令、换方向、换玩家列表或令牌过期（20 秒）都会重新询问。
	• 若保留字同时是在场玩家的名字（名为 All、Ich、On 的玩家），Sentinel 绝不猜测：会要求用 @UserId 说明（或 @名字；@me 和 @all 仍是选择器）。
	• 回复遵循 APM 的语言设置，而不是你输入的语言。
	• 自定义命令：名称仍为 ASCII；已被任意语言的官方表述占用的名称或别名会被拒绝（官方表述优先；冲突列在 Sentinel Helper > 存储）。含“fly all”的步骤仍需确认。
	• Sentinel Helper >“命令语言”：按语言列出官方表述（只读）；引擎测试会显示识别出的语言、规范动作、方向、目标以及是否需要确认。
	• 开发者：表述位于 Server > Core > Assistant > CommandLocalization（每种语言一个 ModuleScript：Commands、Off、OffPrefixes、Selectors、Booleans、Units、Local、Choices）。
	  添加第 8 种语言 = 添加一个以语言代码命名的子 ModuleScript（格式与 fr / en 相同），无需修改其他任何内容。若某表述会指向两个动作，则被排除并报告（Report().Collisions）；
	  两种语言为同一动作共用的表述属于正常情况。
	• 限制：仅支持结构化命令（不理解自由句子）；中文中命令与参数之间用空格分隔；在一种语言中是选择器或 on / off 的词，在所有语言中都是保留词；小数“1,5”可接受，“1,000”会被拒绝（有歧义）。

	=====================================================================================================
	5. 模块
	=====================================================================================================

	每个模块都可以在“设置 > 功能与权限”中关闭，或只对部分等级开放。

	玩家标签页（先选择玩家，再选择操作）
		踢出 (Kick) · 封禁 (Ban) · 警告 (Warn) · 禁言 (Mute) · 冻结 (Freeze) · 击杀 (Kill)
		治疗 (Heal) · 重生 (Respawn) · 拉到身边 (Bring) · 前往 (Teleport)
		送回 (Return) · 回到出生点 (ToSpawn)
		Kick、Ban、Warn、Mute 和 Freeze 可填写原因和时长（分钟，留空 = 永久）。
		“全局”视图：所有曾经加入过的账号名录，包括离线账号。

	管理标签页（作用于你自己）
		Godmode（无限生命）· 隐身 · 行走速度 · 跳跃力量
		工具：Fly（飞行）、Noclip（穿墙）、ESP（透过墙看到玩家）、Spectator（观察玩家）
		全服公告。

	游戏标签页
		给予工具 (GiveTool) · Leaderstats（修改数值）· 游戏时间 (TimeOfDay)
		服务器维护 (Shutdown)：锁定服务器、发布公告，并在延时后踢出没有等级的玩家。

	封禁标签页
		封禁列表、解封 (Unban)、按准确用户名或 UserId 封禁账号。


	=====================================================================================================
	6. 扩展（面向开发者）
	=====================================================================================================

	将扩展添加到生效的 APM_Extensions 文件夹。APM_DeveloperTemplates 不会运行：先阅读 START_HERE，
	再仅将所需示例复制到对应的生效文件夹。
	• Commands.MonJeu.MonJeu_Informer：将 MonJeu 文件夹复制到 Commands。
	• ClientPages.MonJeu.MonJeuPage：将 MonJeu 复制到 ClientPages。
	• Server.MonJeuIntegration 和 Adapters.MonJeuStatus：将各 ModuleScript 复制到对应文件夹。
	请选择唯一的命令名称和命名空间。权限不会自动添加：请在生效的 ServerSettings 的 Settings.PermissionDefaults 中
	明确声明 MonJeu.Page / MonJeu.Status，并设置所需的最低等级。更改源代码或配置后，请重新启动 Play。

	A) 命令：APM_Extensions > Commands 中的一个 ModuleScript
		return {
			ApiVersion = 1,
			Name = "Confetti",               -- 唯一标识（字母、数字、_ - .）
			Category = "Players",            -- Players、Moderation、Game... 或自定义类别
			Mode = "target",                 -- "action" | "target"（一名玩家）| "toggle" | "slider"
			MinRank = "Staff",               -- 默认最低等级
			Label = { zh = "彩纸", en = "Confetti" },
			Description = { zh = "撒彩纸。", en = "Throws confetti." },
			-- 可选：Group、Order、Color、Confirm、AllowSelf、Min / Max / Default（slider）、
			--       Fields = { { Name = "Amount", Type = "number", Min = 1, Max = 100 } }、
			--       Inputs = { "Reason", "Minutes" }、Init = function(ctx) end、OnAccessRevoked = function(ctx, player) end
			Execute = function(ctx, admin, target, value)
				-- 服务器已经检查过等级、权限、层级和数值
				return true, "彩纸已撒出！"   -- （是否成功, 显示给管理员的消息）
			end,
		}
		字段类型："number"、"choice"（Options）、"text"、"string"。每次执行都会写入日志。

	B) 服务器集成：APM_Extensions > Server 中的一个 ModuleScript
		return { ApiVersion = 1, Id = "MyGame", Init = function(api)
			-- api.RegisterCommand(command), api.RegisterOptions(name, provider), api.AddProfileProvider(fn),
			-- api.RegisterAdapter(name, adapter), api.HasPermission(player, permission), api.CanTarget(admin, target),
			-- api.Authorize(admin, command, target), api.Notify(player, message, success), api.Log(actor, action, target, detail)
		end }
	在 Init(api) 中同步注册命令，在创建延后任务之前完成注册，并检查结果。
	不要在 Init 内调用 APM.WaitForReady()：APM 已在等待该初始化完成。

	C) AutoBridge 适配器：APM_Extensions > Adapters  →  { ApiVersion = 1, Id = "...", Adapter = { Permission, Probe, Actions } }
	D) 面板页面：APM_Extensions > ClientPages > MonJeu > MonJeuPage（ModuleScript 位于其命名空间文件夹内）。
	   保留 ModuleScript 属性 ApiVersion = 1 和 Permission = "MonJeu.Page"。在生效的 ServerSettings 中明确声明
	   Settings.PermissionDefaults = { ["MonJeu.Page"] = "Owner" }，并自行选择最低等级。
	   返回一个表，包含 ApiVersion = 1、相同的 Permission、唯一且有效的 Id = "MonJeuPage"，以及 Build(Core, page)。
	   Label、Order 和 Visible(Core) 为可选项。Handles 只能列出属于此命名空间的类别。
	   标识符可使用字母、数字、_、. 或 -，且不得与 APM 的标识符冲突。
	   使用 APM_DeveloperTemplates.ClientPages.MonJeu.MonJeuPage 作为可运行的示例。页面只发送给拥有相应权限的管理员。
	   切勿在客户端代码中存放秘密信息。使用 Core.On(signal, callback) 建立连接，
	   使用 Core.Action(command, target, value) 调用已获授权的服务器命令。

	E) 在你的其他服务器脚本中：
		local ServerStorage = game:GetService("ServerStorage")
		local core = ServerStorage:WaitForChild("APM_Core", 10)
		local server = core and core:WaitForChild("Server", 10)
		local service = server and server:WaitForChild("APMService", 10)
		assert(service and service:IsA("ModuleScript"), "APMService 不可用。")
		local APM = require(service)
		APM.WaitForReady()
		APM.IsAdmin(player)  APM.GetRank(player)  APM.HasRankAtLeast(player, "Staff")
		APM.Notify(player, text, success)  APM.Log(actor, action, target, detail, category, "info"|"warning"|"danger")
		APM.AddProfileProvider(fn)  APM.RegisterOptions(name, fn)  APM.TrackDataStore(store, "Name")

	扩展的状态（已加载 / 错误）显示在“诊断”标签页中。


	=====================================================================================================
	7. 更新与帮助
	=====================================================================================================

	• 更新：用新版本替换 APM_Kit。保留你的 APM_Extensions 文件夹：兼容的外部配置
	  ServerStorage.APM_Extensions 会被保留并优先使用。永远不要修改 APM_Core。
	• 面板打不开？检查你的等级（Settings.Users）、ToolboxBootstrap 是否启用，以及套件是否只放在
	  ServerStorage 中。一切正常时，输出窗口（Output）会显示“[APM] Serveur prêt”（服务器就绪）。
	• 卡在等级模拟中？在聊天中输入 /apm-restore。
	• 显示“内存模式”？在 Studio 中很正常：测试期间不会保存任何内容。


	更新日志 2.10.2
	• 新增：Sentinel 悬浮命令助手（可移动、两个独立的收起箭头、超紧凑模式）。
	• 新增：Sentinel Helper 标签页（偏好、服务器设置、自定义命令、可选外部 AI、引擎测试）。
	• 新增：主页上的 Sentinel 开关；按账号保存偏好（位置、收起状态、大小、动画）。
	• 新增：权限 Assistant.Use / Configure / Commands / External；“功能与访问”中新增 Sentinel（助手）类别。
	• 新增：speed 和 jump 支持目标（speed bob 50）；freeze 和 mute 提供可读状态（不会误切换）。
	• 变更：APMService.perform 成为面板按钮与 Sentinel 共用的执行核心（相同检查，相同日志）。
	• 变更：Preferences 接受 4 个个人字段（AssistantEnabled、AssistantLayout、AssistantWave、AssistantScale）；SuiteConfig 接受 SentinelAssistant 部分。
	• 新增：分布式操作（Dispatcher + ActionExecutor）：Fly 和 Noclip 现在也可用于其他玩家（“fly bob”“fly all”“unfly bob”“noclip bob”），由服务器验证，在目标玩家自己的设备上执行并由其确认。
	• 新增：每个分布式操作都由服务器把关（等级、工具权限、层级：“all”绝不绕过保护），带有唯一标识和有效期，并以数字汇总结束（已影响、受保护、失败、未确认）。客户端的回复只是确认，而不是绝对证据：服务器会验证它能验证的内容（Fly：Humanoid 状态；Noclip：碰撞）。
	• 新增：玩家标签页的“玩家能力”卡片（对所选玩家切换，“所有人”按钮需确认）；“spectate bob”用于观察玩家；“esp bob”被有意拒绝（ESP 是本地视图，绝不授予其他玩家）。
	• 变更：面板开关与服务器共用唯一的 Fly / Noclip 控制器（APM_Shared > ActionExecutor > Effects）：不会重复。新增 remotes：ActionDispatch / ActionReport（公开，仅回复）、DispatchAction（管理员面板）。
	• 变更：对服务器命令使用“all”会给出汇总：“Freeze：已影响 8，受保护 2，失败 0，跳过 1”。
	• 开发者：添加分布式操作 = 在 ActionCatalog 中声明 + 在 ActionExecutor/Effects 中添加控制器（可选 Dispatcher/Hooks）；Settings.Modules.Dispatcher = false 可禁用。不保存任何数据：玩家离开后效果即结束。
	• 无数据迁移：DataSchemaVersion 仍为 2；现有配置和存档不受影响。
	• NEW：多语言 Sentinel：同时支持中文、英语、法语、西班牙语、葡萄牙语、德语和俄语命令，与界面语言无关；同一个规范动作，相同的权限、保护和确认。
	• NEW：隐式目标：“fly”、“unfly”、“noclip”作用于你自己；“fly Bob”指定某个玩家；“fly all”（及其各语言译法）始终需要确认。
	• CHANGE：任何“all”目标都需要确认（kill、freeze、mute、heal、respawn、bring、speed、jump、fly、noclip），即使 ConfirmDangerous = false；确认绑定到规范动作和实际解析出的玩家。
	• CHANGE：与在场玩家名字相同的保留词（All、Ich、On……）有歧义：请使用 @UserId。
	• NEW：Sentinel Helper 新增“命令语言”卡片，引擎测试更详细；Unicode 规范化（西里尔字母、中文、全角、重音）；长度按字符（200）而非字节计算。
	• 开发者：CommandLocalization（每种语言一个 ModuleScript）；第 8 种语言 = 再加一个 ModuleScript。

	• 新增：“help”现在打开交互式命令目录：以 3 列网格显示注册表中的全部命令。你无权执行的命令带有挂锁（由服务器计算，不赋予任何权限）。点击命令只会在输入框中“准备”它（绝不会执行）。
	• 新增：自动补全：命令与别名（7 种语言）、玩家（用户名、显示名、@UserId）、选择器、on/off 以及该命令适用的时长；方向键浏览，Tab 补全，Enter 发送（或补全你用方向键选中的建议），Esc 关闭。只建议已注册且你有权使用的命令；本地计算，每次按键都不发请求。
	• 新增：时长：10秒 · 5分 · 2时 · 1天（及其他语言写法）。命令无法满足的时长会被拒绝并给出提示：ban 以整分钟计算（30秒、0.5 会被拒绝，而不是变成永久封禁）；未知格式（1w）不会被当作原因吞掉。
	• 修复：主页与 Sentinel Helper 读取同一状态：在主页关闭 Sentinel 会立即在 Sentinel Helper 中显示（反之亦然）；关闭 APM 不会改变它。
	• 变更：输入区的收起箭头跟随窗口位置（左半屏向左收起，右半屏向右收起）；箭头带有低调的深色底，在浅色背景上也清晰可见。

	MIT 许可 · 免费 · 作者：APM contributors

]==]
return {}
