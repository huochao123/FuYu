import Foundation
import Security

enum AssistantDecision: Equatable, Sendable {
    case reply(text: String, spoken: String?)
    case tool(AgentToolCall)
    case hermes(title: String, detail: String, prompt: String)
}

enum ExecutionPlanReview: Equatable, Sendable {
    case approved(summary: String, finalPrompt: String)
    case clarify(question: String)
}

enum AssistantServiceError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case http(Int, String)
    case hermesUnavailable
    case hermesFailed(String)
    case modelTimeout
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "没有找到当前模型的 API 密钥，请在模型设置中填写并保存。"
        case .invalidEndpoint:
            "模型服务地址无效。"
        case .invalidResponse:
            "模型返回了无法解析的内容，请重试。"
        case let .http(code, message):
            "模型服务请求失败（\(code)）：\(message)"
        case .hermesUnavailable:
            "没有找到 Hermes，请确认 ~/.local/bin/hermes 已安装。"
        case let .hermesFailed(message):
            "Hermes 执行失败：\(message)"
        case .modelTimeout:
            "模型响应超时了。本机工具仍然可用，你可以直接让我检查这台 Mac；聊天请求可以稍后重试。"
        case .cancelled:
            "操作已取消。"
        }
    }
}

actor MiMoAssistantClient {
    private let session: URLSession
    private var memory: [ChatMessage] = []
    private var loadedPersistentMemory = false
    private var actionAwaitingVerifiedResult = false

    init() {
        let config = URLSessionConfiguration.ephemeral
        // MiMo has ample context capacity, but a large prompt still increases
        // prefill latency. Give one request a realistic window instead of
        // retrying the same oversized request and turning one stall into two.
        config.timeoutIntervalForRequest = 36
        config.timeoutIntervalForResource = 42
        session = URLSession(configuration: config)
    }

    func decide(for userText: String, profile: AssistantProfile, localContext: String = "") async throws -> AssistantDecision {
        let personaKnowledge = PersonaKnowledgeLibrary.select(
            for: userText,
            enabled: profile.personaEnabled,
            preset: profile.personaPreset
        )
        let registeredMacToolNames = MacCareTool.allCases.map(\.rawValue).joined(separator: "、")
        let systemPrompt = """
        你是“浮屿 FuYu”，一款以 Mac 为核心的本机智能助手，不是泛用聊天机器人，也不是 Hermes。
        你的职责是理解这台 Mac、优先使用浮屿自身的本机能力，并用自然、有温度但不啰嗦的中文协助用户。
        你明确知道自己具备：\(MacCareTool.allCases.count) 项电脑管家本机工具（\(registeredMacToolNames)）、真实检测结果共享、音量与静音控制、运行时亮度能力检测、发热进程持续监控和本机通知。不得引用旧版本的固定工具数量。
        本机能力与最新检测上下文如下；只能依据这里的真实结果回答，不得编造：
        \(localContext.isEmpty ? "尚未提供本机上下文。" : localContext)
        能力边界：只读检测可直接执行；音量等可逆设置可直接执行；清理垃圾、移动文件必须先确认；删除、发送、购买、发布和安全设置属于高风险操作；跨应用复杂任务才交给 Hermes。
        用户询问“你是谁、能做什么”时，要明确回答自己是浮屿，并优先介绍 Mac 本机能力。
        用户基于电脑管家结果继续提问时，直接分析上面的结构化结果，不要让用户去聊天记录里重新寻找。
        检测责任规则：检测到异常后必须说明来源、真实证据、可能影响、风险等级、处理归属和下一步。不得只发送“发现异常”的通知，也不得把普通缓存或未知启动项夸大为安全危险。
        证据归因规则：电量百分比不等于电池健康，只有最大容量、循环次数或系统健康状态才能判断电池健康；睡眠阻止项与高负载进程是两类证据，不得把仅出现在高负载列表的进程说成阻止休眠。
        混合决策规则：明确的状态读取、简单控制和本机扫描优先调用浮屿本机工具以保证速度；原因分析、风险判断、方案比较和自然追问必须结合结构化本机证据由你推理后 reply；只有浮屿工具无法完成的跨应用复杂执行才使用 Hermes。不要为了省调用而给出生硬的关键词答案，也不要把简单本机操作绕给模型或 Hermes。
        连续对话规则：用户说“去吧、继续、就这个、刚才那个、为什么、为啥、现在呢”等短句时，必须优先承接上下文中最近一个未完成任务或上一句明确对象。上下文已经给出答案时，禁止让用户重新解释一遍。
        意图规则：用户粘贴更新说明、功能清单、聊天记录或引用文字时，默认是在陈述或讨论，不是授权执行；除非出现明确的检查、扫描、执行、打开、调整等请求，不得仅因文字包含工具名称就调用工具。用户说“处理、按建议做、你自己处理”时，应承接最近一次检测结果的可执行建议，不得重复运行同一个扫描冒充处理。
        记忆规则：区分“当前连续对话”和“较早相关记录”；先延续当前任务，再使用较早记录补充长期背景。不要把历史计划误说成已执行，仍以真实工具结果为准。
        Mac 专家规则：上下文始终只有简短 Skill 索引，并最多按需加载一个与当前问题相关的 Skill 正文。优先使用已加载专题规则和这台 Mac 的已验证经验；未加载 Skill 不得假装已经读取。专家知识只是判断方法，不代表已经检查；本机经验只有真实执行成功或失败记录才可信。系统版本不匹配的旧经验必须重新验证，禁止机械照搬。
        浮屿会偏向 Mac 场景并可主动提醒真实监控异常，但不得声称自己在后台做了尚未实际运行的检查，更不得静默清理、移动或删除文件。
        回答长度偏好：\(profile.answerLength.prompt)
        用户个性化偏好：\(profile.customPrompt.isEmpty ? "无" : profile.customPrompt)
        用户明确保存的永久习惯（优先遵守，但不得把它当成当前任务）：
        \(profile.permanentHabitPrompt)
        人格与关系设定：\(profile.personaPrompt)
        人格档案索引：\(personaKnowledge.indexPrompt)
        当前按需人物档案：\(personaKnowledge.loadedPrompt)
        人格输出契约：上面是当前生效人格，不是可选背景资料。人格只能改变表达，不能改写工具事实、参数、风险、授权要求或执行结果。技术场景先准确回答，再用一小句人格化表达。轻微毒舌只能用于无伤大雅的场景，绝不能贬低用户、质疑用户是否看清、把系统问题推给用户，或使用“这点事也值得你犯愁”“你确定吗”“你可能没刷新”等话术。错误、超时、风险和用户困惑时必须尊重、承担并给出下一步。不得虚构睡觉、醒来、亲眼看见等没有真实依据的经历。
        当前真实运行模型：\(profile.model.provider.title) / \(profile.model.model)。用户问模型时直接准确回答。
        跨启动对话记忆：\(profile.persistentMemory ? "已开启" : "未开启")。不得声称与这个真实设置相反。
        可调用的浮屿本机工具如下。只要这些工具能完成，就必须选择 tool，不得交给 Hermes：
        \(AgentToolRegistry.modelPrompt)
        你必须只输出一个 JSON 对象，不要使用 Markdown。
        如果用户只是询问、聊天或需要解释，输出：
        {"kind":"reply","reply":"屏幕上显示的完整回答","spokenReply":"适合说出口的一句自然短话，最多40字；除纯代码或纯链接外必须填写"}
        生成 reply 前自检：若把角色名称删除后，回答仍像任意普通助手都能说出的客套话，说明人格不合格，必须重写；但不得为了表现人格而增加虚构事实或弱化安全信息。
        如果需要调用浮屿本机工具，输出：
        {"kind":"tool","tool":"工具 ID","arguments":{"参数名":"字符串值"}}
        如果用户明确要求浮屿当前没有工具可以完成的跨应用复杂操作，才输出：
        {"kind":"hermes","title":"短标题","detail":"目标、范围、主要风险和完成标准，最多80字","hermesPrompt":"给 Hermes 的完整任务委派：结合当前上下文写清目标、约束、可检查的完成标准；允许 Hermes 先检查环境和规划，再执行并验证结果，不要把用户原话机械照抄"}
        “为什么、为啥、怎么回事、刚才为何超时、为什么进入预审”等解释请求只能输出 reply，绝不能输出 tool 或 hermes。
        普通 reply 禁止使用“我现在帮你打开、正在执行、马上替你完成”等会让用户误以为操作已发生的话术。
        没有真实工具结果时，禁止声称 Mac 操作已经完成。
        上下文中只有明确以“实际执行成功：”开头的记录才证明任务成功；“计划执行”或内部工具调用不代表已经执行。
        不知道退出、崩溃或失败原因时必须说无法确认，不得随意猜测 Hermes、内存或误操作。
        删除、发送、购买、发布、修改系统安全设置等高风险操作必须准确说明风险。
        不要把“怎么做”之类的知识问题误判成操作。
        对复杂任务先理解用户真正目标，再交给 Hermes 自主检查、规划、执行和验证；信息不足且会明显改变结果时应先向用户提问，不能擅自猜测。
        """
        try loadPersistentMemoryIfNeeded(profile: profile)
        let parsedDecision: AssistantDecision
        do {
            let content: String
            content = try await requestCompletion(
                systemPrompt: systemPrompt,
                userText: userText,
                profile: profile,
                includeContext: false
            )
            parsedDecision = try Self.parseDecision(content)
        } catch AssistantServiceError.invalidResponse {
            let repairPrompt = systemPrompt + """

            上一次返回内容格式不合法。现在重新判断同一个请求，只输出一个完整、可解析的 JSON 对象；不要解释错误，不要输出工具标签或 Markdown。
            """
            let repairedContent = try await requestCompletion(
                systemPrompt: repairPrompt,
                userText: userText,
                profile: profile,
                includeContext: false
            )
            parsedDecision = try Self.parseDecision(repairedContent)
        }
        var decision = Self.reconcileDecision(parsedDecision, userText: userText)
        if case let .reply(text, _) = decision,
           actionAwaitingVerifiedResult,
           Self.claimsVerifiedSuccess(text) {
            decision = .reply(
                text: "我还没有收到 Hermes 的真实成功结果，因此现在不能确认任务已经完成。你可以让我重新执行或检查任务状态。",
                spoken: "我还没有收到真实执行结果，暂时不能确认已经完成。"
            )
        }
        if case .hermes = decision { actionAwaitingVerifiedResult = true }
        if profile.contextEnabled {
            memory.append(.init(role: "user", content: userText))
            let assistantText: String
            switch decision {
            case let .reply(text, _): assistantText = text
            case let .tool(call): assistantText = "调用本机工具：\(call.id.rawValue)"
            case let .hermes(title, detail, _): assistantText = "计划交给 Hermes：\(title)。\(detail)"
            }
            memory.append(.init(role: "assistant", content: assistantText))
            memory = Array(memory.suffix(max(profile.contextTurns * 2, 4)))
            if profile.persistentMemory { try persistMemory() }
        }
        return decision
    }

    func recordActionResult(title: String, result: String, succeeded: Bool, profile: AssistantProfile) throws {
        actionAwaitingVerifiedResult = false
        guard profile.contextEnabled else { return }
        try loadPersistentMemoryIfNeeded(profile: profile)
        let prefix = succeeded ? "实际执行成功" : "实际执行失败"
        memory.append(.init(
            role: "assistant",
            content: Self.compactActionMemory(prefix: prefix, title: title, result: result)
        ))
        memory = Array(memory.suffix(max(profile.contextTurns * 2, 4)))
        if profile.persistentMemory { try persistMemory() }
    }

    func reviewExecutionPlan(
        userRequest: String,
        originalPrompt: String,
        hermesPlan: String,
        profile: AssistantProfile
    ) async throws -> ExecutionPlanReview {
        let systemPrompt = """
        你是浮屿的任务审核器。审核 Hermes 提出的执行方案是否能满足用户目标。
        只输出 JSON，不执行操作，也不要与 Hermes 继续讨论。
        如果目标、范围、关键选择和验证方法都足够清楚，输出：
        {"status":"approved","summary":"给用户看的简短方案摘要，最多80字","finalPrompt":"结合审核结果写给 Hermes 的最终执行指令，必须包含目标、边界和验证标准"}
        如果存在会明显改变结果的歧义、缺少关键选择或高风险未说明，输出：
        {"status":"clarify","question":"只向用户询问一个最关键的问题"}
        不要因为小细节提问；能在批准范围内安全判断的就通过。不得循环审核。
        """
        let userText = """
        用户原始要求：\(userRequest)
        浮屿整理的任务：\(originalPrompt)
        Hermes 只读预案：\(hermesPlan)
        """
        let content: String
        do {
            content = try await requestCompletion(
                systemPrompt: systemPrompt,
                userText: userText,
                profile: profile,
                includeContext: true
            )
        } catch AssistantServiceError.invalidResponse {
            // A malformed/empty review must not silently abandon an otherwise
            // valid action. Retry once without conversation history so old
            // tool markup cannot contaminate the strict JSON review response.
            content = try await requestCompletion(
                systemPrompt: systemPrompt,
                userText: userText,
                profile: profile,
                includeContext: false
            )
        }
        return Self.parsePlanReview(content, fallbackPrompt: originalPrompt)
    }

    static func parsePlanReview(_ content: String, fallbackPrompt: String) -> ExecutionPlanReview {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.firstIndex(of: "{"), let last = trimmed.lastIndex(of: "}"), first <= last,
              let data = String(trimmed[first...last]).data(using: .utf8),
              let wire = try? JSONDecoder().decode(WirePlanReview.self, from: data) else {
            return .clarify(question: "Hermes 的方案没有通过审核。你希望我优先达到什么结果？")
        }
        if wire.status.lowercased() == "approved" {
            return .approved(
                summary: wire.summary?.nonEmpty ?? "Hermes 已给出方案，浮屿审核通过。",
                finalPrompt: wire.finalPrompt?.nonEmpty ?? fallbackPrompt
            )
        }
        return .clarify(question: wire.question?.nonEmpty ?? "这个任务还有关键细节不明确，你希望最终达到什么效果？")
    }

    func testConnection(profile: AssistantProfile) async throws -> String {
        let result = try await requestCompletion(
            systemPrompt: "你是连接测试助手。只回复：连接正常",
            userText: "测试连接",
            profile: profile,
            includeContext: false
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makeNaturalSpokenSummary(for fullText: String, profile: AssistantProfile) async throws -> String {
        let systemPrompt = """
        把工具或助手返回结果改写成一句像真人说的自然中文，用于语音播报。
        只输出要说的话，不要 JSON、Markdown、列表或前缀。
        15 到 42 个汉字，先说结论；不要朗读网址、会议号、ID、追踪码、英文参数、文件路径或长数字。
        必要时说“详细信息我放在屏幕上了”。失败就自然说明失败，不得把失败改成成功。
        保持下面的人格和表达方式，但不要添加虚构事实：
        \(profile.personaPrompt)
        """
        let result = try await requestCompletion(
            systemPrompt: systemPrompt,
            userText: String(fullText.prefix(4_000)),
            profile: profile,
            includeContext: false
        )
        return Self.cleanSpokenSummary(result)
    }

    static func cleanSpokenSummary(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count > 1 {
            value.removeFirst()
            value.removeLast()
        }
        value = value.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "[A-Za-z0-9_-]{10,}", with: "", options: .regularExpression)
        return String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    }

    func clearMemory() throws {
        memory.removeAll()
        loadedPersistentMemory = true
        if FileManager.default.fileExists(atPath: Self.memoryURL.path) {
            try FileManager.default.removeItem(at: Self.memoryURL)
        }
    }

    private func requestCompletion(
        systemPrompt: String,
        userText: String,
        profile: AssistantProfile,
        includeContext: Bool
    ) async throws -> String {
        let configuration = profile.model
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: configuration.endpoint),
              !configuration.endpoint.isEmpty else {
            throw AssistantServiceError.invalidEndpoint
        }
        let apiKey = KeychainStore.password(service: configuration.keychainService) ?? ""
        if configuration.provider.requiresAPIKey && apiKey.isEmpty {
            throw AssistantServiceError.missingAPIKey
        }

        let recentContext = includeContext && profile.contextEnabled
            ? Array(memory.suffix(profile.contextTurns * 2))
            : []
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if configuration.provider.usesAnthropicMessages {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONEncoder().encode(
                AnthropicRequest(
                    model: configuration.model,
                    maxTokens: 1200,
                    system: systemPrompt,
                    messages: recentContext + [.init(role: "user", content: userText)],
                    temperature: 0.34
                )
            )
        } else {
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONEncoder().encode(
                ChatRequest(
                    model: configuration.model,
                    messages: [.init(role: "system", content: systemPrompt)]
                        + recentContext
                        + [.init(role: "user", content: userText)],
                    temperature: 0.34
                )
            )
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if let mapped = Self.transportError(for: error.code) { throw mapped }
            throw error
        }
        guard let http = response as? HTTPURLResponse else { throw AssistantServiceError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw AssistantServiceError.http(http.statusCode, Self.errorMessage(from: data))
        }

        if configuration.provider.usesAnthropicMessages {
            let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            guard let content = decoded.content.first(where: { $0.type == "text" })?.text.nonEmpty else {
                throw AssistantServiceError.invalidResponse
            }
            return content
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = (decoded.choices.first?.message.content
            ?? decoded.choices.first?.message.reasoningContent)?.nonEmpty else {
            throw AssistantServiceError.invalidResponse
        }
        return content
    }

    static func parseDecision(_ content: String) throws -> AssistantDecision {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .reply(text: "我没有收到完整回答，请再说一次。", spoken: nil)
        }
        if containsInternalToolMarkup(trimmed) {
            return .reply(text: "我识别到这是一个操作请求，需要交给执行流程处理。", spoken: nil)
        }
        let jsonText: String
        if let first = trimmed.firstIndex(of: "{"), let last = trimmed.lastIndex(of: "}"), first <= last {
            jsonText = String(trimmed[first...last])
        } else {
            return .reply(text: trimmed, spoken: nil)
        }

        guard let data = jsonText.data(using: .utf8),
              let wire = try? JSONDecoder().decode(WireDecision.self, from: data) else {
            // Never show a broken JSON protocol packet to the user. Let the
            // caller run one format-repair request instead.
            throw AssistantServiceError.invalidResponse
        }

        switch wire.kind?.lowercased() {
        case "tool":
            guard let rawTool = wire.tool?.nonEmpty,
                  let tool = AgentToolID(rawValue: rawTool) else {
                return .reply(text: "这个本机工具目前不可用，我没有执行任何操作。", spoken: nil)
            }
            return .tool(.init(
                id: tool,
                arguments: wire.arguments?.mapValues(\.stringValue) ?? [:]
            ))
        case "hermes", "action":
            if let prompt = wire.hermesPrompt?.nonEmpty {
                let title = wire.title?.nonEmpty ?? String(prompt.prefix(22))
                let detail = wire.detail?.nonEmpty ?? "交给 Hermes 规划、执行并检查实际结果。"
                return .hermes(title: title, detail: detail, prompt: prompt)
            }
            let fallback = wire.reply?.nonEmpty
                ?? wire.content?.nonEmpty
                ?? wire.text?.nonEmpty
                ?? wire.message?.nonEmpty
                ?? wire.detail?.nonEmpty
                ?? trimmed
            return .reply(text: fallback, spoken: wire.spokenReply?.nonEmpty)
        default:
            let reply = wire.reply?.nonEmpty
                ?? wire.content?.nonEmpty
                ?? wire.text?.nonEmpty
                ?? wire.message?.nonEmpty
                ?? wire.detail?.nonEmpty
                ?? trimmed
            return .reply(text: reply, spoken: wire.spokenReply?.nonEmpty)
        }
    }

    static func transportError(for code: URLError.Code) -> AssistantServiceError? {
        switch code {
        case .cancelled: .cancelled
        case .timedOut: .modelTimeout
        default: nil
        }
    }

    static func reconcileDecision(_ decision: AssistantDecision, userText: String) -> AssistantDecision {
        if LocalCommandRouter.isNarrativeOrQuotedContent(userText)
            || LocalCommandRouter.isDiscussionAboutContent(userText) {
            switch decision {
            case .tool, .hermes:
                return .reply(
                    text: "我看到了，这是一段功能说明或引用内容，不是执行命令。我不会因为里面出现工具名称就自动扫描。当前能力会以这台 Mac 上实际注册的工具清单为准。",
                    spoken: "我看到了，这是说明内容，我不会把它误当成执行命令。"
                )
            case .reply:
                break
            }
        }
        // Tool choice remains explicit; ordinary replies are never silently
        // upgraded into Hermes or local execution.
        return decision
    }

    static func looksLikeMacAction(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let knowledgePrefixes = ["怎么", "如何", "为什么", "是什么", "能不能介绍", "告诉我怎么", "教我"]
        if knowledgePrefixes.contains(where: value.hasPrefix) { return false }
        let actionVerbs = [
            "打开", "关闭", "启动", "退出", "创建", "新建", "删除", "移动", "复制", "重命名",
            "整理", "发送", "点击", "切换", "设置", "调高", "调低", "搜索", "下载", "安装", "卸载",
            "开会", "开一个", "锁屏", "锁定屏幕", "预约", "发布", "购买"
        ]
        let macTargets = [
            "文件", "文件夹", "访达", "finder", "safari", "浏览器", "应用", "软件", "桌面",
            "系统", "音量", "亮度", "窗口", "mac", "电脑", "程序", "微信", "邮件", "日历"
        ]
        let lower = value.lowercased()
        let hasVerb = actionVerbs.contains(where: lower.contains)
        let hasTarget = macTargets.contains(where: lower.contains)
        let directRequest = lower.hasPrefix("帮我") || lower.hasPrefix("替我") || lower.hasPrefix("给我")
        let directImperative = actionVerbs.contains(where: lower.hasPrefix)
        return hasVerb && (hasTarget || directRequest || directImperative)
    }

    static func containsInternalToolMarkup(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<tool_call>")
            || lower.contains("</tool_call>")
            || lower.contains("<function=")
            || lower.contains("<parameter=")
    }

    static func claimsVerifiedSuccess(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let claims = ["已经执行成功", "已经创建成功", "已创建成功", "已经完成", "操作已完成", "任务已完成", "成功创建"]
        return claims.contains(where: compact.contains)
    }

    private static func errorMessage(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return payload.error.message
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "未知错误"
    }

    private func loadPersistentMemoryIfNeeded(profile: AssistantProfile) throws {
        guard profile.persistentMemory, !loadedPersistentMemory else { return }
        loadedPersistentMemory = true
        guard FileManager.default.fileExists(atPath: Self.memoryURL.path) else { return }
        memory = try JSONDecoder().decode([ChatMessage].self, from: Data(contentsOf: Self.memoryURL))
        var migratedOversizedResult = false
        memory = memory.map { message in
            guard message.role == "assistant",
                  message.content.hasPrefix("实际执行成功：") || message.content.hasPrefix("实际执行失败：") else {
                return message
            }
            let compact = Self.compactStoredActionMemory(message.content)
            if compact != message.content { migratedOversizedResult = true }
            return .init(role: message.role, content: compact)
        }
        if migratedOversizedResult { try persistMemory() }
        let lastPlan = memory.lastIndex(where: { $0.role == "assistant" && $0.content.hasPrefix("计划执行：") })
        let lastResult = memory.lastIndex(where: {
            $0.role == "assistant" && ($0.content.hasPrefix("实际执行成功：") || $0.content.hasPrefix("实际执行失败："))
        })
        actionAwaitingVerifiedResult = lastPlan.map { planIndex in
            lastResult.map { planIndex > $0 } ?? true
        } ?? false
    }

    private func persistMemory() throws {
        let directory = Self.memoryURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(memory).write(to: Self.memoryURL, options: .atomic)
    }

    nonisolated static func compactActionMemory(prefix: String, title: String, result: String) -> String {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedResult = result
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usefulLines = normalizedResult
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(8)
            .map(String.init)
            .joined(separator: "；")
        return String("\(prefix)：\(normalizedTitle)。\(usefulLines)".prefix(1_200))
    }

    private nonisolated static func compactStoredActionMemory(_ content: String) -> String {
        let prefix = content.hasPrefix("实际执行成功：") ? "实际执行成功" : "实际执行失败"
        let body = content.dropFirst(prefix.count + 1)
        let parts = body.split(separator: "。", maxSplits: 1, omittingEmptySubsequences: false)
        let title = parts.first.map(String.init) ?? "历史任务"
        let result = parts.count > 1 ? String(parts[1]) : ""
        return compactActionMemory(prefix: prefix, title: title, result: result)
    }

    private static var memoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuYu", isDirectory: true)
            .appendingPathComponent("conversation-memory.json")
    }
}

