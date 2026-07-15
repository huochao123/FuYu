import Foundation

enum VoiceReplyPolicy: String, CaseIterable, Identifiable, Sendable {
    case smart, always, never
    var id: String { rawValue }
    var title: String {
        switch self {
        case .smart: "智能播报"
        case .always: "全部播报"
        case .never: "仅显示文字"
        }
    }
}

enum RecognitionEngine: String, CaseIterable, Identifiable, Sendable {
    case appleLocal, appleAutomatic, mimoHybrid
    var id: String { rawValue }
    var title: String {
        switch self {
        case .appleLocal: "Apple 本地识别"
        case .appleAutomatic: "Apple 自动识别"
        case .mimoHybrid: "MiMo 在线校正（推荐）"
        }
    }
}

enum FloatingSkin: String, CaseIterable, Identifiable, Sendable {
    case particleFrame, particleBare, classicOrb, auroraFlow, orbitField, crystalPulse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .particleFrame: "粒子声场（推荐）"
        case .particleBare: "无框点波"
        case .classicOrb: "经典圆球"
        case .auroraFlow: "极光流体"
        case .orbitField: "星轨共振"
        case .crystalPulse: "晶格脉冲"
        }
    }
}

enum FloatingPlacement: String, CaseIterable, Identifiable, Sendable {
    case notch, bottomRight, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notch: "刘海下方（推荐）"
        case .bottomRight: "右下角"
        case .custom: "自由拖动位置"
        }
    }
}

enum PersonaRelationship: String, CaseIterable, Identifiable, Sendable {
    case friend, partner, family, colleague, mentor, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .friend: "亲密朋友"
        case .partner: "伴侣"
        case .family: "家人"
        case .colleague: "工作搭档"
        case .mentor: "导师"
        case .custom: "自定义关系"
        }
    }
}

enum PushToTalkShortcut: String, CaseIterable, Identifiable, Sendable {
    case fnHold, optionSpace, optionShiftSpace, controlSpace, commandShiftSpace, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fnHold: "长按 Fn / 地球键"
        case .optionSpace: "⌥ Space"
        case .optionShiftSpace: "⌥⇧ Space"
        case .controlSpace: "⌃ Space"
        case .commandShiftSpace: "⌘⇧ Space"
        case .off: "关闭快捷键"
        }
    }
}

enum SpeechEngine: String, CaseIterable, Identifiable, Sendable {
    case system, mimo, openAI, localClone
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "系统语音（免费离线）"
        case .mimo: "MiMo 云端语音（推荐）"
        case .openAI: "OpenAI 自然语音"
        case .localClone: "本地声音克隆（预留）"
        }
    }
}

enum MiMoVoice: String, CaseIterable, Identifiable, Sendable {
    case bingtang = "冰糖", moli = "茉莉", soda = "苏打", birch = "白桦"
    case mia = "Mia", chloe = "Chloe", milo = "Milo", dean = "Dean"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .bingtang: "冰糖 · 活泼少女"
        case .moli: "茉莉 · 知性女声（推荐）"
        case .soda: "苏打 · 阳光少年"
        case .birch: "白桦 · 成熟男声"
        case .mia: "Mia · 英文活泼女声"
        case .chloe: "Chloe · 英文甜美女声"
        case .milo: "Milo · 英文阳光男声"
        case .dean: "Dean · 英文沉稳男声"
        }
    }
}

enum OpenAIVoice: String, CaseIterable, Identifiable, Sendable {
    case marin, cedar, coral, shimmer, nova, alloy, ash, ballad, echo, fable, onyx, sage, verse
    var id: String { rawValue }
    var title: String {
        switch self {
        case .marin: "Marin · 自然清晰（推荐）"
        case .cedar: "Cedar · 温暖沉稳（推荐）"
        case .coral: "Coral · 明亮亲切"
        case .shimmer: "Shimmer · 轻柔"
        case .nova: "Nova · 活泼"
        case .alloy: "Alloy · 中性"
        case .ash: "Ash · 干净利落"
        case .ballad: "Ballad · 柔和叙事"
        case .echo: "Echo · 沉稳"
        case .fable: "Fable · 表现力强"
        case .onyx: "Onyx · 低沉"
        case .sage: "Sage · 平静"
        case .verse: "Verse · 自然对话"
        }
    }
}

