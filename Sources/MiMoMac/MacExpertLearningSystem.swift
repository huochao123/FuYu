import Foundation

struct MacSkillIndexEntry: Codable, Equatable {
    let id: String
    let title: String
    let description: String
    let triggers: [String]
    let risk: String
    let minimumMacOS: Int
}

struct MacSkillSelection: Equatable {
    let indexPrompt: String
    let loadedPrompt: String
    let loadedIDs: [String]
    let loadedCharacterCount: Int
}

enum MacSkillLibrary {
    static func select(for query: String, limit: Int = 2) -> MacSkillSelection {
        let entries = loadIndex()
        let indexPrompt = entries.map {
            "- \($0.id)：\($0.title)"
        }.joined(separator: "\n")
        let normalized = query.lowercased()
        let selected = entries.map { entry in
            let triggerScore = entry.triggers.filter { normalized.contains($0.lowercased()) }.count * 10
            return (entry: entry, score: triggerScore)
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }
        .prefix(limit)

        var loaded: [(String, String)] = []
        for match in selected {
            guard let body = loadSkill(id: match.entry.id) else { continue }
            loaded.append((match.entry.id, body))
        }
        let loadedPrompt = loaded.map { "[已按需加载 \($0.0)]\n\($0.1)" }.joined(separator: "\n\n")
        return .init(
            indexPrompt: indexPrompt.isEmpty ? "Mac Skill索引不可用。" : indexPrompt,
            loadedPrompt: loadedPrompt.isEmpty ? "当前请求未触发完整Mac Skill，只提供能力索引。" : loadedPrompt,
            loadedIDs: loaded.map(\.0),
            loadedCharacterCount: loaded.reduce(0) { $0 + $1.1.count }
        )
    }

    static func validationErrors() -> [String] {
        let entries = loadIndex()
        var errors: [String] = []
        if entries.isEmpty { errors.append("索引为空或无法解析") }
        let ids = entries.map(\.id)
        if Set(ids).count != ids.count { errors.append("Skill ID重复") }
        for entry in entries {
            if entry.triggers.isEmpty { errors.append("\(entry.id)没有触发词") }
            guard let body = loadSkill(id: entry.id) else {
                errors.append("\(entry.id)缺少SKILL.md")
                continue
            }
            if !body.hasPrefix("---\nname:") || !body.contains("\ndescription:") {
                errors.append("\(entry.id)的frontmatter不完整")
            }
        }
        return errors
    }

    private static func loadIndex() -> [MacSkillIndexEntry] {
        guard let data = try? Data(contentsOf: rootURL.appendingPathComponent("index.json")) else { return [] }
        return (try? JSONDecoder().decode([MacSkillIndexEntry].self, from: data)) ?? []
    }

    private static func loadSkill(id: String) -> String? {
        let url = rootURL.appendingPathComponent(id, isDirectory: true).appendingPathComponent("SKILL.md")
        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static var rootURL: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("MacSkills", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("index.json").path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/MacSkills", isDirectory: true)
    }
}

enum MacExpertKnowledgeBase {
    struct Playbook {
        let title: String
        let terms: [String]
        let guidance: String
    }

    private static let playbooks: [Playbook] = [
        .init(
            title: "性能、发热与耗电",
            terms: ["发热", "温度", "风扇", "耗电", "卡顿", "cpu", "内存", "进程", "性能"],
            guidance: "先读取持续 CPU、内存压力、系统负载和进程身份；瞬时峰值不能直接判异常。优先区分用户应用、系统索引、更新进程与失控进程，结束进程前提醒保存工作。"
        ),
        .init(
            title: "存储、APFS 与安全清理",
            terms: ["空间", "磁盘", "存储", "垃圾", "缓存", "apfs", "快照", "大文件", "清理"],
            guidance: "区分真实占用、可清除空间、APFS 快照和缓存；扫描与删除分开。只对明确白名单缓存给出安全清理，默认移到废纸篓，不删除用户文档，不把 purgeable 空间误报为可立即释放。"
        ),
        .init(
            title: "文件整理与重复文件",
            terms: ["文件", "文件夹", "下载", "整理", "重复", "同名", "照片"],
            guidance: "重复文件必须以内容哈希确认，不能只看名称；整理先生成移动预览，避免覆盖同名文件并保留撤销路径。照片图库、云盘占位文件和应用资源不得按普通文件批量处理。"
        ),
        .init(
            title: "隐私权限与系统安全",
            terms: ["权限", "麦克风", "摄像头", "录屏", "辅助功能", "隐私", "tcc", "sip", "安全"],
            guidance: "优先说明系统设置中的准确授权入口和当前授权状态；不得绕过 TCC、SIP、Gatekeeper 或静默修改安全设置。权限变化后要重新验证真实能力，不能仅凭按钮状态声称成功。"
        ),
        .init(
            title: "音频、语音与 CoreAudio",
            terms: ["声音", "音量", "麦克风", "语音", "识别", "耳机", "蓝牙", "coreaudio", "fn"],
            guidance: "区分输入设备、输出设备、系统媒体声与麦克风回声；连续语音要验证每轮真实音频缓冲和识别回调。音量 ducking 必须在收音结束后恢复原值，用户主动调高时不得覆盖。"
        ),
        .init(
            title: "网络、Wi-Fi 与外接网卡",
            terms: ["网络", "wifi", "以太网", "网卡", "断网", "dns", "dhcp", "usb", "扩展坞"],
            guidance: "先区分物理链路/设备重枚举、接口状态、DHCP 与 DNS。设备被移除并重新挂载不是普通 DNS 故障；日志采集应限定时间范围，避免高负载重复扫描。"
        ),
        .init(
            title: "启动项、后台服务与 launchd",
            terms: ["启动项", "开机", "后台", "常驻", "launchd", "代理", "服务"],
            guidance: "同时检查登录项、后台项目和用户/系统 launchd；先识别签名、来源与用途，再建议停用。不得因为名称陌生就删除 plist，修改后要验证服务状态。"
        ),
        .init(
            title: "备份、更新与恢复",
            terms: ["备份", "恢复", "更新", "升级", "time machine", "版本", "迁移"],
            guidance: "涉及系统升级、磁盘修改和批量文件操作时先确认可恢复路径；区分当前 macOS 版本与旧经验，旧版本方案只能作为参考，执行前重新验证。"
        )
    ]

