import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum InteractionSource: Equatable {
        case voice
        case text
        case notification
    }

    enum OverlayMode: Equatable {
        case orb
        case voice
        case response
        case task
        case approval
        case history
    }

    enum Phase: String, Equatable {
        case idle = "待命"
        case listening = "正在聆听"
        case thinking = "正在思考"
        case executing = "正在执行"
        case speaking = "正在回复"
        case answered = "已回复"
        case error = "出现问题"
    }

    struct TaskStep: Identifiable, Equatable {
        enum Status: Equatable { case pending, active, complete }
        let id: UUID
        let title: String
        let detail: String
        var status: Status

        init(id: UUID = UUID(), title: String, detail: String, status: Status) {
            self.id = id
            self.title = title
            self.detail = detail
            self.status = status
        }
    }

    struct ConversationItem: Identifiable, Equatable, Codable {
        enum Kind: String, Equatable, Codable { case user, assistant, action, error }
        let id: UUID
        let kind: Kind
        let text: String
        let createdAt: Date

        init(id: UUID = UUID(), kind: Kind, text: String, createdAt: Date = Date()) {
            self.id = id
            self.kind = kind
            self.text = text
            self.createdAt = createdAt
        }
    }

    @Published var isExpanded = false
    @Published private(set) var interactionSource: InteractionSource = .voice
    @Published var phase: Phase = .idle
    @Published var audioLevel = 0.0
    @Published var activitySource = "本机"
    @Published var remoteChannelStatus = "飞书未配置"
    @Published var transcript = "需要我做什么？"
    @Published var modelLabel = "MiMo"
    @Published var taskTitle = "准备任务"
    @Published var progress = 0.0
    @Published var showPermission = false
    @Published var approvalTitle = "允许浮屿执行这个操作？"
    @Published var approvalDetail = "执行前会再次确认，不会在后台静默操作。"
    @Published var approvalIsListening = false
    @Published var approvalHeardText = ""
    @Published private(set) var approvalID: UUID?
    @Published var steps: [TaskStep] = []
    @Published var conversation: [ConversationItem] = []
    @Published var showHistory = false
    @Published private(set) var latestMacCareReports: [MacCareTool: MacCareReport] = [:]
    @Published private(set) var latestMacCareReport: MacCareReport?
    @Published private(set) var macCareReportVersion = 0

    var onVoiceRequested: (() -> Void)?
    var onVoiceSubmitRequested: (() -> Void)?
    var onCancelRequested: (() -> Void)?
    var onApprovalGranted: ((UUID) -> Void)?

    private var demoTask: Task<Void, Never>?
    private var replyCollapseTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var isRunningDemo = false
    private let conversationHistoryURL: URL
    private let memorySystem: FuYuMemorySystem
    private var isInitializingMemory = true

    init(historyURL: URL? = nil) {
        let resolvedHistoryURL = historyURL ?? Self.defaultConversationHistoryURL
        conversationHistoryURL = resolvedHistoryURL
        memorySystem = FuYuMemorySystem(historyURL: resolvedHistoryURL)
        if let stored = Self.loadConversationHistory(from: conversationHistoryURL), !stored.isEmpty {
            conversation = stored
        } else {
            conversation = Self.importLegacyModelHistory()
        }
        conversation.removeAll {
            $0.text == "等待确认：创建腾讯会议\n下午 3 点到 4 点 · 单次会议 · 使用腾讯会议 MCP"
        }
        markInterruptedActionIfNeeded()
        persistConversationHistory()
        memorySystem.bootstrapArchiveIfNeeded(with: conversation)
        memorySystem.bootstrapWorkingFocusIfNeeded(with: conversation)
        isInitializingMemory = false
    }

    var phaseColor: Color {
        switch phase {
        case .idle: .secondary
        case .listening: Color(red: 0.12, green: 0.66, blue: 1.0)
        case .thinking: Color(red: 0.58, green: 0.38, blue: 1.0)
        case .executing: Color(red: 0.08, green: 0.72, blue: 0.61)
        case .speaking: Color(red: 0.94, green: 0.30, blue: 0.55)
        case .answered: Color(red: 0.19, green: 0.72, blue: 0.56)
        case .error: Color(red: 0.95, green: 0.25, blue: 0.28)
        }
    }

    var overlayMode: OverlayMode {
        guard isExpanded else { return .orb }
        if interactionSource == .notification { return .response }
        if showPermission { return .approval }
        if phase == .executing { return .task }
        if showHistory { return .history }
        if phase == .answered { return .voice }
        return .voice
    }

    func requestVoice() {
        replyCollapseTask?.cancel()
        onVoiceRequested?()
    }

    func submitVoice() {
        onVoiceSubmitRequested?()
    }

    func beginListening(preservingApproval: Bool = false) {
        interactionSource = .voice
        demoTask?.cancel()
        replyCollapseTask?.cancel()
        errorDismissTask?.cancel()
        if !preservingApproval { showPermission = false }
        isExpanded = true
        phase = .listening
        activitySource = "麦克风"
        transcript = preservingApproval ? "请说“允许执行”或“取消执行”" : "我在听…"
        approvalIsListening = preservingApproval
        if preservingApproval { approvalHeardText = "" }
        progress = 0
        steps = []
    }

    func updateTranscript(_ text: String) {
        guard phase == .listening else { return }
        if showPermission {
            approvalHeardText = text
            return
        }
        transcript = text.isEmpty ? "我在听…" : text
    }

    func beginThinking(userText: String) {
        replyCollapseTask?.cancel()
        showPermission = false
        isExpanded = interactionSource == .voice
        phase = .thinking
        audioLevel = 0
        transcript = userText
        progress = 0
        steps = []
        appendConversation(.user, userText)
    }

    @discardableResult
    func presentApproval(title: String, detail: String) -> UUID {
        let id = UUID()
        approvalID = id
        approvalTitle = title
        approvalDetail = detail
        approvalIsListening = false
        approvalHeardText = ""
        showPermission = true
        isExpanded = interactionSource == .voice
        phase = .thinking
        appendConversation(.action, "等待确认：\(title)\n\(detail)")
        return id
    }

    func beginExecution(title: String) {
        showPermission = false
        approvalIsListening = false
        isExpanded = interactionSource == .voice
        phase = .executing
        audioLevel = 0
        taskTitle = title
        progress = 0.08
        steps = [
            .init(title: "正在连接 Hermes", detail: "准备安全执行环境", status: .active),
            .init(title: "Hermes 已接收任务", detail: "正在按照指令执行", status: .pending),
            .init(title: "正在检查结果", detail: "确认操作是否完成", status: .pending)
        ]
        appendConversation(.action, "正在执行：\(title)")
    }

    func beginLocalExecution(title: String) {
        showPermission = false
        approvalIsListening = false
        isExpanded = interactionSource == .voice
        phase = .executing
        audioLevel = 0
        taskTitle = title
        progress = 0.12
        steps = [
            .init(title: "调用浮屿本机能力", detail: "无需经过 Hermes", status: .active),
            .init(title: "正在读取真实系统状态", detail: "只使用本机结果", status: .pending),
            .init(title: "正在整理结果", detail: "同步到电脑管家与聊天", status: .pending)
        ]
        appendConversation(.action, "本机执行：\(title)")
    }

    func updateExecution(progress newProgress: Double, step index: Int) {
        progress = min(max(newProgress, 0), 1)
        guard steps.indices.contains(index) else { return }
        for i in steps.indices {
            if i < index { steps[i].status = .complete }
            else if i == index { steps[i].status = .active }
        }
    }

    func beginSpeaking(_ text: String) {
        replyCollapseTask?.cancel()
        showPermission = false
        isExpanded = true
        phase = .speaking
        audioLevel = 0
        transcript = text
        progress = steps.isEmpty ? 0 : 1
        for index in steps.indices { steps[index].status = .complete }
        appendConversation(.assistant, text)
    }

    func finishSpeaking() {
        guard phase == .speaking else { return }
        phase = .idle
        audioLevel = 0
        activitySource = "本机"
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.phase == .idle, !self.showPermission else { return }
            self.isExpanded = false
        }
    }

    func presentSilentReply(_ text: String) {
        replyCollapseTask?.cancel()
        showPermission = false
        isExpanded = interactionSource == .voice
        phase = .answered
        audioLevel = 0
        transcript = text
        progress = steps.isEmpty ? 0 : 1
        for index in steps.indices { steps[index].status = .complete }
        appendConversation(.assistant, text)

        replyCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, !Task.isCancelled, self.phase == .answered else { return }
            self.resetToIdle()
        }
    }

    func presentError(_ message: String) {
        errorDismissTask?.cancel()
        showPermission = false
        isExpanded = interactionSource == .voice
        phase = .error
        audioLevel = 0
        transcript = message
        progress = 0
        appendConversation(.error, message)
        errorDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled, self.phase == .error else { return }
            self.resetToIdle()
        }
    }

    func approveFromUserInteraction() {
        guard showPermission, let approvalID else { return }
        showPermission = false
        approvalIsListening = false
        self.approvalID = nil
        if isRunningDemo {
            finishDemo()
            return
        }
        onApprovalGranted?(approvalID)
    }

    func cancel() {
        demoTask?.cancel()
        demoTask = nil
        isRunningDemo = false
        replyCollapseTask?.cancel()
        replyCollapseTask = nil
        errorDismissTask?.cancel()
        errorDismissTask = nil
        onCancelRequested?()
        resetToIdle(message: "已停止")
    }

    func resetToIdle(message: String = "需要我做什么？") {
        replyCollapseTask?.cancel()
        replyCollapseTask = nil
        errorDismissTask?.cancel()
        errorDismissTask = nil
        showPermission = false
        interactionSource = .voice
        approvalIsListening = false
        approvalHeardText = ""
        approvalID = nil
        phase = .idle
        audioLevel = 0
        activitySource = "本机"
        progress = 0
        transcript = message
        steps = []
        showHistory = false
        isExpanded = false
    }

    func beginTextInteraction() {
        interactionSource = .text
        isExpanded = false
        showHistory = false
    }

    func beginVoiceInteraction() {
        interactionSource = .voice
    }

    func presentNotification(_ message: String, duration: Duration = .seconds(9)) {
        replyCollapseTask?.cancel()
        interactionSource = .notification
        showPermission = false
        showHistory = false
        phase = .answered
        audioLevel = 0
        transcript = message
        isExpanded = true
        appendConversation(.action, "系统提醒：\(message)")
        replyCollapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard let self, !Task.isCancelled, self.interactionSource == .notification else { return }
            self.resetToIdle()
        }
    }

    func openHistory() {
        showHistory = true
        isExpanded = true
    }

    func closeHistory() {
        showHistory = false
        if phase == .idle || phase == .answered || phase == .error {
            resetToIdle()
        }
    }

    func recordActionStatus(_ text: String, failed: Bool = false) {
        appendConversation(failed ? .error : .action, text)
    }

    func recordAssistantMessage(_ text: String) {
        appendConversation(.assistant, text)
    }

    func publishMacCareReport(_ report: MacCareReport) {
        latestMacCareReports[report.tool] = report
        latestMacCareReport = report
        macCareReportVersion &+= 1
    }

    var macCareContextPrompt: String {
        guard !latestMacCareReports.isEmpty else { return "尚无电脑管家检测结果。" }
        return MacCareTool.allCases.compactMap { tool in
            guard let report = latestMacCareReports[tool] else { return nil }
            let details = report.details.prefix(8).joined(separator: "；")
            let recommendations = report.recommendations.prefix(4).map {
                "\($0.title)（收益：\($0.benefit)；风险：\($0.risk)）"
            }.joined(separator: "；")
            return "[\(tool.rawValue)] \(report.headline)\n详情：\(details.isEmpty ? "无" : details)\n可执行建议：\(recommendations.isEmpty ? "无" : recommendations)"
        }.joined(separator: "\n")
    }

    func conversationContextPrompt(for query: String) -> String {
        guard !conversation.isEmpty else { return "尚无历史对话。" }
        let recentCount = 20
        let recentStart = max(0, conversation.count - recentCount)
        let recent = Array(conversation[recentStart...])
        let relevant = memorySystem.relevantHistory(
            for: query,
            excluding: Set(recent.map(\.id)),
            limit: 8
        )

        func render(_ items: [ConversationItem]) -> String {
            items.map { item in
                let role: String
                switch item.kind {
                case .user: role = "用户"
                case .assistant: role = "浮屿"
                case .action: role = "真实工具/任务状态"
                case .error: role = "执行错误"
                }
                let compact = item.text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                return "\(role)：\(String(compact.prefix(650)))"
            }.joined(separator: "\n")
        }

        let relevantText = relevant.isEmpty ? "无额外匹配记录。" : render(relevant)
        return """
        当前连续对话（按时间顺序，必须承接代词、追问和“继续/去吧/这个/为什么”等短句）：
        \(render(recent))

        当前工作记忆（跨重启保留）：
        \(memorySystem.focusPrompt)

        与当前请求相关的较早记录（仅作为历史，不要误当成刚发生）：
        \(relevantText)
        """
    }

    func contextualizedRequest(_ text: String) -> String {
        memorySystem.contextualizedRequest(text)
    }

    func markTaskFocus(_ status: FuYuMemorySystem.TaskFocus.Status) {
        memorySystem.markFocus(status)
    }

    func clearConversationMemory() throws {
        conversation.removeAll()
        try memorySystem.clear()
        if FileManager.default.fileExists(atPath: conversationHistoryURL.path) {
            try FileManager.default.removeItem(at: conversationHistoryURL)
        }
    }

    private func appendConversation(_ kind: ConversationItem.Kind, _ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if conversation.last?.kind == kind, conversation.last?.text == value { return }
        let item = ConversationItem(kind: kind, text: value)
        conversation.append(item)
        conversation = Array(conversation.suffix(500))
        persistConversationHistory()
        guard !isInitializingMemory else { return }
        memorySystem.append(item)
        if kind == .user { memorySystem.observeUserMessage(value) }
        if kind == .assistant { memorySystem.observeAssistantReply(value) }
    }

    private func persistConversationHistory() {
        do {
            let directory = conversationHistoryURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(conversation).write(to: conversationHistoryURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: conversationHistoryURL.path)
        } catch {
            // The current session remains readable; the next message retries persistence.
        }
    }

    private struct LegacyMessage: Decodable {
        let role: String
        let content: String
    }

    private static func loadConversationHistory(from url: URL) -> [ConversationItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([ConversationItem].self, from: data)
    }

    private static func importLegacyModelHistory() -> [ConversationItem] {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuYu", isDirectory: true)
            .appendingPathComponent("conversation-memory.json")
        guard let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([LegacyMessage].self, from: data) else { return [] }
        return messages.suffix(200).map { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let kind: ConversationItem.Kind
            if message.role == "user" {
                kind = .user
            } else if content.hasPrefix("实际执行失败") {
                kind = .error
            } else if content.hasPrefix("计划执行") || content.hasPrefix("实际执行成功") {
                kind = .action
            } else if content.contains("<tool_call>") || content.contains("<function=") {
                kind = .error
            } else {
                kind = .assistant
            }
            let displayText = (content.contains("<tool_call>") || content.contains("<function="))
                ? "旧记录：模型曾返回未解析的内部工具调用，未确认实际执行。"
                : content
            return .init(kind: kind, text: displayText)
        }
    }

    private func markInterruptedActionIfNeeded() {
        let lastStarted = conversation.lastIndex(where: {
            $0.kind == .action && $0.text.hasPrefix("正在执行：")
        })
        let lastFinished = conversation.lastIndex(where: {
            ($0.kind == .action || $0.kind == .error)
                && ($0.text.hasPrefix("执行成功：")
                    || $0.text.hasPrefix("执行失败：")
                    || $0.text.contains("取消了操作")
                    || $0.text.contains("任务已中断"))
        })
        guard let lastStarted, lastFinished.map({ lastStarted > $0 }) ?? true else { return }
        conversation.append(.init(
            kind: .error,
            text: "任务已中断：应用在收到真实执行结果前退出，因此不能确认任务成功。请根据需要重新执行。"
        ))
    }

    private static var defaultConversationHistoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuYu", isDirectory: true)
            .appendingPathComponent("conversation-history.json")
    }

    func runDemo() {
        demoTask?.cancel()
        isRunningDemo = true
        beginThinking(userText: "帮我整理下载文件夹里的文件。")

        demoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            self.presentApproval(
                title: "允许浮屿整理下载文件夹？",
                detail: "将按类型移动 12 个文件，不会删除内容，可随时撤销。"
            )
        }
    }

    private func finishDemo() {
        beginExecution(title: "整理下载文件夹")
        demoTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self.updateExecution(progress: 0.5, step: 1)
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            self.updateExecution(progress: 0.92, step: 2)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.isRunningDemo = false
            self.beginSpeaking("演示完成。没有修改任何文件。")
        }
    }
}
