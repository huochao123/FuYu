import CryptoKit
import Foundation
import CleanerEngine

enum MacCareTool: String, CaseIterable, Sendable {
    case systemCheck = "系统体检"
    case junkScan = "垃圾清理"
    case organize = "智能整理"
    case largeFiles = "大文件"
    case duplicates = "重复文件"
    case loginItems = "启动项"
    case hotProcesses = "发热进程"
    case appLeftovers = "应用残留"
    case optimization = "优化建议"
}

struct MacCareReport: Sendable {
    let tool: MacCareTool
    let headline: String
    let details: [String]
    let cleanupPlan: LevelScanResult?

    init(tool: MacCareTool, headline: String, details: [String], cleanupPlan: LevelScanResult? = nil) {
        self.tool = tool
        self.headline = headline
        self.details = details
        self.cleanupPlan = cleanupPlan
    }

    var displayText: String {
        (["电脑管家 · \(tool.rawValue)", headline] + details.map { "• \($0)" }).joined(separator: "\n")
    }
}

enum MacCareService {
    private struct FileEntry: Sendable {
        let url: URL
        let size: Int64
        let modifiedAt: Date?
    }

    static func run(_ tool: MacCareTool) async throws -> MacCareReport {
        try Task.checkCancellation()
        switch tool {
        case .systemCheck: return try systemCheck()
        case .junkScan: return await junkScan()
        case .organize: return try organizePreview()
        case .largeFiles: return try largeFileScan()
        case .duplicates: return try duplicateScan()
        case .loginItems: return try loginItemScan()
        case .hotProcesses: return try hotProcessScan()
        case .appLeftovers: return try appLeftoverScan()
        case .optimization: return try optimizationScan()
        }
    }

    static func cleanSafe(_ plan: LevelScanResult) async -> DeletionResult {
        let engine = CleanerEngine()
        return await engine.delete(
            levelResult: plan,
            options: CleanerOptions(
                dryRun: false,
                moveToTrash: true,
                cleanupLevel: .safe,
                trashForUndo: true
            )
        )
    }

    private static func systemCheck() throws -> MacCareReport {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let available = Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let usedRatio = total > 0 ? Double(total - available) / Double(total) : 0
        let uptimeHours = ProcessInfo.processInfo.systemUptime / 3600
        let processes = try topProcesses(limit: 3)
        var details = [
            "可用空间 \(format(available))，磁盘已使用约 \(Int(usedRatio * 100))%",
            "物理内存 \(format(Int64(ProcessInfo.processInfo.physicalMemory)))",
            "本次开机已运行 \(String(format: "%.1f", uptimeHours)) 小时"
        ]
        if !processes.isEmpty { details.append("当前高负载：\(processes.joined(separator: "；"))") }
        let headline = usedRatio > 0.9 ? "磁盘空间偏紧，建议先检查大文件和缓存。" : "基础状态检查完成，未修改任何系统设置。"
        return .init(tool: .systemCheck, headline: headline, details: details)
    }

    private static func junkScan() async -> MacCareReport {
        let engine = CleanerEngine()
        let options = CleanerOptions(dryRun: true, cleanupLevel: .safe)
        // The full Dusty safe registry intentionally re-checks overlapping
        // browser subpaths. FuYu's quick scan starts with the two broad,
        // allowlisted roots and uses the engine's persistent size cache.
        let quickTargets = CleanupTargetRegistry.targets(for: .safe).filter {
            $0.id == "user-caches" || $0.id == "user-logs"
        }
        let safeTargets = await withTaskGroup(of: TargetScanResult.self) { group in
            for target in quickTargets {
                group.addTask {
                    await engine.scanTarget(target, options: options, sizingPolicy: .cached)
                }
            }
            var results: [TargetScanResult] = []
            for await result in group { results.append(result) }
            return results
        }
        let plan = LevelScanResult(level: .safe, targetResults: safeTargets)
        let targets = plan.targetResults
            .filter { $0.totalBytes > 0 }
            .sorted { $0.totalBytes > $1.totalBytes }
        let details = targets.prefix(12).map { "\($0.target.displayName)：约 \(format($0.totalBytes))" }
        return .init(
            tool: .junkScan,
            headline: "白名单引擎扫描到约 \(format(plan.totalBytes)) 的安全清理候选，当前只是预览，没有删除。",
            details: details.isEmpty ? ["没有扫描到安全清理候选"] : details,
            cleanupPlan: plan.totalBytes > 0 ? plan : nil
        )
    }

    private static func organizePreview() throws -> MacCareReport {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let entries = try fileEntries(in: [downloads], recursive: false, itemLimit: 20_000)
        var groups: [String: Int] = [:]
        for entry in entries {
            let ext = entry.url.pathExtension.lowercased()
            let category: String
            if ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg"].contains(ext) { category = "图片" }
            else if ["mp4", "mov", "mkv", "avi", "mp3", "wav", "m4a"].contains(ext) { category = "影音" }
            else if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md"].contains(ext) { category = "文档" }
            else if ["zip", "rar", "7z", "dmg", "pkg"].contains(ext) { category = "安装包与压缩包" }
            else { category = "其他" }
            groups[category, default: 0] += 1
        }
        let details = groups.sorted { $0.key < $1.key }.map { "\($0.key)：\($0.value) 个" }
        return .init(
            tool: .organize,
            headline: "下载文件夹共有 \(entries.count) 个文件，可按类型生成文件夹；当前没有移动。",
            details: details.isEmpty ? ["下载文件夹当前没有可整理文件"] : details
        )
    }