enum AnswerLength: String, CaseIterable, Identifiable, Sendable {
    case concise, natural, detailed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .concise: "极简"
        case .natural: "自然"
        case .detailed: "详细"
        }
    }

    var prompt: String {
        switch self {
        case .concise: "默认先给结论，能一句话说清就不要展开；除非用户要求详细说明。"
        case .natural: "回答自然简洁，先给结论，需要时补充少量关键细节。"
        case .detailed: "在结论后提供必要背景、步骤与注意事项，但避免重复。"
        }
    }
}

enum ModelProvider: String, CaseIterable, Identifiable, Sendable {
    case mimo, openAI, anthropic, gemini, deepseek, qwen, kimi, zhipu, ollama, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mimo: "Xiaomi MiMo"
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic Claude"
        case .gemini: "Google Gemini"
        case .deepseek: "DeepSeek"
        case .qwen: "通义千问"
        case .kimi: "Kimi"
        case .zhipu: "智谱 GLM"
        case .ollama: "Ollama / LM Studio"
        case .custom: "自定义兼容服务"
        }
    }

    var badge: String {
        switch self {
        case .mimo: "MiMo"
        case .openAI: "OpenAI"
        case .anthropic: "Claude"
        case .gemini: "Gemini"
        case .deepseek: "DeepSeek"
        case .qwen: "Qwen"
        case .kimi: "Kimi"
        case .zhipu: "GLM"
        case .ollama: "Local"
        case .custom: "Custom"
        }
    }

    var defaultModel: String {
        switch self {
        case .mimo: "mimo-v2.5"
        case .openAI: "gpt-4.1-mini"
        case .anthropic: "claude-sonnet-4-5"
        case .gemini: "gemini-3.5-flash"
        case .deepseek: "deepseek-v4-flash"
        case .qwen: "qwen-plus"
        case .kimi: "kimi-k2.5"
        case .zhipu: "glm-4.5-flash"
        case .ollama: "qwen3:8b"
        case .custom: ""
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .mimo: "https://token-plan-cn.xiaomimimo.com/v1/chat/completions"
        case .openAI: "https://api.openai.com/v1/chat/completions"
        case .anthropic: "https://api.anthropic.com/v1/messages"
        case .gemini: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .deepseek: "https://api.deepseek.com/chat/completions"
        case .qwen: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions"
        case .kimi: "https://api.moonshot.cn/v1/chat/completions"
        case .zhipu: "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        case .ollama: "http://127.0.0.1:11434/v1/chat/completions"
        case .custom: ""
        }
    }

    var keychainService: String { "fuyu-model-key-\(rawValue)" }
    var usesAnthropicMessages: Bool { self == .anthropic }
    var requiresAPIKey: Bool { self != .ollama && self != .custom }
}

struct ModelRuntimeConfiguration: Sendable {
    let provider: ModelProvider
    let model: String
    let endpoint: String
    var keychainService: String { provider == .mimo ? "codex-mimo-api-key" : provider.keychainService }
}

struct AssistantProfile: Sendable {
    let answerLength: AnswerLength
    let customPrompt: String
    let model: ModelRuntimeConfiguration
    let contextEnabled: Bool
    let contextTurns: Int
    let persistentMemory: Bool
    let permanentHabitPrompt: String
    let personaPrompt: String
}

struct PermanentHabit: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var text: String
    var updatedAt: Date
}

enum PermanentMemoryCommand: Equatable, Sendable {
    case remember(String)
    case forget(String)
    case list
}

