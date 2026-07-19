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

    enum RecognitionStage: Equatable {
        case waiting
        case live
        case finalizing
        case final
    }

    enum BackgroundTaskStatus: Equatable {
        case running
        case stalled
        case completed
        case failed
    }

    struct BackgroundJob: Identifiable, Equatable {
        enum Kind: String, Equatable { case readOnly = "只读", localMutation = "本机修改", hermes = "跨应用" }
        let id: UUID
        let title: String
        let kind: Kind
        let startedAt: Date
        var lastProgressAt: Date
        var status: BackgroundTaskStatus
        var summary: String
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

    struct HealthEvent: Identifiable, Equatable, Codable {
        enum Severity: String, Codable { case normal = "正常", attention = "关注", warning = "风险" }
        let id: UUID
        let occurredAt: Date
        let category: String
        let title: String
        let evidence: String
        let severity: Severity
        let resolution: String

        init(id: UUID = UUID(), occurredAt: Date = Date(), category: String, title: String,
             evidence: String, severity: Severity, resolution: String) {
            self.id = id
            self.occurredAt = occurredAt
            self.category = category
            self.title = title
            self.evidence = evidence
            self.severity = severity
            self.resolution = resolution
        }
    }

    @Published var isExpanded = false
    @Published private(set) var voiceSessionActive = false
    @Published private(set) var backgroundTaskTitle: String?
    @Published private(set) var backgroundTaskStatus: BackgroundTaskStatus?
    @Published private(set) var backgroundTaskStartedAt: Date?
    @Published private(set) var backgroundTaskLastProgressAt: Date?
    @Published private(set) var backgroundJobs: [BackgroundJob] = []
    @Published private(set) var interactionSource: InteractionSource = .voice
    @Published var phase: Phase = .idle
    @Published var audioLevel = 0.0
    @Published var activitySource = "本机"
    @Published var remoteChannelStatus = "飞书未配置"
    @Published var transcript = "需要我做什么？"
    @Published private(set) var recognitionStage: RecognitionStage = .waiting
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
    @Published private(set) var latestMacDiagnosticFindings: [MacCareTool: MacDiagnosticFinding] = [:]
    @Published private(set) var latestMacDiagnosticFinding: MacDiagnosticFinding?
    @Published private(set) var macCareReportVersion = 0
    @Published private(set) var healthEvents: [HealthEvent] = []
    @Published private(set) var lastOrganizationTransaction: [CompletedFileMove] = []

    var onVoiceRequested: (() -> Void)?
    var onVoiceSubmitRequested: (() -> Void)?
    var onCancelRequested: (() -> Void)?
    var onVoiceSessionEndRequested: (() -> Void)?
    var onApprovalGranted: ((UUID) -> Void)?
    var onBackgroundJobCancelRequested: ((UUID) -> Void)?

    private var demoTask: Task<Void, Never>?
    private var replyCollapseTask: Task<Void, Never>?
    private var errorDismissTask: Task<Void, Never>?
    private var backgroundStatusDismissTask: Task<Void, Never>?
    private var backgroundTaskMonitor: Task<Void, Never>?
    private var backgroundJobMonitors: [UUID: Task<Void, Never>] = [:]
    private var backgroundJobCancellationHandlers: [UUID: () -> Void] = [:]
    private var legacyBackgroundJobID: UUID?
    private var isRunningDemo = false
    private let conversationHistoryURL: URL
    private let healthEventsURL: URL
    private let memorySystem: FuYuMemorySystem
    private var isInitializingMemory = true

    init(historyURL: URL? = nil) {
        let resolvedHistoryURL = historyURL ?? Self.defaultConversationHistoryURL
        conversationHistoryURL = resolvedHistoryURL
        healthEventsURL = historyURL == nil
            ? resolvedHistoryURL.deletingLastPathComponent().appendingPathComponent("health-events.json")
            : resolvedHistoryURL.deletingPathExtension().appendingPathExtension("health-events.json")
        memorySystem = FuYuMemorySystem(historyURL: resolvedHistoryURL)
        healthEvents = Self.loadHealthEvents(from: healthEventsURL)
        if let stored = Self.loadConversationHistory(from: conversationHistoryURL), !stored.isEmpty {
            conversation = stored
        } else {
            conversation = Self.importLegacyModelHistory()
        }
        conversation.removeAll {
            $0.text == "等待确认：创建腾讯会议\n下午 3 点到 4 点 · 单次会议 · 使用腾讯会议 MCP"
        }
        deduplicateLegacyMacCareAlerts()
        markInterruptedActionIfNeeded()
        persistConversationHistory()
        memorySystem.bootstrapArchiveIfNeeded(with: conversation)
        memorySystem.bootstrapWorkingFocusIfNeeded(with: conversation)
        isInitializingMemory = false
    }

    private func deduplicateLegacyMacCareAlerts() {
        let pattern = #"检测到\s+([^\s，]+)\s+(?:已连续|持续)高负载"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        var lastKept: [String: Date] = [:]
        conversation = conversation.filter { item in
            guard item.kind == .action else { return true }
            let range = NSRange(item.text.startIndex..<item.text.endIndex, in: item.text)
            guard let match = regex.firstMatch(in: item.text, range: range),
                  let keyRange = Range(match.range(at: 1), in: item.text) else { return true }
            let key = String(item.text[keyRange])
            if item.text.hasPrefix("系统提醒："), lastKept[key] != nil { return false }
            if let previous = lastKept[key], item.createdAt.timeIntervalSince(previous) < 2 * 60 * 60 { return false }
            lastKept[key] = item.createdAt
            return true
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
        voiceSessionActive = true
        demoTask?.cancel()
        replyCollapseTask?.cancel()
        errorDismissTask?.cancel()
        if !preservingApproval { showPermission = false }
        isExpanded = true
        phase = .listening
        activitySource = "麦克风"
        transcript = preservingApproval ? "请说“允许执行”或“取消执行”" : "我在听…"
        recognitionStage = .waiting
        approvalIsListening = preservingApproval
        if preservingApproval { approvalHeardText = "" }
        progress = 0
        steps = []
    }

    func updateTranscript(_ text: String, isFinal: Bool = false) {
        guard phase == .listening else { return }
        if showPermission {
            approvalHeardText = text
            return
        }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = cleaned.isEmpty ? "我在听…" : cleaned
        recognitionStage = cleaned.isEmpty ? .waiting : (isFinal ? .final : .live)
    }

    func noteDetectedVoiceActivity() {
        guard phase == .listening, !showPermission, recognitionStage == .waiting else { return }
        transcript = "听到声音，正在识别…"
        recognitionStage = .live
    }

    func beginFinalizingRecognition() {
        guard phase == .listening, !showPermission else { return }
        recognitionStage = .finalizing
    }

    func presentFinalRecognition(_ text: String) {
        guard phase == .listening, !showPermission else { return }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        transcript = cleaned
        recognitionStage = .final
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
        let bounded = min(max(newProgress, 0), 1)
        if bounded > progress {
            backgroundTaskLastProgressAt = Date()
            if backgroundTaskStatus == .stalled { backgroundTaskStatus = .running }
        }
        progress = bounded
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

    func finishSpeaking(keepExpanded: Bool = false) {
        guard phase == .speaking else { return }
        phase = .idle
        audioLevel = 0
        activitySource = "本机"
        if keepExpanded {
            // Continuous conversation owns the next transition. Never let an
            // old delayed collapse race the next microphone session.
            isExpanded = true
            return
        }
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

    func endVoiceSession() {
        onVoiceSessionEndRequested?()
        resetToIdle(message: "语音对话已结束")
    }

    @discardableResult
    func beginBackgroundJob(
        _ title: String,
        kind: BackgroundJob.Kind,
        onCancel: (() -> Void)? = nil
    ) -> UUID {
        let now = Date()
        let id = UUID()
        backgroundJobs.append(.init(id: id, title: title, kind: kind, startedAt: now, lastProgressAt: now, status: .running, summary: "已开始"))
        if let onCancel { backgroundJobCancellationHandlers[id] = onCancel }
        backgroundJobs = Array(backgroundJobs.suffix(20))
        syncBackgroundSummary()
        backgroundJobMonitors[id] = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled,
                  let job = self.backgroundJobs.first(where: { $0.id == id }),
                  job.status == .running || job.status == .stalled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled,
                      let index = self.backgroundJobs.firstIndex(where: { $0.id == id }),
                      self.backgroundJobs[index].status == .running,
                      Self.shouldMarkBackgroundTaskStalled(
                        startedAt: self.backgroundJobs[index].startedAt,
                        lastProgressAt: self.backgroundJobs[index].lastProgressAt,
                        now: Date()
                      ) else { continue }
                self.backgroundJobs[index].status = .stalled
                self.backgroundJobs[index].summary = "超过 5 分钟没有新进度"
                self.syncBackgroundSummary()
                let elapsed = Self.elapsedDescription(from: self.backgroundJobs[index].startedAt, to: Date())
                self.appendConversation(
                    .error,
                    "后台任务可能卡住：\(title) 已运行\(elapsed)，超过 5 分钟没有新进度。"
                )
                if !self.voiceSessionActive {
                    self.presentNotification("后台任务“\(title)”可能卡住：已运行\(elapsed)，超过 5 分钟没有新进度。", recordInHistory: false)
                }
            }
        }
        return id
    }

    func updateBackgroundJob(_ id: UUID, summary: String) {
        guard let index = backgroundJobs.firstIndex(where: { $0.id == id }) else { return }
        backgroundJobs[index].lastProgressAt = Date()
        backgroundJobs[index].status = .running
        backgroundJobs[index].summary = summary
        syncBackgroundSummary()
    }

    func finishBackgroundJob(_ id: UUID, summary: String, failed: Bool = false) {
        backgroundJobMonitors[id]?.cancel()
        backgroundJobMonitors[id] = nil
        backgroundJobCancellationHandlers[id] = nil
        guard let index = backgroundJobs.firstIndex(where: { $0.id == id }) else { return }
        backgroundJobs[index].lastProgressAt = Date()
        backgroundJobs[index].status = failed ? .failed : .completed
        backgroundJobs[index].summary = summary
        syncBackgroundSummary()
    }

    func requestCancelBackgroundJob(_ id: UUID) {
        if let handler = backgroundJobCancellationHandlers[id] {
            handler()
        } else {
            onBackgroundJobCancelRequested?(id)
        }
    }

    func beginBackgroundTask(_ title: String) {
        legacyBackgroundJobID = beginBackgroundJob(title, kind: .hermes)
    }

    func finishBackgroundTask(_ title: String, failed: Bool = false) {
        guard let id = legacyBackgroundJobID else { return }
        finishBackgroundJob(id, summary: title, failed: failed)
        legacyBackgroundJobID = nil
    }

    func clearBackgroundTask() {
        backgroundStatusDismissTask?.cancel()
        backgroundStatusDismissTask = nil
        backgroundTaskMonitor?.cancel()
        backgroundTaskMonitor = nil
        for task in backgroundJobMonitors.values { task.cancel() }
        backgroundJobMonitors.removeAll()
        backgroundJobCancellationHandlers.removeAll()
        backgroundJobs.removeAll()
        legacyBackgroundJobID = nil
        backgroundTaskTitle = nil
        backgroundTaskStatus = nil
        backgroundTaskStartedAt = nil
        backgroundTaskLastProgressAt = nil
    }

    private func syncBackgroundSummary() {
        let candidate = backgroundJobs.reversed().first(where: { $0.status == .running || $0.status == .stalled })
            ?? backgroundJobs.last
        backgroundTaskTitle = candidate?.title
        backgroundTaskStatus = candidate?.status
        backgroundTaskStartedAt = candidate?.startedAt
        backgroundTaskLastProgressAt = candidate?.lastProgressAt
    }

    var backgroundTaskElapsedDescription: String {
        guard let startedAt = backgroundTaskStartedAt else { return "未知时长" }
        return Self.elapsedDescription(from: startedAt, to: Date())
    }

    var backgroundTaskContextPrompt: String {
        if !backgroundJobs.isEmpty {
            return backgroundJobs.suffix(8).map { job in
                let elapsed = Self.elapsedDescription(from: job.startedAt, to: Date())
                return "[\(job.kind.rawValue)] \(job.title)；状态=\(job.status)；已运行=\(elapsed)；进度=\(job.summary)"
            }.joined(separator: "\n")
        }
        guard let title = backgroundTaskTitle,
              let status = backgroundTaskStatus,
              let startedAt = backgroundTaskStartedAt else { return "当前没有后台任务。" }
        let statusText: String
        switch status {
        case .running: statusText = "执行中"
        case .stalled: statusText = "可能卡住（不得描述为正常）"
        case .completed: statusText = "已完成"
        case .failed: statusText = "失败"
        }
        let lastProgress = backgroundTaskLastProgressAt.map { Self.memoryTimestamp(for: $0) } ?? "没有记录"
        return "任务：\(title)\n状态：\(statusText)\n开始：\(Self.memoryTimestamp(for: startedAt))\n已运行：\(backgroundTaskElapsedDescription)\n最后进度：\(lastProgress)"
    }

    var backgroundTaskUserSummary: String? {
        guard let title = backgroundTaskTitle,
              let status = backgroundTaskStatus,
              let startedAt = backgroundTaskStartedAt else { return nil }
        let started = Self.displayTimestamp(for: startedAt)
        let lastProgress = backgroundTaskLastProgressAt.map { Self.displayTimestamp(for: $0) } ?? "没有记录"
        switch status {
        case .running:
            return "后台任务“\(title)”从\(started)开始，已经运行\(backgroundTaskElapsedDescription)。最后一次进度在\(lastProgress)，目前仍在执行。"
        case .stalled:
            return "后台任务“\(title)”从\(started)开始，已经运行\(backgroundTaskElapsedDescription)，并且超过 5 分钟没有新进度，可能已经卡住。你可以让我检查、取消或重新执行，不能再把它当作正常运行。"
        case .completed:
            return "后台任务“\(title)”已经完成，总等待时间约\(backgroundTaskElapsedDescription)。"
        case .failed:
            return "后台任务“\(title)”执行失败，开始于\(started)，已等待约\(backgroundTaskElapsedDescription)。"
        }
    }

    nonisolated static func shouldMarkBackgroundTaskStalled(
        startedAt: Date?,
        lastProgressAt: Date?,
        now: Date,
        threshold: TimeInterval = 300
    ) -> Bool {
        guard let startedAt, let lastProgressAt else { return false }
        return now.timeIntervalSince(startedAt) >= threshold
            && now.timeIntervalSince(lastProgressAt) >= threshold
    }

    nonisolated static func elapsedDescription(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)秒" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分钟" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)小时" : "\(hours)小时\(remainder)分钟"
    }

    func resetToIdle(message: String = "需要我做什么？") {
        replyCollapseTask?.cancel()
        replyCollapseTask = nil
        errorDismissTask?.cancel()
        errorDismissTask = nil
        showPermission = false
        interactionSource = .voice
        voiceSessionActive = false
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
        voiceSessionActive = false
        isExpanded = false
        showHistory = false
    }

    func beginVoiceInteraction() {
        interactionSource = .voice
    }

    func presentNotification(_ message: String, duration: Duration = .seconds(9), recordInHistory: Bool = true) {
        replyCollapseTask?.cancel()
        interactionSource = .notification
        showPermission = false
        showHistory = false
        phase = .answered
        audioLevel = 0
        transcript = message
        isExpanded = true
        if recordInHistory { appendConversation(.action, "系统提醒：\(message)") }
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
        let finding = MacDiagnosticFinding(report: report)
        let previous = latestMacDiagnosticFindings[report.tool]
        let shouldRecord = previous == nil
            || previous?.summary != finding.summary
            || Date().timeIntervalSince(previous?.detectedAt ?? .distantPast) >= 2 * 60 * 60
        latestMacCareReports[report.tool] = report
        latestMacCareReport = report
        latestMacDiagnosticFindings[report.tool] = finding
        latestMacDiagnosticFinding = finding
        macCareReportVersion &+= 1
        if shouldRecord {
            recordActionStatus("""
            检测结论 · \(report.tool.rawValue)：\(finding.summary)
            风险：\(finding.severity.rawValue)；处理：\(finding.ownership.rawValue)
            影响：\(finding.impact)
            """)
            recordHealthEvent(from: finding, tool: report.tool)
        }
        // A successful scan is evidence, not proof that a recommendation was
        // applied. Only actual tool executions belong in learned experience.
    }

    func recordOrganizationTransaction(_ moves: [CompletedFileMove]) {
        lastOrganizationTransaction = moves
    }

    func clearOrganizationTransaction() {
        lastOrganizationTransaction = []
    }

    private func recordHealthEvent(from finding: MacDiagnosticFinding, tool: MacCareTool) {
        let severity: HealthEvent.Severity = switch finding.severity {
        case .normal: .normal
        case .attention: .attention
        case .warning: .warning
        }
        healthEvents.append(.init(
            category: tool.rawValue,
            title: finding.summary,
            evidence: finding.evidence.prefix(3).joined(separator: "；"),
            severity: severity,
            resolution: finding.nextStep
        ))
        if healthEvents.count > 200 { healthEvents.removeFirst(healthEvents.count - 200) }
        persistHealthEvents()
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

    var macDiagnosticContextPrompt: String {
        guard !latestMacDiagnosticFindings.isEmpty else { return "尚无结构化异常或检测结论。" }
        return MacCareTool.allCases.compactMap { tool in
            latestMacDiagnosticFindings[tool].map { "[\(tool.rawValue)]\n\($0.prompt)" }
        }.joined(separator: "\n\n")
    }

    func conversationContextPrompt(for query: String, includePersistent: Bool = true, recentLimit: Int = 6) -> String {
        guard !conversation.isEmpty else { return "尚无历史对话。" }
        // Keep the active window focused. Older relevant facts are supplied by
        // the retrieval layer below instead of duplicating a long transcript.
        let recentCount = min(max(recentLimit, 2), 8)
        let recentStart = max(0, conversation.count - recentCount)
        let recent = Array(conversation[recentStart...])
        let relevant = includePersistent
            ? memorySystem.relevantHistory(for: query, excluding: Set(recent.map(\.id)), limit: 3)
            : []

        func render(_ items: [ConversationItem]) -> String {
            items.map { item in
                let role: String
                switch item.kind {
                case .user: role = "用户"
                case .assistant: role = "浮屿"
                case .action: role = "真实工具/任务状态"
                case .error: role = "执行错误"
                }
                let compact = Self.compactConversationMemory(item.text, kind: item.kind)
                return "[\(Self.memoryTimestamp(for: item.createdAt))] \(role)：\(compact)"
            }.joined(separator: "\n")
        }

        let relevantText = relevant.isEmpty ? "无额外匹配记录。" : render(relevant)
        return """
        当前时间：\(Self.memoryTimestamp(for: Date()))；时区：\(TimeZone.current.identifier)。

        当前连续对话（按时间顺序，必须承接代词、追问和“继续/去吧/这个/为什么”等短句）：
        \(render(recent))

        当前工作记忆：
        \(includePersistent ? memorySystem.focusPrompt : "跨启动工作记忆已关闭，本轮只使用即时对话。")

        与当前请求相关的较早记录（仅作为历史，不要误当成刚发生）：
        \(includePersistent ? relevantText : "跨启动工作记忆已关闭，未调用会话归档。")
        """
    }

    nonisolated static func compactConversationMemory(_ text: String, kind: ConversationItem.Kind) -> String {
        let compact = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limit: Int
        switch kind {
        case .user: limit = 700
        case .assistant: limit = 520
        case .action, .error: limit = 420
        }
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit)) + "…（完整结果保留在状态屏）"
    }

    nonisolated static func memoryTimestamp(for date: Date, relativeTo now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
        let absolute = formatter.string(from: date)
        let calendar = Calendar.current
        let relation: String
        if calendar.isDateInToday(date) {
            relation = "今天"
        } else if calendar.isDateInYesterday(date) {
            relation = "昨天"
        } else if calendar.isDateInTomorrow(date) {
            relation = "明天"
        } else {
            let days = calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: now)
            ).day ?? 0
            relation = days > 0 ? "\(days)天前" : (days < 0 ? "\(-days)天后" : "当天")
        }
        return "\(absolute) · \(relation)"
    }

    nonisolated static func displayTimestamp(for date: Date, relativeTo now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: now) ? "'今天' HH:mm:ss" : "MM-dd HH:mm:ss"
        if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'昨天' HH:mm:ss"
        }
        return formatter.string(from: date)
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

    private func persistHealthEvents() {
        do {
            try FileManager.default.createDirectory(
                at: healthEventsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(healthEvents).write(to: healthEventsURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: healthEventsURL.path)
        } catch {
            // A later event retries persistence; the current session remains available.
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

    private static func loadHealthEvents(from url: URL) -> [HealthEvent] {
        guard let data = try? Data(contentsOf: url),
              let events = try? JSONDecoder().decode([HealthEvent].self, from: data) else { return [] }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return Array(events.suffix(200))
    }

    private static func importLegacyModelHistory() -> [ConversationItem] {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuYu", isDirectory: true)
            .appendingPathComponent("conversation-memory.json")
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
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
