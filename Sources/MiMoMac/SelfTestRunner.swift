import Foundation

@MainActor
enum SelfTestRunner {
    static func run() -> Bool {
        var failures: [String] = []

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() {
                print("✓ \(name)")
            } else {
                print("✗ \(name)")
                failures.append(name)
            }
        }

        let state = AppState()
        check(state.overlayMode == .orb, "初始状态是悬浮球")
        state.beginListening()
        check(state.overlayMode == .voice && state.phase == .listening, "录音状态切换")
        state.beginExecution(title: "自检任务")
        check(state.overlayMode == .task && state.steps.count == 3, "执行卡状态切换")
        state.updateExecution(progress: 2, step: 2)
        check(state.progress == 1, "进度边界限制")

        var approvals = 0
        state.onApprovalGranted = { _ in approvals += 1 }
        state.presentApproval(title: "确认？", detail: "自检")
        check(state.overlayMode == .approval, "权限确认卡状态切换")
        state.approveFromUserInteraction()
        check(approvals == 1 && !state.showPermission, "单次批准回调")

        var cancelled = false
        state.onCancelRequested = { cancelled = true }
        state.cancel()
        check(cancelled && state.overlayMode == .orb, "取消会回收后台状态")

        state.presentSilentReply("完整文字只显示，不播报")
        check(state.phase == .answered && state.overlayMode == .voice, "静默回复使用气泡保持可读")
        state.resetToIdle()

        let suiteName = "ai.fuyu.selftest.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        defer { testDefaults.removePersistentDomain(forName: suiteName) }
        let preferences = AssistantPreferences(defaults: testDefaults)
        check(
            preferences.spokenText(fullText: "好的，已经完成。", suggested: nil) == "好的，已经完成。",
            "智能播报保留短结论"
        )
        check(
            preferences.spokenText(fullText: "详情见 https://example.com", suggested: nil) == nil,
            "智能播报过滤链接"
        )
        check(ModelProvider.allCases.count == 10, "主流模型服务预设")
        check(SpeechEngine.allCases.count == 4 && MiMoVoice.allCases.count == 8, "语音引擎与 MiMo 音色预设")
        check(RecognitionEngine.allCases.count == 3, "本地、自动与混合语音识别预设")
        check(FloatingSkin.allCases.count == 6 && preferences.floatingSkin == .particleFrame, "六种悬浮入口皮肤")
        check(FloatingPlacement.allCases.count == 3 && preferences.floatingPlacement == .notch, "刘海下方默认位置")
        check(!preferences.showDockIcon, "程序坞图标默认保持关闭")
        check(preferences.requireActionApproval, "Mac 操作确认默认开启")
        check(PushToTalkShortcut.allCases.count == 6 && preferences.pushToTalkShortcut == .fnHold, "Fn 与可修改快捷键预设")
        var shortcutPresses = 0
        var shortcutReleases = 0
        let shortcutMonitor = GlobalShortcutMonitor(
            shortcut: .fnHold,
            onPress: { shortcutPresses += 1 },
            onRelease: { shortcutReleases += 1 }
        )
        shortcutMonitor.handleFunctionFlags(.function)
        shortcutMonitor.handleFunctionFlags([])
        check(shortcutPresses == 1 && shortcutReleases == 1, "Fn 按下与松开事件")
        check(
            AppDelegate.deepLinkAction(for: URL(string: "fuyu://listen")!) == "listen"
                && AppDelegate.deepLinkAction(for: URL(string: "fuyu://settings")!) == "settings",
            "Siri 与快捷指令 URL 入口"
        )
        preferences.speechEngine = .mimo
        preferences.mimoVoice = .moli
        check(preferences.speechEngine == .mimo && preferences.mimoVoice.rawValue == "茉莉", "MiMo 语音配置切换")
        preferences.endPauseSeconds = 2.8
        preferences.continuousConversation = true
        check(preferences.endPauseSeconds == 2.8 && preferences.continuousConversation, "停顿等待与连续对话配置")
        check(
            VoiceService.automaticSubmissionDelayMilliseconds(for: "我还想说然后", baseSeconds: 2.3) == 3_600
                && VoiceService.automaticSubmissionDelayMilliseconds(for: "你好", baseSeconds: 2.3) == 2_650,
            "停顿提交会给短句和未完句留出时间"
        )
        preferences.modelProvider = .ollama
        check(
            preferences.profile.model.endpoint.contains("127.0.0.1")
                && preferences.profile.model.model == "qwen3:8b",
            "本地模型配置切换"
        )
        preferences.contextTurns = 12
        check(
            preferences.profile.contextEnabled && preferences.profile.contextTurns == 12,
            "上下文记忆配置"
        )

        do {
            let reply = try MiMoAssistantClient.parseDecision(#"{"kind":"reply","reply":"这里是完整回答","spokenReply":"你好"}"#)
            check(reply == .reply(text: "这里是完整回答", spoken: "你好"), "普通回答解析")
            let action = try MiMoAssistantClient.parseDecision(
                #"{"kind":"action","title":"打开访达","detail":"只打开访达","hermesPrompt":"打开 Finder"}"#
            )
            check(
                action == .action(title: "打开访达", detail: "只打开访达", hermesPrompt: "打开 Finder"),
                "Mac 操作规划解析"
            )
        } catch {
            failures.append("模型规划解析：\(error.localizedDescription)")
        }

        if failures.isEmpty {
            print("\n浮屿自检全部通过")
            return true
        }
        print("\n浮屿自检失败：\(failures.joined(separator: "、"))")
        return false
    }
}
