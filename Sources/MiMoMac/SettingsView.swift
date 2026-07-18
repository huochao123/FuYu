import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "常规"
    case chat = "聊天"
    case voice = "声音"
    case models = "模型"
    case memory = "记忆"
    case persona = "人格"
    case remote = "远程"
    case advanced = "高级"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .chat: "bubble.left.and.bubble.right.fill"
        case .voice: "waveform"
        case .models: "cpu"
        case .memory: "brain.head.profile"
        case .persona: "person.crop.circle.badge.sparkles"
        case .remote: "antenna.radiowaves.left.and.right"
        case .advanced: "gearshape.2"
        }
    }
}

@MainActor
private final class SettingsViewState: ObservableObject {
    @Published var selection: SettingsSection = CommandLine.arguments.contains("--chat-demo") ? .chat : .general
    @Published var modelStatus = ""
    @Published var voiceStatus = ""
    @Published var personaStatus = ""
    @Published var chatDraft = ""
    @Published var newHabitDraft = ""
    @Published var chatStatus = ""
    @Published var tavernPreview: TavernImportPreview?
    @Published var isTesting = false
    @Published var showClearConfirmation = false
    @Published var hoveredSection: SettingsSection?
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: AssistantPreferences
    @ObservedObject fileprivate var viewState: SettingsViewState
    let testConnection: () async throws -> String
    let clearMemory: () async throws -> Void
    let previewVoice: () -> Void
    let sendText: (String) -> Void
    let runDiagnostics: () async -> String

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().opacity(0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    pageHeader
                    pageContent
                        .id(viewState.selection)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                .padding(26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 820, height: 600)
        .background(
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.025, green: 0.105, blue: 0.12), Color(red: 0.018, green: 0.045, blue: 0.07), .black.opacity(0.96)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(colors: [.cyan.opacity(0.13), .clear], center: .topLeading, startRadius: 10, endRadius: 480)
            }
        )
        .buttonStyle(SettingsGlassButtonStyle())
        .preferredColorScheme(.dark)
        .alert("清除对话与任务记忆？", isPresented: $viewState.showClearConfirmation) {
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
            Text("将删除即时上下文、当前任务和本机会话归档；永久习惯不会被删除，可在习惯区域单独管理。")
        }
        .sheet(item: $viewState.tavernPreview) { preview in
            TavernImportPreviewSheet(
                preview: preview,
                onApplyCharacter: applyImportedCharacter,
                onApplyPreset: applyImportedPreset,
                onCancel: { viewState.tavernPreview = nil }
            )
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
                    .buttonStyle(SettingsSidebarButtonStyle(selected: viewState.selection == section))
                    .onHover { hovering in
                        withAnimation(.easeOut(duration: 0.15)) {
                            viewState.hoveredSection = hovering ? section : (viewState.hoveredSection == section ? nil : viewState.hoveredSection)
                        }
                    }
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
        .frame(width: 190)
        .background(
            LinearGradient(
                colors: [.white.opacity(0.06), .cyan.opacity(0.025), .black.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .background(.ultraThinMaterial)
        .overlay(alignment: .trailing) {
            Rectangle().fill(.white.opacity(0.075)).frame(width: 0.7)
        }
    }

    private var pageHeader: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.cyan.opacity(0.1))
                Image(systemName: viewState.selection.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.cyan)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 4) {
                Text(viewState.selection.rawValue)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(pageSubtitle)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(.mint).frame(width: 6, height: 6)
                Text("设置即时生效")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(0.035), in: Capsule())
        }
    }

    private var pageSubtitle: String {
        switch viewState.selection {
        case .general: "决定浮屿怎么回答，以及哪些内容值得说出口"
        case .chat: "直接打字对话，并查看每次操作的真实结果"
        case .voice: "切换免费系统音色、MiMo 云端语音或本地克隆服务"
        case .models: "随时切换云端模型、本地模型或兼容服务"
        case .memory: "控制对话上下文和跨启动记忆的保存范围"
        case .persona: "定义浮屿是谁，以及它用什么方式陪你说话"
        case .remote: "通过飞书在外面直接与浮屿对话，并安全触发 Mac 任务"
        case .advanced: "调整自动提交、静默收起和语音交互节奏"
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch viewState.selection {
        case .general: generalPage
        case .chat: chatPage
        case .voice: voicePage
        case .models: modelsPage
        case .memory: memoryPage
        case .persona: personaPage
        case .remote: remotePage
        case .advanced: advancedPage
        }
    }

    private var chatPage: some View {
        VStack(spacing: 14) {
            settingsCard {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("文字聊天").font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("与语音共享上下文；文字输入默认不会朗读")
                            .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            viewState.chatStatus = "正在检查…"
                            let result = await runDiagnostics()
                            state.recordAssistantMessage("本机功能自检\n\(result)")
                            viewState.chatStatus = "自检完成"
                        }
                    } label: {
                        Label("本机自检", systemImage: "stethoscope")
                    }
                    .buttonStyle(SettingsGlassButtonStyle(tint: .cyan))
                }

                Divider()

                if state.conversation.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.system(size: 24)).foregroundStyle(.tertiary)
                        Text("还没有聊天记录")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("在下方输入文字，语音对话和 Mac 操作结果也会显示在这里。")
                            .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 285)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 9) {
                                ForEach(state.conversation) { item in
                                    settingsChatRow(item).id(item.id)
                                }
                            }
                        }
                        .frame(height: 285)
                        .onAppear {
                            if let last = state.conversation.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                        .onChange(of: state.conversation) { _, items in
                            if let last = items.last {
                                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                    }
                }

                Divider()

                HStack(spacing: 9) {
                    TextField("输入消息或 Mac 操作，例如：检查刚才的任务是否完成", text: $viewState.chatDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { submitTextChat() }
                    Button {
                        submitTextChat()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 26, height: 26)
                    }
                    .buttonStyle(SettingsGlassButtonStyle(tint: .cyan, prominent: true))
                    .disabled(viewState.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            HStack {
                Label("成功、失败、等待授权和 Hermes 返回结果都会进入同一份记录。", systemImage: "checkmark.message.fill")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                if !viewState.chatStatus.isEmpty {
                    Text(viewState.chatStatus).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func submitTextChat() {
        let value = viewState.chatDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        viewState.chatDraft = ""
        viewState.chatStatus = "已发送"
        sendText(value)
    }

    private func settingsChatRow(_ item: AppState.ConversationItem) -> some View {
        let tint: Color = switch item.kind {
        case .user: .cyan
        case .assistant: .purple
        case .action: .mint
        case .error: .red
        }
        let title: String = switch item.kind {
        case .user: "你"
        case .assistant: "浮屿"
        case .action: "操作"
        case .error: "失败"
        }
        return HStack(alignment: .top, spacing: 9) {
            Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(tint)
                    Spacer()
                    Text(AppState.displayTimestamp(for: item.createdAt))
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                }
                Text(item.text)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.86))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(tint.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var voicePage: some View {
        VStack(spacing: 14) {
            settingsCard {
                Toggle(isOn: $preferences.voiceInputEnabled) {
                    settingLabel("语音输入", detail: "只有点击说话或明确长按快捷键才会请求权限；打字与系统通知不会启动麦克风")
                }
                Divider()
                settingRow("按住说话快捷键", detail: "Fn 需明确长按约 0.3 秒，轻触不会启动收音") {
                    Picker("", selection: $preferences.pushToTalkShortcut) {
                        ForEach(PushToTalkShortcut.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 220)
                }
                .disabled(!preferences.voiceInputEnabled)
                Divider()
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
                Label("文字聊天与语音完全分离；云端声音只在需要播报时生成。", systemImage: "hand.raised.fill")
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

    private var personaPage: some View {
        VStack(spacing: 14) {
            settingsCard {
                Toggle(isOn: $preferences.personaEnabled) {
                    settingLabel("启用角色扮演", detail: "可以作为朋友、伴侣、家人、搭档或你创建的人物")
                }
                Divider()
                settingRow("人格方案", detail: preferences.personaPreset.summary) {
                    Picker("", selection: $preferences.personaPreset) {
                        ForEach(PersonaPreset.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 210)
                }
                .disabled(!preferences.personaEnabled)
                if preferences.personaEnabled, preferences.personaPreset == .wanNing {
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("绾宁 · 古来客", systemImage: "moon.stars.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("架空古代书香门第少女，因铜镜异变误入Mac。不了解现代世界，却能从浮屿的Mac知识中学习；表面毒舌、实际细心护短，最信任你但不会盲从危险命令。文字与语音共同生效，不改变工具能力。")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
                Divider()
                settingRow("关系预设", detail: "预设只提供关系方向，下面的内容仍可完全修改") {
                    Picker("", selection: $preferences.personaRelationship) {
                        ForEach(PersonaRelationship.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 180)
                }
                .disabled(!preferences.personaEnabled || preferences.personaPreset != .custom)
                Divider()
                settingRow("角色名称", detail: "留空时由对话和人物背景自然决定") {
                    TextField("例如：小屿", text: $preferences.personaName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                .disabled(!preferences.personaEnabled || preferences.personaPreset != .custom)
            }

            settingsCard {
                personaEditor(
                    "人物背景",
                    hint: "年龄、身份、经历、世界观、与用户如何认识……",
                    text: $preferences.personaBackground,
                    height: 105
                )
                Divider()
                personaEditor(
                    "性格特点",
                    hint: "例如：温柔、嘴硬心软、幽默、理性、会主动关心人",
                    text: $preferences.personaTraits,
                    height: 72
                )
                Divider()
                personaEditor(
                    "说话语气",
                    hint: "例如：自然口语、短句、偶尔开玩笑、称呼我为……",
                    text: $preferences.personaStyle,
                    height: 72
                )
            }
            .disabled(!preferences.personaEnabled || preferences.personaPreset != .custom)

            settingsCard {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.purple.opacity(0.12))
                        Image(systemName: "person.text.rectangle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SillyTavern / AI 酒馆兼容")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("导入前先预览识别结果，可选择替换或合并，不会直接覆盖当前人物。")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("本机解析")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Color.green.opacity(0.1), in: Capsule())
                }
                Divider()
                HStack(spacing: 9) {
                    Button { importTavernCharacter() } label: {
                        Label("角色卡", systemImage: "person.crop.square")
                    }
                    .buttonStyle(SettingsGlassButtonStyle(tint: .purple, prominent: true))
                    Button { importTavernPreset() } label: {
                        Label("提示词预设", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(SettingsGlassButtonStyle(tint: .purple))
                    Spacer()
                }
                Text("支持 Character Card V1/V2 JSON、带嵌入数据的 PNG，以及常见 Chat Completion 预设 JSON。")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.tertiary)
                if !viewState.personaStatus.isEmpty {
                    Text(viewState.personaStatus)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Text("人物内容由你定义；Mac 操作是否确认由高级设置决定。未实际执行的操作不会被描述为已完成。")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func personaEditor(
        _ title: String,
        hint: String,
        text: Binding<String>,
        height: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold, design: .rounded))
            TextEditor(text: text)
                .font(.system(size: 11, design: .rounded))
                .scrollContentBackground(.hidden)
                .padding(7)
                .frame(height: height)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            Text(hint).font(.system(size: 9, design: .rounded)).foregroundStyle(.tertiary)
        }
    }

    private func importTavernCharacter() {
        let panel = NSOpenPanel()
        panel.title = "导入酒馆角色卡"
        panel.allowedContentTypes = [.json, .png]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try TavernImportService.importCharacter(from: url)
            viewState.tavernPreview = .character(imported)
        } catch {
            viewState.personaStatus = "导入失败：\(error.localizedDescription)"
        }
    }

    private func importTavernPreset() {
        let panel = NSOpenPanel()
        panel.title = "导入酒馆提示词预设"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            viewState.tavernPreview = .preset(try TavernImportService.previewPreset(from: url))
        } catch {
            viewState.personaStatus = "导入失败：\(error.localizedDescription)"
        }
    }

    private func applyImportedCharacter(_ imported: ImportedTavernPersona, merge: Bool) {
        preferences.personaEnabled = true
        preferences.personaPreset = .custom
        preferences.personaRelationship = .custom
        if !imported.name.isEmpty { preferences.personaName = imported.name }
        if merge {
            preferences.personaBackground = mergedText(preferences.personaBackground, imported.background)
            preferences.personaTraits = mergedText(preferences.personaTraits, imported.traits)
            preferences.personaStyle = mergedText(preferences.personaStyle, imported.style)
        } else {
            preferences.personaBackground = imported.background
            preferences.personaTraits = imported.traits
            preferences.personaStyle = imported.style
        }
        viewState.personaStatus = "已应用角色卡：\(imported.displayName) · \(imported.fields.count) 个字段"
        viewState.tavernPreview = nil
    }

    private func applyImportedPreset(_ imported: ImportedTavernPreset, append: Bool) {
        preferences.customPrompt = append
            ? mergedText(preferences.customPrompt, imported.composedPrompt)
            : imported.composedPrompt
        viewState.personaStatus = "已应用预设：\(imported.name) · \(imported.sections.count) 个提示词段落"
        viewState.tavernPreview = nil
    }

    private func mergedText(_ current: String, _ imported: String) -> String {
        let old = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let new = imported.trimmingCharacters(in: .whitespacesAndNewlines)
        if old.isEmpty { return new }
        if new.isEmpty || old.contains(new) { return old }
        return old + "\n\n" + new
    }

    private var memoryPage: some View {
        VStack(spacing: 14) {
            memoryLayerOverview
            settingsCard {
                Toggle(isOn: $preferences.contextEnabled) {
                    settingLabel("启用连续对话", detail: "让“去吧、继续、昨天那个任务”按真实时间自然承接")
                }
                Divider()
                settingRow("即时原文", detail: "较早内容仍会从本机会话归档按需检索") {
                    HStack {
                        Slider(value: $preferences.contextTurns, in: 2...8, step: 1).frame(width: 150)
                        Text("\(Int(preferences.contextTurns)) 条")
                            .font(.system(size: 11, design: .monospaced)).frame(width: 42)
                    }
                }
                .disabled(!preferences.contextEnabled)
            }
            settingsCard {
                Toggle(isOn: $preferences.permanentHabitsEnabled) {
                    settingLabel("永久习惯记忆", detail: "参考 Hermes：只保存你明确要求记住的习惯")
                }
                Divider()
                HStack(spacing: 8) {
                    TextField("例如：回答尽量简短，操作前先说明风险", text: $viewState.newHabitDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addPermanentHabit() }
                    Button("记住") { addPermanentHabit() }
                        .disabled(viewState.newHabitDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if preferences.permanentHabits.isEmpty {
                    Text("暂无永久习惯。你也可以直接对浮屿说“记住……”")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(preferences.permanentHabits) { habit in
                        Divider()
                        HStack(spacing: 8) {
                            Text(habit.text)
                                .font(.system(size: 11, design: .rounded))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button(role: .destructive) { preferences.deleteHabit(id: habit.id) } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Divider()
                    HStack {
                        Text("共 \(preferences.permanentHabits.count) 条 · 每次对话都会提供给模型")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Spacer()
                        Button("全部清除", role: .destructive) { preferences.clearPermanentHabits() }
                    }
                }
            }
            settingsCard {
                Toggle(isOn: $preferences.persistentMemory) {
                    settingLabel("跨启动工作记忆", detail: "保留任务创建时间、最后更新时间、会话归档与按日期检索")
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("清除记忆").font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("删除对话、当前任务与会话归档；保留永久习惯").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("清除…", role: .destructive) { viewState.showClearConfirmation = true }
                }
                Divider()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Mac 本机经验").font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("仅保存真实操作结果、系统版本与时间；当前 \(MacExperienceStore.shared.count) 条")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("清除经验", role: .destructive) {
                        try? MacExperienceStore.shared.clear()
                        viewState.modelStatus = "Mac 本机经验已清除"
                    }
                }
            }
                Label("记录文件只保存在本机且不保存录音；回答时，命中的少量记忆会发送给你当前选择的模型。", systemImage: "clock.badge.checkmark")
                .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
        }
    }

    private var memoryLayerOverview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("浮屿分层记忆")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("不再只靠固定聊天轮数；时间轴贯穿每层记忆")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("本机存储", systemImage: "lock.fill")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.mint)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.mint.opacity(0.1), in: Capsule())
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                memoryLayerCard(
                    icon: "text.bubble.fill",
                    title: "即时对话",
                    detail: "承接代词、追问和短指令",
                    status: preferences.contextEnabled ? "最近 \(Int(preferences.contextTurns)) 条" : "已关闭",
                    color: .cyan
                )
                memoryLayerCard(
                    icon: "scope",
                    title: "当前任务",
                    detail: "保存目标、创建时间和最后更新",
                    status: preferences.persistentMemory ? "跨重启" : "仅本次",
                    color: .blue
                )
                memoryLayerCard(
                    icon: "archivebox.fill",
                    title: "会话归档",
                    detail: "按日期与相关性检索真实原话",
                    status: preferences.persistentMemory ? "自动归档" : "暂停调用",
                    color: .indigo
                )
                memoryLayerCard(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "永久习惯",
                    detail: "只保存你明确要求记住的偏好",
                    status: preferences.permanentHabitsEnabled ? "\(preferences.permanentHabits.count) 条" : "已关闭",
                    color: .mint
                )
                memoryLayerCard(
                    icon: "laptopcomputer.and.arrow.down",
                    title: "Mac 经验学习",
                    detail: "按系统版本复用真实成败经验",
                    status: "\(MacExperienceStore.shared.count) 条已验证",
                    color: .orange
                )
            }
        }
        .padding(14)
        .background(
            LinearGradient(colors: [.cyan.opacity(0.075), .blue.opacity(0.045), .black.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.8))
    }

    private func memoryLayerCard(
        icon: String,
        title: String,
        detail: String,
        status: String,
        color: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    Text(status)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(color)
                }
                Text(detail)
                    .font(.system(size: 9.5, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func addPermanentHabit() {
        let value = viewState.newHabitDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard preferences.rememberHabit(value) else { return }
        viewState.newHabitDraft = ""
    }

    private var advancedPage: some View {
        VStack(spacing: 14) {
            settingsCard {
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
                Toggle(isOn: $preferences.voiceInterruption) {
                    settingLabel("允许说话打断", detail: "浮屿朗读时，你一开口就停止播报并听取新指令")
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
                Toggle(isOn: $preferences.autonomousMaintenance) {
                    settingLabel("低频自主维护", detail: "每 12 小时进行一次只读本机体检；不调用模型，只有异常才提醒")
                }
                Divider()
                settingRow("Siri 唤醒口令", detail: "快捷指令使用“打开 URL”，名称建议设为“开始说话”") {
                    Button("复制唤醒地址") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("fuyu://listen", forType: .string)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            viewState.chatStatus = "唤醒地址已复制"
                        }
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
                Toggle(isOn: $preferences.voiceActionApproval) {
                    settingLabel("允许语音确认", detail: "授权卡出现后，说“允许执行”或“取消执行”")
                }
                .disabled(!preferences.requireActionApproval)
                Divider()
                settingLabel("错误自动隐藏", detail: "普通错误提示 4 秒后收起，不再卡住回复条")
                Divider()
                settingLabel("本地模型", detail: "Ollama / LM Studio 默认连接 127.0.0.1，不需要上传密钥")
            }
        }
    }

    private var remotePage: some View {
        VStack(spacing: 14) {
            settingsCard {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.blue.opacity(0.13))
                        Image(systemName: "message.badge.waveform.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.blue)
                    }
                    .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("飞书远程助手")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("使用企业自建应用的 WebSocket 长连接，无需公网服务器。")
                            .font(.system(size: 10, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $preferences.feishuEnabled)
                        .labelsHidden()
                        .disabled(preferences.feishuAppID.isEmpty || preferences.feishuAllowedSenderID.isEmpty || !preferences.hasStoredFeishuSecret)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("App ID")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    TextField("cli_xxxxxxxxxxxxxxxx", text: $preferences.feishuAppID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("允许的发送者 Open ID")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    TextField("ou_xxxxxxxxxxxxxxxx", text: $preferences.feishuAllowedSenderID)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    Text("只有这个飞书用户可以向浮屿下达指令；未配置时远程助手无法开启。")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("App Secret")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                    HStack(spacing: 9) {
                        SecureField(
                            preferences.hasStoredFeishuSecret ? "已安全保存；输入新值可替换" : "输入 App Secret",
                            text: $preferences.feishuSecretDraft
                        )
                        .textFieldStyle(.roundedBorder)
                        Button("保存连接") {
                            do {
                                try preferences.saveFeishuCredentials()
                                viewState.chatStatus = "飞书凭证已保存；现在可以启用远程助手"
                            } catch {
                                viewState.chatStatus = "保存失败：\(error.localizedDescription)"
                            }
                        }
                        .disabled(preferences.feishuAppID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if !viewState.chatStatus.isEmpty {
                    Text(viewState.chatStatus)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            settingsCard {
                Label("飞书应用需要开启机器人能力，并订阅“接收消息 v2.0”。", systemImage: "checkmark.shield.fill")
                    .font(.system(size: 11, design: .rounded))
                Divider()
                settingLabel("远程操作仍需确认", detail: "聊天回复可以直接返回；清理、移动文件和系统修改会停在 Mac 上等待确认。")
                Divider()
                settingLabel("建议使用独立飞书应用", detail: "不要与 Hermes 共用同一个 App ID，避免两条 WebSocket 连接随机分流消息。")
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) { content() }
            .padding(17)
            .background(
                LinearGradient(
                    colors: [.white.opacity(0.075), .cyan.opacity(0.025), .black.opacity(0.055)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.16), .cyan.opacity(0.08), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: .black.opacity(0.19), radius: 17, y: 8)
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

private struct SettingsGlassButtonStyle: ButtonStyle {
    var tint: Color = .cyan
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .frame(minHeight: 30)
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.78 : 0.94))
            .background(
                LinearGradient(
                    colors: [
                        .white.opacity(configuration.isPressed ? 0.13 : 0.085),
                        tint.opacity(configuration.isPressed ? 0.27 : (prominent ? 0.2 : 0.09)),
                        .black.opacity(0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(tint.opacity(prominent ? 0.4 : 0.19), lineWidth: 0.8)
            }
            .shadow(color: tint.opacity(prominent ? 0.17 : 0.07), radius: configuration.isPressed ? 5 : 10, y: configuration.isPressed ? 2 : 5)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .brightness(configuration.isPressed ? 0.07 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

private struct SettingsSidebarButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                (selected ? Color.cyan.opacity(0.13) : .white.opacity(configuration.isPressed ? 0.07 : 0)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.cyan.opacity(0.24) : .clear, lineWidth: 0.7)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.07 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct TavernImportPreviewSheet: View {
    let preview: TavernImportPreview
    let onApplyCharacter: (ImportedTavernPersona, Bool) -> Void
    let onApplyPreset: (ImportedTavernPreset, Bool) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch preview {
                    case let .character(character): characterPreview(character)
                    case let .preset(preset): presetPreview(preset)
                    }
                }
                .padding(22)
            }
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 620, height: 540)
        .background(
            LinearGradient(
                colors: [Color(NSColor.windowBackgroundColor), Color.purple.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(Color.purple.opacity(0.13))
                Image(systemName: previewIcon)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(previewTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text("检查识别结果，确认后才会修改浮屿设置")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("仅在本机读取", systemImage: "lock.fill")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(Color.green.opacity(0.1), in: Capsule())
        }
        .padding(18)
    }

    @ViewBuilder
    private func characterPreview(_ character: ImportedTavernPersona) -> some View {
        HStack(spacing: 14) {
            if character.sourceURL.pathExtension.lowercased() == "png",
               let image = NSImage(contentsOf: character.sourceURL) {
                Image(nsImage: image)
                    .resizable().scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.16)) }
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.purple.opacity(0.1))
                    Image(systemName: "person.crop.square.fill").font(.system(size: 30)).foregroundStyle(.purple)
                }
                .frame(width: 76, height: 76)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(character.displayName)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(character.format)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.purple)
                Text("识别到 \(character.fields.count) 个可用字段")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
        }

        previewFields(character.fields)

        if !character.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Label("兼容性提示", systemImage: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange)
                ForEach(character.warnings, id: \.self) { warning in
                    Text("• \(warning)")
                        .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
                }
            }
            .padding(13)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        }

        Label("应用时可选择替换当前角色，或保留当前设定并合并不重复内容。", systemImage: "arrow.triangle.merge")
            .font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func presetPreview(_ preset: ImportedTavernPreset) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(preset.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Chat Completion 提示词预设")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.purple)
                Text("识别到 \(preset.sections.count) 个提示词段落 · 共 \(preset.composedPrompt.count) 个字符")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(.secondary)
            }
            Spacer()
        }

        previewFields(preset.sections)

        Text("应用时可选择替换或追加到“常规 → 自定义偏好”；不会修改模型地址、密钥或 Mac 操作权限。")
            .font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
    }

    private func previewFields(_ fields: [TavernImportField]) -> some View {
        VStack(spacing: 8) {
            ForEach(fields) { field in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(field.title)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(field.text.count) 字")
                            .font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                    Text(field.text)
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("取消", action: onCancel).keyboardShortcut(.cancelAction)
            Spacer()
            switch preview {
            case let .character(character):
                Button("合并到当前角色") {
                    onApplyCharacter(character, true)
                }
                .buttonStyle(.bordered)
                Button("替换并启用") {
                    onApplyCharacter(character, false)
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            case let .preset(preset):
                Button("追加到现有偏好") {
                    onApplyPreset(preset, true)
                }
                .buttonStyle(.bordered)
                Button("替换并应用") {
                    onApplyPreset(preset, false)
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    private var previewTitle: String {
        switch preview {
        case .character: "预览角色卡"
        case .preset: "预览提示词预设"
        }
    }

    private var previewIcon: String {
        switch preview {
        case .character: "person.crop.square.fill"
        case .preset: "text.badge.checkmark"
        }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(
        state: AppState,
        preferences: AssistantPreferences,
        testConnection: @escaping () async throws -> String,
        clearMemory: @escaping () async throws -> Void,
        previewVoice: @escaping () -> Void,
        sendText: @escaping (String) -> Void,
        runDiagnostics: @escaping () async -> String
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "浮屿设置"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 540)
        window.center()
        let viewState = SettingsViewState()
        window.contentView = NSHostingView(
            rootView: SettingsView(
                state: state,
                preferences: preferences,
                viewState: viewState,
                testConnection: testConnection,
                clearMemory: clearMemory,
                previewVoice: previewVoice,
                sendText: sendText,
                runDiagnostics: runDiagnostics
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
