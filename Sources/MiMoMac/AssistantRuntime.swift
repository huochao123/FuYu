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
    private var backgroundActionTasks: [UUID: Task<Void, Never>] = [:]
    private var backgroundRunners: [UUID: HermesCommandRunner] = [:]
    private var readOnlyTasks: [UUID: Task<Void, Never>] = [:]
    private var mutationTasks: [UUID: Task<Void, Never>] = [:]
    private var mutationTail: Task<Void, Never>?
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
            self?.cancelAllWork()
        }
        state.onVoiceSessionEndRequested = { [weak self] in
            self?.voice.cancelAll()
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
        state.onBackgroundJobCancelRequested = { [weak self] id in
            self?.cancelBackgroundJob(id)
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
        if Self.isEndConversationCommand(text) {
            voice.cancelAll()
            state.recordActionStatus("用户通过语音结束了连续对话")
            state.resetToIdle(message: "语音对话已结束")
            return
        }
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
            let approvePhrases = ["允许执行", "确认执行", "同意执行", "可以执行", "执行吧", "继续执行", "去吧"]
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
            // A typed question while an approval is visible must not silently
            // replace or bypass the pending action. Keep the card in place and
            // explain the exact operation in ordinary text instead.
            state.recordAssistantMessage("当前还在等你确认“\(state.approvalTitle)”。\(state.approvalDetail) 如果同意，请输入“允许执行”；不想做就输入“取消执行”。想修改要求时，先取消再告诉我新的做法。")
            return
        }

        if Self.isBackgroundTaskStatusQuery(cleaned),
           let summary = state.backgroundTaskUserSummary {
            cancelCurrentWork()
            state.beginThinking(userText: cleaned)
            deliverReply(summary, suggestedSpoken: summary, shouldSpeak: shouldSpeak)
            return
        }

        if let interruptedAction = activeAction,
           Self.isBackgroundTaskControlCommand(cleaned) {
            let originalRequest = interruptedAction.originalRequest
            let pauseOnly = Self.isPauseOnlyCommand(cleaned)
            cancelBackgroundWork()
            cancelCurrentWork()
            state.recordActionStatus("已暂停当前任务：\(interruptedAction.title)")
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

        if Self.requestsPlainLanguageMemory(cleaned) {
            cancelCurrentWork()
            state.beginThinking(userText: cleaned)
            _ = preferences.rememberHabit("技术与系统检测结果请用新手能看懂的简单中文解释；先说结论、影响和怎么处理，不直接堆进程路径、编号或原始日志。")
            deliverReply("记住了。以后系统结果我先讲人话：哪里有问题、会有什么影响、你要不要处理；原始数据只在你想看时再展开。", suggestedSpoken: "记住了，以后我先用简单的话讲清结论和处理办法。", shouldSpeak: shouldSpeak)
            return
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

        let needsPersonaLore = preferences.personaEnabled
            && preferences.personaPreset == .wanNing
            && PersonaKnowledgeLibrary.shouldLoadLore(for: cleaned)
        if !needsPersonaLore {
            switch AgentIntentEngine.route(for: cleaned, conversation: state.conversation) {
            case let .reply(reply):
                cancelCurrentWork()
                state.beginThinking(userText: cleaned)
                deliverReply(reply, suggestedSpoken: nil, shouldSpeak: shouldSpeak)
                return
            case let .local(localCommand):
                cancelCurrentWork()
                state.beginThinking(userText: cleaned)
                handleLocalCommand(localCommand, shouldSpeak: shouldSpeak)
                return
            case .model:
                break
            }
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
        if effectiveRequest != cleaned,
           let question = Self.missingCriticalDetailsQuestion(for: effectiveRequest) {
            pendingClarification = .init(originalRequest: effectiveRequest)
            state.beginThinking(userText: cleaned)
            state.recordActionStatus("执行前仍需补充：\(question)")
            deliverReply(question, suggestedSpoken: question, shouldSpeak: shouldSpeak)
            return
        }
        let requestForModel = preferences.profile.persistentMemory
            ? state.contextualizedRequest(effectiveRequest)
            : "[当前命令时间：\(AppState.memoryTimestamp(for: Date()))]\n用户命令：\(effectiveRequest)"

        cancelCurrentWork(preservingClarification: true)
        state.beginThinking(userText: cleaned)

        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let capabilities = await LocalMacCapabilityManifest.current()
                let diagnosticHint = self.state.latestMacDiagnosticFinding.map {
                    "\($0.source) \($0.summary) \($0.skillID)"
                } ?? ""
                let skillSelection = MacSkillLibrary.select(
                    for: effectiveRequest + " " + diagnosticHint,
                    limit: 1
                )
                let learnedExperience = MacExperienceStore.shared.context(for: effectiveRequest)
                let contextQuery = effectiveRequest.lowercased()
                let needsCareEvidence = [
                    "电脑", "mac", "系统", "发热", "温度", "卡顿", "内存", "磁盘", "空间",
                    "垃圾", "缓存", "重复", "启动项", "异常", "检测", "优化", "管家", "进程"
                ].contains(where: contextQuery.contains)
                let refersToTask = [
                    "任务", "执行", "进度", "多久", "完成", "刚才", "继续", "取消", "它", "那个"
                ].contains(where: contextQuery.contains)
                let careContext = needsCareEvidence
                    ? "\n最新电脑管家结果：\n" + self.state.macCareContextPrompt
                        + "\n\n结构化检测责任卡：\n" + self.state.macDiagnosticContextPrompt
                    : ""
                let taskContext = refersToTask
                    ? "\n\n当前后台任务及耗时：\n" + self.state.backgroundTaskContextPrompt
                    : ""
                let localContext = capabilities.prompt
                    + "\n\nMac Skill 能力索引（仅目录，不是诊断结论）：\n" + skillSelection.indexPrompt
                    + "\n\n当前按需加载的 Mac Skill（最多一个，只有相关时才加载正文）：\n" + skillSelection.loadedPrompt
                    + "\n\n这台 Mac 的已验证经验（系统版本不匹配时只能参考，必须重新验证）：\n" + learnedExperience
                    + careContext
                    + taskContext
                    + "\n\n对话记忆：\n" + self.state.conversationContextPrompt(
                        for: effectiveRequest,
                        includePersistent: self.preferences.profile.persistentMemory,
                        recentLimit: self.preferences.profile.contextTurns
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
                case let .tool(call):
                    guard let localCommand = AgentToolRegistry.localCommand(for: call) else {
                        self.state.presentError("浮屿没有识别出这个本机工具的参数，未执行任何操作。")
                        return
                    }
                    self.state.recordActionStatus("浮屿选择本机工具：\(call.id.rawValue)")
                    self.handleLocalCommand(localCommand, shouldSpeak: shouldSpeak)
                case let .hermes(title, detail, prompt):
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
                        let proposedPlan = try await HermesCommandRunner().proposePlan(for: prompt)
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
            } catch AssistantServiceError.modelTimeout {
                let message = AssistantServiceError.modelTimeout.localizedDescription
                // One user-visible reply is enough; recording a separate failed
                // action produced two nearly identical cards for one timeout.
                self.deliverReply(message, suggestedSpoken: "模型响应超时，本机工具仍然可以直接使用。", shouldSpeak: shouldSpeak)
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

        let hasTime = value.range(of: #"([0-2]?\d)[:：点时]|今天|明天|后天|上午|下午|晚上|现在|立即|马上"#, options: .regularExpression) != nil
        let hasDuration = value.range(of: #"([0-9一二两三四五六七八九十]+)\s*(分钟|小时)|到\s*[0-2]?\d"#, options: .regularExpression) != nil
        let hasRecurrenceChoice = ["单次", "临时", "长期", "周期", "每天", "每周", "工作日", "重复"].contains(where: value.contains)
        let asksLongTerm = ["长期", "周期", "每天", "每周", "工作日", "重复"].contains(where: value.contains)
        let hasLongTermBoundary = !asksLongTerm || ["到", "截止", "共", "场", "次", "长期有效"].contains(where: value.contains)
        guard hasTime, hasDuration, hasRecurrenceChoice, hasLongTermBoundary else {
            return "这个会议什么时候开始、持续多久？是单次会议还是长期重复？如果长期，请告诉我重复频率和结束日期或总场次。"
        }
        return nil
    }

    static func requestsPlainLanguageMemory(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        let asksRemember = compact.contains("记住") || compact.contains("下次") || compact.contains("以后")
        let needsSimple = compact.contains("看不懂") || compact.contains("小白") || compact.contains("简单点")
            || compact.contains("大白话") || compact.contains("这么说")
        return asksRemember && needsSimple
    }

    static func normalizedApprovalPhrase(_ text: String) -> String {
        text.filter { $0.isLetter || $0.isNumber }
    }

    static func isPauseOnlyCommand(_ text: String) -> Bool {
        let compact = text.filter { $0.isLetter || $0.isNumber }
        return ["停", "停一下", "等一下", "先停一下", "先别执行", "暂停", "暂停任务", "取消任务"]
            .contains(compact)
    }

    static func isBackgroundTaskControlCommand(_ text: String) -> Bool {
        let compact = text.filter { $0.isLetter || $0.isNumber }
        if isPauseOnlyCommand(compact) { return true }
        return [
            "取消当前任务", "停止当前任务", "暂停当前任务", "终止当前任务",
            "取消这个任务", "停止这个任务", "暂停这个任务", "终止这个任务",
            "修改当前任务", "修改这个任务", "这个任务改成", "当前任务改成"
        ].contains(where: compact.contains)
    }

    static func isBackgroundTaskStatusQuery(_ text: String) -> Bool {
        let compact = text.filter { $0.isLetter || $0.isNumber }
        let taskSignals = ["任务", "执行", "后台", "刚才那个", "那个操作"]
        let statusSignals = ["怎么样", "怎么了", "完成了吗", "好了吗", "还没好", "多久", "进度", "正常吗", "卡住", "还在做"]
        return taskSignals.contains(where: compact.contains)
            && statusSignals.contains(where: compact.contains)
    }

    static func isEndConversationCommand(_ text: String) -> Bool {
        var compact = text.filter { $0.isLetter || $0.isNumber }
        for prefix in ["请", "帮我", "麻烦"] where compact.hasPrefix(prefix) {
            compact.removeFirst(prefix.count)
        }
        for suffix in ["吧", "了", "谢谢"] where compact.hasSuffix(suffix) {
            compact.removeLast(suffix.count)
        }
        return [
            "结束对话", "关闭对话", "停止对话", "退出对话",
            "结束聊天", "关闭聊天", "结束语音", "关闭语音", "退出语音",
            "结束通话", "关闭通话", "挂断", "挂断电话"
        ].contains(compact)
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
        if !preservingClarification { pendingClarification = nil }
        voice.cancelAll()
    }

    private func cancelBackgroundWork() {
        for task in backgroundActionTasks.values { task.cancel() }
        for task in readOnlyTasks.values { task.cancel() }
        for task in mutationTasks.values { task.cancel() }
        for runner in backgroundRunners.values { runner.cancel() }
        backgroundActionTasks.removeAll()
        backgroundRunners.removeAll()
        readOnlyTasks.removeAll()
        mutationTasks.removeAll()
        mutationTail?.cancel()
        mutationTail = nil
        activeAction = nil
        hermes.cancel()
        state.clearBackgroundTask()
    }

    private func cancelBackgroundJob(_ id: UUID) {
        backgroundActionTasks[id]?.cancel()
        readOnlyTasks[id]?.cancel()
        mutationTasks[id]?.cancel()
        backgroundRunners[id]?.cancel()
        backgroundActionTasks[id] = nil
        readOnlyTasks[id] = nil
        mutationTasks[id] = nil
        backgroundRunners[id] = nil
        state.finishBackgroundJob(id, summary: "用户已取消", failed: true)
        state.recordActionStatus("已取消后台任务", failed: true)
    }

    private func cancelAllWork() {
        cancelCurrentWork()
        cancelBackgroundWork()
    }

    private func handleLocalCommand(_ command: LocalMacCommand, shouldSpeak: Bool) {
        if case let .scan(tool) = command {
            startReadOnlyScan(tool, shouldSpeak: shouldSpeak)
            return
        }
        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                switch command {
                case .scan:
                    return
                case let .volume(adjustment):
                    self.state.markTaskFocus(.executing)
                    self.state.beginLocalExecution(title: "音量控制")
                    let result = try await LocalMacControlService.shared.adjustVolume(adjustment)
                    self.state.updateExecution(progress: 1, step: 2)
                    self.state.recordActionStatus("浮屿本机控制 · \(result)")
                    MacExperienceStore.shared.record(task: "本机音量控制", result: result, succeeded: true)
                    self.state.markTaskFocus(.completed)
                    self.deliverReply(result, suggestedSpoken: result, shouldSpeak: shouldSpeak)
                case let .brightness(adjustment):
                    self.state.markTaskFocus(.executing)
                    self.state.beginLocalExecution(title: "屏幕亮度")
                    let result = try await LocalMacControlService.shared.adjustBrightness(adjustment)
                    self.state.updateExecution(progress: 1, step: 2)
                    self.state.recordActionStatus("浮屿本机控制 · \(result)")
                    MacExperienceStore.shared.record(task: "本机亮度控制", result: result, succeeded: true)
                    self.state.markTaskFocus(.completed)
                    self.deliverReply(result, suggestedSpoken: result, shouldSpeak: shouldSpeak)
                case let .openApplication(name):
                    self.state.beginLocalExecution(title: "打开应用")
                    let result = try await LocalMacControlService.shared.openApplication(named: name)
                    self.state.recordActionStatus("浮屿本机控制 · \(result)")
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

    private func startReadOnlyScan(_ tool: MacCareTool, shouldSpeak: Bool) {
        let jobID = state.beginBackgroundJob("电脑管家 · \(tool.rawValue)", kind: .readOnly)
        state.beginLocalExecution(title: tool.rawValue)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.readOnlyTasks[jobID] = nil }
            do {
                self.state.updateBackgroundJob(jobID, summary: "正在读取本机状态")
                let report = try await Task.detached(priority: .userInitiated) {
                    try await MacCareService.run(tool)
                }.value
                try Task.checkCancellation()
                self.state.publishMacCareReport(report)
                self.state.finishBackgroundJob(jobID, summary: report.headline)
                try? await self.modelClient.recordActionResult(
                    title: "电脑管家 · \(tool.rawValue)", result: report.displayText,
                    succeeded: true, profile: self.preferences.profile
                )
                self.deliverReply(report.displayText, suggestedSpoken: report.headline, shouldSpeak: shouldSpeak)
            } catch is CancellationError {
                self.state.finishBackgroundJob(jobID, summary: "已取消", failed: true)
            } catch {
                self.state.finishBackgroundJob(jobID, summary: error.localizedDescription, failed: true)
                self.state.presentError(error.localizedDescription)
            }
        }
        readOnlyTasks[jobID] = task
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
        let jobID = state.beginBackgroundJob(pending.title, kind: .localMutation)
        state.markTaskFocus(.executing)
        keepVoiceAvailableDuringBackgroundTask()
        let predecessor = mutationTail
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.mutationTasks[jobID] = nil }
            if let predecessor { await predecessor.value }
            guard !Task.isCancelled else { return }
            do {
                self.state.updateBackgroundJob(jobID, summary: "正在执行已确认的本机修改")
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
                self.state.finishBackgroundJob(jobID, summary: "已完成 · \(pending.title)")
                if self.state.voiceSessionActive {
                    self.state.recordAssistantMessage("后台任务已完成：\(pending.title)\n\(report.displayText)")
                    self.resumeVoiceIfExecutionCardIsVisible()
                } else {
                    self.deliverReply(report.displayText, suggestedSpoken: report.headline, shouldSpeak: pending.shouldSpeak)
                }
            } catch is CancellationError {
                return
            } catch {
                self.state.markTaskFocus(.failed)
                self.state.recordActionStatus("本机执行失败：\(error.localizedDescription)", failed: true)
                self.state.finishBackgroundJob(jobID, summary: "失败 · \(pending.title)", failed: true)
                if self.state.voiceSessionActive {
                    self.resumeVoiceIfExecutionCardIsVisible()
                } else {
                    self.state.presentError(error.localizedDescription)
                }
            }
        }
        mutationTail = task
        mutationTasks[jobID] = task
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
            state.recordOrganizationTransaction(result.completedMoves)
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
        case .openPrivacySettings:
            let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension")!
            if !NSWorkspace.shared.open(url) {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
            }
            return MacCareReport(tool: .privacyAudit, headline: "已打开隐私与安全性", details: ["撤销权限前请确认对应功能是否仍需要"])
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
        let jobID = state.beginBackgroundJob(action.title, kind: .hermes)
        state.markTaskFocus(.executing)
        activeAction = action
        keepVoiceAvailableDuringBackgroundTask()

        let runner = HermesCommandRunner()
        backgroundRunners[jobID] = runner
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.backgroundActionTasks[jobID] = nil
                self.backgroundRunners[jobID] = nil
            }
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
                self.state.updateBackgroundJob(jobID, summary: "Hermes 正在执行并验证")
                let result = try await runner.execute(action.prompt)
                try Task.checkCancellation()
                self.activeAction = nil
                self.state.updateExecution(progress: 0.94, step: 2)
                try? await Task.sleep(for: .milliseconds(220))
                try Task.checkCancellation()
                self.state.recordActionStatus("执行成功：\(action.title)\n\(result)")
                MacExperienceStore.shared.record(task: action.title, result: result, succeeded: true)
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
                self.state.finishBackgroundJob(jobID, summary: "已完成 · \(action.title)")
                if self.state.voiceSessionActive {
                    self.state.recordAssistantMessage("后台任务已完成：\(action.title)\n\(result)")
                    self.resumeVoiceIfExecutionCardIsVisible()
                } else {
                    self.deliverReply(result, suggestedSpoken: naturalSpoken, shouldSpeak: action.shouldSpeak)
                }
            } catch is CancellationError {
                return
            } catch AssistantServiceError.cancelled {
                return
            } catch {
                self.activeAction = nil
                let message = error.localizedDescription
                self.state.recordActionStatus("执行失败：\(action.title)\n\(message)", failed: true)
                MacExperienceStore.shared.record(task: action.title, result: message, succeeded: false)
                self.state.markTaskFocus(.failed)
                try? await self.modelClient.recordActionResult(
                    title: action.title,
                    result: message,
                    succeeded: false,
                    profile: self.preferences.profile
                )
                self.state.finishBackgroundJob(jobID, summary: "失败 · \(action.title)", failed: true)
                if self.state.voiceSessionActive {
                    self.resumeVoiceIfExecutionCardIsVisible()
                } else {
                    self.state.presentError(message)
                }
            }
        }
        backgroundActionTasks[jobID] = task
    }

    private func keepVoiceAvailableDuringBackgroundTask() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self,
                  self.state.backgroundJobs.contains(where: { $0.status == .running || $0.status == .stalled }),
                  self.state.voiceSessionActive else { return }
            await self.voice.startListening()
        }
    }

    private func resumeVoiceIfExecutionCardIsVisible() {
        guard state.voiceSessionActive, state.phase == .executing else { return }
        Task { @MainActor [weak self] in await self?.voice.startListening() }
    }

    private func deliverReply(_ text: String, suggestedSpoken: String?, shouldSpeak: Bool) {
        let displayText = preferences.personaStyledReply(text)
        if shouldSpeak, let spoken = preferences.spokenText(fullText: displayText, suggested: suggestedSpoken) {
            voice.speak(preferences.personaStyledSpeech(spoken), displayText: displayText)
        } else {
            state.presentSilentReply(displayText)
            if state.interactionSource == .voice {
                voice.continueAfterSilentReply()
            }
        }
    }
}
