import AppKit
import Foundation

enum LocalMacCommand: Equatable {
    enum Adjustment: Equatable {
        case read
        case set(Int)
        case change(Int)
        case mute(Bool)
    }

    case scan(MacCareTool)
    case volume(Adjustment)
    case brightness(Adjustment)
    case openApplication(String)
    case applyLatest(MacCareTool)
    case capabilities
}

enum LocalCommandRouter {
    static func command(for text: String) -> LocalMacCommand? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        // Explanations are handled by the agent's dialogue layer. Words such
        // as “执行” inside a why-question must never be interpreted as a new action.
        if AgentIntentEngine.isExplanationRequest(value) { return nil }

        if ["你是谁", "你是什么助手", "你能做什么", "你会做什么", "你的能力", "你有什么功能"].contains(where: value.contains) {
            return .capabilities
        }

        if value.contains("取消静音") || value.contains("解除静音") {
            return .volume(.mute(false))
        }
        if value.contains("静音") { return .volume(.mute(true)) }

        if value.contains("音量") || value.contains("声音") {
            if let number = percentage(in: value) { return .volume(.set(number)) }
            if ["多少", "当前", "查看", "查询"].contains(where: value.contains) { return .volume(.read) }
            if ["调高", "增大", "大一点", "增加"].contains(where: value.contains) { return .volume(.change(10)) }
            if ["调低", "减小", "小一点", "降低"].contains(where: value.contains) { return .volume(.change(-10)) }
            if value.contains("最大") { return .volume(.set(100)) }
        }

        if value.contains("亮度") || value.contains("亮一点") || value.contains("暗一点") {
            if let number = percentage(in: value) { return .brightness(.set(number)) }
            if ["多少", "当前", "查看", "查询"].contains(where: value.contains) { return .brightness(.read) }
            if ["调高", "亮一点", "增加"].contains(where: value.contains) { return .brightness(.change(10)) }
            if ["调低", "暗一点", "降低"].contains(where: value.contains) { return .brightness(.change(-10)) }
            if value.contains("最高") { return .brightness(.set(100)) }
            if value.contains("最低") { return .brightness(.set(0)) }
        }

        for prefix in ["帮我打开", "请打开", "打开一下", "打开", "启动", "运行"] where value.hasPrefix(prefix) {
            let remainder = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if remainder.contains("会议"), ["开一个", "开个", "创建", "新建", "预约", "安排"].contains(where: remainder.contains) {
                continue
            }
            let name = remainder.split(whereSeparator: { "，,。；;！？!?".contains($0) }).first.map(String.init) ?? remainder
            if !name.isEmpty, name.count <= 40 { return .openApplication(name) }
        }

        let mentionsDownloads = value.contains("下载") && (value.contains("文件夹") || value.contains("目录") || value.contains("东西"))
        let asksToInspect = ["分析", "看看", "看下", "检查", "统计", "有什么", "情况", "概览"].contains(where: value.contains)
        if mentionsDownloads, asksToInspect { return .scan(.organize) }

        if ["执行建议", "确认优化", "开始优化", "帮我优化", "清理掉", "确认清理"].contains(where: value.contains) {
            if value.contains("整理") { return .applyLatest(.organize) }
            if value.contains("重复") { return .applyLatest(.duplicates) }
            if value.contains("优化") { return .applyLatest(.optimization) }
            return .applyLatest(.junkScan)
        }

        let mappings: [(MacCareTool, [String])] = [
            (.duplicates, ["重复文件", "查重"]),
            (.largeFiles, ["大文件", "空间占用"]),
            (.loginItems, ["启动项", "开机启动"]),
            (.hotProcesses, ["发热进程", "发热检测", "高负载进程"]),
            (.appLeftovers, ["应用残留", "卸载残留"]),
            (.appHealth, ["应用健康", "应用档案", "软件健康"]),
            (.batteryHealth, ["电池健康", "电池与发热", "耗电原因", "续航检查"]),
            (.privacyAudit, ["隐私权限", "权限检查", "麦克风权限", "屏幕录制权限"]),
            (.incidentSnapshot, ["故障现场", "现场快照", "保存现场", "记录异常"]),
            (.organize, ["整理下载", "智能整理", "分析下载文件夹", "检查下载文件夹", "看看下载文件夹"]),
            (.junkScan, ["垃圾清理", "清理垃圾", "垃圾扫描", "缓存清理", "扫描垃圾"]),
            (.systemCheck, ["系统体检", "电脑体检", "检查电脑", "检查系统"]),
            (.optimization, ["优化建议", "检查优化", "系统优化"])
        ]
        for (tool, keywords) in mappings where keywords.contains(where: value.contains) {
            return .scan(tool)
        }
        return nil
    }

    private static func percentage(in text: String) -> Int? {
        guard let range = text.range(of: #"\d{1,3}"#, options: .regularExpression),
              let value = Int(text[range]), (0...100).contains(value) else { return nil }
        return value
    }
}

struct LocalMacCapabilityManifest {
    let brightnessAvailable: Bool

    static func current() async -> LocalMacCapabilityManifest {
        .init(brightnessAvailable: await LocalMacControlService.shared.brightnessIsAvailable())
    }

