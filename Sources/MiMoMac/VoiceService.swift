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
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: "ai.fuyu.desktop", category: "voice")
    private var audioPlayer: AVAudioPlayer?
    private var speechTask: Task<Void, Never>?
    private var continuousTask: Task<Void, Never>?
    private var outputVolumeRestoreTask: Task<Void, Never>?

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
    private var continuousGeneration = 0
    private var isContinuousFollowUp = false
    private var activeSystemUtteranceID: ObjectIdentifier?
    private var activeAudioPlayerID: ObjectIdentifier?

    init(state: AppState, preferences: AssistantPreferences) {
        self.state = state
        self.preferences = preferences
        super.init()
        synthesizer.delegate = self
    }

    var permissionSummary: String {
        "语音识别=\(SFSpeechRecognizer.authorizationStatus().rawValue)，麦克风=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)"
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

    func startListening() async {
        guard !isListening else { return }
        isContinuousFollowUp = false
        await startListening(continuousFollowUp: false)
    }

    private func startListening(continuousFollowUp: Bool) async {
        guard preferences.voiceInputEnabled else {
            state.resetToIdle(message: "语音识别已关闭")
            return
        }
        isContinuousFollowUp = continuousFollowUp
        recognitionRecoveryAttempts = 0
        listeningForApproval = false
        await beginListening()
    }

    func startListeningForApproval() async {
        isContinuousFollowUp = false
        recognitionRecoveryAttempts = 0
        if isListening {
            stopRecognitionResources()
            cleanupRecording()
        }
        listeningForApproval = true
        await beginListening()
    }

    func startListeningForTaskInterruption() async {
        guard preferences.voiceInterruption else { return }
        isContinuousFollowUp = false
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
        cleanupRecording()
        latestTranscript = ""
        recognitionGeneration &+= 1
        let generation = recognitionGeneration
        logger.notice("Starting recognition generation \(generation)")

        guard let speechRecognizer, speechRecognizer.isAvailable else {
            state.presentError("语音识别暂时不可用，请稍后再试。")
            return
        }
        if preferences.recognitionEngine == .appleLocal,
           !speechRecognizer.supportsOnDeviceRecognition {
            state.presentError("这台 Mac 当前没有可用的中文本地识别，请安装听写语言或改用在线识别。")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.requiresOnDeviceRecognition = preferences.recognitionEngine == .appleLocal
        recognitionRequest = request

        recognitionTask = Self.makeRecognitionTask(
            recognizer: speechRecognizer,
            request: request,
            service: self,
            generation: generation
        )

        let originalOutputState = try? await LocalMacControlService.shared.volumeState()
        let input = audioEngine.inputNode
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
            service: self
        )
        tapInstalled = true

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            protectOutputVolume(originalOutputState, generation: generation)
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
        audioEngine.stop()
        removeTapIfNeeded()
        recognitionRequest?.endAudio()
        isListening = false

        let captured = latestTranscript
        let capturedRecordingURL = recordingURL
        submissionTask?.cancel()
        submissionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(320))
            guard let self, !Task.isCancelled else { return }
            var finalText = self.latestTranscript.isEmpty ? captured : self.latestTranscript
            self.stopRecognitionResources()
            if self.preferences.recognitionEngine == .mimoHybrid,
               let capturedRecordingURL {
                do {
                    let corrected = try await self.transcribeWithMiMo(fileURL: capturedRecordingURL)
                    if !corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        finalText = corrected
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
            self.listeningForTaskInterruption = false
            self.onTranscriptReady?(finalText)
        }
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
        outputVolumeRestoreTask?.cancel()
        outputVolumeRestoreTask = nil
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
            ["role": "user", "content": String(preferences.speechInstructions.prefix(500))],
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
            "instructions": String(preferences.speechInstructions.prefix(500)),
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
            "instructions": String(preferences.speechInstructions.prefix(500))
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
        let speechAllowed: Bool
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechAllowed = true
        case .notDetermined:
            speechAllowed = await Self.requestSpeechAuthorization()
        default:
            speechAllowed = false
        }

        let microphoneAllowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneAllowed = true
        case .notDetermined:
            microphoneAllowed = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            microphoneAllowed = false
        }

        return speechAllowed && microphoneAllowed
    }

    private func protectOutputVolume(
        _ original: LocalMacControlService.VolumeState?,
        generation: Int
    ) {
        outputVolumeRestoreTask?.cancel()
        guard let original, !original.muted else { return }
        outputVolumeRestoreTask = Task { @MainActor [weak self] in
            // Voice Processing can asynchronously halve the output slider on
            // some Macs. Only correct changes during microphone startup, so a
            // later manual volume adjustment is never overridden.
            for delay in [0, 80, 180, 360] {
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                guard let self,
                      !Task.isCancelled,
                      self.isListening,
                      self.recognitionGeneration == generation else { return }
                guard let observed = try? await LocalMacControlService.shared.volumeState(),
                      Self.shouldRestoreOutputVolume(
                        original: original.level,
                        observed: observed.level
                      ) else { continue }
                _ = try? await LocalMacControlService.shared.adjustVolume(.set(original.level))
            }
        }
    }

    static func shouldRestoreOutputVolume(original: Int, observed: Int) -> Bool {
        original > 0 && observed >= 0 && observed <= original - 2
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
                    service.state.updateTranscript(service.latestTranscript)
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
        service: VoiceService
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
                guard let service else { return }
                service.state.audioLevel = service.state.audioLevel * 0.58 + normalized * 0.42
            }
        }
    }

    private func stopRecognitionResources() {
        outputVolumeRestoreTask?.cancel()
        outputVolumeRestoreTask = nil
        silenceTask?.cancel()
        silenceTask = nil
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        removeTapIfNeeded()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        recognitionGeneration &+= 1
        recordingFile = nil
        isListening = false
        state.audioLevel = 0
        audioEngine.reset()
        if audioEngine.inputNode.isVoiceProcessingEnabled {
            try? audioEngine.inputNode.setVoiceProcessingEnabled(false)
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
        audioEngine.inputNode.removeTap(onBus: 0)
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
            "停一下", "等一下", "先别执行", "暂停任务", "取消任务"
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
        let timeout = preferences.silenceTimeout
        let generation = recognitionGeneration
        silenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self,
                  !Task.isCancelled,
                  self.isListening,
                  self.recognitionGeneration == generation,
                  self.latestTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
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
            try? await Task.sleep(for: .milliseconds(550))
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
