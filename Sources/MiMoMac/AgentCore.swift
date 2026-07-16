import Foundation

enum AgentToolRisk: String, Sendable {
    case readOnly
    case reversible
    case requiresApproval
}

enum AgentToolID: String, CaseIterable, Codable, Sendable {
    case systemCheck = "mac.system_check"
    case junkScan = "mac.junk_scan"
    case organizeDownloads = "mac.downloads_analyze"
    case largeFiles = "mac.large_files"
    case duplicates = "mac.duplicates"
    case loginItems = "mac.login_items"
    case hotProcesses = "mac.hot_processes"
    case appLeftovers = "mac.app_leftovers"
    case optimization = "mac.optimization"
    case volume = "mac.volume"
    case brightness = "mac.brightness"
    case capabilities = "fuyu.capabilities"
    case applyJunkCleanup = "mac.junk_apply"
    case applyDownloadsOrganization = "mac.downloads_apply"
}

struct AgentToolCall: Equatable, Sendable {
    let id: AgentToolID
    let arguments: [String: String]
}

struct AgentToolDefinition: Sendable {
    let id: AgentToolID
    let title: String
    let purpose: String
    let risk: AgentToolRisk
    let arguments: String
}

enum AgentToolRegistry {
    static let definitions: [AgentToolDefinition] = [
        .init(id: .systemCheck, title: "系统体检", purpose: "读取磁盘、内存、开机时间和高负载状态", risk: .readOnly, arguments: "无"),
        .init(id: .junkScan, title: "垃圾扫描", purpose: "预览白名单安全缓存，不删除", risk: .readOnly, arguments: "无"),
        .init(id: .organizeDownloads, title: "下载文件夹分析", purpose: "分析下载文件类型并生成整理预览，不移动", risk: .readOnly, arguments: "无"),
        .init(id: .largeFiles, title: "大文件", purpose: "查找超过阈值的大文件", risk: .readOnly, arguments: "无"),
        .init(id: .duplicates, title: "重复文件", purpose: "使用哈希确认重复文件，只扫描不删除", risk: .readOnly, arguments: "无"),
        .init(id: .loginItems, title: "启动项", purpose: "读取登录项与后台常驻项目", risk: .readOnly, arguments: "无"),
        .init(id: .hotProcesses, title: "发热进程", purpose: "读取持续高 CPU 进程", risk: .readOnly, arguments: "无"),
        .init(id: .appLeftovers, title: "应用残留", purpose: "扫描应用缓存和卸载残留", risk: .readOnly, arguments: "无"),
        .init(id: .optimization, title: "优化建议", purpose: "综合存储和性能状态给出建议", risk: .readOnly, arguments: "无"),
        .init(id: .volume, title: "音量", purpose: "读取、设置、增减音量或静音", risk: .reversible, arguments: "action=read|set|change|mute，value=0...100 或增量，muted=true|false"),
        .init(id: .brightness, title: "亮度", purpose: "在硬件支持时读取或调整屏幕亮度", risk: .reversible, arguments: "action=read|set|change，value=0...100 或增量"),
        .init(id: .capabilities, title: "浮屿能力", purpose: "说明浮屿身份、真实本机能力和安全边界", risk: .readOnly, arguments: "无"),
        .init(id: .applyJunkCleanup, title: "执行安全清理", purpose: "根据最新垃圾预览移到废纸篓", risk: .requiresApproval, arguments: "无；必须已有最新扫描"),
        .init(id: .applyDownloadsOrganization, title: "执行下载整理", purpose: "根据最新预览移动下载文件", risk: .requiresApproval, arguments: "无；必须已有最新扫描")
    ]

    static var modelPrompt: String {
        definitions.map {
            "- \($0.id.rawValue)：\($0.title)；\($0.purpose)；风险=\($0.risk.rawValue)；参数=\($0.arguments)"
        }.joined(separator: "\n")
    }

    static func localCommand(for call: AgentToolCall) -> LocalMacCommand? {
        switch call.id {
        case .systemCheck: .scan(.systemCheck)
        case .junkScan: .scan(.junkScan)
        case .organizeDownloads: .scan(.organize)
        case .largeFiles: .scan(.largeFiles)
        case .duplicates: .scan(.duplicates)
        case .loginItems: .scan(.loginItems)
        case .hotProcesses: .scan(.hotProcesses)
        case .appLeftovers: .scan(.appLeftovers)
        case .optimization: .scan(.optimization)
        case .capabilities: .capabilities
        case .applyJunkCleanup: .applyLatest(.junkScan)
        case .applyDownloadsOrganization: .applyLatest(.organize)
        case .volume:
            adjustmentCommand(arguments: call.arguments, brightness: false)
        case .brightness:
            adjustmentCommand(arguments: call.arguments, brightness: true)
        }
    }

    private static func adjustmentCommand(arguments: [String: String], brightness: Bool) -> LocalMacCommand? {
        let action = arguments["action"]?.lowercased() ?? "read"
        let adjustment: LocalMacCommand.Adjustment
        switch action {
        case "read": adjustment = .read
        case "set": adjustment = .set(Int(arguments["value"] ?? "") ?? 50)
        case "change": adjustment = .change(Int(arguments["value"] ?? "") ?? 10)
        case "mute" where !brightness:
            adjustment = .mute((arguments["muted"] ?? "true").lowercased() != "false")
        default: return nil
        }
        return brightness ? .brightness(adjustment) : .volume(adjustment)
    }
}

enum AgentFastRoute: Equatable {
    case local(LocalMacCommand)
    case reply(String)
    case model
}

enum AgentIntentEngine {
    static func route(for text: String, conversation: [AppState.ConversationItem]) -> AgentFastRoute {
        if let explanation = localExplanation(for: text, conversation: conversation) {
            return .reply(explanation)
        }
        if let local = LocalCommandRouter.command(for: text) { return .local(local) }
        return .model
    }

    static func isExplanationRequest(_ text: String) -> Bool {
        let value = text.lowercased()
        let asksWhy = ["为什么", "为啥", "怎么会", "解释", "怎么回事", "什么问题", "只是让你解释"].contains(where: value.contains)
        let refersToRuntime = ["超时", "hermes", "赫尔墨斯", "复杂任务预审", "执行", "取消", "没反应"].contains(where: value.contains)
        return asksWhy && refersToRuntime
    }

    private static func localExplanation(
        for text: String,
        conversation: [AppState.ConversationItem]
    ) -> String? {
        guard isExplanationRequest(text) else { return nil }
        let recent = conversation.suffix(16)
        let hadPlanReview = recent.contains { $0.kind == .action && $0.text.contains("复杂任务预审") }
        let timedOut = recent.contains { $0.kind == .error && $0.text.contains("超时") }
        let cancelled = recent.contains { $0.kind == .error && $0.text.contains("已取消") }
        var facts: [String] = []
        if hadPlanReview { facts.append("刚才确实进入了 Hermes 复杂任务预审") }
        if timedOut { facts.append("随后记录到请求超时") }
        if cancelled { facts.append("期间还出现过旧请求取消记录") }
        let prefix = facts.isEmpty ? "我检查了刚才的任务记录。" : facts.joined(separator: "，") + "。"
        return prefix + "这类问题只需要解释，不应该再次启动任何工具或 Hermes。浮屿会保留当前任务，等待你继续或修改要求。"
    }
}