@MainActor
final class AssistantPreferences: ObservableObject {
    private enum Key {
        static let voicePolicy = "assistantVoiceReplyPolicy"
        static let answerLength = "assistantAnswerLength"
        static let speechRate = "assistantSpeechRate"
        static let customPrompt = "assistantCustomPrompt"
        static let modelProvider = "assistantModelProvider"
        static let contextEnabled = "assistantContextEnabled"
        static let contextTurns = "assistantContextTurns"
        static let persistentMemory = "assistantPersistentMemory"
        static let permanentHabitsEnabled = "assistantPermanentHabitsEnabled"
        static let autoSubmit = "assistantAutoSubmit"
        static let silenceTimeout = "assistantSilenceTimeout"
        static let speechEngine = "assistantSpeechEngine"
        static let systemVoiceIdentifier = "assistantSystemVoiceIdentifier"
        static let openAIVoice = "assistantOpenAIVoice"
        static let mimoVoice = "assistantMiMoVoice"
        static let clonedVoiceID = "assistantClonedVoiceID"
        static let speechInstructions = "assistantSpeechInstructions"
        static let speechFallback = "assistantSpeechFallback"
        static let localCloneEndpoint = "assistantLocalCloneEndpoint"
        static let recognitionEngine = "assistantRecognitionEngine"
        static let endPauseSeconds = "assistantEndPauseSeconds"
        static let continuousConversation = "assistantContinuousConversation"
        static let floatingSkin = "assistantFloatingSkin"
        static let showDockIcon = "assistantShowDockIcon"
        static let pushToTalkShortcut = "assistantPushToTalkShortcut"
        static let floatingPlacement = "assistantFloatingPlacement"
        static let requireActionApproval = "assistantRequireActionApproval"
        static let voiceActionApproval = "assistantVoiceActionApproval"
        static let personaEnabled = "assistantPersonaEnabled"
        static let personaRelationship = "assistantPersonaRelationship"
        static let personaName = "assistantPersonaName"
        static let personaBackground = "assistantPersonaBackground"
        static let personaTraits = "assistantPersonaTraits"
        static let personaStyle = "assistantPersonaStyle"
    }

    @Published var voicePolicy: VoiceReplyPolicy { didSet { defaults.set(voicePolicy.rawValue, forKey: Key.voicePolicy) } }
    @Published var answerLength: AnswerLength { didSet { defaults.set(answerLength.rawValue, forKey: Key.answerLength) } }
    @Published var speechRate: Double { didSet { defaults.set(speechRate, forKey: Key.speechRate) } }
    @Published var customPrompt: String { didSet { defaults.set(String(customPrompt.prefix(8000)), forKey: Key.customPrompt) } }
    @Published var modelProvider: ModelProvider {
        didSet {
            defaults.set(modelProvider.rawValue, forKey: Key.modelProvider)
            guard ready else { return }
            loadProviderFields()
        }
    }
    @Published var modelName: String { didSet { if ready { defaults.set(modelName, forKey: modelKey("model")) } } }
    @Published var endpoint: String { didSet { if ready { defaults.set(endpoint, forKey: modelKey("endpoint")) } } }
    @Published var apiKeyDraft = ""
    @Published var contextEnabled: Bool { didSet { defaults.set(contextEnabled, forKey: Key.contextEnabled) } }
    @Published var contextTurns: Double { didSet { defaults.set(contextTurns, forKey: Key.contextTurns) } }
    @Published var persistentMemory: Bool { didSet { defaults.set(persistentMemory, forKey: Key.persistentMemory) } }
    @Published var permanentHabitsEnabled: Bool { didSet { defaults.set(permanentHabitsEnabled, forKey: Key.permanentHabitsEnabled) } }
    @Published private(set) var permanentHabits: [PermanentHabit]
    @Published var autoSubmit: Bool { didSet { defaults.set(autoSubmit, forKey: Key.autoSubmit) } }
    @Published var silenceTimeout: Double { didSet { defaults.set(silenceTimeout, forKey: Key.silenceTimeout) } }
    @Published var speechEngine: SpeechEngine { didSet { defaults.set(speechEngine.rawValue, forKey: Key.speechEngine) } }
    @Published var systemVoiceIdentifier: String { didSet { defaults.set(systemVoiceIdentifier, forKey: Key.systemVoiceIdentifier) } }
    @Published var openAIVoice: OpenAIVoice { didSet { defaults.set(openAIVoice.rawValue, forKey: Key.openAIVoice) } }
    @Published var mimoVoice: MiMoVoice { didSet { defaults.set(mimoVoice.rawValue, forKey: Key.mimoVoice) } }
    @Published var clonedVoiceID: String { didSet { defaults.set(clonedVoiceID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.clonedVoiceID) } }
    @Published var speechInstructions: String { didSet { defaults.set(String(speechInstructions.prefix(500)), forKey: Key.speechInstructions) } }
    @Published var speechFallback: Bool { didSet { defaults.set(speechFallback, forKey: Key.speechFallback) } }
    @Published var localCloneEndpoint: String { didSet { defaults.set(localCloneEndpoint, forKey: Key.localCloneEndpoint) } }
    @Published var recognitionEngine: RecognitionEngine { didSet { defaults.set(recognitionEngine.rawValue, forKey: Key.recognitionEngine) } }
    @Published var endPauseSeconds: Double { didSet { defaults.set(endPauseSeconds, forKey: Key.endPauseSeconds) } }
    @Published var continuousConversation: Bool { didSet { defaults.set(continuousConversation, forKey: Key.continuousConversation) } }
    @Published var floatingSkin: FloatingSkin { didSet { defaults.set(floatingSkin.rawValue, forKey: Key.floatingSkin) } }
    @Published var showDockIcon: Bool { didSet { defaults.set(showDockIcon, forKey: Key.showDockIcon) } }
    @Published var pushToTalkShortcut: PushToTalkShortcut { didSet { defaults.set(pushToTalkShortcut.rawValue, forKey: Key.pushToTalkShortcut) } }
    @Published var floatingPlacement: FloatingPlacement { didSet { defaults.set(floatingPlacement.rawValue, forKey: Key.floatingPlacement) } }
    @Published var requireActionApproval: Bool { didSet { defaults.set(requireActionApproval, forKey: Key.requireActionApproval) } }
    @Published var voiceActionApproval: Bool { didSet { defaults.set(voiceActionApproval, forKey: Key.voiceActionApproval) } }
    @Published var personaEnabled: Bool { didSet { defaults.set(personaEnabled, forKey: Key.personaEnabled) } }
    @Published var personaRelationship: PersonaRelationship { didSet { defaults.set(personaRelationship.rawValue, forKey: Key.personaRelationship) } }
    @Published var personaName: String { didSet { defaults.set(String(personaName.prefix(40)), forKey: Key.personaName) } }
    @Published var personaBackground: String { didSet { defaults.set(String(personaBackground.prefix(4000)), forKey: Key.personaBackground) } }
    @Published var personaTraits: String { didSet { defaults.set(String(personaTraits.prefix(1200)), forKey: Key.personaTraits) } }
    @Published var personaStyle: String { didSet { defaults.set(String(personaStyle.prefix(2400)), forKey: Key.personaStyle) } }
    @Published var ttsAPIKeyDraft = ""