    var prompt: String {
        let tools = MacCareTool.allCases.map(\.rawValue).joined(separator: "、")
        let process = ProcessInfo.processInfo
        #if arch(arm64)
        let architecture = "Apple Silicon / arm64"
        #else
        let architecture = "Intel / x86_64"
        #endif
        let memory = ByteCountFormatter.string(fromByteCount: Int64(process.physicalMemory), countStyle: .memory)
        return """
        当前 Mac 画像：macOS \(process.operatingSystemVersionString)；架构 \(architecture)；物理内存 \(memory)；处理器核心 \(process.processorCount)。所有旧经验必须与当前系统版本核对。
        浮屿本机工具：\(tools)。这些检测不经过 Hermes。
        系统控制：音量和静音可直接本机控制；亮度\(brightnessAvailable ? "可直接本机控制" : "当前内置屏幕接口不可用，必须如实说明，不能声称已调整")。
        主动能力：发热进程监控会在连续三次高负载后通知；其余检查只在用户要求时运行。
        """
    }
}

actor LocalMacControlService {
    static let shared = LocalMacControlService()

    struct VolumeState: Equatable {
        let level: Int
        let muted: Bool
    }

    func volumeState() throws -> VolumeState {
        let output = try Self.run("/usr/bin/osascript", ["-e", "get volume settings"])
        guard let level = Self.captureInt(#"output volume:(\d+)"#, in: output) else {
            throw LocalMacToolError.invalidSystemResponse
        }
        return .init(level: level, muted: output.contains("output muted:true"))
    }

    func adjustVolume(_ adjustment: LocalMacCommand.Adjustment) throws -> String {
        let current = try volumeState()
        switch adjustment {
        case .read:
            return "当前输出音量为 \(current.level)%\(current.muted ? "，已静音" : "")。"
        case let .mute(muted):
            _ = try Self.run("/usr/bin/osascript", ["-e", "set volume output muted \(muted ? "true" : "false")"])
        case let .set(level):
            _ = try Self.run("/usr/bin/osascript", ["-e", "set volume output volume \(max(0, min(100, level)))"])
        case let .change(delta):
            _ = try Self.run("/usr/bin/osascript", ["-e", "set volume output volume \(max(0, min(100, current.level + delta)))"])
        }
        let updated = try volumeState()
        return "已在本机调整，当前输出音量为 \(updated.level)%\(updated.muted ? "，已静音" : "")。"
    }

    func brightnessIsAvailable() -> Bool {
        guard let path = Self.brightnessExecutable else { return false }
        return (try? Self.run(path, ["-l"]))?.contains("brightness ") == true
    }

    func adjustBrightness(_ adjustment: LocalMacCommand.Adjustment) throws -> String {
        guard let path = Self.brightnessExecutable,
              let listing = try? Self.run(path, ["-l"]),
              let currentValue = Self.captureDouble(#"brightness ([0-9.]+)"#, in: listing) else {
            throw LocalMacToolError.brightnessUnavailable
        }
        let current = Int((currentValue * 100).rounded())
        let target: Int
        switch adjustment {
        case .read: return "当前屏幕亮度约为 \(current)% 。"
        case let .set(value): target = value
        case let .change(delta): target = current + delta
        case .mute: throw LocalMacToolError.brightnessUnavailable
        }
        let clamped = max(0, min(100, target))
        _ = try Self.run(path, [String(format: "%.2f", Double(clamped) / 100)])
        return "已在本机把屏幕亮度调到约 \(clamped)% 。"
    }

    func openApplication(named rawName: String) async throws -> String {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LocalMacToolError.applicationNotFound(rawName) }
        let aliases: [String: String] = [
            "访达": "com.apple.finder", "finder": "com.apple.finder",
            "系统设置": "com.apple.systempreferences", "设置": "com.apple.systempreferences",
            "活动监视器": "com.apple.ActivityMonitor", "日历": "com.apple.iCal",
            "备忘录": "com.apple.Notes", "音乐": "com.apple.Music",
            "safari": "com.apple.Safari", "微信": "com.tencent.xinWeChat",
            "qq": "com.tencent.qq", "腾讯会议": "com.tencent.meeting",
            "chrome": "com.google.Chrome", "谷歌浏览器": "com.google.Chrome"
        ]
        let lowered = name.lowercased()
        let bundleID = aliases.first(where: { lowered.contains($0.key) })?.value
        let url = bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            ?? Self.installedApplicationURL(named: name)
        guard let url else { throw LocalMacToolError.applicationNotFound(name) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return "已在本机打开 \(url.deletingPathExtension().lastPathComponent)。"
    }

    private static func installedApplicationURL(named name: String) -> URL? {
        let manager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        let target = name.lowercased().replacingOccurrences(of: ".app", with: "")
        return roots.lazy.flatMap { root in
            (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        }.first { url in
            url.pathExtension == "app" && url.deletingPathExtension().lastPathComponent.lowercased() == target
        }
    }

    private static var brightnessExecutable: String? {
        ["/opt/homebrew/bin/brightness", "/usr/local/bin/brightness"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func run(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else { throw LocalMacToolError.commandFailed(output) }
        return output
    }

    private static func captureInt(_ pattern: String, in text: String) -> Int? {
        guard let match = text.range(of: pattern, options: .regularExpression) else { return nil }
        return Int(text[match].split(separator: ":").last ?? "")
    }

    private static func captureDouble(_ pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }
}

enum LocalMacToolError: LocalizedError {
    case invalidSystemResponse
    case commandFailed(String)
    case brightnessUnavailable
    case applicationNotFound(String)

    var errorDescription: String? {
        switch self {
        case .invalidSystemResponse: "没有读到可靠的系统状态，因此没有执行。"
        case let .commandFailed(message): "本机控制失败：\(message.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .brightnessUnavailable: "这台 Mac 当前没有可用的屏幕亮度控制接口，我没有假装执行。你仍可用键盘亮度键或系统设置调整。"
        case let .applicationNotFound(name): "没有找到名为“\(name)”的已安装应用，因此没有执行。"
        }
    }
}