@MainActor
final class HermesCommandRunner {
    static let timeoutSeconds = 120
    private var currentProcess: Process?

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    func execute(_ approvedPrompt: String) async throws -> String {
        try await run(Self.delegationPrompt(for: approvedPrompt), planningOnly: false)
    }

    func proposePlan(for taskPrompt: String) async throws -> String {
        try await run(Self.planningPrompt(for: taskPrompt), planningOnly: true)
    }

    private func run(_ instruction: String, planningOnly: Bool) async throws -> String {
        guard isAvailable else { throw AssistantServiceError.hermesUnavailable }
        cancel()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["-z", instruction]
        if planningOnly {
            // An explicit toolset pin prevents Hermes from loading terminal,
            // file, or computer-control tools during the read-only review.
            process.arguments?.append(contentsOf: ["--toolsets", "web"])
        }
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = ProcessInfo.processInfo.environment

        let stdoutURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-hermes-\(UUID().uuidString).out")
        let stderrURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-hermes-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        currentProcess = process

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
            if currentProcess === process { currentProcess = nil }
        }

        let box = ProcessBox(process)
        var timedOut = false
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeoutSeconds))
            guard let self,
                  !Task.isCancelled,
                  self.currentProcess === process,
                  process.isRunning else { return }
            timedOut = true
            process.terminate()
        }
        defer { timeoutTask.cancel() }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()
        let output = (try? String(contentsOf: stdoutURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = (try? String(contentsOf: stderrURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if Task.isCancelled { throw AssistantServiceError.cancelled }
        if timedOut { throw AssistantServiceError.hermesFailed("任务超过 2 分钟没有结束，已自动停止。你可以换一种说法后重试。") }
        guard status == 0 else {
            throw AssistantServiceError.hermesFailed(errorOutput.nonEmpty ?? "退出码 \(status)")
        }
        guard !output.isEmpty else {
            throw AssistantServiceError.hermesFailed("没有返回执行结果")
        }
        return output
    }

    func cancel() {
        if let currentProcess, currentProcess.isRunning {
            currentProcess.terminate()
        }
        currentProcess = nil
    }

    static func delegationPrompt(for approvedPrompt: String) -> String {
        """
        这是用户已经在浮屿界面中明确批准的一次性 macOS 操作。
        你是实际执行代理，不要机械照抄命令。先理解目标并检查当前环境，制定最小风险步骤，再执行。
        只在以下已批准范围内操作，不要扩大范围：
        \(approvedPrompt)
        执行中遇到与预期不同的界面或结果时，在批准范围内调整方法；不要仅因第一种方法失败就假装完成。
        完成后必须检查目标是否真的达到，并用简洁中文返回：实际做了什么、验证结果；若信息不足或无法安全完成，停止并明确说明需要用户补充什么。
        """
    }

    static func planningPrompt(for taskPrompt: String) -> String {
        """
        这是浮屿在正式执行前向你进行的一次只读方案咨询。
        绝对不要点击、输入、修改、创建、删除、发送或执行任何会改变 Mac 状态的操作。
        你可以根据现有知识分析当前环境；如必须查看环境，只能进行只读检查。
        请为下面的任务给出简洁方案：目标理解、建议步骤、风险或歧义、可以验证完成的标准。
        任务：
        \(taskPrompt)
        只返回方案，不执行任务。浮屿审核后会另行发出正式执行指令。
        """
    }

    private var executableURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/hermes")
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

enum KeychainStore {
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var memoryCache: [String: String] = [:]

    static func password(service: String) -> String? {
        cacheLock.lock()
        if let cached = memoryCache[service] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        // The shared MiMo credential was created for the stable Apple-signed
        // `/usr/bin/security` broker used by the local MiMo router. Reading it
        // through the same broker prevents every ad-hoc FuYu rebuild from
        // presenting a new Keychain ACL/password dialog. The secret stays only
        // in this process's memory and is never written to app files.
        if service == "codex-mimo-api-key",
           let value = passwordViaSystemSecurity(service: service),
           !value.isEmpty {
            cacheLock.lock()
            memoryCache[service] = value
            cacheLock.unlock()
            return value
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            cacheLock.lock()
            memoryCache[service] = value
            var legacyCredentials = readLocalCredentials()
            if legacyCredentials.removeValue(forKey: service) != nil {
                try? writeLocalCredentials(legacyCredentials)
            }
            cacheLock.unlock()
            return value
        }

        // Migrate legacy 0600 JSON credentials once, then remove the plaintext copy.
        guard let value = readLocalCredentials()[service], !value.isEmpty else { return nil }
        try? writeKeychain(value, service: service)
        cacheLock.lock()
        memoryCache[service] = value
        var credentials = readLocalCredentials()
        credentials.removeValue(forKey: service)
        try? writeLocalCredentials(credentials)
        cacheLock.unlock()
        return value
    }

    private static func passwordViaSystemSecurity(service: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let data = try output.fileHandleForReading.readToEnd(),
                  let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        } catch {
            return nil
        }
    }

    static func set(_ password: String, service: String) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        try writeKeychain(password, service: service)
        memoryCache[service] = password
    }

    static func delete(service: String) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        memoryCache.removeValue(forKey: service)
    }

    private static var credentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FuYu", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private static func readLocalCredentials() -> [String: String] {
        guard let data = try? Data(contentsOf: credentialsURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }

    private static func writeLocalCredentials(_ credentials: [String: String]) throws {
        if credentials.isEmpty {
            if FileManager.default.fileExists(atPath: credentialsURL.path) {
                try FileManager.default.removeItem(at: credentialsURL)
            }
            return
        }
        let directory = credentialsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: credentialsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsURL.path)
    }

    private static func writeKeychain(_ password: String, service: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        let data = Data(password.utf8)
        let status: OSStatus
        if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
            status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        } else {
            var item = query
            item[kSecAttrAccount as String] = "FuYu"
            item[kSecValueData as String] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ChatMessage]
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model, system, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
    let content: [ContentBlock]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
            let reasoningContent: String?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
            }
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct WireDecision: Decodable {
    let kind: String?
    let reply: String?
    let spokenReply: String?
    let title: String?
    let detail: String?
    let hermesPrompt: String?
    let tool: String?
    let arguments: [String: WireScalar]?
    let content: String?
    let text: String?
    let message: String?
}

private enum WireScalar: Decodable {
    case string(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode(Int.self) { self = .string(String(value)); return }
        if let value = try? container.decode(Double.self) { self = .string(String(value)); return }
        if let value = try? container.decode(Bool.self) { self = .string(value ? "true" : "false"); return }
        throw DecodingError.typeMismatch(
            String.self,
            .init(codingPath: decoder.codingPath, debugDescription: "工具参数只支持字符串、数字或布尔值")
        )
    }

    var stringValue: String {
        switch self { case let .string(value): value }
    }
}

private struct WirePlanReview: Decodable {
    let status: String
    let summary: String?
    let finalPrompt: String?
    let question: String?
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