    private let defaults: UserDefaults
    private let habitStoreURL: URL
    private var ready = false

    init(defaults: UserDefaults = .standard, habitStoreURL: URL? = nil) {
        self.defaults = defaults
        self.habitStoreURL = habitStoreURL ?? Self.defaultHabitStoreURL
        permanentHabits = Self.loadHabits(from: habitStoreURL ?? Self.defaultHabitStoreURL)
        voicePolicy = VoiceReplyPolicy(rawValue: defaults.string(forKey: Key.voicePolicy) ?? "smart") ?? .smart
        answerLength = AnswerLength(rawValue: defaults.string(forKey: Key.answerLength) ?? "concise") ?? .concise
        speechRate = min(max(defaults.object(forKey: Key.speechRate) as? Double ?? 0.49, 0.38), 0.58)
        customPrompt = defaults.string(forKey: Key.customPrompt) ?? ""
        modelProvider = ModelProvider(rawValue: defaults.string(forKey: Key.modelProvider) ?? "mimo") ?? .mimo
        modelName = ""
        endpoint = ""
        contextEnabled = defaults.object(forKey: Key.contextEnabled) as? Bool ?? true
        contextTurns = min(max(defaults.object(forKey: Key.contextTurns) as? Double ?? 8, 2), 24)
        persistentMemory = defaults.object(forKey: Key.persistentMemory) as? Bool ?? false
        permanentHabitsEnabled = defaults.object(forKey: Key.permanentHabitsEnabled) as? Bool ?? true
        autoSubmit = defaults.object(forKey: Key.autoSubmit) as? Bool ?? true
        silenceTimeout = min(max(defaults.object(forKey: Key.silenceTimeout) as? Double ?? 5, 3), 12)
        let defaultSpeechEngine = KeychainStore.password(service: "codex-mimo-api-key")?.isEmpty == false ? "mimo" : "system"
        speechEngine = SpeechEngine(rawValue: defaults.string(forKey: Key.speechEngine) ?? defaultSpeechEngine) ?? .system
        systemVoiceIdentifier = defaults.string(forKey: Key.systemVoiceIdentifier) ?? ""
        openAIVoice = OpenAIVoice(rawValue: defaults.string(forKey: Key.openAIVoice) ?? "marin") ?? .marin
        mimoVoice = MiMoVoice(rawValue: defaults.string(forKey: Key.mimoVoice) ?? "冰糖") ?? .bingtang
        clonedVoiceID = defaults.string(forKey: Key.clonedVoiceID) ?? ""
        speechInstructions = defaults.string(forKey: Key.speechInstructions) ?? "用自然、温柔、有亲和力的中文说话，像真实的语音助手，不要播音腔。"
        speechFallback = defaults.object(forKey: Key.speechFallback) as? Bool ?? true
        localCloneEndpoint = defaults.string(forKey: Key.localCloneEndpoint) ?? "http://127.0.0.1:9880/tts"
        recognitionEngine = RecognitionEngine(rawValue: defaults.string(forKey: Key.recognitionEngine) ?? "mimoHybrid") ?? .mimoHybrid
        endPauseSeconds = min(max(defaults.object(forKey: Key.endPauseSeconds) as? Double ?? 2.3, 1.2), 5)
        continuousConversation = defaults.object(forKey: Key.continuousConversation) as? Bool ?? false
        floatingSkin = FloatingSkin(rawValue: defaults.string(forKey: Key.floatingSkin) ?? "particleFrame") ?? .particleFrame
        showDockIcon = defaults.object(forKey: Key.showDockIcon) as? Bool ?? false
        pushToTalkShortcut = PushToTalkShortcut(rawValue: defaults.string(forKey: Key.pushToTalkShortcut) ?? "fnHold") ?? .fnHold
        floatingPlacement = FloatingPlacement(rawValue: defaults.string(forKey: Key.floatingPlacement) ?? "notch") ?? .notch
        requireActionApproval = defaults.object(forKey: Key.requireActionApproval) as? Bool ?? true
        voiceActionApproval = defaults.object(forKey: Key.voiceActionApproval) as? Bool ?? true
        personaEnabled = defaults.object(forKey: Key.personaEnabled) as? Bool ?? false
        personaRelationship = PersonaRelationship(rawValue: defaults.string(forKey: Key.personaRelationship) ?? "friend") ?? .friend
        personaName = defaults.string(forKey: Key.personaName) ?? ""
        personaBackground = defaults.string(forKey: Key.personaBackground) ?? ""
        personaTraits = defaults.string(forKey: Key.personaTraits) ?? "温柔、真诚、有幽默感，尊重边界"
        personaStyle = defaults.string(forKey: Key.personaStyle) ?? "自然口语化，不说教，像真实的人一样回应"
        ready = true
        loadProviderFields()
    }

