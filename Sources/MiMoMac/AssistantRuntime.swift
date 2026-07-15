import Foundation

@MainActor
final class AssistantRuntime {
    private struct PendingAction {
        let approvalID: UUID
        let title: String
        let prompt: String
        let shouldSpeak: Bool
    }

    private let state: AppState
    private let voice: VoiceService
    private let preferences: AssistantPreferences
    private let modelClient: MiMoAssistantClient
    private let hermes = HermesCommandRunner()

    private var requestTask: Task<Void, Never>?
    private var pendingAction: PendingAction?

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
        handleUserInput(text, shouldSpeak: true)
    }

    func handleTextInput(_ text: String) {
        handleUserInput(text, shouldSpeak: false)
    }

    private func handleUserInput(_ text: String, shouldSpeak: Bool) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            state.presentError("没有听清，请再说一次。")
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

        cancelCurrentWork()
        state.beginThinking(userText: cleaned)

        requestTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let decision = try await self.modelClient.decide(
                    for: cleaned,
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
                    if self.preferences.requireActionApproval {
                        let approvalID = self.state.presentApproval(title: title, detail: detail)
                        self.pendingAction = PendingAction(
                            approvalID: approvalID,
                            title: title,
                            prompt: prompt,
                            shouldSpeak: shouldSpeak
                        )
                    } else {
                        let approvalID = UUID()
                        self.pendingAction = PendingAction(
                            approvalID: approvalID,
                            title: title,
                            prompt: prompt,
                            shouldSpeak: shouldSpeak
                        )
                        self.executeApprovedAction(approvalID: approvalID)
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

    func cancelCurrentWork() {
        requestTask?.cancel()
        requestTask = nil
        pendingAction = nil
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
                self.deliverReply(result, suggestedSpoken: nil, shouldSpeak: action.shouldSpeak)
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
