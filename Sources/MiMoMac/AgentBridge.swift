import Foundation
import Security

enum AssistantDecision: Equatable, Sendable {
    case reply(text: String, spoken: String?)
    case action(title: String, detail: String, hermesPrompt: String)
}

enum AssistantServiceError: LocalizedError {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse
    case http(Int, String)
    case hermesUnavailable
    case hermesFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "没有找到当前模型的 API 密钥，请在模型设置中填写并保存。"
        case .invalidEndpoint:
            "模型服务地址无效。"
        case .invalidResponse:
            "模型返回了无法解析的内容，请重试。"
        case let .http(code, message):
            "模型服务请求失败（\(code)）：\(message)"
        case .hermesUnavailable:
            "没有找到 Hermes，请确认 ~/.local/bin/hermes 已安装。"
        case let .hermesFailed(message):
            "Hermes 执行失败：\(message)"
        case .cancelled:
            "操作已取消。"
        }
    }
}

actor MiMoAssistantClient {
    private let session: URLSession
    private var memory: [ChatMessage] = []
    private var loadedPersistentMemory = false

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    func decide(for userText: String, profile: AssistantProfile) async throws -> AssistantDecision {
        let systemPrompt = """
        你是 macOS 语音助手“浮屿”的规划器。使用自然、有温度但不啰嗦的中文。
        回答长度偏好：\(profile.answerLength.prompt)
        用户个性化偏好：\(profile.customPrompt.isEmpty ? "无" : profile.customPrompt)
        人格与关系设定：\(profile.personaPrompt)
        你必须只输出一个 JSON 对象，不要使用 Markdown。
        如果用户只是询问、聊天或需要解释，输出：
        {"kind":"reply","reply":"屏幕上显示的完整回答","spokenReply":"适合说出口的一句自然短话，最多40字；除纯代码或纯链接外必须填写"}
        如果用户明确要求操作这台 Mac、应用或文件，禁止直接执行，输出：
        {"kind":"action","title":"短标题","detail":"将做什么以及主要风险，最多45字","hermesPrompt":"给 Hermes 的完整、明确、最小权限执行指令"}
        普通 reply 禁止使用“我现在帮你打开、正在执行、马上替你完成”等会让用户误以为操作已发生的话术。
        没有真实工具结果时，禁止声称 Mac 操作已经完成。
        删除、发送、购买、发布、修改系统安全设置等高风险操作必须准确说明风险。
        不要把“怎么做”之类的知识问题误判成操作。
        """
        try loadPersistentMemoryIfNeeded(profile: profile)
        let content = try await requestCompletion(
            systemPrompt: systemPrompt,
            userText: userText,
            profile: profile,
            includeContext: true
        )
        let parsedDecision = try Self.parseDecision(content)
        let decision = Self.reconcileDecision(parsedDecision, userText: userText)
        if profile.contextEnabled {
            memory.append(.init(role: "user", content: userText))
            let assistantText: String
            switch decision {
            case let .reply(text, _): assistantText = text
            case let .action(title, detail, _): assistantText = "计划执行：\(title)。\(detail)"
            }
            memory.append(.init(role: "assistant", content: assistantText))
            memory = Array(memory.suffix(max(profile.contextTurns * 2, 4)))
            if profile.persistentMemory { try persistMemory() }
        }
        return decision
    }

    func recordActionResult(title: String, result: String, succeeded: Bool, profile: AssistantProfile) throws {
        guard profile.contextEnabled else { return }
        let prefix = succeeded ? "实际执行成功" : "实际执行失败"
        memory.append(.init(role: "assistant", content: "\(prefix)：\(title)。\(result)"))
        memory = Array(memory.suffix(max(profile.contextTurns * 2, 4)))
        if profile.persistentMemory { try persistMemory() }
    }

    func testConnection(profile: AssistantProfile) async throws -> String {
        let result = try await requestCompletion(
            systemPrompt: "你是连接测试助手。只回复：连接正常",
            userText: "测试连接",
            profile: profile,
            includeContext: false
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func clearMemory() throws {
        memory.removeAll()
        loadedPersistentMemory = true
        if FileManager.default.fileExists(atPath: Self.memoryURL.path) {
            try FileManager.default.removeItem(at: Self.memoryURL)
        }
    }

    private func requestCompletion(
        systemPrompt: String,
        userText: String,
        profile: AssistantProfile,
        includeContext: Bool
    ) async throws -> String {
        let configuration = profile.model
        guard !configuration.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: configuration.endpoint),
              !configuration.endpoint.isEmpty else {
            throw AssistantServiceError.invalidEndpoint
        }
        let apiKey = KeychainStore.password(service: configuration.keychainService) ?? ""
        if configuration.provider.requiresAPIKey && apiKey.isEmpty {
            throw AssistantServiceError.missingAPIKey
        }

        let recentContext = includeContext && profile.contextEnabled
            ? Array(memory.suffix(profile.contextTurns * 2))
            : []
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if configuration.provider.usesAnthropicMessages {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONEncoder().encode(
                AnthropicRequest(
                    model: configuration.model,
                    maxTokens: 1200,
                    system: systemPrompt,
                    messages: recentContext + [.init(role: "user", content: userText)],
                    temperature: 0.34
                )
            )
        } else {
            if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONEncoder().encode(
                ChatRequest(
                    model: configuration.model,
                    messages: [.init(role: "system", content: systemPrompt)]
                        + recentContext
                        + [.init(role: "user", content: userText)],
                    temperature: 0.34
                )
            )
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AssistantServiceError.invalidResponse }
        guard 200..<300 ~= http.statusCode else {
            throw AssistantServiceError.http(http.statusCode, Self.errorMessage(from: data))
        }

        if configuration.provider.usesAnthropicMessages {
            let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
            guard let content = decoded.content.first(where: { $0.type == "text" })?.text.nonEmpty else {
                throw AssistantServiceError.invalidResponse
            }
            return content
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content.nonEmpty else {
            throw AssistantServiceError.invalidResponse
        }
        return content
    }

    static func parseDecision(_ content: String) throws -> AssistantDecision {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if let first = trimmed.firstIndex(of: "{"), let last = trimmed.lastIndex(of: "}"), first <= last {
            jsonText = String(trimmed[first...last])
        } else {
            return .reply(text: trimmed, spoken: nil)
        }

        guard let data = jsonText.data(using: .utf8),
              let wire = try? JSONDecoder().decode(WireDecision.self, from: data) else {
            return .reply(text: trimmed, spoken: nil)
        }

        switch wire.kind {
        case "action":
            guard let title = wire.title?.nonEmpty,
                  let detail = wire.detail?.nonEmpty,
                  let prompt = wire.hermesPrompt?.nonEmpty else {
                throw AssistantServiceError.invalidResponse
            }
            return .action(title: title, detail: detail, hermesPrompt: prompt)
        default:
            guard let reply = wire.reply?.nonEmpty else {
                throw AssistantServiceError.invalidResponse
            }
            return .reply(text: reply, spoken: wire.spokenReply?.nonEmpty)
        }
    }

    static func reconcileDecision(_ decision: AssistantDecision, userText: String) -> AssistantDecision {
        guard case .reply = decision, looksLikeMacAction(userText) else { return decision }
        let compact = userText.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(compact.prefix(22))
        return .action(
            title: title.isEmpty ? "执行 Mac 操作" : title,
            detail: "浮屿识别到这是 Mac 操作，将在执行前确认。",
            hermesPrompt: compact
        )
    }

    static func looksLikeMacAction(_ text: String) -> Bool {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return false }
        let knowledgePrefixes = ["怎么", "如何", "为什么", "是什么", "能不能介绍", "告诉我怎么", "教我"]
        if knowledgePrefixes.contains(where: value.hasPrefix) { return false }
        let actionVerbs = [
            "打开", "关闭", "启动", "退出", "创建", "新建", "删除", "移动", "复制", "重命名",
            "整理", "发送", "点击", "切换", "设置", "调高", "调低", "搜索", "下载", "安装", "卸载"
        ]
        let macTargets = [
            "文件", "文件夹", "访达", "finder", "safari", "浏览器", "应用", "软件", "桌面",
            "系统", "音量", "亮度", "窗口", "mac", "电脑", "程序", "微信", "邮件", "日历"
        ]
        let lower = value.lowercased()
        let hasVerb = actionVerbs.contains(where: lower.contains)
        let hasTarget = macTargets.contains(where: lower.contains)
        let directRequest = lower.hasPrefix("帮我") || lower.hasPrefix("替我") || lower.hasPrefix("给我")
        return hasVerb && (hasTarget || directRequest)
    }

    private static func errorMessage(from data: Data) -> String {
        if let payload = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return payload.error.message
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? "未知错误"
    }

    private func loadPersistentMemoryIfNeeded(profile: AssistantProfile) throws {
        guard profile.persistentMemory, !loadedPersistentMemory else { return }
        loadedPersistentMemory = true
        guard FileManager.default.fileExists(atPath: Self.memoryURL.path) else { return }
        memory = try JSONDecoder().decode([ChatMessage].self, from: Data(contentsOf: Self.memoryURL))
    }

    private func persistMemory() throws {
        let directory = Self.memoryURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(memory).write(to: Self.memoryURL, options: .atomic)
    }

    private static var memoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuYu", isDirectory: true)
            .appendingPathComponent("conversation-memory.json")
    }
}