    var profile: AssistantProfile {
        AssistantProfile(
            answerLength: answerLength,
            customPrompt: String(customPrompt.prefix(8000)),
            model: ModelRuntimeConfiguration(provider: modelProvider, model: modelName, endpoint: endpoint),
            contextEnabled: contextEnabled,
            contextTurns: Int(contextTurns.rounded()),
            persistentMemory: persistentMemory,
            permanentHabitPrompt: permanentHabitPrompt,
            personaPrompt: personaPrompt
        )
    }

    var permanentHabitPrompt: String {
        guard permanentHabitsEnabled else { return "永久习惯记忆已关闭。" }
        guard !permanentHabits.isEmpty else { return "暂无用户明确保存的永久习惯。" }
        return permanentHabits.enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
    }

    @discardableResult
    func rememberHabit(_ rawText: String) -> Bool {
        let text = Self.normalizedHabit(rawText)
        guard !text.isEmpty else { return false }
        if let index = permanentHabits.firstIndex(where: { $0.text.localizedCaseInsensitiveCompare(text) == .orderedSame }) {
            permanentHabits[index].updatedAt = Date()
        } else {
            permanentHabits.append(.init(id: UUID(), text: text, updatedAt: Date()))
        }
        trimHabitsToLimits()
        persistHabits()
        return true
    }

    func updateHabit(id: UUID, text rawText: String) {
        let text = Self.normalizedHabit(rawText)
        guard let index = permanentHabits.firstIndex(where: { $0.id == id }) else { return }
        if text.isEmpty {
            permanentHabits.remove(at: index)
        } else {
            permanentHabits[index].text = text
            permanentHabits[index].updatedAt = Date()
        }
        trimHabitsToLimits()
        persistHabits()
    }