    private static func largeFileScan() throws -> MacCareReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Downloads", "Desktop", "Documents", "Movies"].map { home.appendingPathComponent($0) }
        let entries = try fileEntries(in: roots, recursive: true, itemLimit: 100_000)
            .filter { $0.size >= 200 * 1_024 * 1_024 }
            .sorted { $0.size > $1.size }
        let details = entries.prefix(8).map { "\($0.url.lastPathComponent)：\(format($0.size))" }
        let total = entries.reduce(Int64(0)) { $0 + $1.size }
        return .init(
            tool: .largeFiles,
            headline: "找到 \(entries.count) 个超过 200 MB 的文件，合计 \(format(total))。",
            details: details.isEmpty ? ["常用目录中没有超过 200 MB 的文件"] : details
        )
    }

    private static func duplicateScan() throws -> MacCareReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
        let entries = try fileEntries(in: roots, recursive: true, itemLimit: 60_000)
            .filter { $0.size >= 1_024 * 1_024 }
        let candidates = Dictionary(grouping: entries, by: \FileEntry.size).values.filter { $0.count > 1 }
        var hashes: [String: [FileEntry]] = [:]
        for group in candidates {
            for entry in group.prefix(20) {
                try Task.checkCancellation()
                if let digest = sha256(entry.url) { hashes[digest, default: []].append(entry) }
            }
        }
        let duplicateGroups = hashes.values.filter { $0.count > 1 }
        let reclaimable = duplicateGroups.reduce(Int64(0)) { total, group in
            total + Int64(group.count - 1) * (group.first?.size ?? 0)
        }
        let details = duplicateGroups.prefix(6).map { group in
            "\(group.first?.url.lastPathComponent ?? "重复文件")：\(group.count) 份，单份 \(format(group.first?.size ?? 0))"
        }
        return .init(
            tool: .duplicates,
            headline: "用文件哈希确认 \(duplicateGroups.count) 组重复项，预计可释放 \(format(reclaimable))。",
            details: details.isEmpty ? ["常用目录中暂未发现明确重复项"] : details
        )
    }

    private static func loginItemScan() throws -> MacCareReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            URL(fileURLWithPath: "/Library/LaunchDaemons")
        ]
        let files = roots.flatMap { (try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .filter { $0.pathExtension == "plist" }
        let details = files.prefix(10).map { $0.deletingPathExtension().lastPathComponent }
        return .init(
            tool: .loginItems,
            headline: "本机发现 \(files.count) 个后台启动配置，当前没有停用。",
            details: details.isEmpty ? ["没有发现 LaunchAgent 或 LaunchDaemon 配置"] : details
        )
    }

    private static func hotProcessScan() throws -> MacCareReport {
        let processes = try topProcesses(limit: 10)
        return .init(
            tool: .hotProcesses,
            headline: "已直接读取当前 CPU 与内存占用，没有结束任何进程。",
            details: processes.isEmpty ? ["当前未取得进程快照"] : processes
        )
    }

    private static func appLeftoverScan() throws -> MacCareReport {
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: cache,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sized = urls.map { ($0, directorySize($0, itemLimit: 12_000)) }.sorted { $0.1 > $1.1 }
        let details = sized.prefix(10).map { "\($0.0.lastPathComponent)：约 \(format($0.1))" }
        let total = sized.reduce(Int64(0)) { $0 + $1.1 }
        return .init(
            tool: .appLeftovers,
            headline: "已列出体积最大的应用缓存候选（合计约 \(format(total))），需确认应用来源后才能删除。",
            details: details.isEmpty ? ["没有发现应用缓存目录"] : details
        )
    }

    private static func optimizationScan() throws -> MacCareReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let values = try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        let available = Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let cache = directorySize(home.appendingPathComponent("Library/Caches"), itemLimit: 80_000)
        let downloads = (try? fileEntries(in: [home.appendingPathComponent("Downloads")], recursive: true, itemLimit: 40_000)) ?? []
        let oldDownloads = downloads.filter { ($0.modifiedAt ?? .now) < Date().addingTimeInterval(-90 * 86_400) }
        var details = ["缓存约 \(format(cache))", "90 天以上下载文件 \(oldDownloads.count) 个"]
        if total > 0 { details.insert("磁盘可用 \(format(available))（\(Int(Double(available) / Double(total) * 100))%）", at: 0) }
        details.append(contentsOf: try topProcesses(limit: 3))
        return .init(tool: .optimization, headline: "本机快速优化分析完成，以下项目按收益优先检查。", details: details)
    }

    private static func fileEntries(in roots: [URL], recursive: Bool, itemLimit: Int) throws -> [FileEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]
        var result: [FileEntry] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            if recursive {
                guard let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                for case let url as URL in enumerator {
                    if result.count >= itemLimit { return result }
                    if result.count.isMultiple(of: 500) { try Task.checkCancellation() }
                    guard let values = try? url.resourceValues(forKeys: Set(keys)),
                          values.isRegularFile == true,
                          values.isSymbolicLink != true else { continue }
                    result.append(.init(url: url, size: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate))
                }
            } else {
                let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
                for url in urls.prefix(itemLimit) {
                    guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                    result.append(.init(url: url, size: Int64(values.fileSize ?? 0), modifiedAt: values.contentModificationDate))
                }
            }
        }
        return result
    }

    private static func directorySize(_ url: URL, itemLimit: Int) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return 0 }
        var total: Int64 = 0
        var count = 0
        for case let file as URL in enumerator {
            if count >= itemLimit || Task.isCancelled { break }
            count += 1
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static func sha256(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            guard let data = try? handle.read(upToCount: 1_048_576), !data.isEmpty else { return false }
            hasher.update(data: data)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func topProcesses(limit: Int) throws -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,%cpu=,%mem=,comm=", "-r"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        return text.split(separator: "\n").prefix(limit).map { line in
            line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/Applications/", with: "")
        }
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
