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
        let archiveURL = historyURL.deletingPathExtension().appendingPathExtension("archive.jsonl")
        let focusURL = historyURL.deletingPathExtension().appendingPathExtension("task-focus.json")
        defer {
            try? FileManager.default.removeItem(at: historyURL)
            try? FileManager.default.removeItem(at: archiveURL)
            try? FileManager.default.removeItem(at: focusURL)
        }
        let state = AppState(historyURL: historyURL)
        check(state.overlayMode == .orb, "初始状态是悬浮球")
        state.beginListening()
        check(state.overlayMode == .voice && state.phase == .listening, "录音状态切换")
        check(state.recognitionStage == .waiting && state.transcript == "我在听…", "识别窗口等待声音")
        state.updateTranscript("帮我创建一个会议")
        check(state.recognitionStage == .live && state.transcript == "帮我创建一个会议", "识别窗口实时显示文字")
        state.beginFinalizingRecognition()
        check(state.recognitionStage == .finalizing, "识别窗口显示校正状态")
        state.presentFinalRecognition("帮我创建一个下午三点的会议")
        check(state.recognitionStage == .final && state.transcript == "帮我创建一个下午三点的会议", "识别窗口保留最终采用文字")
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
        check(
            state.overlayMode == .approval && state.showPermission && state.approvalIsListening,
            "授权卡保持显示并使用独立语音状态"
        )
        state.updateTranscript("允许执行")
        check(state.approvalHeardText == "允许执行", "授权口令显示在授权卡而非普通对话")
        state.approveFromUserInteraction()
        check(approvals == 1 && !state.showPermission, "单次批准回调")

        var cancelled = false
        state.onCancelRequested = { cancelled = true }
        state.cancel()
        check(cancelled && state.overlayMode == .orb, "取消会回收后台状态")

        state.presentSilentReply("完整文字只显示，不播报")
        check(state.phase == .answered && state.overlayMode == .voice, "静默回复使用气泡保持可读")
        state.beginTextInteraction()
        state.beginThinking(userText: "纯文字输入")
        state.presentSilentReply("纯文字回复")
        check(
            state.interactionSource == .text && !state.isExpanded && state.conversation.last?.text == "纯文字回复",
            "文字聊天不唤起悬浮窗或语音交互"
        )
        state.beginVoiceInteraction()
        state.beginThinking(userText: "语音输入")
        check(state.interactionSource == .voice && state.isExpanded, "语音输入继续使用悬浮窗")
        state.beginSpeaking("第一轮语音回答")
        state.finishSpeaking(keepExpanded: true)
        check(
            state.phase == .idle && state.isExpanded,
            "连续对话等待下一轮时不会被旧收起任务关闭"
        )
        state.presentNotification("发热监控提醒", duration: .seconds(30))
        check(
            state.interactionSource == .notification && state.overlayMode == .response && state.isExpanded,
            "系统异常使用无麦克风的文字通知悬浮窗"
        )
        state.resetToIdle()
        state.openHistory()
        check(state.overlayMode == .history && !state.conversation.isEmpty, "聊天与执行记录面板")
        state.recordAssistantMessage("文字聊天自检")
        check(state.conversation.last?.text == "文字聊天自检", "文字聊天共享会话记录")
        state.recordActionStatus("执行成功：自检任务")
        let restoredState = AppState(historyURL: historyURL)
        check(restoredState.conversation.contains(where: { $0.text == "文字聊天自检" }), "聊天页面跨启动加载本机历史")
        let interruptedURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-interrupted-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: interruptedURL)
            try? FileManager.default.removeItem(at: interruptedURL.deletingPathExtension().appendingPathExtension("archive.jsonl"))
            try? FileManager.default.removeItem(at: interruptedURL.deletingPathExtension().appendingPathExtension("task-focus.json"))
        }
        let interruptedState = AppState(historyURL: interruptedURL)
        interruptedState.beginExecution(title: "中断自检")
        let recoveredInterruptedState = AppState(historyURL: interruptedURL)
        check(recoveredInterruptedState.conversation.last?.text.contains("任务已中断") == true, "重启后标记没有真实结果的中断任务")
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
        check(preferences.voiceInterruption, "朗读与执行过程默认允许语音打断")
        check(preferences.voiceInputEnabled, "主界面语音识别总开关默认开启")
        check(MainWindowTheme.allCases.count == 3 && preferences.mainWindowTheme == .deepOcean, "三套主界面皮肤与深海默认主题")
        check(MacCareTool.allCases.count == 9, "电脑管家九项本机工具注册")
        let sharedReport = MacCareReport(
            tool: .hotProcesses,
            headline: "发现 1 个持续高负载进程",
            details: ["ExampleApp · CPU 88%"]
        )
        state.publishMacCareReport(sharedReport)
        check(
            state.latestMacCareReport?.tool == .hotProcesses
                && state.macCareContextPrompt.contains("ExampleApp")
                && state.macCareReportVersion == 1,
            "电脑管家结果同步到助手共享上下文"
        )
        state.recordAssistantMessage("我把这个重复文件甄别任务交给执行流程。")
        state.beginTextInteraction()
        state.beginThinking(userText: "去吧")
        let continuityContext = state.conversationContextPrompt(for: "去吧")
        check(
            continuityContext.contains("重复文件甄别任务")
                && continuityContext.contains("用户：去吧")
                && continuityContext.contains("必须承接"),
            "短指令携带最近任务上下文，不再把每句话当新会话"
        )
        for index in 0..<30 {
            state.recordActionStatus("较早任务 \(index)：下载文件夹分析")
        }
        let retrievedContext = state.conversationContextPrompt(for: "之前下载文件夹分析怎么样")
        check(
            retrievedContext.contains("较早记录") && retrievedContext.contains("下载文件夹分析"),
            "超过即时窗口后仍可从本机历史检索相关任务"
        )
        let continuityURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-continuity-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: continuityURL)
            try? FileManager.default.removeItem(at: continuityURL.deletingPathExtension().appendingPathExtension("archive.jsonl"))
            try? FileManager.default.removeItem(at: continuityURL.deletingPathExtension().appendingPathExtension("task-focus.json"))
        }
        let continuityState = AppState(historyURL: continuityURL)
        continuityState.beginTextInteraction()
        continuityState.beginThinking(userText: "把重复文件仔细甄别后移到废纸篓")
        continuityState.presentSilentReply("我会先确认保留规则，再等待你同意执行。")
        continuityState.beginThinking(userText: "你没记忆吗，每一句话都失忆")
        continuityState.presentSilentReply("我会检查连续对话记忆，但不会丢掉原任务。")
        let resumedContinuityState = AppState(historyURL: continuityURL)
        let resumedRequest = resumedContinuityState.contextualizedRequest("去吧")
        check(
            resumedRequest.contains("不是新会话")
                && resumedRequest.contains("重复文件仔细甄别")
                && resumedRequest.contains("不会丢掉原任务"),
            "跨重启工作记忆会让去吧继续上一任务"
        )
        check(
            LocalCommandRouter.command(for: "把音量调到 35%") == .volume(.set(35))
                && LocalCommandRouter.command(for: "检查一下启动项") == .scan(.loginItems)
                && LocalCommandRouter.command(for: "删除重复文件") == .scan(.duplicates)
                && LocalCommandRouter.command(for: "你能做什么") == .capabilities
                && LocalCommandRouter.command(for: "帮我分析下载文件夹") == .scan(.organize)
                && LocalCommandRouter.command(for: "下载文件夹分析下") == .scan(.organize),
            "基础 Mac 指令优先路由到浮屿本机能力且重复文件不直接删除"
        )
        let explanationFixture: [AppState.ConversationItem] = [
            .init(kind: .action, text: "复杂任务预审：正在向 Hermes 获取只读方案"),
            .init(kind: .error, text: "模型响应超时")
        ]
        if case let .reply(explanation) = AgentIntentEngine.route(
            for: "那你为啥执行复杂任务预审然后超时",
            conversation: explanationFixture
        ) {
            check(
                explanation.contains("不应该再次启动任何工具或 Hermes")
                    && explanation.contains("请求超时"),
                "运行原因追问只解释且不重复执行"
            )
        } else {
            check(false, "运行原因追问只解释且不重复执行")
        }
        check(
            AgentToolRegistry.localCommand(for: .init(id: .organizeDownloads, arguments: [:])) == .scan(.organize)
                && AgentToolRegistry.localCommand(for: .init(id: .volume, arguments: ["action": "set", "value": "36"])) == .volume(.set(36)),
            "统一 Agent 工具注册表映射真实本机能力"
        )
        let unavailableManifest = LocalMacCapabilityManifest(brightnessAvailable: false).prompt
        check(
            unavailableManifest.contains("九项") == false
                && unavailableManifest.contains("系统体检")
                && unavailableManifest.contains("不能声称已调整"),
            "动态能力清单如实描述浮屿身份边界"
        )
        let thermalMonitor = ThermalProcessMonitor()
        check(thermalMonitor.summary == "正在建立基线", "发热进程后台监测初始状态")
        check(
            !ThermalProcessMonitor.isSustainedHot(cpu: 90, consecutiveSamples: 2)
                && ThermalProcessMonitor.isSustainedHot(cpu: 90, consecutiveSamples: 3),
            "发热提醒只在连续三次真实高负载后触发"
        )
        check(
            VoiceService.approvalDecision(for: "允许执行") == true
                && VoiceService.approvalDecision(for: "不允许执行") == false
                && VoiceService.approvalDecision(for: "打开计算器") == nil,
            "授权专用识别只接受允许或取消口令"
        )
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
                && VoiceService.automaticSubmissionDelayMilliseconds(for: "你好", baseSeconds: 2.3) == 2_650
                && VoiceService.automaticSubmissionDelayMilliseconds(for: "好，就这样去执行吧", baseSeconds: 2.3) == 320
                && VoiceService.automaticSubmissionDelayMilliseconds(for: "可以了", baseSeconds: 2.3) == 320,
            "停顿提交会给短句和未完句留出时间"
        )
        check(
            VoiceService.automaticSubmissionBaseSeconds(configured: 2.8, continuousFollowUp: false) == 2.8
                && VoiceService.automaticSubmissionBaseSeconds(configured: 2.8, continuousFollowUp: true) == 4.0,
            "连续对话第二轮增加停顿余量避免话没说完就提交"
        )
        check(
            VoiceService.shouldRestoreOutputVolumeAfterListening(original: 22, observed: 11)
                && !VoiceService.shouldRestoreOutputVolumeAfterListening(original: 22, observed: 22)
                && !VoiceService.shouldRestoreOutputVolumeAfterListening(original: 22, observed: 28),
            "松开 Fn 后恢复收音前音量且不压低用户主动调高的音量"
        )
        check(
            VoiceService.shouldRestartAudioCapture(bufferCount: 0, recoveryAttempts: 0)
                && !VoiceService.shouldRestartAudioCapture(bufferCount: 1, recoveryAttempts: 0)
                && !VoiceService.shouldRestartAudioCapture(bufferCount: 0, recoveryAttempts: 1),
            "第二轮麦克风没有音频缓冲时只自动重建一次"
        )
        check(
            VoiceService.userInterruptionText(transcript: "这是助手正在说的话", spokenText: "这是助手正在说的话") == nil
                && VoiceService.userInterruptionText(transcript: "停一下改成下午五点", spokenText: "我正在执行创建会议") == "停一下改成下午五点",
            "朗读回声会被忽略而用户抢话会被接收"
        )
        check(
            AssistantRuntime.isPauseOnlyCommand("等一下")
                && AssistantRuntime.isPauseOnlyCommand("先别执行")
                && !AssistantRuntime.isPauseOnlyCommand("等一下，改成下午五点"),
            "执行中暂停与修改指令分流"
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
            let tool = try MiMoAssistantClient.parseDecision(
                #"{"kind":"tool","tool":"mac.downloads_analyze","arguments":{}}"#
            )
            check(
                tool == .tool(.init(id: .organizeDownloads, arguments: [:])),
                "本机 Agent 工具调用解析"
            )
            let numericTool = try MiMoAssistantClient.parseDecision(
                #"{"kind":"tool","tool":"mac.volume","arguments":{"action":"set","value":36}}"#
            )
            check(
                numericTool == .tool(.init(id: .volume, arguments: ["action": "set", "value": "36"])),
                "模型数字参数可稳定转换为本机工具参数"
            )
            let hermes = try MiMoAssistantClient.parseDecision(
                "```json\n{\"kind\":\"hermes\",\"hermesPrompt\":\"打开 Safari 并检查首页\"}\n```"
            )
            if case let .hermes(_, detail, prompt) = hermes {
                check(detail.contains("Hermes") && prompt.contains("Safari"), "Hermes 专家委派解析")
            } else {
                check(false, "Hermes 专家委派解析")
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
            if case .cancelled? = MiMoAssistantClient.transportError(for: .cancelled),
               case .modelTimeout? = MiMoAssistantClient.transportError(for: .timedOut) {
                check(true, "取消旧请求不会显示成失败且超时有独立提示")
            } else {
                check(false, "取消旧请求不会显示成失败且超时有独立提示")
            }
            let corrected = MiMoAssistantClient.reconcileDecision(
                .reply(text: "好的，我来帮你打开。", spoken: "马上为你打开"),
                userText: "帮我打开 Safari"
            )
            check(
                corrected == .reply(text: "好的，我来帮你打开。", spoken: "马上为你打开"),
                "普通回复不会再被自动升级为 Hermes"
            )
            let genericAppAction = MiMoAssistantClient.reconcileDecision(
                .reply(text: "需要交给执行流程", spoken: nil),
                userText: "打开计算器"
            )
            check(
                genericAppAction == .reply(text: "需要交给执行流程", spoken: nil),
                "Hermes 只接受模型明确选择而不是关键词强制升级"
            )
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
            check(
                AssistantRuntime.normalizedApprovalPhrase("允，允许，允许执行。") == "允允许允许执行"
                    && AssistantRuntime.cleanActionTitle("帮我开一个会议\n用户补充信息：下午三点") == "帮我开一个会议",
                "语音授权容错与授权标题美化"
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
