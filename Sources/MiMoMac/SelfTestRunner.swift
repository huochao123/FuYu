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

        let historyURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: historyURL) }
        let state = AppState(historyURL: historyURL)
        check(state.overlayMode == .orb, "初始状态是悬浮球")
        state.beginListening()
        check(state.overlayMode == .voice && state.phase == .listening, "录音状态切换")
        state.beginExecution(title: "自检任务")
        check(state.overlayMode == .task && state.steps.count == 3, "执行卡状态切换")
        check(
            state.steps.map(\.title) == ["正在连接 Hermes", "Hermes 已接收任务", "正在检查结果"]
                && HermesCommandRunner.timeoutSeconds == 120,
            "执行气泡展示 Hermes 阶段并限制卡住时间"
        )
        state.updateExecution(progress: 2, step: 2)
        check(state.progress == 1, "进度边界限制")

        var approvals = 0
        state.onApprovalGranted = { _ in approvals += 1 }
        state.presentApproval(title: "确认？", detail: "自检")
        check(state.overlayMode == .approval, "权限确认卡状态切换")
        state.beginListening(preservingApproval: true)
        check(state.overlayMode == .approval && state.showPermission, "授权卡保持显示并等待语音确认")
        state.approveFromUserInteraction()
        check(approvals == 1 && !state.showPermission, "单次批准回调")

        var cancelled = false
        state.onCancelRequested = { cancelled = true }
        state.cancel()
        check(cancelled && state.overlayMode == .orb, "取消会回收后台状态")

        state.presentSilentReply("完整文字只显示，不播报")
        check(state.phase == .answered && state.overlayMode == .voice, "静默回复使用气泡保持可读")
        state.openHistory()
        check(state.overlayMode == .history && !state.conversation.isEmpty, "聊天与执行记录面板")
        state.recordAssistantMessage("文字聊天自检")
        check(state.conversation.last?.text == "文字聊天自检", "文字聊天共享会话记录")
        let restoredState = AppState(historyURL: historyURL)
        check(restoredState.conversation.last?.text == "文字聊天自检", "聊天页面跨启动加载本机历史")
        state.resetToIdle()

        let suiteName = "ai.fuyu.selftest.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: suiteName)!
        let habitURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-habits-\(UUID().uuidString).json")
        defer {
            testDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: habitURL)
        }
        let preferences = AssistantPreferences(defaults: testDefaults, habitStoreURL: habitURL)
        check(
            preferences.spokenText(fullText: "好的，已经完成。", suggested: nil) == "好的，已经完成。",
            "智能播报保留短结论"
        )
        check(
            preferences.spokenText(fullText: "详情见 https://example.com", suggested: nil) == nil,
            "智能播报过滤链接"
        )
        check(
            preferences.spokenText(
                fullText: "这是一个比较长的回答，里面包含很多补充说明，用来验证智能播报不会再完全跳过，而是至少读出一句简短结论。后面还有更多内容。",
                suggested: nil
            )?.isEmpty == false,
            "长回复至少生成一句播报"
        )
        let technicalSpeech = preferences.spokenText(
            fullText: "会议创建成功。会议ID：2439430414761153758\n加入链接：https://meeting.tencent.com/dm/Example\nX-Tc-Trace: abcdef1234567890",
            suggested: nil
        ) ?? ""
        check(
            !technicalSpeech.isEmpty
                && !technicalSpeech.lowercased().contains("trace")
                && !technicalSpeech.contains("https")
                && !technicalSpeech.contains("2439430414761153758"),
            "语音审校过滤链接、ID 和英文追踪码"
        )
        check(ModelProvider.allCases.count == 10, "主流模型服务预设")
        check(SpeechEngine.allCases.count == 4 && MiMoVoice.allCases.count == 8, "语音引擎与 MiMo 音色预设")
        check(RecognitionEngine.allCases.count == 3, "本地、自动与混合语音识别预设")
        check(FloatingSkin.allCases.count == 6 && preferences.floatingSkin == .particleFrame, "六种悬浮入口皮肤")
        check(FloatingPlacement.allCases.count == 3 && preferences.floatingPlacement == .notch, "刘海下方默认位置")
        check(!preferences.showDockIcon, "程序坞图标默认保持关闭")
        check(preferences.requireActionApproval, "Mac 操作确认默认开启")
        check(preferences.voiceActionApproval, "授权卡默认支持明确语音确认")
        preferences.personaEnabled = true
        preferences.personaRelationship = .partner
        preferences.personaName = "小屿"
        check(
            preferences.profile.personaPrompt.contains("小屿")
                && preferences.profile.personaPrompt.contains("伴侣"),
            "自定义人格与关系设定"
        )
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
        check(
            VoiceService.shouldAttemptRecognitionRecovery(attempts: 0, hasCapturedText: false)
                && VoiceService.shouldAttemptRecognitionRecovery(attempts: 1, hasCapturedText: false)
                && !VoiceService.shouldAttemptRecognitionRecovery(attempts: 2, hasCapturedText: false)
                && !VoiceService.shouldAttemptRecognitionRecovery(attempts: 0, hasCapturedText: true),
            "语音中断有限重连并优先保留已识别文字"
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
        check(
            AssistantPreferences.memoryCommand(for: "记住：我喜欢简短回答") == .remember("我喜欢简短回答")
                && AssistantPreferences.memoryCommand(for: "忘记简短回答") == .forget("简短回答")
                && AssistantPreferences.memoryCommand(for: "你记住了什么") == .list,
            "永久记忆语音命令识别"
        )
        check(
            preferences.rememberHabit("我喜欢简短回答")
                && preferences.profile.permanentHabitPrompt.contains("简短回答")
                && FileManager.default.fileExists(atPath: habitURL.path),
            "永久习惯本机保存并注入模型"
        )
        check(preferences.forgetHabits(matching: "简短回答") == 1, "永久习惯可精确删除")

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
            let incompleteAction = try MiMoAssistantClient.parseDecision(
                "```json\n{\"kind\":\"action\",\"hermesPrompt\":\"打开 Safari 并检查首页\"}\n```"
            )
            if case let .action(_, detail, prompt) = incompleteAction {
                check(detail.contains("Hermes") && prompt.contains("Safari"), "不完整 JSON 操作回复自动补全")
            } else {
                check(false, "不完整 JSON 操作回复自动补全")
            }
            let alternateReply = try MiMoAssistantClient.parseDecision(#"{"content":"这是兼容回复"}"#)
            check(alternateReply == .reply(text: "这是兼容回复", spoken: nil), "非标准模型回复兼容解析")
            let leakedTool = try MiMoAssistantClient.parseDecision("<tool_call><function=hermes_mcp__run></function></tool_call>")
            check(
                leakedTool == .reply(text: "我识别到这是一个操作请求，需要交给执行流程处理。", spoken: nil)
                    && MiMoAssistantClient.containsInternalToolMarkup("<tool_call>"),
                "内部工具调用不会泄漏到聊天或语音"
            )
            check(
                MiMoAssistantClient.claimsVerifiedSuccess("会议已经创建成功")
                    && !MiMoAssistantClient.claimsVerifiedSuccess("我准备创建会议"),
                "无真实结果时识别并拦截成功声明"
            )
            let corrected = MiMoAssistantClient.reconcileDecision(
                .reply(text: "好的，我来帮你打开。", spoken: "马上为你打开"),
                userText: "帮我打开 Safari"
            )
            if case .action = corrected {
                check(true, "Mac 操作意图二次校验")
            } else {
                check(false, "Mac 操作意图二次校验")
            }
            let delegation = HermesCommandRunner.delegationPrompt(for: "整理下载目录")
            check(
                delegation.contains("先理解目标") && delegation.contains("检查当前环境") && delegation.contains("验证结果"),
                "复杂任务交给 Hermes 规划、执行与验证"
            )
            check(
                !AssistantRuntime.requiresPlanReview(userText: "打开 Safari")
                    && AssistantRuntime.requiresPlanReview(userText: "整理下载文件夹，然后按照类型归档，并检查是否有重复文件")
                    && AssistantRuntime.requiresPlanReview(userText: "帮我开一个长期会议"),
                "简单任务直达、复杂任务进入方案预审"
            )
            check(AssistantRuntime.missingCriticalDetailsQuestion(for: "帮我开一个会议")?.contains("什么时候") == true, "会议信息缺失时先补问")
            let brightnessQuestion = AssistantRuntime.missingCriticalDetailsQuestion(for: "把亮度调一下")
            check(brightnessQuestion?.contains("百分之多少") == true, "亮度数值缺失时先补问")
            check(AssistantRuntime.missingCriticalDetailsQuestion(for: "打开 Safari") == nil, "参数完整的简单任务不多问")
            check(
                AssistantRuntime.missingCriticalDetailsQuestion(
                    for: "创建会议，今天下午3点到4点，单次会议"
                ) == nil,
                "参数完整的会议无需重复询问"
            )
            let approvedReview = MiMoAssistantClient.parsePlanReview(
                #"{"status":"approved","summary":"按类型整理并检查结果","finalPrompt":"只整理下载目录，完成后检查分类"}"#,
                fallbackPrompt: "整理下载目录"
            )
            check(
                approvedReview == .approved(summary: "按类型整理并检查结果", finalPrompt: "只整理下载目录，完成后检查分类"),
                "Hermes 方案审核通过解析"
            )
            let clarifyReview = MiMoAssistantClient.parsePlanReview(
                #"{"status":"clarify","question":"重复文件要保留哪一份？"}"#,
                fallbackPrompt: "整理下载目录"
            )
            check(clarifyReview == .clarify(question: "重复文件要保留哪一份？"), "复杂任务歧义会停止并询问用户")
            check(
                HermesCommandRunner.planningPrompt(for: "整理下载目录").contains("只返回方案，不执行任务"),
                "预审阶段禁止 Hermes 修改电脑"
            )

            let cardURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("fuyu-card-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: cardURL) }
            try Data(#"{"spec":"chara_card_v2","spec_version":"2.0","data":{"name":"小雪","description":"来自未来城市","personality":"温柔、聪明","scenario":"与用户合租","first_mes":"欢迎回家"}}"#.utf8)
                .write(to: cardURL)
            let imported = try TavernImportService.importCharacter(from: cardURL)
            check(
                imported.name == "小雪"
                    && imported.background.contains("未来城市")
                    && imported.style.contains("欢迎回家")
                    && imported.fields.count == 5
                    && imported.format.contains("V2"),
                "SillyTavern V2 角色卡导入"
            )

            let v1URL = FileManager.default.temporaryDirectory
                .appendingPathComponent("fuyu-card-v1-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: v1URL) }
            try Data(#"{"name":"阿岚","description":"旅行摄影师","personality":"开朗","mes_example":"{{char}}: 今天去哪里？"}"#.utf8)
                .write(to: v1URL)
            let importedV1 = try TavernImportService.importCharacter(from: v1URL)
            check(importedV1.name == "阿岚" && importedV1.format.contains("V1"), "SillyTavern V1 JSON 导入")

            let pngURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("fuyu-card-png-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: pngURL) }
            let embeddedJSON = Data(#"{"spec":"chara_card_v2","data":{"name":"青禾","description":"图像内嵌角色"}}"#.utf8)
            let textPayload = Data("chara\0".utf8) + Data(embeddedJSON.base64EncodedString().utf8)
            var png = Data([137, 80, 78, 71, 13, 10, 26, 10])
            let length = UInt32(textPayload.count).bigEndian
            withUnsafeBytes(of: length) { png.append(contentsOf: $0) }
            png.append(Data("tEXt".utf8))
            png.append(textPayload)
            png.append(Data(repeating: 0, count: 4))
            try png.write(to: pngURL)
            let importedPNG = try TavernImportService.importCharacter(from: pngURL)
            check(
                importedPNG.name == "青禾" && importedPNG.format.contains("PNG"),
                "SillyTavern PNG 内嵌角色卡导入"
            )

            let presetURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("fuyu-preset-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: presetURL) }
            try Data(#"{"main_prompt":"保持沉浸式对话","post_history_instructions":"延续人物语气"}"#.utf8)
                .write(to: presetURL)
            let presetPreview = try TavernImportService.previewPreset(from: presetURL)
            check(
                presetPreview.sections.count == 2
                    && presetPreview.composedPrompt.contains("保持沉浸式对话")
                    && presetPreview.composedPrompt.contains("历史后置提示"),
                "SillyTavern 提示词预设解析与预览"
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
