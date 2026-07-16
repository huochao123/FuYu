import AppKit
import Combine
import SwiftUI

@main
enum MiMoMacApp {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            exit(SelfTestRunner.run() ? 0 : 1)
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let state = AppState(historyURL: CommandLine.arguments.contains("--approval-demo")
        ? FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-approval-demo-history.json")
        : nil)
    private let preferences = AssistantPreferences()
    private let thermalMonitor = ThermalProcessMonitor()
    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    private var assistantStatusItem: NSMenuItem?
    private var shortcutStatusItem: NSMenuItem?
    private var shortcutMonitor: GlobalShortcutMonitor?
    private var voiceService: VoiceService?
    private var runtime: AssistantRuntime?
    private var settingsWindowController: SettingsWindowController?
    private var mainWindowController: MainWindowController?
    private var feishuBridge: FeishuBridgeService?
    private var remoteReplyObservers: [String: AnyCancellable] = [:]
    private var pendingDeepLink: URL?
    private var voiceActivity: NSUserActivity?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        panelController = FloatingPanelController(
            state: state,
            preferences: preferences,
            showSettings: { [weak self] in self?.showSettings() },
            quitApp: { [weak self] in self?.quit() }
        )
        panelController?.show()

        let voiceService = VoiceService(state: state, preferences: preferences)
        let runtime = AssistantRuntime(
            state: state,
            voice: voiceService,
            preferences: preferences
        )
        self.voiceService = voiceService
        self.runtime = runtime
        let feishuBridge = FeishuBridgeService(state: state)
        feishuBridge.onMessage = { [weak self] message in self?.handleFeishuMessage(message) }
        self.feishuBridge = feishuBridge
        mainWindowController = MainWindowController(
            state: state,
            preferences: preferences,
            thermalMonitor: thermalMonitor,
            startVoice: { [weak self] in
                guard let self else { return }
                if self.state.phase == .listening {
                    self.state.cancel()
                } else {
                    self.state.requestVoice()
                }
            },
            sendText: { [weak self] text in self?.runtime?.handleTextInput(text) },
            showSettings: { [weak self] in self?.showSettings() }
        )
        state.modelLabel = preferences.modelProvider.badge
        preferences.$modelProvider
            .map(\.badge)
            .sink { [weak state] badge in state?.modelLabel = badge }
            .store(in: &cancellables)
        preferences.$showDockIcon
            .removeDuplicates()
            .sink { visible in
                NSApplication.shared.setActivationPolicy(visible ? .regular : .accessory)
            }
            .store(in: &cancellables)
        Publishers.CombineLatest(
            preferences.$feishuEnabled.removeDuplicates(),
            preferences.$feishuAppID.removeDuplicates()
        )
        .sink { [weak self] enabled, appID in
            guard let self else { return }
            self.feishuBridge?.configure(
                enabled: enabled,
                appID: appID.trimmingCharacters(in: .whitespacesAndNewlines),
                appSecret: self.preferences.feishuAppSecret
            )
        }
        .store(in: &cancellables)

