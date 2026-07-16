import Foundation

struct FeishuInboundMessage: Sendable {
    let messageID: String
    let chatID: String
    let senderID: String
    let text: String
}

@MainActor
final class FeishuBridgeService {
    var onMessage: ((FeishuInboundMessage) -> Void)?

    private let state: AppState
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = ""
    private var seenMessageIDs: Set<String> = []

    init(state: AppState) {
        self.state = state
    }

    func configure(enabled: Bool, appID: String, appSecret: String?) {
        stop()
        guard enabled else {
            state.remoteChannelStatus = appID.isEmpty ? "飞书未配置" : "飞书已关闭"
            return
        }
        guard !appID.isEmpty, let appSecret, !appSecret.isEmpty else {
            state.remoteChannelStatus = "飞书缺少凭证"
            return
        }
        guard let pythonURL = Self.pythonURL else {
            state.remoteChannelStatus = "飞书组件不可用"
            return
        }
        guard let scriptURL = Self.bridgeScriptURL else {
            state.remoteChannelStatus = "飞书桥接缺失"
            return
        }

        let process = Process()
        let stdout = Pipe()
        let stdin = Pipe()
        process.executableURL = pythonURL
        process.arguments = [scriptURL.path]
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = stdin
        var environment = ProcessInfo.processInfo.environment
        environment["FUYU_FEISHU_APP_ID"] = appID
        environment["FUYU_FEISHU_APP_SECRET"] = appSecret
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consume(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.process != nil else { return }
                self.state.remoteChannelStatus = "飞书连接已断开"
            }
        }

        do {
            try process.run()
            self.process = process
            inputHandle = stdin.fileHandleForWriting
            state.remoteChannelStatus = "飞书已启用"
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            state.remoteChannelStatus = "飞书启动失败"
        }
    }

    func reply(to message: FeishuInboundMessage, text: String) {
        guard let inputHandle else { return }
        let payload: [String: String] = [
            "kind": "reply",
            "chat_id": message.chatID,
            "text": String(text.prefix(12_000))
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var line = String(data: data, encoding: .utf8) else { return }
        line.append("\n")
        try? inputHandle.write(contentsOf: Data(line.utf8))
    }

    func stop() {
        process?.standardOutput.flatMap { ($0 as? Pipe)?.fileHandleForReading }?.readabilityHandler = nil
        inputHandle?.closeFile()
        inputHandle = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
        outputBuffer = ""
    }

    private func consume(_ data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        outputBuffer += chunk
        let lines = outputBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        outputBuffer = String(lines.last ?? "")
        for line in lines.dropLast() {
            consumeLine(String(line))
        }
    }

    private func consumeLine(_ line: String) {
        let prefix = "FUYU_EVENT "
        guard line.hasPrefix(prefix),
              let data = String(line.dropFirst(prefix.count)).data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let kind = payload["kind"] as? String else { return }

        if kind == "message" {
            let message = FeishuInboundMessage(
                messageID: payload["message_id"] as? String ?? "",
                chatID: payload["chat_id"] as? String ?? "",
                senderID: payload["sender_id"] as? String ?? "",
                text: payload["text"] as? String ?? ""
            )
            guard !message.chatID.isEmpty, !message.text.isEmpty else { return }
            if !message.messageID.isEmpty {
                guard seenMessageIDs.insert(message.messageID).inserted else { return }
                if seenMessageIDs.count > 500 { seenMessageIDs.removeAll(keepingCapacity: true) }
            }
            state.remoteChannelStatus = "飞书已连接"
            state.activitySource = "飞书"
            onMessage?(message)
        } else if payload["status"] as? String == "error" {
            state.remoteChannelStatus = "飞书连接失败"
        }
    }

    private static var bridgeScriptURL: URL? {
        if let bundled = Bundle.main.url(forResource: "fuyu_feishu_bridge", withExtension: "py") {
            return bundled
        }
        let source = URL(fileURLWithPath: #filePath)
        let projectRoot = source.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let development = projectRoot.appendingPathComponent("Resources/fuyu_feishu_bridge.py")
        return FileManager.default.fileExists(atPath: development.path) ? development : nil
    }

    private static var pythonURL: URL? {
        let candidates = [
            NSHomeDirectory() + "/.hermes/hermes-agent/venv/bin/python",
            NSHomeDirectory() + "/.local/bin/python3.11",
            "/usr/bin/python3"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }
}
