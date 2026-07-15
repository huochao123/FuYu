import Foundation

@MainActor
final class AssistantRuntime {
    private struct PendingAction {
        let approvalID: UUID
        let title: String
        let prompt: String
        let shouldSpeak: Bool
    }

    private struct PendingClarification {
        let originalRequest: String
    }

    private let state: AppState
    private let voice: VoiceService
    private let preferences: AssistantPreferences
    private let modelClient: MiMoAssistantClient
    private let hermes = HermesCommandRunner()

    private var requestTask: Task<Void, Never>?
    private var pendingAction: PendingAction?
    private var pendingClarification: PendingClarification?

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
            self?.executeApprovedAction(approvalID: approvalID)
        }
    }

    var isHermesAvailable: Bool { hermes.isAvailable }

    func testModelConnection() async throws -> String {
        try await modelClient.testConnection(profile: preferences.profile)
    }

    func clearMemory() async throws {
        try await modelClient.clearMemory()
    }

    func handleTranscript(_ text: String) {
        handleUserInput(text, shouldSpeak: true, isVoice: true)
    }

    func handleTextInput(_ text: String) {
        handleUserInput(text, shouldSpeak: false, isVoice: false)
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

        cancelCurrentWork(preservingClarification: true)
        state.beginThinking(userText: cleaned)

        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let decision = try await self.modelClient.decide(
                    for: effectiveRequest,
                    profile: self.preferences.profile
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
                                shouldSpeak: shouldSpeak
                            )
                        case let .clarify(question):
                            self.pendingAction = nil
                            self.pendingClarification = .init(originalRequest: effectiveRequest)
                            self.state.recordActionStatus("方案需要补充信息：\(question)")
                            self.deliverReply(question, suggestedSpoken: question, shouldSpeak: shouldSpeak)
                        }
                    } else {
                        self.prepareAction(title: title, detail: detail, prompt: prompt, shouldSpeak: shouldSpeak)
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

    private func prepareAction(title: String, detail: String, prompt: String, shouldSpeak: Bool) {
        let displayTitle = Self.cleanActionTitle(title)
        if preferences.requireActionApproval {
            let approvalID = state.presentApproval(title: displayTitle, detail: detail)
            pendingAction = PendingAction(
                approvalID: approvalID,
                title: displayTitle,
                prompt: prompt,
                shouldSpeak: shouldSpeak
            )
            if preferences.voiceActionApproval {
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
        if !preservingClarification { pendingClarification = nil }
        hermes.cancel()
        voice.cancelAll()
    }

    private func executeApprovedAction(approvalID: UUID) {
        guard let action = pendingAction, action.approvalID == approvalID else {
            state.presentError("批准信息已失效，请重新说一次。")
            return
        }
        pendingAction = nil
        state.beginExecution(title: action.title)

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
                self.state.updateExecution(progress: 0.94, step: 2)
                try? await Task.sleep(for: .milliseconds(220))
                try Task.checkCancellation()
                self.state.recordActionStatus("执行成功：\(action.title)\n\(result)")
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
                let message = error.localizedDescription
                self.state.recordActionStatus("执行失败：\(action.title)\n\(message)", failed: true)
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
            voice.continueAfterSilentReply()
        }
    }
}
