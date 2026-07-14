import AppKit
import AVFoundation
import SwiftUI

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "常规"
    case voice = "声音"
    case models = "模型"
    case memory = "记忆"
    case advanced = "高级"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .voice: "waveform"
        case .models: "cpu"
        case .memory: "brain.head.profile"
        case .advanced: "gearshape.2"
        }
    }
}

@MainActor
private final class SettingsViewState: ObservableObject {
    @Published var selection: SettingsSection = .general
    @Published var modelStatus = ""
    @Published var voiceStatus = ""
    @Published var isTesting = false
    @Published var showClearConfirmation = false
}

struct SettingsView: View {
    @ObservedObject var preferences: AssistantPreferences
    @ObservedObject fileprivate var viewState: SettingsViewState
    let testConnection: () async throws -> String
    let clearMemory: () async throws -> Void
    let previewVoice: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    pageContent
                        .id(viewState.selection)
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 720, height: 540)
        .background(
            LinearGradient(
                colors: [Color(NSColor.windowBackgroundColor), Color.accentColor.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .alert("清除所有对话记忆？", isPresented: $viewState.showClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("清除", role: .destructive) {
                Task {
                    do {
                        try await clearMemory()
                        viewState.modelStatus = "对话记忆已清除"
                    } catch {
                        viewState.modelStatus = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("当前会话和已保存到本机的长期记忆都会被删除。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.16))
                    Image(systemName: "waveform.and.sparkles")
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("浮屿")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("助手设置")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)

            VStack(spacing: 5) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { viewState.selection = section }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .frame(width: 18)
                            Text(section.rawValue)
                            Spacer()
                        }
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(viewState.selection == section ? Color.accentColor : .secondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            viewState.selection == section ? Color.accentColor.opacity(0.11) : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
            VStack(alignment: .leading, spacing: 4) {
                Text(preferences.modelProvider.title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Text(preferences.modelName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
        }
        .padding(16)
        .frame(width: 172)
        .background(.primary.opacity(0.025))
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewState.selection.rawValue)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(pageSubtitle)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var pageSubtitle: String {
        switch viewState.selection {
        case .general: "决定浮屿怎么回答，以及哪些内容值得说出口"
        case .voice: "切换免费系统音色、MiMo 云端语音或本地克隆服务"
        case .models: "随时切换云端模型、本地模型或兼容服务"
        case .memory: "控制对话上下文和跨启动记忆的保存范围"
        case .advanced: "调整自动提交、静默收起和语音交互节奏"
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch viewState.selection {
        case .general: generalPage
        case .voice: voicePage
        case .models: modelsPage
        case .memory: memoryPage
        case .advanced: advancedPage
        }
    }

    private var voicePage: some View {
        VStack(spacing: 14) {
            settingsCard {
                settingRow("语音引擎", detail: "聊天模型和说话声音可以独立选择") {
                    Picker("", selection: $preferences.speechEngine) {
                        ForEach(SpeechEngine.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 220)
                }
                Divider()
                settingRow("语音识别", detail: "MiMo 模式保留实时字幕，并在发送前校正文字") {
                    Picker("", selection: $preferences.recognitionEngine) {
                        ForEach(RecognitionEngine.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 220)
                }
                Divider()
                voiceEngineOptions
            }
            settingsCard {
                VStack(alignment: .leading, spacing: 9) {
                    Text("说话风格").font(.system(size: 12, weight: .semibold, design: .rounded))
                    TextField("例如：温柔自然、不要播音腔", text: $preferences.speechInstructions)
                        .textFieldStyle(.roundedBorder)
                    Toggle("云端语音失败时自动使用系统声音", isOn: $preferences.speechFallback)
                        .font(.system(size: 11, design: .rounded))
                }
            }
            HStack {
                Label("云端声音由 AI 生成；MiMo 会复用已保存的 MiMo 密钥。", systemImage: "cloud")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                Button("试听声音") {
                    previewVoice()
                    viewState.voiceStatus = "正在试听当前声音…"
                }
            }
            if !viewState.voiceStatus.isEmpty {
                Text(viewState.voiceStatus).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var voiceEngineOptions: some View {
        switch preferences.speechEngine {
        case .system:
            settingRow("系统音色", detail: "显示这台 Mac 已安装的中文声音") {
                Picker("", selection: $preferences.systemVoiceIdentifier) {
                    Text("自动选择中文声音").tag("")
                    ForEach(systemChineseVoices, id: \.identifier) { voice in
                        Text(voice.name).tag(voice.identifier)
                    }
                }
                .labelsHidden().frame(width: 220)
            }
        case .mimo:
            settingRow("MiMo 音色", detail: "中文优先推荐茉莉；也可切换男女声") {
                Picker("", selection: $preferences.mimoVoice) {
                    ForEach(MiMoVoice.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden().frame(width: 220)
            }
        case .openAI:
            VStack(alignment: .leading, spacing: 12) {
                settingRow("OpenAI 音色", detail: "Marin 与 Cedar 的自然度较高") {
                    Picker("", selection: $preferences.openAIVoice) {
                        ForEach(OpenAIVoice.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 220)
                }
                Divider()
                HStack {
                    SecureField(preferences.hasStoredTTSAPIKey ? "已保存；输入新密钥可替换" : "OpenAI API 密钥", text: $preferences.ttsAPIKeyDraft)
                        .textFieldStyle(.roundedBorder)
                    Button("保存") {
                        do {
                            try preferences.saveTTSAPIKey()
                            preferences.ttsAPIKeyDraft = ""
                            viewState.voiceStatus = "OpenAI 语音密钥已保存到本机配置"
                        } catch {
                            viewState.voiceStatus = "保存失败：\(error.localizedDescription)"
                        }
                    }
                }
            }
        case .localClone:
            VStack(alignment: .leading, spacing: 9) {
                Text("本地克隆服务地址").font(.system(size: 12, weight: .semibold, design: .rounded))
                TextField("http://127.0.0.1:9880/tts", text: $preferences.localCloneEndpoint)
                    .textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced))
                Text("接口已预留：POST JSON，返回 WAV。以后可接 CosyVoice 或 GPT-SoVITS 适配器。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var systemChineseVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("zh") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var generalPage: some View {
        VStack(spacing: 14) {
            settingsCard {
                settingRow("悬浮入口皮肤", detail: "切换后立即生效，点击和拖动方式不变") {
                    Picker("", selection: $preferences.floatingSkin) {
                        ForEach(FloatingSkin.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 210)
                }
                Divider()
                settingRow("默认悬浮位置", detail: "刘海下方距离视线最近；拖动后会记住新位置") {
                    Picker("", selection: $preferences.floatingPlacement) {
                        ForEach(FloatingPlacement.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 210)
                }
                Divider()
                Toggle(isOn: $preferences.showDockIcon) {
                    settingLabel("在程序坞显示", detail: "开启后可像普通 App 一样从 Dock 打开和切换")
                }
            }
            settingsCard {
                settingRow("语音回复", detail: "智能模式只读短结论与重要提醒") {
                    Picker("", selection: $preferences.voicePolicy) {
                        ForEach(VoiceReplyPolicy.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 150)
                }
                Divider()
                settingRow("回答长度", detail: "决定默认回答的展开程度") {
                    Picker("", selection: $preferences.answerLength) {
                        ForEach(AnswerLength.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                Divider()
                settingRow("播报速度", detail: "只影响语音回复") {
                    HStack(spacing: 8) {
                        Image(systemName: "tortoise.fill")
                        Slider(value: $preferences.speechRate, in: 0.38...0.58).frame(width: 130)
                        Image(systemName: "hare.fill")
                    }.foregroundStyle(.secondary)
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("自定义偏好").font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("不会覆盖安全规则").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    TextEditor(text: $preferences.customPrompt)
                        .font(.system(size: 12, design: .rounded))
                        .scrollContentBackground(.hidden)
                        .padding(7)
                        .frame(height: 110)
                        .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    Text("例如：称呼我为老板；先给结论；不要使用网络流行语。")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var modelsPage: some View {
        VStack(spacing: 14) {
            settingsCard {
                settingRow("服务商", detail: "预设覆盖主流云端和本地服务") {
                    Picker("", selection: $preferences.modelProvider) {
                        ForEach(ModelProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 210)
                }
                Divider()
                settingRow("模型名称", detail: "可以填写服务商支持的任意模型 ID") {
                    TextField("模型 ID", text: $preferences.modelName)
                        .textFieldStyle(.roundedBorder).frame(width: 240)
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text("接口地址").font(.system(size: 12, weight: .semibold, design: .rounded))
                    TextField("https://…/chat/completions", text: $preferences.endpoint)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
            }
            settingsCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("API 密钥").font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text(preferences.hasStoredAPIKey ? "本机配置中已有密钥；留空不会覆盖" : "密钥保存到仅当前用户可读的本机配置")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    HStack(spacing: 9) {
                        SecureField("输入新密钥", text: $preferences.apiKeyDraft)
                            .textFieldStyle(.roundedBorder)
                        Button("保存密钥") { saveKey() }
                        Button {
                            runConnectionTest()
                        } label: {
                            if viewState.isTesting { ProgressView().controlSize(.small) } else { Text("测试连接") }
                        }
                        .disabled(viewState.isTesting)
                    }
                    if !viewState.modelStatus.isEmpty {
                        Text(viewState.modelStatus).font(.system(size: 10, design: .rounded))
                            .foregroundStyle(viewState.modelStatus.contains("失败") ? .red : .secondary)
                    }
                }
            }
            Text("Claude 使用 Anthropic Messages API；其他预设使用各服务商的 OpenAI 兼容接口。")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private var memoryPage: some View {
        VStack(spacing: 14) {
            settingsCard {
                Toggle(isOn: $preferences.contextEnabled) {
                    settingLabel("启用对话上下文", detail: "让浮屿理解你刚才说过的内容")
                }
                Divider()
                settingRow("保留轮数", detail: "轮数越多，上下文消耗越高") {
                    HStack {
                        Slider(value: $preferences.contextTurns, in: 2...24, step: 1).frame(width: 150)
                        Text("\(Int(preferences.contextTurns)) 轮")
                            .font(.system(size: 11, design: .monospaced)).frame(width: 42)
                    }
                }
                .disabled(!preferences.contextEnabled)
            }
            settingsCard {
                Toggle(isOn: $preferences.persistentMemory) {
                    settingLabel("跨启动记忆", detail: "关闭应用后仍保留最近对话，仅存储在本机")
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("清除记忆").font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("删除当前上下文和本机长期记忆").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("清除…", role: .destructive) { viewState.showClearConfirmation = true }
                }
            }
            Label("长期记忆默认关闭。开启后会保存最近的对话文字，不保存录音。", systemImage: "lock.shield")
                .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    private var advancedPage: some View {
        VStack(spacing: 14) {
            settingsCard {
                settingRow("按住说话快捷键", detail: "按住开始聆听，松开后立即发送") {
                    Picker("", selection: $preferences.pushToTalkShortcut) {
                        ForEach(PushToTalkShortcut.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 200)
                }
                Divider()
                Toggle(isOn: $preferences.autoSubmit) {
                    settingLabel("停顿后自动发送", detail: "根据句尾和语气词判断你是否说完")
                }
                Divider()
                settingRow("说完等待时间", detail: "短暂停顿不会立即抢话；连接词会额外延长") {
                    HStack {
                        Slider(value: $preferences.endPauseSeconds, in: 1.2...5, step: 0.1).frame(width: 150)
                        Text(String(format: "%.1f 秒", preferences.endPauseSeconds))
                            .font(.system(size: 11, design: .monospaced)).frame(width: 48)
                    }
                }
                .disabled(!preferences.autoSubmit)
                Divider()
                Toggle(isOn: $preferences.continuousConversation) {
                    settingLabel("连续对话", detail: "浮屿回答完会自动继续聆听，无声时再收起")
                }
                Divider()
                settingRow("无声自动收起", detail: "没有识别到声音时自动关闭回复条") {
                    HStack {
                        Slider(value: $preferences.silenceTimeout, in: 3...12, step: 1).frame(width: 150)
                        Text("\(Int(preferences.silenceTimeout)) 秒")
                            .font(.system(size: 11, design: .monospaced)).frame(width: 40)
                    }
                }
            }
            settingsCard {
                settingRow("Siri 唤醒口令", detail: "快捷指令使用“打开 URL”，名称建议设为“开始说话”") {
                    Button("复制唤醒地址") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("fuyu://listen", forType: .string)
                    }
                }
                Divider()
                Toggle(isOn: $preferences.requireActionApproval) {
                    settingLabel(
                        "执行 Mac 操作前确认",
                        detail: preferences.requireActionApproval
                            ? "每次调用 Hermes / CUA 前显示单次批准卡"
                            : "已关闭：识别为操作指令后将直接执行，请仅在信任当前模型时使用"
                    )
                }
                .tint(preferences.requireActionApproval ? .accentColor : .orange)
                Divider()
                settingLabel("错误自动隐藏", detail: "普通错误提示 4 秒后收起，不再卡住回复条")
                Divider()
                settingLabel("本地模型", detail: "Ollama / LM Studio 默认连接 127.0.0.1，不需要上传密钥")
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) { content() }
            .padding(15)
            .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(0.06), lineWidth: 0.7) }
    }

    private func settingLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(detail).font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    private func settingRow<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            settingLabel(title, detail: detail)
            Spacer()
            content()
        }
    }

    private func saveKey() {
        do {
            try preferences.saveAPIKey()
            viewState.modelStatus = preferences.apiKeyDraft.isEmpty ? "密钥保持不变" : "密钥已保存到本机配置"
            preferences.apiKeyDraft = ""
        } catch {
            viewState.modelStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    private func runConnectionTest() {
        viewState.isTesting = true
        viewState.modelStatus = "正在连接…"
        Task {
            do {
                if !preferences.apiKeyDraft.isEmpty { try preferences.saveAPIKey() }
                let result = try await testConnection()
                viewState.modelStatus = "连接成功：\(result.prefix(48))"
                preferences.apiKeyDraft = ""
            } catch {
                viewState.modelStatus = "连接失败：\(error.localizedDescription)"
            }
            viewState.isTesting = false
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(
        preferences: AssistantPreferences,
        testConnection: @escaping () async throws -> String,
        clearMemory: @escaping () async throws -> Void,
        previewVoice: @escaping () -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "浮屿设置"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 680, height: 500)
        window.center()
        let viewState = SettingsViewState()
        window.contentView = NSHostingView(
            rootView: SettingsView(
                preferences: preferences,
                viewState: viewState,
                testConnection: testConnection,
                clearMemory: clearMemory,
                previewVoice: previewVoice
            )
        )
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