    static func context(for query: String, limit: Int = 3) -> String {
        let normalized = query.lowercased()
        let ranked = playbooks.map { playbook in
            (playbook, playbook.terms.filter { normalized.contains($0) }.count)
        }
        .filter { $0.1 > 0 }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        let selected = ranked.isEmpty ? playbooks.prefix(2).map { ($0, 0) } : Array(ranked)
        return selected.map { "[\($0.0.title)] \($0.0.guidance)" }.joined(separator: "\n")
    }
}

@MainActor
final class MacExperienceStore {
    struct Experience: Codable, Equatable, Identifiable {
        let id: UUID
        let task: String
        let result: String
        let succeeded: Bool
        let systemVersion: String
        let architecture: String
        let createdAt: Date
    }

    static let shared = MacExperienceStore()

    private let storeURL: URL
    private var experiences: [Experience]

    init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? Self.defaultStoreURL
        if let data = try? Data(contentsOf: self.storeURL),
           let decoded = try? JSONDecoder().decode([Experience].self, from: data) {
            experiences = decoded
        } else {
            experiences = []
        }
    }

    var count: Int { experiences.count }

    func clear() throws {
        experiences.removeAll()
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try FileManager.default.removeItem(at: storeURL)
        }
    }

    func record(task: String, result: String, succeeded: Bool) {
        let cleanTask = String(task.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        let cleanResult = String(result.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_200))
        guard !cleanTask.isEmpty, !cleanResult.isEmpty else { return }
        if let last = experiences.last,
           last.task == cleanTask,
           last.result == cleanResult,
           last.succeeded == succeeded { return }
        experiences.append(.init(
            id: UUID(),
            task: cleanTask,
            result: cleanResult,
            succeeded: succeeded,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            createdAt: Date()
        ))
        experiences = Array(experiences.suffix(300))
        persist()
    }

    func context(for query: String, limit: Int = 5) -> String {
        guard !experiences.isEmpty else { return "这台 Mac 还没有可复用的已验证操作经验。" }
        let terms = Self.terms(query)
        let currentVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let scored: [(index: Int, item: Experience, score: Int)] = experiences.enumerated().map { index, item in
            let overlap = terms.intersection(Self.terms(item.task + item.result)).count
            let versionBonus = item.systemVersion == currentVersion ? 4 : 0
            let outcomeBonus = item.succeeded ? 2 : 1
            let score = overlap * 6 + versionBonus + outcomeBonus
            return (index: index, item: item, score: score)
        }
        let matches = scored
        .filter { $0.score > 2 }
        .sorted { lhs, rhs in lhs.score == rhs.score ? lhs.index > rhs.index : lhs.score > rhs.score }
        .prefix(limit)
        guard !matches.isEmpty else { return "没有找到与当前问题相关的本机已验证经验。" }
        return matches.map { match in
            let item = match.item
            let versionNote = item.systemVersion == currentVersion ? "当前系统版本匹配" : "旧系统版本经验，执行前必须重新验证"
            return "[\(AppState.memoryTimestamp(for: item.createdAt)) · \(versionNote) · \(item.succeeded ? "成功" : "失败")] \(item.task)：\(item.result)"
        }.joined(separator: "\n")
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(experiences).write(to: storeURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storeURL.path)
        } catch {
            // Learning remains available for the current process and retries next time.
        }
    }

    private static func terms(_ text: String) -> Set<String> {
        let characters = Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
        var result = Set<String>()
        for index in characters.indices {
            if index + 1 < characters.count { result.insert(String(characters[index...index + 1])) }
            if index + 2 < characters.count { result.insert(String(characters[index...index + 2])) }
        }
        return result
    }

    private static var architecture: String {
        #if arch(arm64)
        "arm64 / Apple Silicon"
        #else
        "x86_64 / Intel"
        #endif
    }

    private static var defaultStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuYu", isDirectory: true)
            .appendingPathComponent("mac-experience.json")
    }
}
