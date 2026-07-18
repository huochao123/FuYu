import AVFoundation
import OSLog
import Speech

@MainActor
final class VoiceService: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    static let maxRecognitionRecoveryAttempts = 2
    var onTranscriptReady: ((String) -> Void)?
    var onApprovalDecision: ((Bool) -> Void)?

    private let state: AppState
    private let preferences: AssistantPreferences
    private let audioEngine = AVAudioEngine()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "ai.fuyu.desktop", category: "voice")
    private var audioPlayer: AVAudioPlayer?
    private var speechTask: Task<Void, Never>?
    private var continuousTask: Task<Void, Never>?
    private var outputVolumeRestoreTask: Task<Void, Never>?
    private var audioStartupWatchdogTask: Task<Void, Never>?
    private var voiceActivitySubmissionTask: Task<Void, Never>?
    private var outputVolumeBeforeListening: LocalMacControlService.VolumeState?

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var submissionTask: Task<Void, Never>?
    private var silenceTask: Task<Void, Never>?
    private var latestTranscript = ""
    private var isListening = false
    private var tapInstalled = false
    private var recordingFile: AVAudioFile?
    private var recordingURL: URL?
    private var recoveryTask: Task<Void, Never>?
    private var recognitionRecoveryAttempts = 0
    private var listeningForApproval = false
    private var listeningForBargeIn = false
    private var listeningForTaskInterruption = false
    private var bargeInSpokenText = ""
    private var bargeInStartTask: Task<Void, Never>?
    private var currentSpokenText = ""
    private var recognitionGeneration = 0
    private var audioBufferCount = 0
    private var detectedUserAudio = false
    private var lastDetectedVoiceAt: Date?
    private var consecutiveVoiceBuffers = 0
    private var audioStartupRecoveryAttempts = 0
    private var continuousGeneration = 0
    private var isContinuousFollowUp = false
    private var activeSystemUtteranceID: ObjectIdentifier?
    private var activeAudioPlayerID: ObjectIdentifier?
    private var audioInputAccessCount = 0

    init(state: AppState, preferences: AssistantPreferences) {
        self.state = state
        self.preferences = preferences
        super.init()
        synthesizer.delegate = self
    }

    /// Regression probe for the text path: cancelling an idle voice service
    /// must not materialize AVAudioEngine.inputNode or touch microphone state.
    func verifyIdleCancellationDoesNotTouchAudioInput() -> Bool {
        let before = audioInputAccessCount
        cancelAll()
        return audioInputAccessCount == before
    }

    private func trackedInputNode() -> AVAudioInputNode {
        audioInputAccessCount &+= 1
        return audioEngine.inputNode
    }

    var permissionSummary: String {
        let speech = SFSpeechRecognizer.authorizationStatus().rawValue
        let microphone = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        let mode = preferences.recognitionEngine == .mimoHybrid ? "MiMo 模式不依赖 Apple 语音授权" : "Apple 识别需要语音授权"
        return "语音识别=\(speech)，麦克风=\(microphone)（\(mode)）"
    }

    func testMiMoSpeech() async throws -> String {
        let data = try await generateMiMoSpeech("你好，我是浮屿。")
        guard data.count > 44 else { throw VoiceOutputError.invalidResponse }
        return "MiMo TTS 已返回可播放音频（\(data.count / 1024) KB）"
    }

    func testMiMoASR() async throws -> String {
        let audio = try await generateMiMoSpeech("你好，我是浮屿。")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FuYu-ASR-Smoke-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try audio.write(to: url, options: .atomic)
        let transcript = try await transcribeWithMiMo(fileURL: url)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw VoiceOutputError.invalidResponse }
        return "MiMo ASR 已识别：\(transcript.prefix(40))"
    }

    func testConsecutiveListeningCycles() async throws -> String {
        cancelAll()
        try await beginRawAudioCaptureForTest()
        guard await waitForAudioBuffers() else {
            cancelAll()
            throw VoicePipelineTestError.noAudioBuffers(cycle: 1)
        }
        let firstCount = audioBufferCount
        stopRecognitionResources()
        cleanupRecording()
        if let outputVolumeRestoreTask { await outputVolumeRestoreTask.value }

        try? await Task.sleep(for: .milliseconds(750))
        try await beginRawAudioCaptureForTest()
        guard await waitForAudioBuffers() else {
            cancelAll()
            throw VoicePipelineTestError.noAudioBuffers(cycle: 2)
        }
        let secondCount = audioBufferCount
        stopRecognitionResources()
        cleanupRecording()
        if let outputVolumeRestoreTask { await outputVolumeRestoreTask.value }
        return "连续两轮均收到真实麦克风音频缓冲（第一轮 \(firstCount)，第二轮 \(secondCount)）"
    }

    private func beginRawAudioCaptureForTest() async throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw VoicePipelineTestError.microphonePermissionMissing
        }
        stopRecognitionResources()
        if let outputVolumeRestoreTask { await outputVolumeRestoreTask.value }
        outputVolumeRestoreTask = nil
        cleanupRecording()
        recognitionGeneration &+= 1
        let generation = recognitionGeneration
        audioBufferCount = 0

        outputVolumeBeforeListening = try? await LocalMacControlService.shared.volumeState()
        let input = trackedInputNode()
        if !input.isVoiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(true)
        }
        if #available(macOS 14.0, *) {
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(
                enableAdvancedDucking: false,
                duckingLevel: .min
            )
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw VoicePipelineTestError.invalidInputFormat
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest = request
        Self.installAudioTap(
            on: input,
            format: format,
            request: request,
            recordingFile: nil,
            service: self,
            generation: generation
        )
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
        isListening = true
    }

    private func waitForAudioBuffers() async -> Bool {
        for _ in 0..<40 {
            if audioBufferCount >= 3 { return true }
            if !isListening { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return audioBufferCount >= 3
    }

    func startListening() async {
        guard !isListening else { return }
        // Only an explicit voice entry point may transition into a permission
        // request. Text messages and passive notifications never get here.
        state.beginVoiceInteraction()
        isContinuousFollowUp = false
        await startListening(continuousFollowUp: false)
    }

    private func startListening(continuousFollowUp: Bool) async {
        guard preferences.voiceInputEnabled else {
            state.resetToIdle(message: "语音识别已关闭")
            return
        }
        isContinuousFollowUp = continuousFollowUp
        audioStartupRecoveryAttempts = 0
        recognitionRecoveryAttempts = 0
        listeningForApproval = false
        await beginListening()
    }

    func startListeningForApproval() async {
        guard state.interactionSource == .voice else { return }
        isContinuousFollowUp = false
        audioStartupRecoveryAttempts = 0
        recognitionRecoveryAttempts = 0
        if isListening {
            stopRecognitionResources()
            cleanupRecording()
        }
        listeningForApproval = true
        await beginListening()
    }

    func startListeningForTaskInterruption() async {
        guard preferences.voiceInterruption, state.voiceSessionActive else { return }
        isContinuousFollowUp = false
        audioStartupRecoveryAttempts = 0
        recognitionRecoveryAttempts = 0
        listeningForApproval = false
        listeningForTaskInterruption = true
        await beginListening(monitoringTaskInterruption: true)
    }

    func stopTaskInterruptionMonitoring() {
        guard listeningForTaskInterruption else { return }
        listeningForTaskInterruption = false
        stopRecognitionResources()
        cleanupRecording()
    }

    private func beginListening(
        preservingSpeechForBargeIn: Bool = false,
        spokenText: String = "",
        monitoringTaskInterruption: Bool = false
    ) async {
        guard !isListening else { return }
        if !preservingSpeechForBargeIn && !monitoringTaskInterruption {
            cancelSpeech()
        }
        submissionTask?.cancel()

        guard await requestPermissionsIfNeeded() else {
            state.presentError("需要麦克风和语音识别权限，请在系统设置中允许。")
            return
        }

        stopRecognitionResources()
        if let outputVolumeRestoreTask { await outputVolumeRestoreTask.value }
        outputVolumeRestoreTask = nil
        cleanupRecording()
        latestTranscript = ""
        voiceActivitySubmissionTask?.cancel()
        voiceActivitySubmissionTask = nil
        audioBufferCount = 0
        detectedUserAudio = false
        lastDetectedVoiceAt = nil
        consecutiveVoiceBuffers = 0
        recognitionGeneration &+= 1
        let generation = recognitionGeneration
        logger.notice("Starting recognition generation \(generation)")

        // A recognizer object that has just been cancelled can remain backed by
        // the previous speech daemon session for a short time. A fresh object
        // per turn prevents the continuous follow-up from inheriting it.
        let useAppleLiveRecognition = SFSpeechRecognizer.authorizationStatus() == .authorized
        let turnRecognizer = useAppleLiveRecognition
            ? SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
            : nil
        if let turnRecognizer {
            speechRecognizer = turnRecognizer
            guard turnRecognizer.isAvailable else {
                state.presentError("语音识别暂时不可用，请稍后再试。")
                return
            }
            if preferences.recognitionEngine == .appleLocal,
               !turnRecognizer.supportsOnDeviceRecognition {
                state.presentError("这台 Mac 当前没有可用的中文本地识别，请安装听写语言或改用在线识别。")
                return
            }
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = preferences.recognitionEngine == .appleLocal
        recognitionRequest = request

        if let turnRecognizer {
            recognitionTask = Self.makeRecognitionTask(
                recognizer: turnRecognizer,
                request: request,
                service: self,
                generation: generation
            )
        } else {
            // MiMo hybrid mode can record and submit audio without Apple's
            // Speech permission. The overlay still reports real voice activity
            // and shows the corrected final text after submission.
            recognitionTask = nil
        }

        outputVolumeBeforeListening = try? await LocalMacControlService.shared.volumeState()
        let input = trackedInputNode()
        // Keep Apple's voice-processing path enabled during normal listening
        // as well as barge-in. Its acoustic echo cancellation substantially
        // reduces speech coming back through the Mac's own speakers.
        if !input.isVoiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(true)
        }
        if #available(macOS 14.0, *) {
            // Echo cancellation stays enabled, but FuYu asks the system for the
            // least possible media ducking so pressing Fn does not crush video volume.
            input.voiceProcessingOtherAudioDuckingConfiguration = .init(
                enableAdvancedDucking: false,
                duckingLevel: .min
            )
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            stopRecognitionResources()
            state.presentError("没有检测到可用的麦克风。")
            return
        }

        prepareRecording(format: format)
        Self.installAudioTap(
            on: input,
            format: format,
            request: request,
            recordingFile: recordingFile,
            service: self,
            generation: generation
        )
        tapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            scheduleAudioStartupWatchdog(
                generation: generation,
                preservingSpeechForBargeIn: preservingSpeechForBargeIn,
                spokenText: spokenText,
                monitoringTaskInterruption: monitoringTaskInterruption
            )
            if preservingSpeechForBargeIn {
                listeningForBargeIn = true
                bargeInSpokenText = spokenText
            } else if monitoringTaskInterruption {
                listeningForTaskInterruption = true
            } else {
                state.beginListening(preservingApproval: listeningForApproval)
                scheduleInitialSilenceTimeout()
            }
        } catch {
            stopRecognitionResources()
            recoverRecognition(after: "无法启动麦克风：\(error.localizedDescription)")
        }
    }

    func stopListeningAndSubmit() {
        guard isListening else { return }
        logger.notice("Submitting recognition generation \(self.recognitionGeneration)")
        silenceTask?.cancel()
        silenceTask = nil
        audioStartupWatchdogTask?.cancel()
        audioStartupWatchdogTask = nil
        voiceActivitySubmissionTask?.cancel()
        voiceActivitySubmissionTask = nil
        audioEngine.stop()
        removeTapIfNeeded()
        recognitionRequest?.endAudio()
        isListening = false
        endVoiceProcessingAndRestoreVolume()

        let captured = latestTranscript
        let capturedRecordingURL = recordingURL
        submissionTask?.cancel()
        submissionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, !Task.isCancelled else { return }
            var finalText = self.latestTranscript.isEmpty ? captured : self.latestTranscript
            self.stopRecognitionResources()
            self.state.beginFinalizingRecognition()
            if self.preferences.recognitionEngine == .mimoHybrid,
               let capturedRecordingURL {
                do {
                    let corrected = try await self.transcribeWithMiMo(fileURL: capturedRecordingURL)
                    if !corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        finalText = Self.preferredTranscript(
                            apple: finalText,
                            mimo: corrected
                        )
                    }
                } catch {
                    // Apple live recognition remains the offline/failure fallback.
                }
            }
            self.cleanupRecording()
            guard !finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.state.resetToIdle()
                return
            }
            self.state.presentFinalRecognition(finalText)
            // Keep the exact sentence FuYu will use on screen long enough for
            // the user to verify it before the assistant starts thinking.
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self.listeningForTaskInterruption = false
            self.onTranscriptReady?(finalText)
        }
    }

    /// MiMo is a correction candidate, not an unconditional replacement.
    /// When both engines heard substantially different words, preserving the
    /// live Apple transcript is safer and keeps the text the user already saw.
    nonisolated static func preferredTranscript(apple: String, mimo: String) -> String {
        let appleText = apple.trimmingCharacters(in: .whitespacesAndNewlines)
        let mimoText = mimo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mimoText.isEmpty else { return appleText }
        guard !appleText.isEmpty else { return mimoText }

        func symbols(_ value: String) -> Set<Character> {
            Set(value.lowercased().filter { $0.isLetter || $0.isNumber })
        }
        let appleSymbols = symbols(appleText)
        let mimoSymbols = symbols(mimoText)
        let union = appleSymbols.union(mimoSymbols)
        let agreement = union.isEmpty
            ? 1.0
            : Double(appleSymbols.intersection(mimoSymbols).count) / Double(union.count)

        // Similar candidates usually mean MiMo repaired punctuation or同音字。
        // Low-overlap rewrites remain uncertain and must not silently win.
        return agreement >= 0.45 ? mimoText : appleText
    }

    private func handleApprovalTranscript(_ transcript: String) -> Bool {
        guard listeningForApproval, let decision = Self.approvalDecision(for: transcript) else { return false }
        stopRecognitionResources()
        cleanupRecording()
        listeningForApproval = false
        state.approvalIsListening = false
        onApprovalDecision?(decision)
        return true
    }

    static func approvalDecision(for transcript: String) -> Bool? {
        let compact = transcript.filter { $0.isLetter || $0.isNumber }
        let deny = ["取消执行", "不要执行", "拒绝执行", "不允许执行", "取消", "算了"]
        if deny.contains(where: compact.contains) { return false }
        let approve = ["允许执行", "确认执行", "同意执行", "可以执行", "执行吧"]
        if approve.contains(where: compact.contains) { return true }
        return nil
    }

    private func scheduleBargeInMonitoring(for spokenText: String) {
        bargeInStartTask?.cancel()
        guard preferences.voiceInterruption, !spokenText.isEmpty else { return }
        bargeInStartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard let self, !Task.isCancelled else { return }
            await self.beginListening(preservingSpeechForBargeIn: true, spokenText: spokenText)
        }
    }

    private func handleBargeInTranscript(_ transcript: String) -> Bool {
        guard listeningForBargeIn else { return false }
        guard let interruption = Self.userInterruptionText(
            transcript: transcript,
            spokenText: bargeInSpokenText
        ) else {
            return true
        }

        listeningForBargeIn = false
        bargeInSpokenText = ""
        cancelSpeech(preservingBargeInRecognition: true)
        latestTranscript = interruption
        state.beginListening()
        state.updateTranscript(interruption)
        scheduleAutomaticSubmission(for: interruption)
        return true
    }

    static func userInterruptionText(transcript: String, spokenText: String) -> String? {
        let heard = transcript.lowercased().filter { $0.isLetter || $0.isNumber }
        let spoken = spokenText.lowercased().filter { $0.isLetter || $0.isNumber }
        guard heard.count >= 2 else { return nil }
        if spoken.contains(heard) { return nil }

        let heardCharacters = Array(heard)
        if heardCharacters.count >= 6 {
            for prefixLength in stride(from: heardCharacters.count - 2, through: 4, by: -1) {
                let prefix = String(heardCharacters.prefix(prefixLength))
                guard spoken.contains(prefix) else { continue }
                let remainder = String(heardCharacters.dropFirst(prefixLength))
                return remainder.count >= 2 ? remainder : nil
            }
        }
        return heard
    }

    func speak(_ text: String, displayText: String? = nil) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        cancelSpeech()
        currentSpokenText = cleaned
        state.beginSpeaking(displayText ?? cleaned)
        switch preferences.speechEngine {
        case .system:
            speakWithSystem(cleaned)
        case .mimo, .openAI, .localClone:
            let engine = preferences.speechEngine
            speechTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let data = try await self.generateCloudSpeech(cleaned, engine: engine)
                    try Task.checkCancellation()
                    try self.play(data)
                } catch is CancellationError {
                    return
                } catch {
                    if self.preferences.speechFallback {
                        self.speakWithSystem(cleaned)
                    } else {
                        self.state.presentError("语音生成失败：\(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func cancelAll() {
        submissionTask?.cancel()
        submissionTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        continuousTask?.cancel()
        continuousTask = nil
        continuousGeneration &+= 1
        audioStartupWatchdogTask?.cancel()
        audioStartupWatchdogTask = nil
        voiceActivitySubmissionTask?.cancel()
        voiceActivitySubmissionTask = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        bargeInStartTask?.cancel()
        bargeInStartTask = nil
        recognitionRecoveryAttempts = 0
        listeningForApproval = false
        listeningForBargeIn = false
        listeningForTaskInterruption = false
        bargeInSpokenText = ""
        stopRecognitionResources()
        cleanupRecording()
        cancelSpeech()
    }

    func continueAfterSilentReply() {
        scheduleContinuousListening()
    }

    private func cancelSpeech(preservingBargeInRecognition: Bool = false) {
        bargeInStartTask?.cancel()
        bargeInStartTask = nil
        if listeningForBargeIn && !preservingBargeInRecognition {
            listeningForBargeIn = false
            bargeInSpokenText = ""
            stopRecognitionResources()
            cleanupRecording()
        }
        speechTask?.cancel()
        speechTask = nil
        if audioPlayer?.isPlaying == true { audioPlayer?.stop() }
        audioPlayer = nil
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activeSystemUtteranceID = nil
        activeAudioPlayerID = nil
    }

    private func speakWithSystem(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if !preferences.systemVoiceIdentifier.isEmpty,
           let selected = AVSpeechSynthesisVoice(identifier: preferences.systemVoiceIdentifier) {
            utterance.voice = selected
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        }
        utterance.rate = Float(preferences.speechRate)
        utterance.pitchMultiplier = 1.02
        activeSystemUtteranceID = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
        scheduleBargeInMonitoring(for: text)
    }

    private func generateCloudSpeech(_ text: String, engine: SpeechEngine) async throws -> Data {
        switch engine {
        case .system:
            throw VoiceOutputError.invalidConfiguration
        case .mimo:
            return try await generateMiMoSpeech(text)
        case .openAI:
            return try await generateOpenAISpeech(text)
        case .localClone:
            return try await generateLocalSpeech(text)
        }
    }

    private func generateMiMoSpeech(_ text: String) async throws -> Data {
        guard let key = KeychainStore.password(service: "codex-mimo-api-key"), !key.isEmpty else {
            throw VoiceOutputError.missingKey("MiMo")
        }
        let messages: [[String: String]] = [
            ["role": "user", "content": preferences.effectiveSpeechInstructions],
            ["role": "assistant", "content": text]
        ]
        let body: [String: Any] = [
            "model": "mimo-v2.5-tts",
            "messages": messages,
            "audio": ["format": "wav", "voice": preferences.mimoVoice.rawValue]
        ]
        let data = try await requestAudio(
            url: preferences.mimoEndpoint,
            key: key,
            body: body,
            extraHeaders: ["api-key": key]
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = object?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let audio = message?["audio"] as? [String: Any]
        guard let encoded = audio?["data"] as? String,
              let decoded = Data(base64Encoded: encoded) else {
            throw VoiceOutputError.invalidResponse
        }
        return decoded
    }

    private func transcribeWithMiMo(fileURL: URL) async throws -> String {
        guard let key = KeychainStore.password(service: "codex-mimo-api-key"), !key.isEmpty else {
            throw VoiceOutputError.missingKey("MiMo")
        }
        let audioData = try Data(contentsOf: fileURL)
        guard !audioData.isEmpty else { throw VoiceOutputError.invalidResponse }
        let dataURI = "data:audio/wav;base64,\(audioData.base64EncodedString())"
        let body: [String: Any] = [
            "model": "mimo-v2.5-asr",
            "messages": [[
                "role": "user",
                "content": [[
                    "type": "input_audio",
                    "input_audio": ["data": dataURI]
                ]]
            ]],
            "asr_options": ["language": "auto"]
        ]
        let data = try await requestAudio(
            url: preferences.mimoEndpoint,
            key: key,
            body: body,
            extraHeaders: ["api-key": key]
        )
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = object?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw VoiceOutputError.invalidResponse
        }
        return content
    }

    private func generateOpenAISpeech(_ text: String) async throws -> Data {
        guard let key = preferences.ttsAPIKey, !key.isEmpty else {
            throw VoiceOutputError.missingKey("OpenAI")
        }
        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "voice": preferences.openAIVoice.rawValue,
            "input": text,
            "instructions": preferences.effectiveSpeechInstructions,
            "response_format": "wav"
        ]
        return try await requestAudio(
            url: "https://api.openai.com/v1/audio/speech",
            key: key,
            body: body
        )
    }

    private func generateLocalSpeech(_ text: String) async throws -> Data {
        guard let url = URL(string: preferences.localCloneEndpoint),
              url.scheme == "http" || url.scheme == "https" else {
            throw VoiceOutputError.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "text": text,
            "format": "wav",
            "instructions": preferences.effectiveSpeechInstructions
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VoiceOutputError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    private func requestAudio(
        url: String,
        key: String,
        body: [String: Any],
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard let endpoint = URL(string: url) else { throw VoiceOutputError.invalidConfiguration }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        extraHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw VoiceOutputError.requestFailed((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    private func play(_ data: Data) throws {
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        player.prepareToPlay()
        guard player.play() else { throw VoiceOutputError.playbackFailed }
        audioPlayer = player
        activeAudioPlayerID = ObjectIdentifier(player)
        scheduleBargeInMonitoring(for: currentSpokenText)
    }

    private func requestPermissionsIfNeeded() async -> Bool {
        let microphoneAllowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAllowed = true
        case .notDetermined:
            guard state.interactionSource == .voice else { return false }
            microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneAllowed = false
        }
        guard microphoneAllowed else { return false }

        // MiMo performs the final transcription from the recorded audio and
        // therefore does not need Apple's separate Speech authorization.
        // If Speech is already allowed, it is used only for live partial text.
        if preferences.recognitionEngine == .mimoHybrid { return true }

        let speechAllowed: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechAllowed = true
        case .notDetermined:
            guard state.interactionSource == .voice else { return false }
            speechAllowed = await Self.requestSpeechAuthorization()
        default:
            speechAllowed = false
        }

        return speechAllowed && microphoneAllowed
    }

    private func scheduleOutputVolumeRestore() {
        guard let original = outputVolumeBeforeListening else { return }
        outputVolumeBeforeListening = nil
        outputVolumeRestoreTask?.cancel()
        guard !original.muted else { return }
        outputVolumeRestoreTask = Task { @MainActor in
            // Let macOS duck media while listening, then restore the exact
            // pre-listening level after Fn is released / capture ends.
            for delay in [0, 80, 180] {
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                guard !Task.isCancelled else { return }
                guard let observed = try? await LocalMacControlService.shared.volumeState(),
                      Self.shouldRestoreOutputVolumeAfterListening(
                        original: original.level,
                        observed: observed.level
                      ) else { continue }
                _ = try? await LocalMacControlService.shared.adjustVolume(.set(original.level))
                return
            }
        }
    }

    static func shouldRestoreOutputVolumeAfterListening(original: Int, observed: Int) -> Bool {
        original > 0 && observed >= 0 && observed <= original - 2
    }

    private func endVoiceProcessingAndRestoreVolume() {
        let input = trackedInputNode()
        if input.isVoiceProcessingEnabled {
            try? input.setVoiceProcessingEnabled(false)
        }
        scheduleOutputVolumeRestore()
    }

    /// Speech invokes its authorization callback on an arbitrary queue. Keeping
    /// this bridge nonisolated prevents Swift 6 from treating that callback as
    /// main-actor code and trapping before the continuation can resume.
    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private nonisolated static func makeRecognitionTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        service: VoiceService,
        generation: Int
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { [weak service] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                guard let service else { return }
                guard generation == service.recognitionGeneration else {
                    service.logger.debug("Ignored stale recognition generation \(generation); active is \(service.recognitionGeneration)")
                    return
                }
                if let transcript {
                    if service.handleBargeInTranscript(transcript) { return }
                    service.latestTranscript = transcript
                    service.voiceActivitySubmissionTask?.cancel()
                    service.voiceActivitySubmissionTask = nil
                    service.state.updateTranscript(service.latestTranscript, isFinal: isFinal)
                    if service.handleApprovalTranscript(transcript) { return }
                    service.scheduleAutomaticSubmission(for: transcript)
                }
                if let errorDescription, service.isListening {
                    service.handleRecognitionInterruption(errorDescription)
                }
            }
        }
    }

    private nonisolated static func installAudioTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat,
        request: SFSpeechAudioBufferRecognitionRequest,
        recordingFile: AVAudioFile?,
        service: VoiceService,
        generation: Int
    ) {
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request, recordingFile, weak service] buffer, _ in
            request?.append(buffer)
            try? recordingFile?.write(from: buffer)
            guard let channel = buffer.floatChannelData?.pointee else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            var sum: Float = 0
            for index in 0..<frameCount {
                let sample = channel[index]
                sum += sample * sample
            }
            let rms = sqrt(sum / Float(frameCount))
            let normalized = min(max((Double(rms) - 0.008) * 12.5, 0), 1)
            Task { @MainActor [weak service] in
                guard let service,
                      service.recognitionGeneration == generation else { return }
                service.audioBufferCount += 1
                service.state.audioLevel = service.state.audioLevel * 0.58 + normalized * 0.42
                if normalized >= 0.08 {
                    service.consecutiveVoiceBuffers += 1
                    service.lastDetectedVoiceAt = Date()
                    if service.consecutiveVoiceBuffers >= 6, !service.detectedUserAudio {
                        service.detectedUserAudio = true
                        if service.listeningForBargeIn {
                            // Voice processing has suppressed the assistant's
                            // own playback and sustained near-end speech remains:
                            // stop talking immediately, then reuse this live
                            // capture as the user's next turn.
                            service.listeningForBargeIn = false
                            service.bargeInSpokenText = ""
                            service.cancelSpeech(preservingBargeInRecognition: true)
                            service.state.beginListening()
                            service.state.noteDetectedVoiceActivity()
                            service.scheduleVoiceActivitySubmissionFallback(generation: generation)
                        } else if !service.listeningForTaskInterruption {
                            service.state.noteDetectedVoiceActivity()
                            service.scheduleVoiceActivitySubmissionFallback(generation: generation)
                        }
                    }
                } else if normalized < 0.04 {
                    service.consecutiveVoiceBuffers = 0
                }
            }
        }
    }

    private func scheduleAudioStartupWatchdog(
        generation: Int,
        preservingSpeechForBargeIn: Bool,
        spokenText: String,
        monitoringTaskInterruption: Bool
    ) {
        audioStartupWatchdogTask?.cancel()
        audioStartupWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self,
                  !Task.isCancelled,
                  self.isListening,
                  self.recognitionGeneration == generation else { return }
            if self.audioBufferCount == 0, self.audioStartupRecoveryAttempts >= 1 {
                self.audioStartupWatchdogTask = nil
                self.stopRecognitionResources()
                self.cleanupRecording()
                self.state.presentError("麦克风没有收到音频，已停止本轮识别。请再次按 Fn 重试。")
                return
            }
            guard Self.shouldRestartAudioCapture(
                bufferCount: self.audioBufferCount,
                recoveryAttempts: self.audioStartupRecoveryAttempts
            ) else { return }

            self.audioStartupRecoveryAttempts += 1
            self.logger.error("Recognition generation \(generation) received no audio buffers; rebuilding capture")
            self.audioStartupWatchdogTask = nil
            self.stopRecognitionResources()
            self.cleanupRecording()
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await self.beginListening(
                preservingSpeechForBargeIn: preservingSpeechForBargeIn,
                spokenText: spokenText,
                monitoringTaskInterruption: monitoringTaskInterruption
            )
        }
    }

    static func shouldRestartAudioCapture(bufferCount: Int, recoveryAttempts: Int) -> Bool {
        bufferCount == 0 && recoveryAttempts < 1
    }

    private func scheduleVoiceActivitySubmissionFallback(generation: Int) {
        guard preferences.recognitionEngine == .mimoHybrid,
              voiceActivitySubmissionTask == nil else { return }
        voiceActivitySubmissionTask = Task { @MainActor [weak self] in
            while let self,
                  !Task.isCancelled,
                  self.isListening,
                  self.recognitionGeneration == generation,
                  self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try? await Task.sleep(for: .milliseconds(250))
                guard let lastVoice = self.lastDetectedVoiceAt else { continue }
                if Date().timeIntervalSince(lastVoice) >= 1.2 {
                    self.voiceActivitySubmissionTask = nil
                    self.stopListeningAndSubmit()
                    return
                }
            }
            self?.voiceActivitySubmissionTask = nil
        }
    }

    private func stopRecognitionResources() {
        // AVAudioEngine.inputNode is lazy. Merely touching it initializes the
        // microphone/CoreAudio pipeline, which must never happen when a text
        // interaction calls cancelAll() without an active voice session.
        let hadActiveCapture = isListening
            || tapInstalled
            || recognitionRequest != nil
            || recognitionTask != nil
            || recordingFile != nil

        audioStartupWatchdogTask?.cancel()
        audioStartupWatchdogTask = nil
        voiceActivitySubmissionTask?.cancel()
        voiceActivitySubmissionTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        if hadActiveCapture {
            if audioEngine.isRunning {
                audioEngine.stop()
            }
            removeTapIfNeeded()
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognitionGeneration &+= 1
        recordingFile = nil
        isListening = false
        state.audioLevel = 0
        if hadActiveCapture {
            audioEngine.reset()
            endVoiceProcessingAndRestoreVolume()
        } else {
            logger.debug("Skipped audio teardown because no capture session was active")
        }
    }

    private func handleRecognitionInterruption(_ description: String) {
        if listeningForBargeIn {
            listeningForBargeIn = false
            bargeInSpokenText = ""
            stopRecognitionResources()
            cleanupRecording()
            return
        }
        if listeningForTaskInterruption {
            stopRecognitionResources()
            cleanupRecording()
            recoveryTask?.cancel()
            recoveryTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard let self, self.listeningForTaskInterruption else { return }
                await self.beginListening(monitoringTaskInterruption: true)
            }
            return
        }
        let captured = latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopRecognitionResources()
        cleanupRecording()
        if !captured.isEmpty {
            state.updateTranscript(captured)
            onTranscriptReady?(captured)
            return
        }
        recoverRecognition(after: "语音识别中断：\(description)")
    }

    private func recoverRecognition(after message: String) {
        guard Self.shouldAttemptRecognitionRecovery(
            attempts: recognitionRecoveryAttempts,
            hasCapturedText: !latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ) else {
            recoveryTask?.cancel()
            recoveryTask = nil
            state.presentError("\(message)；自动恢复失败，请再次唤醒。")
            return
        }
        recognitionRecoveryAttempts += 1
        state.beginListening()
        state.updateTranscript("语音连接恢复中…")
        recoveryTask?.cancel()
        let delay = 420 * recognitionRecoveryAttempts
        recoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.audioEngine.reset()
            await self.beginListening()
        }
    }

    static func shouldAttemptRecognitionRecovery(attempts: Int, hasCapturedText: Bool) -> Bool {
        !hasCapturedText && attempts < maxRecognitionRecoveryAttempts
    }

    private func prepareRecording(format: AVAudioFormat) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FuYu-ASR-\(UUID().uuidString).wav")
        do {
            recordingFile = try AVAudioFile(forWriting: url, settings: format.settings)
            recordingURL = url
        } catch {
            recordingFile = nil
            recordingURL = nil
        }
    }

    private func cleanupRecording() {
        recordingFile = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        trackedInputNode().removeTap(onBus: 0)
        tapInstalled = false
    }

    private func scheduleAutomaticSubmission(for transcript: String) {
        silenceTask?.cancel()
        guard preferences.autoSubmit else { return }
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        let milliseconds = Self.automaticSubmissionDelayMilliseconds(
            for: value,
            baseSeconds: Self.automaticSubmissionBaseSeconds(
                configured: preferences.endPauseSeconds,
                continuousFollowUp: isContinuousFollowUp
            )
        )

        let generation = recognitionGeneration
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(milliseconds))
            guard let self,
                  !Task.isCancelled,
                  self.isListening,
                  self.recognitionGeneration == generation,
                  self.latestTranscript == transcript else { return }
            self.stopListeningAndSubmit()
        }
    }

    static func automaticSubmissionDelayMilliseconds(for value: String, baseSeconds: Double) -> Int {
        let unfinishedEndings = ["然后", "还有", "因为", "但是", "所以", "就是", "比如", "嗯", "呃"]
        let explicitEndings = [
            "就这样", "就这样吧", "去执行吧", "执行吧", "开始执行吧", "开始吧", "就这么办", "按这个做", "照这个做",
            "好了执行吧", "可以了", "好了",
            "停一下", "等一下", "先别执行", "暂停任务", "取消任务",
            "结束对话", "关闭对话", "停止对话", "退出对话", "结束聊天", "关闭聊天",
            "结束语音", "关闭语音", "退出语音", "结束通话", "关闭通话", "挂断", "挂断电话"
        ]
        let sentenceEndings = ["。", "！", "？", ".", "!", "?"]
        let base = Int(baseSeconds * 1_000)
        let compact = value.filter { $0.isLetter || $0.isNumber }
        if explicitEndings.contains(where: compact.hasSuffix) { return 320 }
        if unfinishedEndings.contains(where: value.hasSuffix) { return base + 1_300 }
        if sentenceEndings.contains(where: value.hasSuffix) { return max(1_200, base - 250) }
        return value.count <= 8 ? base + 350 : base
    }

    static func automaticSubmissionBaseSeconds(configured: Double, continuousFollowUp: Bool) -> Double {
        continuousFollowUp ? configured + 1.2 : configured
    }

    private func scheduleInitialSilenceTimeout() {
        silenceTask?.cancel()
        let timeout = preferences.continuousConversation
            ? max(preferences.silenceTimeout, 20)
            : preferences.silenceTimeout
        let generation = recognitionGeneration
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self,
                  !Task.isCancelled,
                  self.isListening,
                  self.recognitionGeneration == generation,
                  self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

            // If Apple returned no partial text but the microphone did hear a
            // real voice, keep waiting until the speaker has paused and submit
            // the recording to MiMo instead of deleting the whole turn.
            while self.detectedUserAudio,
                  let lastVoice = self.lastDetectedVoiceAt,
                  Date().timeIntervalSince(lastVoice) < 1.2 {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled,
                      self.isListening,
                      self.recognitionGeneration == generation,
                      self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            }
            if self.detectedUserAudio,
               self.preferences.recognitionEngine == .mimoHybrid {
                self.stopListeningAndSubmit()
                return
            }
            self.stopRecognitionResources()
            self.cleanupRecording()
            if self.listeningForApproval, self.state.showPermission {
                self.state.approvalIsListening = false
                self.recoveryTask?.cancel()
                self.recoveryTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(350))
                    guard let self, self.state.showPermission else { return }
                    await self.startListeningForApproval()
                }
            } else if self.preferences.continuousConversation,
                      self.state.voiceSessionActive {
                self.state.beginListening()
                self.state.updateTranscript("我还在，随时可以说…")
                self.recoveryTask?.cancel()
                self.recoveryTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self, self.state.voiceSessionActive else { return }
                    await self.beginListening()
                }
            } else {
                self.state.resetToIdle()
            }
        }
    }

    private func scheduleContinuousListening() {
        continuousTask?.cancel()
        guard preferences.continuousConversation else { return }
        continuousGeneration &+= 1
        let generation = continuousGeneration
        logger.notice("Keeping overlay open for continuous conversation")
        continuousTask = Task { @MainActor [weak self] in
            // Give CoreAudio time to fully tear down the barge-in capture
            // before rebuilding the normal follow-up microphone session.
            try? await Task.sleep(for: .milliseconds(750))
            guard let self,
                  !Task.isCancelled,
                  self.continuousGeneration == generation else { return }
            await self.startListening(continuousFollowUp: true)
        }
    }

    private func finishSpeakingNormally() {
        guard state.phase == .speaking else { return }
        bargeInStartTask?.cancel()
        bargeInStartTask = nil
        if listeningForBargeIn {
            listeningForBargeIn = false
            bargeInSpokenText = ""
            stopRecognitionResources()
            cleanupRecording()
        }
        state.finishSpeaking(keepExpanded: preferences.continuousConversation)
        scheduleContinuousListening()
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceID = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, self.activeSystemUtteranceID == utteranceID else { return }
            self.activeSystemUtteranceID = nil
            self.finishSpeakingNormally()
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let playerID = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, self.activeAudioPlayerID == playerID else { return }
            self.activeAudioPlayerID = nil
            self.audioPlayer = nil
            self.finishSpeakingNormally()
        }
    }
}

private enum VoiceOutputError: LocalizedError {
    case missingKey(String), invalidConfiguration, invalidResponse, requestFailed(Int), playbackFailed
    var errorDescription: String? {
        switch self {
        case let .missingKey(provider): "没有找到 \(provider) 语音密钥"
        case .invalidConfiguration: "语音服务配置无效"
        case .invalidResponse: "语音服务没有返回可播放的声音"
        case let .requestFailed(code): "语音服务请求失败（\(code)）"
        case .playbackFailed: "无法播放生成的声音"
        }
    }
}

private enum VoicePipelineTestError: LocalizedError {
    case noAudioBuffers(cycle: Int)
    case microphonePermissionMissing
    case invalidInputFormat

    var errorDescription: String? {
        switch self {
        case let .noAudioBuffers(cycle):
            "第 \(cycle) 轮麦克风没有返回音频缓冲。"
        case .microphonePermissionMissing:
            "麦克风权限尚未允许。"
        case .invalidInputFormat:
            "麦克风输入格式无效。"
        }
    }
}
