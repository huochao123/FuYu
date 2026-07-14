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
    private let state = AppState()
    private let preferences = AssistantPreferences()
    private var panelController: FloatingPanelController?
    private var statusItem: NSStatusItem?
    private var shortcutStatusItem: NSMenuItem?
    private var shortcutMonitor: GlobalShortcutMonitor?
    private var voiceService: VoiceService?
    private var runtime: AssistantRuntime?
    private var settingsWindowController: SettingsWindowController?
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
        donateStartVoiceActivity()

        if let pendingDeepLink {
            self.pendingDeepLink = nil
            handleDeepLink(pendingDeepLink)
        }

        if CommandLine.arguments.contains("--demo") {
            panelController?.showExpanded()
            state.runDemo()
        } else if CommandLine.arguments.contains("--settings") {
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
        } else if let queryIndex = CommandLine.arguments.firstIndex(of: "--query"),
                  CommandLine.arguments.indices.contains(queryIndex + 1) {
            panelController?.showExpanded()
            runtime.handleTranscript(CommandLine.arguments[queryIndex + 1])
        }

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
        activity.webpageURL = URL(string: "fuyu://listen")
        activity.becomeCurrent()
        voiceActivity = activity
    }

    private func handleDeepLink(_ url: URL) {
        switch Self.deepLinkAction(for: url) {
        case "listen": beginVoiceFromExternalTrigger()
        case "settings": showSettings()
        default: break
        }
    }

    static func deepLinkAction(for url: URL) -> String? {
        guard url.scheme?.lowercased() == "fuyu" else { return nil }
        switch url.host?.lowercased() {
        case "listen": return "listen"
        case "settings": return "settings"
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
        item.button?.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "浮屿")

        let menu = NSMenu()
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
        menu.addItem(withTitle: "显示浮屿", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(withTitle: "个性化设置…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "运行交互演示", action: #selector(runDemo), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出浮屿", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showPanel() {
        panelController?.showExpanded()
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
                }
            )
        }
        settingsWindowController?.show()
    }

    @objc private func quit() {
        runtime?.cancelCurrentWork()
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        shortcutMonitor?.stop()
        runtime?.cancelCurrentWork()
    }
}