        shortcutMonitor = GlobalShortcutMonitor(
            shortcut: preferences.pushToTalkShortcut,
            onPress: { [weak self] in
                Task { @MainActor in
                    await self?.voiceService?.startListening()
                }
            },
            onRelease: { [weak self] in
                self?.voiceService?.stopListeningAndSubmit()
            }
        )
        shortcutMonitor?.start()
        preferences.$pushToTalkShortcut
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.shortcutMonitor?.configure(shortcut)
                self?.shortcutStatusItem?.title = "语音快捷键：\(shortcut.title)"
            }
            .store(in: &cancellables)
        installStatusItem()
        state.$phase
            .removeDuplicates()
            .sink { [weak self] phase in self?.updateStatusItem(for: phase) }
            .store(in: &cancellables)
        donateStartVoiceActivity()
        thermalMonitor.start()

        if let pendingDeepLink {
            self.pendingDeepLink = nil
            handleDeepLink(pendingDeepLink)
        }

        if CommandLine.arguments.contains("--demo") {
            panelController?.showExpanded()
            state.runDemo()
        } else if CommandLine.arguments.contains("--task-demo") {
            panelController?.showExpanded()
            state.beginExecution(title: "正在整理下载文件夹")
            state.updateExecution(progress: 0.58, step: 1)
        } else if CommandLine.arguments.contains("--approval-demo") {
            state.presentApproval(
                title: "创建腾讯会议",
                detail: "下午 3 点到 4 点 · 单次会议 · 使用腾讯会议 MCP"
            )
            state.beginListening(preservingApproval: true)
            panelController?.showExpanded()
        } else if CommandLine.arguments.contains("--settings") || CommandLine.arguments.contains("--chat-demo") {
            if CommandLine.arguments.contains("--chat-demo") {
                state.beginThinking(userText: "刚才的整理任务完成了吗？")
                state.recordActionStatus("Hermes 已接收任务：整理下载文件夹")
                state.recordActionStatus("执行成功：已按文件类型完成整理")
                state.recordAssistantMessage("已经完成，Hermes 返回的结果是文件已按类型整理。")
                state.resetToIdle()
            }
            showSettings()
        } else if CommandLine.arguments.contains("--response-demo") {
            state.presentSilentReply("这是一条不会整段朗读的长回复。完整内容会保留在阅读卡中，你可以滚动查看、选择文字，或者直接继续追问。")
            panelController?.showExpanded()
        } else if CommandLine.arguments.contains("--permission-status") {
            print(voiceService.permissionSummary)
            shortcutMonitor?.stop()
            exit(0)
        } else if CommandLine.arguments.contains("--voice-smoke-test") {
            runVoiceSmokeTest()
        } else if CommandLine.arguments.contains("--model-smoke-test") {
            Task { @MainActor [weak self] in
                guard let self else { exit(1) }
                do {
                    let result = try await runtime.testModelConnection()
                    print("浮屿模型连接测试通过：\(result)")
                    self.shortcutMonitor?.stop()
                    exit(0)
                } catch {
                    fputs("浮屿模型连接测试失败：\(error.localizedDescription)\n", stderr)
                    self.shortcutMonitor?.stop()
                    exit(1)
                }
            }
        } else if CommandLine.arguments.contains("--mimo-tts-smoke-test") {
            Task { @MainActor [weak self] in
                guard let self else { exit(1) }
                do {
                    let result = try await voiceService.testMiMoSpeech()
                    print("浮屿语音连接测试通过：\(result)")
                    self.shortcutMonitor?.stop()
                    exit(0)
                } catch {
                    fputs("浮屿语音连接测试失败：\(error.localizedDescription)\n", stderr)
                    self.shortcutMonitor?.stop()
                    exit(1)
                }
            }
        } else if CommandLine.arguments.contains("--mimo-asr-smoke-test") {
            Task { @MainActor [weak self] in
                guard let self else { exit(1) }
                do {
                    let result = try await voiceService.testMiMoASR()
                    print("浮屿识别连接测试通过：\(result)")
                    self.shortcutMonitor?.stop()
                    exit(0)
                } catch {
                    fputs("浮屿识别连接测试失败：\(error.localizedDescription)\n", stderr)
                    self.shortcutMonitor?.stop()
                    exit(1)
                }
            }
        } else if CommandLine.arguments.contains("--mac-care-smoke-test") {
            Task { @MainActor [weak self] in
                do {
                    let system = try await MacCareService.run(.systemCheck)
                    let junk = try await MacCareService.run(.junkScan)
                    guard !system.details.isEmpty, !junk.details.isEmpty else {
                        throw NSError(domain: "FuYuMacCare", code: 1, userInfo: [NSLocalizedDescriptionKey: "本机扫描没有返回结果"])
                    }
                    print("浮屿电脑管家自检通过：九项工具本机直达；\(junk.headline)")
                    self?.shortcutMonitor?.stop()
                    exit(0)
                } catch {
                    fputs("浮屿电脑管家自检失败：\(error.localizedDescription)\n", stderr)
                    self?.shortcutMonitor?.stop()
                    exit(1)
                }
            }
        } else if let queryIndex = CommandLine.arguments.firstIndex(of: "--query"),
                  CommandLine.arguments.indices.contains(queryIndex + 1) {
            panelController?.showExpanded()
            runtime.handleTranscript(CommandLine.arguments[queryIndex + 1])
        } else {
            showMainWindow()
        }

    }

    func applicationDidBecomeActive(_ notification: Notification) {
        statusItem?.isVisible = true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if voiceService == nil {
            pendingDeepLink = url
        } else {
            handleDeepLink(url)
        }
    }

    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == "ai.fuyu.desktop.startVoice" else { return false }
        beginVoiceFromExternalTrigger()
        return true
    }

    private func donateStartVoiceActivity() {
        let activity = NSUserActivity(activityType: "ai.fuyu.desktop.startVoice")
        activity.title = "开始说话"
        activity.isEligibleForSearch = true
        activity.userInfo = ["action": "listen"]
        activity.becomeCurrent()
        voiceActivity = activity
    }

    private func handleDeepLink(_ url: URL) {
        switch Self.deepLinkAction(for: url) {
        case "listen": beginVoiceFromExternalTrigger()
        case "settings": showSettings()
        case "home": showMainWindow()
        default: break
        }
    }

    static func deepLinkAction(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "fuyu" else { return nil }
        switch url.host?.lowercased() {
        case "listen": return "listen"
        case "settings": return "settings"
        case "home": return "home"
        default: return nil
        }
    }

    private func beginVoiceFromExternalTrigger() {
        panelController?.showExpanded()
        Task { @MainActor [weak self] in
            await self?.voiceService?.startListening()
        }
    }

    /// Drives the same entry point as tapping the orb, briefly records, then
    /// cancels without submitting any audio to the model.
    private func runVoiceSmokeTest() {
        Task { @MainActor [weak self] in
            guard let self else { exit(1) }
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.state.requestVoice()

            for _ in 0..<600 {
                if self.state.phase == .listening || self.state.phase == .error { break }
                try? await Task.sleep(for: .milliseconds(100))
            }

            guard self.state.phase == .listening else {
                let message = self.state.phase == .error
                    ? self.state.transcript
                    : "系统授权尚未完成（\(self.voiceService?.permissionSummary ?? "状态未知")）"
                self.runtime?.cancelCurrentWork()
                self.shortcutMonitor?.stop()
                fputs("浮屿语音冒烟测试失败：\(message)\n", stderr)
                exit(1)
            }

            try? await Task.sleep(for: .milliseconds(900))
            self.state.cancel()
            self.shortcutMonitor?.stop()
            print("浮屿语音冒烟测试通过：点击入口、权限、麦克风启动与停止均正常")
            exit(0)
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        item.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        let assistantStatus = NSMenuItem(title: "浮屿运行正常 · 待命", action: nil, keyEquivalent: "")
        assistantStatus.isEnabled = false
        menu.addItem(assistantStatus)
        assistantStatusItem = assistantStatus
        let status = NSMenuItem(
            title: runtime?.isHermesAvailable == true ? "Hermes 已就绪" : "Hermes 未安装",
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        let shortcut = NSMenuItem(
            title: "语音快捷键：\(shortcutMonitor?.shortcutLabel ?? "未注册")",
            action: nil,
            keyEquivalent: ""
        )
        shortcut.isEnabled = false
        menu.addItem(shortcut)
        shortcutStatusItem = shortcut
        menu.addItem(.separator())
        menu.addItem(withTitle: "开始语音", action: #selector(startVoice), keyEquivalent: "")
        menu.addItem(withTitle: "打开主界面", action: #selector(showMainWindow), keyEquivalent: "")
        menu.addItem(withTitle: "显示悬浮气泡", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "个性化设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "运行交互演示", action: #selector(runDemo), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出浮屿", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
        updateStatusItem(for: state.phase)
    }

    private func updateStatusItem(for phase: AppState.Phase) {
        guard let button = statusItem?.button else { return }
        button.image = Self.makeFuYuStatusIcon(for: phase)
        button.toolTip = "浮屿正在运行 · \(phase.rawValue)"
        assistantStatusItem?.title = "浮屿运行正常 · \(phase.rawValue)"
    }

    private static func makeFuYuStatusIcon(for phase: AppState.Phase) -> NSImage {
        let color: NSColor = switch phase {
        case .idle: .labelColor
        case .listening: .systemCyan
        case .thinking: .systemPurple
        case .executing, .answered: .systemGreen
        case .speaking: .systemPink
        case .error: .systemRed
        }
        let energy: [CGFloat] = switch phase {
        case .idle: [0.28, 0.48, 0.68, 0.48, 0.28]
        case .listening: [0.32, 0.78, 1.0, 0.7, 0.4]
        case .thinking: [0.7, 0.34, 0.9, 0.42, 0.76]
        case .executing: [0.42, 0.62, 0.82, 1.0, 0.72]
        case .speaking: [0.72, 1.0, 0.54, 0.9, 0.38]
        case .answered: [0.3, 0.46, 0.62, 0.46, 0.3]
        case .error: [0.82, 0.3, 0.82, 0.3, 0.82]
        }
        let image = NSImage(size: NSSize(width: 19, height: 18), flipped: false) { _ in
            color.setFill()
            for (index, value) in energy.enumerated() {
                let radius = 1.15 + value * 0.55
                let x = 3.0 + CGFloat(index) * 3.25
                let y = 9 + (value - 0.5) * 6 * (index.isMultiple(of: 2) ? 1 : -1)
                NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
            }
            let orbit = NSBezierPath()
            orbit.appendArc(withCenter: NSPoint(x: 9.5, y: 9), radius: 8, startAngle: 205, endAngle: 338)
            orbit.lineWidth = 0.7
            color.withAlphaComponent(0.45).setStroke()
            orbit.stroke()
            return true
        }
        image.isTemplate = phase == .idle
        image.accessibilityDescription = "浮屿 · \(phase.rawValue)"
        return image
    }

    @objc private func showPanel() {
        panelController?.showExpanded()
    }

    @objc private func showMainWindow() {
        mainWindowController?.show()
    }

    @objc private func startVoice() {
        state.requestVoice()
    }

    @objc private func runDemo() {
        panelController?.showExpanded()
        state.runDemo()
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                state: state,
                preferences: preferences,
                testConnection: { [weak self] in
                    guard let runtime = self?.runtime else { throw AssistantServiceError.invalidResponse }
                    return try await runtime.testModelConnection()
                },
                clearMemory: { [weak self] in
                    guard let runtime = self?.runtime else { return }
                    try await runtime.clearMemory()
                },
                previewVoice: { [weak self] in
                    self?.voiceService?.speak("你好，我是浮屿。以后我会用这个声音陪你处理 Mac 上的事情。")
                },
                sendText: { [weak self] text in
                    self?.runtime?.handleTextInput(text)
                },
                runDiagnostics: { [weak self] in
                    guard let self else { return "浮屿运行状态不可用" }
                    let modelKey = self.preferences.modelProvider.requiresAPIKey
                        ? (self.preferences.hasStoredAPIKey ? "已配置" : "未配置")
                        : "不需要"
                    return """
                    应用：运行正常
                    语音权限：\(self.voiceService?.permissionSummary ?? "未知")
                    当前模型：\(self.preferences.modelProvider.title) / \(self.preferences.modelName)
                    模型密钥：\(modelKey)
                    Hermes：\(self.runtime?.isHermesAvailable == true ? "已就绪" : "未安装或不可用")
                    操作确认：\(self.preferences.requireActionApproval ? "已开启" : "已关闭")
                    """
                }
            )
        }
        settingsWindowController?.show()
    }

    @objc private func quit() {
        runtime?.cancelCurrentWork()
        NSApplication.shared.terminate(nil)
    }

    private func handleFeishuMessage(_ message: FeishuInboundMessage) {
        guard let runtime, let feishuBridge else { return }
        let key = message.messageID.isEmpty ? UUID().uuidString : message.messageID
        let initialCount = state.conversation.count
        var observer: AnyCancellable?
        observer = state.$conversation
            .dropFirst()
            .compactMap { items -> AppState.ConversationItem? in
                guard items.count > initialCount, let last = items.last, last.kind != .user else { return nil }
                return last
            }
            .first()
            .sink { [weak self] item in
                feishuBridge.reply(to: message, text: item.text)
                self?.remoteReplyObservers[key] = nil
            }
        remoteReplyObservers[key] = observer
        state.activitySource = "飞书"
        runtime.handleTextInput(message.text)
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutMonitor?.stop()
        thermalMonitor.stop()
        feishuBridge?.stop()
        runtime?.cancelCurrentWork()
    }
}
