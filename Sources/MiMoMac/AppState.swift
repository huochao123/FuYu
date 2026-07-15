import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
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
    @Published var phase: Phase = .idle
    @Published var transcript = "需要我做什么？"
    @Published var modelLabel = "MiMo"
    @Published var taskTitle = "准备任务"
    @Published var progress = 0.0
    @Published var showPermission = false
    @Published var approvalTitle = "允许浮屿执行这个操作？"
    @Published var approvalDetail = "执行前会再次确认，不会在后台静默操作。"
    @Published private(set) var approvalID: UUID?
    @Published var steps: [TaskStep] = []
    @Published var conversation: [ConversationItem] = []
    @Published var showHistory = false

    var onVoiceRequested: (() -> Void)?
    var onVoiceSubmitRequested: (() -> Void)?
    var onCancelRequested: (() -> Void)?
    var onApprovalGranted: ((UUID) -> Void)?

    private var demoTask: Task<Void, Never>?
    private var replyCollapseTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var isRunningDemo = false
    private let conversationHistoryURL: URL

    init(historyURL: URL? = nil) {
        conversationHistoryURL = historyURL ?? Self.defaultConversationHistoryURL
        if let stored = Self.loadConversationHistory(from: conversationHistoryURL), !stored.isEmpty {
            conversation = stored
        } else {
            conversation = Self.importLegacyModelHistory()
            persistConversationHistory()
        }
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
        demoTask?.cancel()
        replyCollapseTask?.cancel()
        errorDismissTask?.cancel()
        if !preservingApproval { showPermission = false }
        isExpanded = true
        phase = .listening
        transcript = preservingApproval ? "请说“允许执行”或“取消执行”" : "我在听…"
        progress = 0
        steps = []
    }

    func updateTranscript(_ text: String) {
        guard phase == .listening else { return }
        transcript = text.isEmpty ? "我在听…" : text
    }

    func beginThinking(userText: String) {
        replyCollapseTask?.cancel()
        showPermission = false
        isExpanded = true
        phase = .thinking
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
        showPermission = true
        isExpanded = true
        phase = .thinking
        appendConversation(.action, "等待确认：\(title)\n\(detail)")
        return id
    }

    func beginExecution(title: String) {
        showPermission = false
        isExpanded = true
        phase = .executing
        taskTitle = title
        progress = 0.08
        steps = [
            .init(title: "正在连接 Hermes", detail: "准备安全执行环境", status: .active),
            .init(title: "Hermes 已接收任务", detail: "正在按照指令执行", status: .pending),
            .init(title: "正在检查结果", detail: "确认操作是否完成", status: .pending)
        ]
        appendConversation(.action, "正在执行：\(title)")
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
        transcript = text
        progress = steps.isEmpty ? 0 : 1
        for index in steps.indices { steps[index].status = .complete }
        appendConversation(.assistant, text)
    }

    func finishSpeaking() {
        guard phase == .speaking else { return }
        phase = .idle
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, self.phase == .idle, !self.showPermission else { return }
            self.isExpanded = false
        }
    }

    func presentSilentReply(_ text: String) {
        replyCollapseTask?.cancel()
        showPermission = false
        isExpanded = true
        phase = .answered
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
        isExpanded = true
        phase = .error
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
        approvalID = nil
        phase = .idle
        progress = 0
        transcript = message
        steps = []
        showHistory = false
        isExpanded = false
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

    private func appendConversation(_ kind: ConversationItem.Kind, _ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if conversation.last?.kind == kind, conversation.last?.text == value { return }
        conversation.append(.init(kind: kind, text: value))
        conversation = Array(conversation.suffix(500))
        persistConversationHistory()
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