@MainActor
final class HermesCommandRunner {
    static let timeoutSeconds = 120
    private var currentProcess: Process?

    var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executableURL.path)
    }

    func execute(_ approvedPrompt: String) async throws -> String {
        guard isAvailable else { throw AssistantServiceError.hermesUnavailable }
        cancel()

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "-z",
            """
            这是用户已经在浮屿界面中明确批准的一次性 macOS 操作。
            只执行以下已批准内容，不要扩大范围，不要进行额外操作：
            \(approvedPrompt)
            完成后用简洁中文说明实际做了什么；若无法安全完成，停止并说明原因。
            """
        ]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = ProcessInfo.processInfo.environment

        let stdoutURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-hermes-\(UUID().uuidString).out")
        let stderrURL = FileManager.default.temporaryDirectory.appendingPathComponent("fuyu-hermes-\(UUID().uuidString).err")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        currentProcess = process

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
            if currentProcess === process { currentProcess = nil }
        }

        let box = ProcessBox(process)
        var timedOut = false
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.timeoutSeconds))
            guard let self,
                  !Task.isCancelled,
                  self.currentProcess === process,
                  process.isRunning else { return }
            timedOut = true
            process.terminate()
        }
        defer { timeoutTask.cancel() }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { finished in
                    continuation.resume(returning: finished.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }

        try? stdoutHandle.synchronize()
        try? stderrHandle.synchronize()
        let output = (try? String(contentsOf: stdoutURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let errorOutput = (try? String(contentsOf: stderrURL, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if Task.isCancelled { throw AssistantServiceError.cancelled }
        if timedOut { throw AssistantServiceError.hermesFailed("任务超过 2 分钟没有结束，已自动停止。你可以换一种说法后重试。") }
        guard status == 0 else {
            throw AssistantServiceError.hermesFailed(errorOutput.nonEmpty ?? "退出码 \(status)")
        }
        guard !output.isEmpty else {
            throw AssistantServiceError.hermesFailed("没有返回执行结果")
        }
        return output
    }

    func cancel() {
        if let currentProcess, currentProcess.isRunning {
            currentProcess.terminate()
        }
        currentProcess = nil
    }

    private var executableURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/hermes")
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}

enum KeychainStore {
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var memoryCache: [String: String] = [:]

    static func password(service: String) -> String? {
        cacheLock.lock()
        if let cached = memoryCache[service] {
            cacheLock.unlock()
            return cached
        }
        if let local = readLocalCredentials()[service], !local.isEmpty {
            memoryCache[service] = local
            cacheLock.unlock()
            return local
        }
        cacheLock.unlock()

        // One-time migration for existing installations. Once copied, all
        // future reads use the local configuration and never touch Keychain.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        guard let value = String(data: data, encoding: .utf8) else { return nil }
        cacheLock.lock()
        memoryCache[service] = value
        var credentials = readLocalCredentials()
        credentials[service] = value
        try? writeLocalCredentials(credentials)
        cacheLock.unlock()
        return value
    }

    static func set(_ password: String, service: String) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        var credentials = readLocalCredentials()
        credentials[service] = password
        try writeLocalCredentials(credentials)
        memoryCache[service] = password
    }

    static func delete(service: String) throws {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        var credentials = readLocalCredentials()
        credentials.removeValue(forKey: service)
        try writeLocalCredentials(credentials)
        memoryCache.removeValue(forKey: service)
    }

    private static var credentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FuYu", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private static func readLocalCredentials() -> [String: String] {
        guard let data = try? Data(contentsOf: credentialsURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return values
    }

    private static func writeLocalCredentials(_ credentials: [String: String]) throws {
        let directory = credentialsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let data = try JSONEncoder().encode(credentials)
        try data.write(to: credentialsURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: credentialsURL.path)
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct AnthropicRequest: Encodable {
    let model: String
    let maxTokens: Int
    let system: String
    let messages: [ChatMessage]
    let temperature: Double

    enum CodingKeys: String, CodingKey {
        case model, system, messages, temperature
        case maxTokens = "max_tokens"
    }
}

private struct AnthropicResponse: Decodable {
    struct ContentBlock: Decodable {
        let type: String
        let text: String
    }
    let content: [ContentBlock]
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable { let message: ChatMessage }
    let choices: [Choice]
}

private struct WireDecision: Decodable {
    let kind: String
    let reply: String?
    let spokenReply: String?
    let title: String?
    let detail: String?
    let hermesPrompt: String?
}

private struct APIErrorEnvelope: Decodable {
    struct APIError: Decodable { let message: String }
    let error: APIError
}

private extension String {
    var nonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
