import Foundation

@MainActor
final class AssistantRuntime {
    private struct PendingAction {
        let approvalID: UUID
        let title: String
        let prompt: String
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
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            state.presentError("没有听清，请再说一次。")
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
                    self.deliverReply(text, suggestedSpoken: spoken)
                case let .action(title, detail, prompt):
                    if self.preferences.requireActionApproval {
                        let approvalID = self.state.presentApproval(title: title, detail: detail)
                        self.pendingAction = PendingAction(
                            approvalID: approvalID,
                            title: title,
                            prompt: prompt
                        )
                    } else {
                        let approvalID = UUID()
                        self.pendingAction = PendingAction(
                            approvalID: approvalID,
                            title: title,
                            prompt: prompt
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
                self.deliverReply(result, suggestedSpoken: nil)
            } catch is CancellationError {
                return
            } catch AssistantServiceError.cancelled {
                return
            } catch {
                self.state.presentError(error.localizedDescription)
            }
        }
    }

    private func deliverReply(_ text: String, suggestedSpoken: String?) {
        if let spoken = preferences.spokenText(fullText: text, suggested: suggestedSpoken) {
            voice.speak(spoken, displayText: text)
        } else {
            state.presentSilentReply(text)
            voice.continueAfterSilentReply()
        }
    }
}
