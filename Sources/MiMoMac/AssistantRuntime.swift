import AppKit
import Foundation

@MainActor
final class AssistantRuntime {
    private struct PendingAction {
        let approvalID: UUID
        let title: String
        let prompt: String
        let originalRequest: String
        let shouldSpeak: Bool
    }

    private struct PendingClarification {
        let originalRequest: String
    }

    private struct PendingLocalAction {
        let approvalID: UUID
        let title: String
        let recommendation: MacCareRecommendation
        let report: MacCareReport
        let shouldSpeak: Bool
    }

    private let state: AppState
    private let voice: VoiceService
    private let preferences: AssistantPreferences
    private let modelClient: MiMoAssistantClient
    private let hermes = HermesCommandRunner()

    private var requestTask: Task<Void, Never>?
    private var pendingAction: PendingAction?
    private var activeAction: PendingAction?
    private var pendingClarification: PendingClarification?
    private var pendingLocalAction: PendingLocalAction?

    init(
        state: AppState,
        voice: VoiceService,
        preferences: AssistantPreferences,
        modelClient: MiMoAssistantClient = MiMoAssistantClient()
    ) {
        self.state = state
        self.voice = voice
        self.preferences = preferences
        self.modelClient = modelClient

        voice.onTranscriptReady = { [weak self] text in
            self?.handleTranscript(text)
        }
        voice.onApprovalDecision = { [weak self] approved in
            self?.handleApprovalDecision(approved)
        }
        state.onVoiceRequested = { [weak self] in
            guard let self else { return }
            Task { @MainActor in await self.voice.startListening() }
        }
        state.onCancelRequested = { [weak self] in
            self?.cancelCurrentWork()
        }
        state.onVoiceSubmitRequested = { [weak self] in
            self?.voice.stopListeningAndSubmit()
        }
        state.onApprovalGranted = { [weak self] approvalID in
            guard let self else { return }
            if self.pendingLocalAction?.approvalID == approvalID {
                self.executeApprovedLocalAction(approvalID: approvalID)
            } else {
                self.executeApprovedAction(approvalID: approvalID)
            }
        }
    }

    var isHermesAvailable: Bool { hermes.isAvailable }

    func testModelConnection() async throws -> String {
        try await modelClient.testConnection(profile: preferences.profile)
    }

    func clearMemory() async throws {
        try await modelClient.clearMemory()
        try state.clearConversationMemory()
    }

    func handleTranscript(_ text: String) {
        state.beginVoiceInteraction()
        handleUserInput(text, shouldSpeak: true, isVoice: true)
    }

    func handleTextInput(_ text: String) {
        voice.cancelAll()
        state.beginTextInteraction()
        handleUserInput(text, shouldSpeak: false, isVoice: false)
    }

    private func handleApprovalDecision(_ approved: Bool) {
        guard state.showPermission else { return }
        if approved {
            state.recordActionStatus("已通过语音确认")
            state.approveFromUserInteraction()
        } else {
            state.recordActionStatus("用户通过语音取消了操作", failed: true)
            cancelCurrentWork()
            state.resetToIdle(message: "操作已取消")
        }
    }