    func deleteHabit(id: UUID) {
        permanentHabits.removeAll { $0.id == id }
        persistHabits()
    }

    @discardableResult
    func forgetHabits(matching rawText: String) -> Int {
        let query = Self.normalizedHabit(rawText).lowercased()
        guard !query.isEmpty else { return 0 }
        let oldCount = permanentHabits.count
        permanentHabits.removeAll {
            let value = $0.text.lowercased()
            return value.contains(query) || query.contains(value)
        }
        if oldCount != permanentHabits.count { persistHabits() }
        return oldCount - permanentHabits.count
    }

    func clearPermanentHabits() {
        permanentHabits.removeAll()
        persistHabits()
    }

    static func memoryCommand(for rawText: String) -> PermanentMemoryCommand? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = text.replacingOccurrences(of: " ", with: "")
        let listCommands = ["你记住了什么", "你记得我什么", "查看永久记忆", "查看我的习惯", "列出永久记忆"]
        if listCommands.contains(where: compact.contains) { return .list }

        let rememberPrefixes = ["请记住：", "请记住:", "帮我记住：", "帮我记住:", "记住：", "记住:", "请记住", "帮我记住", "记住"]
        if let prefix = rememberPrefixes.first(where: text.hasPrefix) {
            let value = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : .remember(value)
        }
        let forgetPrefixes = ["请忘记：", "请忘记:", "删除记忆：", "删除记忆:", "忘记：", "忘记:", "请忘记", "删除记忆", "忘记"]
        if let prefix = forgetPrefixes.first(where: text.hasPrefix) {
            let value = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : .forget(value)
        }
        return nil
    }

    var personaPrompt: String {
        guard personaEnabled else {
            return """
            默认人格是一位温柔、认真、可靠的女性秘书助理。
            说话自然亲切、有分寸，不使用生硬的客服腔；办事前先理解目标并确认关键参数，执行后只汇报真实结果。
            遇到技术日志、英文参数或长编号时先理解含义，再用自然中文说明，不原样朗读。
            """
        }
        return """
        已启用角色扮演。
        角色名称：\(personaName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "由上下文自然决定" : personaName)
        与用户关系：\(personaRelationship.title)
        人物背景：\(personaBackground.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "无额外背景" : String(personaBackground.prefix(4000)))
        性格特点：\(String(personaTraits.prefix(1200)))
        说话方式、开场与示例：\(String(personaStyle.prefix(2400)))
        保持角色连贯。人物背景、虚构经历、关系和表达方式以用户设定为准。
        只有一个工具事实约束：没有收到真实执行结果时，不得声称已经完成 Mac 操作。
        """
    }

    var hasStoredAPIKey: Bool {
        KeychainStore.password(service: profile.model.keychainService)?.isEmpty == false
    }

    var mimoEndpoint: String {
        defaults.string(forKey: "assistantModel.mimo.endpoint") ?? ModelProvider.mimo.defaultEndpoint
    }

    static let ttsKeychainService = "fuyu-tts-key-openai"

    var hasStoredTTSAPIKey: Bool {
        ttsAPIKey?.isEmpty == false
    }

    var ttsAPIKey: String? {
        KeychainStore.password(service: Self.ttsKeychainService)
            ?? KeychainStore.password(service: ModelProvider.openAI.keychainService)
    }

    func saveAPIKey() throws {
        let value = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            try KeychainStore.delete(service: profile.model.keychainService)
        } else {
            try KeychainStore.set(value, service: profile.model.keychainService)
        }
    }

    func saveTTSAPIKey() throws {
        let value = ttsAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            try KeychainStore.set(value, service: Self.ttsKeychainService)
        }
    }

    func spokenText(fullText: String, suggested: String?) -> String? {
        switch voicePolicy {
        case .never: return nil
        case .always:
            return speechFriendlyText(fullText, allowSummary: false)
        case .smart:
            let candidate = suggested.flatMap { speechFriendlyText($0, allowSummary: false) }
            if let candidate, !candidate.isEmpty, isSuitableForSpeech(candidate) { return candidate }
            let cleaned = speechFriendlyText(fullText, allowSummary: true)
            if let cleaned, isSuitableForSpeech(cleaned) { return cleaned }
            return smartSpeechSummary(cleaned ?? fullText)
        }
    }

    private func speechFriendlyText(_ text: String, allowSummary: Bool) -> String? {
        if text.contains("实际执行失败") || text.contains("执行失败") {
            return "任务没有完成，具体原因我放在屏幕上了。"
        }
        var value = text
            .replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "https?://\\S+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[A-Za-z][A-Za-z0-9_-]{7,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\b\\d{7,}\\b", with: " ", options: .regularExpression)
        let blockedLabels = ["trace", "rpcuuid", "uuid", "会议id", "加入链接", "追踪信息", "参数", "token"]
        value = value
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { line in
                let lower = line.lowercased()
                return !blockedLabels.contains(where: lower.contains)
            }
            .joined(separator: "，")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("http://") || text.contains("https://") {
            let linkOnlyPhrases = ["详情见", "查看链接", "请看链接", "网址", "链接"]
            if linkOnlyPhrases.contains(value) { return nil }
        }
        let chineseCount = value.unicodeScalars.filter { (0x4E00...0x9FFF).contains(Int($0.value)) }.count
        let latinCount = value.unicodeScalars.filter { CharacterSet.letters.contains($0) && !(0x4E00...0x9FFF).contains(Int($0.value)) }.count
        if value.isEmpty || (latinCount > chineseCount && latinCount > 6) {
            if text.contains("创建成功") {
                return "已经创建好了，详细信息我放在屏幕上了。"
            }
            if text.contains("成功") || text.contains("完成") {
                return "任务已经完成，详细信息我放在屏幕上了。"
            }
            return "我收到了一段技术信息，已经整理在屏幕上了。"
        }
        if allowSummary, value.count > 52 { return smartSpeechSummary(value) }
        return value
    }

    private func smartSpeechSummary(_ text: String) -> String? {
        let withoutCode = text.replacingOccurrences(
            of: "```[\\s\\S]*?```",
            with: " ",
            options: .regularExpression
        )
        let withoutLinks = withoutCode.replacingOccurrences(
            of: "https?://\\S+",
            with: " ",
            options: .regularExpression
        )
        let cleanedLines = withoutLinks
            .split(whereSeparator: \.isNewline)
            .map { line in
                String(line)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#*-•>|` "))
            }
            .filter { !$0.isEmpty }
        guard !cleanedLines.isEmpty else { return nil }
        let joined = cleanedLines.joined(separator: "，")
        let firstSentence = joined.split(whereSeparator: { "。！？!?".contains($0) }).first.map(String.init) ?? joined
        let value = firstSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if text.contains("http://") || text.contains("https://") {
            let linkOnlyPhrases = ["详情见", "查看链接", "请看链接", "网址", "链接"]
            if linkOnlyPhrases.contains(value) { return nil }
        }
        return value.count <= 44 ? value : String(value.prefix(42)) + "……"
    }

    private func modelKey(_ field: String) -> String { "assistantModel.\(modelProvider.rawValue).\(field)" }

    private func loadProviderFields() {
        modelName = defaults.string(forKey: modelKey("model")) ?? modelProvider.defaultModel
        endpoint = defaults.string(forKey: modelKey("endpoint")) ?? modelProvider.defaultEndpoint
        apiKeyDraft = ""
    }

    private func isSuitableForSpeech(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 52 else { return false }
        let blocked = ["http://", "https://", "```", "|", "•", "\n- ", "\n1."]
        return !blocked.contains(where: value.contains) && value.filter(\.isNewline).count <= 1
    }

    private func trimHabitsToLimits() {
        permanentHabits = Array(permanentHabits.suffix(40))
        while permanentHabits.map(\.text.count).reduce(0, +) > 4_000, permanentHabits.count > 1 {
            permanentHabits.removeFirst()
        }
    }

    private func persistHabits() {
        do {
            let directory = habitStoreURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(permanentHabits).write(to: habitStoreURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: habitStoreURL.path)
        } catch {
            // The in-memory copy remains usable; a later edit retries persistence.
        }
    }

    private static func normalizedHabit(_ text: String) -> String {
        String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
    }

    private static func loadHabits(from url: URL) -> [PermanentHabit] {
        guard let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([PermanentHabit].self, from: data) else { return [] }
        return Array(values.suffix(40))
    }

    private static var defaultHabitStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuYu", isDirectory: true)
            .appendingPathComponent("permanent-habits.json")
    }
}