    private func handleUserInput(_ text: String, shouldSpeak: Bool, isVoice: Bool) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            state.presentError("没有听清，请再说一次。")
            return
        }

        if preferences.voiceActionApproval, state.showPermission {
            let compact = Self.normalizedApprovalPhrase(cleaned)
            let approvePhrases = ["允许执行", "确认执行", "同意执行", "可以执行", "执行吧"]
            let denyPhrases = ["取消执行", "不要执行", "拒绝执行", "不允许执行", "取消", "算了"]
            if denyPhrases.contains(where: compact.contains) {
                state.recordActionStatus(isVoice ? "用户通过语音取消了操作" : "用户通过文字取消了操作", failed: true)
                cancelCurrentWork()
                state.resetToIdle(message: "操作已取消")
                return
            }
            if approvePhrases.contains(where: compact.contains) {
                state.recordActionStatus(isVoice ? "已通过语音确认" : "已通过文字确认")
                state.approveFromUserInteraction()
                return
            }
            if isVoice {
                state.recordActionStatus("没有识别到明确授权，仍在等待“允许执行”或“取消执行”")
                Task { @MainActor [weak self] in await self?.voice.startListeningForApproval() }
                return
            }
        }

        if let interruptedAction = activeAction {
            let originalRequest = interruptedAction.originalRequest
            let pauseOnly = Self.isPauseOnlyCommand(cleaned)
            cancelCurrentWork()
            state.recordActionStatus("已暂停当前任务：(interruptedAction.title)")
            pendingClarification = .init(originalRequest: originalRequest)
            if pauseOnly {
                state.beginThinking(userText: cleaned)
                deliverReply(
                    "已经暂停。你可以直接告诉我需要修改或补充什么，我会按新要求重新规划。",
                    suggestedSpoken: "已经暂停，你直接告诉我需要怎么改。",
                    shouldSpeak: shouldSpeak
                )
                return
            }
        }

        if let command = AssistantPreferences.memoryCommand(for: cleaned) {
            cancelCurrentWork()
            state.beginThinking(userText: cleaned)
            let response: String
            switch command {
            case let .remember(value):
                response = preferences.rememberHabit(value) ? "记住了：\(value)" : "这条习惯是空的，我没有保存。"
            case let .forget(value):
                let count = preferences.forgetHabits(matching: value)
                response = count > 0 ? "已经忘记与“\(value)”有关的 \(count) 条永久记忆。" : "没有找到与“\(value)”匹配的永久记忆。"
            case .list:
                response = preferences.permanentHabits.isEmpty
                    ? "我还没有保存你的永久习惯。你可以说：记住，我喜欢简短回答。"
                    : "我永久记住了：\n" + preferences.permanentHabits.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
            }
            deliverReply(response, suggestedSpoken: nil, shouldSpeak: shouldSpeak)
            return
        }

        if let localCommand = LocalCommandRouter.command(for: cleaned) {
            cancelCurrentWork()
            state.beginThinking(userText: cleaned)
            handleLocalCommand(localCommand, shouldSpeak: shouldSpeak)
            return
        }

        let effectiveRequest: String
        if let clarification = pendingClarification {
            if cleaned == "取消" || cleaned == "算了" {
                pendingClarification = nil
                cancelCurrentWork()
                state.beginThinking(userText: cleaned)
                deliverReply("好的，这个任务已经取消。", suggestedSpoken: nil, shouldSpeak: shouldSpeak)
                return
            }
            effectiveRequest = clarification.originalRequest + "\n用户补充信息：" + cleaned
            pendingClarification = nil
        } else if let question = Self.missingCriticalDetailsQuestion(for: cleaned) {
            cancelCurrentWork()
            state.beginThinking(userText: cleaned)
            pendingClarification = .init(originalRequest: cleaned)
            state.recordActionStatus("执行前需要补充：\(question)")
            deliverReply(question, suggestedSpoken: question, shouldSpeak: shouldSpeak)
            return
        } else {
            effectiveRequest = cleaned
        }
        let requestForModel = preferences.profile.persistentMemory
            ? state.contextualizedRequest(effectiveRequest)
            : effectiveRequest

        cancelCurrentWork(preservingClarification: true)
        state.beginThinking(userText: cleaned)

        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let capabilities = await LocalMacCapabilityManifest.current()
                let localContext = capabilities.prompt
                    + "\n最新电脑管家结果：\n" + self.state.macCareContextPrompt
                    + "\n\n对话记忆：\n" + self.state.conversationContextPrompt(
                        for: effectiveRequest,
                        includePersistent: self.preferences.profile.persistentMemory
                    )
                let decision = try await self.modelClient.decide(
                    for: requestForModel,
                    profile: self.preferences.profile,
                    localContext: localContext
                )
                try Task.checkCancellation()
                switch decision {
                case let .reply(text, spoken):
                    self.pendingAction = nil
                    self.deliverReply(text, suggestedSpoken: spoken, shouldSpeak: shouldSpeak)
                case let .action(title, detail, prompt):
                    guard self.hermes.isAvailable else {
                        let message = AssistantServiceError.hermesUnavailable.localizedDescription
                        self.state.recordActionStatus("未执行：\(title)\n\(message)", failed: true)
                        try? await self.modelClient.recordActionResult(
                            title: title,
                            result: message,
                            succeeded: false,
                            profile: self.preferences.profile
                        )
                        self.state.presentError(message)
                        return
                    }
                    if Self.requiresPlanReview(userText: effectiveRequest) {
                        self.state.recordActionStatus("复杂任务预审：正在向 Hermes 获取只读方案")
                        let proposedPlan = try await self.hermes.proposePlan(for: prompt)
                        try Task.checkCancellation()
                        let review = try await self.modelClient.reviewExecutionPlan(
                            userRequest: effectiveRequest,
                            originalPrompt: prompt,
                            hermesPlan: proposedPlan,
                            profile: self.preferences.profile
                        )
                        try Task.checkCancellation()
                        switch review {
                        case let .approved(summary, finalPrompt):
                            self.state.recordActionStatus("方案审核通过：\(summary)")
                            self.prepareAction(
                                title: title,
                                detail: summary,
                                prompt: finalPrompt,
                                originalRequest: effectiveRequest,
                                shouldSpeak: shouldSpeak
                            )
                        case let .clarify(question):
                            self.pendingAction = nil
                            self.pendingClarification = .init(originalRequest: effectiveRequest)
                            self.state.recordActionStatus("方案需要补充信息：\(question)")
                            self.deliverReply(question, suggestedSpoken: question, shouldSpeak: shouldSpeak)
                        }
                    } else {
                        self.prepareAction(
                            title: title,
                            detail: detail,
                            prompt: prompt,
                            originalRequest: effectiveRequest,
                            shouldSpeak: shouldSpeak
                        )
                    }
                }
            } catch is CancellationError {
                return
            } catch AssistantServiceError.cancelled {
                return
            } catch {
                self.state.presentError(error.localizedDescription)
            }
        }
    }

    private func prepareAction(
        title: String,
        detail: String,
        prompt: String,
        originalRequest: String,
        shouldSpeak: Bool
    ) {
        let displayTitle = Self.cleanActionTitle(title)
        if preferences.requireActionApproval {
            state.markTaskFocus(.awaitingApproval)
            let approvalID = state.presentApproval(title: displayTitle, detail: detail)
            pendingAction = PendingAction(
                approvalID: approvalID,
                title: displayTitle,
                prompt: prompt,
                originalRequest: originalRequest,
                shouldSpeak: shouldSpeak
            )
            if preferences.voiceActionApproval, shouldSpeak {
                Task { @MainActor [weak self] in
                    await self?.voice.startListeningForApproval()
                }
            }
        } else {
            let approvalID = UUID()
            pendingAction = PendingAction(
                approvalID: approvalID,
                title: displayTitle,
                prompt: prompt,
                originalRequest: originalRequest,
                shouldSpeak: shouldSpeak
            )
            executeApprovedAction(approvalID: approvalID)
        }
    }

    static func requiresPlanReview(userText: String) -> Bool {
        let value = userText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return false }
        let simpleVerbs = ["打开", "关闭", "启动", "退出", "调高", "调低", "切换"]
        let complexSignals = [
            "然后", "之后", "同时", "并且", "全部", "所有", "批量", "按照", "整理", "开发", "修改",
            "修复", "测试", "检查", "分析", "优化", "安装", "卸载", "配置", "项目", "文件夹里的",
            "长期", "周期", "重复会议", "创建会议", "开一个会", "预约", "日程", "发送", "删除", "发布", "购买"
        ]
        let punctuationSteps = value.filter { ",，;；".contains($0) }.count
        if value.count <= 24, simpleVerbs.contains(where: value.contains), !complexSignals.contains(where: value.contains) {
            return false
        }
        return value.count >= 38 || punctuationSteps >= 2 || complexSignals.contains(where: value.contains)
    }

    static func missingCriticalDetailsQuestion(for userText: String) -> String? {
        let value = userText.lowercased()
        let hasNumber = value.unicodeScalars.contains { (48...57).contains($0.value) }
        if value.contains("亮度"),
           !hasNumber, !["调高", "调低", "最高", "最低", "增加", "降低"].contains(where: value.contains) {
            return "你想把屏幕亮度调到百分之多少？也可以说调高一点或调低一点。"
        }
        if value.contains("音量"),
           !hasNumber, !["调高", "调低", "静音", "最大", "增加", "降低"].contains(where: value.contains) {
            return "你想把音量调到百分之多少？也可以说调高一点、调低一点或静音。"
        }
        if ["发消息", "发送消息", "发邮件", "发送邮件"].contains(where: value.contains) {
            let hasRecipient = ["给", "发给", "收件人", "联系人"].contains(where: value.contains)
            let hasContent = ["内容", "说", "告诉", "主题"].contains(where: value.contains)
            if !hasRecipient || !hasContent { return "你要发给谁，具体内容是什么？我确认清楚后再执行。" }
        }
        if value.contains("删除"), !["这个", "这些", "文件", "文件夹", "."].contains(where: value.contains) {
            return "你想删除哪个具体内容？请告诉我名称或位置。"
        }
        let isMeetingCreation = value.contains("会议")
            && ["创建", "新建", "开一个", "开个", "预约", "安排"].contains(where: value.contains)
        guard isMeetingCreation else { return nil }

        let hasTime = value.range(of: #"([0-2]?\d)[:：点时]|今天|明天|后天|上午|下午|晚上"#, options: .regularExpression) != nil
        let hasDuration = value.range(of: #"\d+\s*(分钟|小时)|到\s*[0-2]?\d"#, options: .regularExpression) != nil
        let hasRecurrenceChoice = ["单次", "临时", "长期", "周期", "每天", "每周", "工作日", "重复"].contains(where: value.contains)
        let asksLongTerm = ["长期", "周期", "每天", "每周", "工作日", "重复"].contains(where: value.contains)
        let hasLongTermBoundary = !asksLongTerm || ["到", "截止", "共", "场", "次", "长期有效"].contains(where: value.contains)
        guard hasTime, hasDuration, hasRecurrenceChoice, hasLongTermBoundary else {
            return "这个会议什么时候开始、持续多久？是单次会议还是长期重复？如果长期，请告诉我重复频率和结束日期或总场次。"
        }
        return nil
    }

    static func normalizedApprovalPhrase(_ text: String) -> String {
        text.filter { $0.isLetter || $0.isNumber }
    }

    static func isPauseOnlyCommand(_ text: String) -> Bool {
        let compact = text.filter { $0.isLetter || $0.isNumber }
        return ["停", "停一下", "等一下", "先停一下", "先别执行", "暂停", "暂停任务", "取消任务"]
            .contains(compact)
    }

    static func cleanActionTitle(_ title: String) -> String {
        let firstLine = title.split(whereSeparator: \.isNewline).first.map(String.init) ?? title
        let value = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "执行 Mac 操作" : String(value.prefix(28))
    }

    func cancelCurrentWork() {
        cancelCurrentWork(preservingClarification: false)
    }

    private func cancelCurrentWork(preservingClarification: Bool) {
        requestTask?.cancel()
        requestTask = nil
        pendingAction = nil
        pendingLocalAction = nil
        activeAction = nil
        if !preservingClarification { pendingClarification = nil }
        hermes.cancel()
        voice.cancelAll()
    }

    private func handleLocalCommand(_ command: LocalMacCommand, shouldSpeak: Bool) {
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch command {
                case let .scan(tool):
                    self.state.markTaskFocus(.executing)
                    self.state.beginLocalExecution(title: tool.rawValue)
                    self.state.updateExecution(progress: 0.48, step: 1)
                    let report = try await Task.detached(priority: .userInitiated) {
                        try await MacCareService.run(tool)
                    }.value
                    try Task.checkCancellation()
                    self.state.updateExecution(progress: 0.94, step: 2)
                    self.state.publishMacCareReport(report)
                    self.state.recordActionStatus(report.displayText)
                    self.state.markTaskFocus(.completed)
                    try? await self.modelClient.recordActionResult(
                        title: "电脑管家 · \(tool.rawValue)",
                        result: report.displayText,
                        succeeded: true,
                        profile: self.preferences.profile
                    )
                    self.deliverReply(report.displayText, suggestedSpoken: report.headline, shouldSpeak: shouldSpeak)
                case let .volume(adjustment):
                    self.state.markTaskFocus(.executing)
                    self.state.beginLocalExecution(title: "音量控制")
                    let result = try await LocalMacControlService.shared.adjustVolume(adjustment)
                    self.state.updateExecution(progress: 1, step: 2)
                    self.state.recordActionStatus("浮屿本机控制 · \(result)")
                    self.state.markTaskFocus(.completed)
                    self.deliverReply(result, suggestedSpoken: result, shouldSpeak: shouldSpeak)
                case let .brightness(adjustment):
                    self.state.markTaskFocus(.executing)
                    self.state.beginLocalExecution(title: "屏幕亮度")
                    let result = try await LocalMacControlService.shared.adjustBrightness(adjustment)
                    self.state.updateExecution(progress: 1, step: 2)
                    self.state.recordActionStatus("浮屿本机控制 · \(result)")
                    self.state.markTaskFocus(.completed)
                    self.deliverReply(result, suggestedSpoken: result, shouldSpeak: shouldSpeak)
                case let .applyLatest(tool):
                    guard let report = self.state.latestMacCareReports[tool] else {
                        self.state.markTaskFocus(.executing)
                        self.state.beginLocalExecution(title: tool.rawValue)
                        let scanned = try await Task.detached(priority: .userInitiated) {
                            try await MacCareService.run(tool)
                        }.value
                        self.state.publishMacCareReport(scanned)
                        self.state.recordActionStatus(scanned.displayText)
                        self.state.markTaskFocus(.completed)
                        self.deliverReply(
                            scanned.displayText + "\n\n请查看建议并确认后再执行；浮屿不会静默修改文件。",
                            suggestedSpoken: "检测完成，请确认建议后再执行。",
                            shouldSpeak: shouldSpeak
                        )
                        return
                    }
                    guard let recommendation = report.recommendations.first else {
                        self.deliverReply(
                            "\(tool.rawValue)的最新结果没有需要执行的项目。\n\(report.headline)",
                            suggestedSpoken: "最新结果没有需要执行的项目。",
                            shouldSpeak: shouldSpeak
                        )
                        return
                    }
                    self.prepareLocalRecommendation(recommendation, report: report, shouldSpeak: shouldSpeak)
                case .capabilities:
                    let capabilities = await LocalMacCapabilityManifest.current()
                    let brightness = capabilities.brightnessAvailable ? "屏幕亮度" : "亮度能力检测（当前屏幕不支持直接控制）"
                    let reply = """
                    我是浮屿 FuYu，一款以这台 Mac 为核心的本机智能助手。

                    我能直接在本机完成九项电脑管家检测、音量与静音控制、\(brightness)，并持续监测异常发热进程。电脑管家的检测结果会同步给我，所以你可以直接接着问“有什么问题”或“执行哪条建议”。

                    只读检查和可逆设置优先由我自己完成，不经过 Hermes；跨应用的复杂任务才交给 Hermes。清理、移动、删除、发送或修改安全设置前，我会先说明收益和风险并等你确认。
                    """
                    self.deliverReply(reply, suggestedSpoken: "我是浮屿，这台 Mac 的本机智能助手。", shouldSpeak: shouldSpeak)
                }
            } catch is CancellationError {
                return
            } catch {
                self.state.markTaskFocus(.failed)
                self.state.recordActionStatus("浮屿本机执行失败：\(error.localizedDescription)", failed: true)
                self.state.presentError(error.localizedDescription)
            }
        }
    }

    private func prepareLocalRecommendation(
        _ recommendation: MacCareRecommendation,
        report: MacCareReport,
        shouldSpeak: Bool
    ) {
        let modifiesFiles: Bool
        switch recommendation.action {
        case .cleanSafe, .organizeDownloads: modifiesFiles = true
        default: modifiesFiles = false
        }
        if modifiesFiles {
            state.markTaskFocus(.awaitingApproval)
            let detail = "收益：\(recommendation.benefit)\n风险：\(recommendation.risk)"
            let approvalID = state.presentApproval(title: recommendation.title, detail: detail)
            pendingLocalAction = .init(
                approvalID: approvalID,
                title: recommendation.title,
                recommendation: recommendation,
                report: report,
                shouldSpeak: shouldSpeak
            )
            if preferences.voiceActionApproval, shouldSpeak {
                Task { @MainActor [weak self] in await self?.voice.startListeningForApproval() }
            }
        } else {
            let approvalID = UUID()
            pendingLocalAction = .init(
                approvalID: approvalID,
                title: recommendation.title,
                recommendation: recommendation,
                report: report,
                shouldSpeak: shouldSpeak
            )
            executeApprovedLocalAction(approvalID: approvalID)
        }
    }

    private func executeApprovedLocalAction(approvalID: UUID) {
        guard let pending = pendingLocalAction, pending.approvalID == approvalID else {
            state.presentError("本机操作的确认信息已失效，请重新检测。")
            return
        }
        pendingLocalAction = nil
        voice.cancelAll()
        state.beginLocalExecution(title: pending.title)
        state.markTaskFocus(.executing)
        requestTask?.cancel()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let report = try await self.executeLocalAction(pending.recommendation.action, sourceReport: pending.report)
                try Task.checkCancellation()
                self.state.publishMacCareReport(report)
                self.state.recordActionStatus(report.displayText)
                self.state.markTaskFocus(.completed)
                try? await self.modelClient.recordActionResult(
                    title: pending.title,
                    result: report.displayText,
                    succeeded: true,
                    profile: self.preferences.profile
                )
                self.deliverReply(report.displayText, suggestedSpoken: report.headline, shouldSpeak: pending.shouldSpeak)
            } catch is CancellationError {
                return
            } catch {
                self.state.markTaskFocus(.failed)
                self.state.recordActionStatus("本机执行失败：\(error.localizedDescription)", failed: true)
                self.state.presentError(error.localizedDescription)
            }
        }
    }

    private func executeLocalAction(_ action: MacCareAction, sourceReport: MacCareReport) async throws -> MacCareReport {
        switch action {
        case .cleanSafe:
            guard let plan = sourceReport.cleanupPlan else { throw LocalMacToolError.invalidSystemResponse }
            let result = await MacCareService.cleanSafe(plan)
            return MacCareReport(
                tool: .junkScan,
                headline: "已将 \(result.entries.count) 项、约 \(ByteCountFormatter.string(fromByteCount: result.bytesFreed, countStyle: .file)) 移到废纸篓",
                details: ["可从废纸篓恢复", "安全校验跳过：\(result.skippedPaths.count) 项"]
            )
        case let .organizeDownloads(moves):
            let result = await Task.detached { MacCareService.organizeDownloads(moves) }.value
            return MacCareReport(
                tool: .organize,
                headline: "已整理 \(result.moved) 个文件，跳过 \(result.skipped) 个",
                details: ["没有覆盖同名文件", "没有删除文件"] + result.failures.prefix(12).map { "失败：\($0)" }
            )
        case let .revealFiles(urls):
            let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
            NSWorkspace.shared.activateFileViewerSelecting(existing)
            return MacCareReport(tool: sourceReport.tool, headline: "已在 Finder 定位 \(existing.count) 个项目", details: ["浮屿没有删除任何文件"])
        case .openLoginItems:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!)
            return MacCareReport(tool: .loginItems, headline: "已打开登录项设置", details: ["请按名称确认后再关闭不需要的项目"])
        case .openActivityMonitor:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
            return MacCareReport(tool: .hotProcesses, headline: "已打开活动监视器", details: ["结束进程前请先保存工作"])
        case let .runTool(tool):
            return try await MacCareService.run(tool)
        }
    }

    private func executeApprovedAction(approvalID: UUID) {
        guard let action = pendingAction, action.approvalID == approvalID else {
            state.presentError("批准信息已失效，请重新说一次。")
            return
        }
        pendingAction = nil
        voice.cancelAll()
        state.beginExecution(title: action.title)
        state.markTaskFocus(.executing)
        activeAction = action
        if action.shouldSpeak {
            Task { @MainActor [weak self] in
                await self?.voice.startListeningForTaskInterruption()
            }
        }

        requestTask?.cancel()
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let progressTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, !Task.isCancelled else { return }
                self.state.updateExecution(progress: 0.42, step: 1)
                try? await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else { return }
                self.state.updateExecution(progress: 0.72, step: 1)
            }
            defer { progressTask.cancel() }

            do {
                let result = try await self.hermes.execute(action.prompt)
                try Task.checkCancellation()
                self.voice.stopTaskInterruptionMonitoring()
                self.activeAction = nil
                self.state.updateExecution(progress: 0.94, step: 2)
                try? await Task.sleep(for: .milliseconds(220))
                try Task.checkCancellation()
                self.state.recordActionStatus("执行成功：\(action.title)\n\(result)")
                self.state.markTaskFocus(.completed)
                try? await self.modelClient.recordActionResult(
                    title: action.title,
                    result: result,
                    succeeded: true,
                    profile: self.preferences.profile
                )
                let naturalSpoken = action.shouldSpeak
                    ? try? await self.modelClient.makeNaturalSpokenSummary(for: result, profile: self.preferences.profile)
                    : nil
                self.deliverReply(result, suggestedSpoken: naturalSpoken, shouldSpeak: action.shouldSpeak)
            } catch is CancellationError {
                return
            } catch AssistantServiceError.cancelled {
                return
            } catch {
                self.voice.stopTaskInterruptionMonitoring()
                self.activeAction = nil
                let message = error.localizedDescription
                self.state.recordActionStatus("执行失败：\(action.title)\n\(message)", failed: true)
                self.state.markTaskFocus(.failed)
                try? await self.modelClient.recordActionResult(
                    title: action.title,
                    result: message,
                    succeeded: false,
                    profile: self.preferences.profile
                )
                self.state.presentError(message)
            }
        }
    }

    private func deliverReply(_ text: String, suggestedSpoken: String?, shouldSpeak: Bool) {
        if shouldSpeak, let spoken = preferences.spokenText(fullText: text, suggested: suggestedSpoken) {
            voice.speak(spoken, displayText: text)
        } else {
            state.presentSilentReply(text)
            if state.interactionSource == .voice {
                voice.continueAfterSilentReply()
            }
        }
    }
}
