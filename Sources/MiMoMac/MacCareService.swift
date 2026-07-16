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

struct FileOrganizationMove: Sendable {
    let source: URL
    let destinationDirectory: URL
}

struct OrganizationResult: Sendable {
    let moved: Int
    let skipped: Int
    let failures: [String]
}

enum MacCareAction: Sendable {
    case cleanSafe
    case organizeDownloads([FileOrganizationMove])
    case revealFiles([URL])
    case openLoginItems
    case openActivityMonitor
    case runTool(MacCareTool)
}

struct MacCareRecommendation: Identifiable, Sendable {
    let id: UUID
    let title: String
    let benefit: String
    let risk: String
    let buttonTitle: String
    let action: MacCareAction

    init(
        id: UUID = UUID(),
        title: String,
        benefit: String,
        risk: String,
        buttonTitle: String,
        action: MacCareAction
    ) {
        self.id = id
        self.title = title
        self.benefit = benefit
        self.risk = risk
        self.buttonTitle = buttonTitle
        self.action = action
    }
}

struct MacCareReport: Sendable {
    let tool: MacCareTool
    let headline: String
    let details: [String]
    let cleanupPlan: LevelScanResult?
    let recommendations: [MacCareRecommendation]

    init(
        tool: MacCareTool,
        headline: String,
        details: [String],
        cleanupPlan: LevelScanResult? = nil,
        recommendations: [MacCareRecommendation] = []
    ) {
        self.tool = tool
        self.headline = headline
        self.details = details
        self.cleanupPlan = cleanupPlan
        self.recommendations = recommendations
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

    static func organizeDownloads(_ moves: [FileOrganizationMove], allowedRoot: URL? = nil) -> OrganizationResult {
        let manager = FileManager.default
        let downloads = (allowedRoot ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true))
            .standardizedFileURL
        var moved = 0
        var skipped = 0
        var failures: [String] = []

        for move in moves {
            if Task.isCancelled { break }
            let source = move.source.standardizedFileURL
            let directory = move.destinationDirectory.standardizedFileURL
            guard source.path.hasPrefix(downloads.path + "/"),
                  directory.path.hasPrefix(downloads.path + "/"),
                  manager.fileExists(atPath: source.path) else {
                skipped += 1
                continue
            }
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(source.lastPathComponent)
                guard !manager.fileExists(atPath: destination.path) else {
                    skipped += 1
                    continue
                }
                try manager.moveItem(at: source, to: destination)
                moved += 1
            } catch {
                failures.append("\(source.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return .init(moved: moved, skipped: skipped, failures: failures)
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
        var recommendations: [MacCareRecommendation] = []
        if usedRatio > 0.8 {
            recommendations.append(.init(
                title: "继续检查可释放空间",
                benefit: "定位安全缓存，通常能缓解磁盘空间紧张并减少临时文件堆积。",
                risk: "下一步仍然只扫描；真正清理前会再次确认。",
                buttonTitle: "扫描垃圾",
                action: .runTool(.junkScan)
            ))
        }
        if !processes.isEmpty {
            recommendations.append(.init(
                title: "检查当前高负载进程",
                benefit: "确认持续占用 CPU 的应用，有助于降低发热和耗电。",
                risk: "只打开活动监视器，不会自动结束进程；强制退出前请保存工作。",
                buttonTitle: "打开活动监视器",
                action: .openActivityMonitor
            ))
        }
        return .init(tool: .systemCheck, headline: headline, details: details, recommendations: recommendations)
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
        let recommendations: [MacCareRecommendation] = plan.totalBytes > 0 ? [.init(
            title: "清理白名单缓存与日志",
            benefit: "预计释放约 \(format(plan.totalBytes))，并减少过期临时文件占用。",
            risk: "仅处理白名单缓存和日志，移到废纸篓以便恢复；应用之后可能重新生成缓存。",
            buttonTitle: "确认清理",
            action: .cleanSafe
        )] : []
        return .init(
            tool: .junkScan,
            headline: "白名单引擎扫描到约 \(format(plan.totalBytes)) 的安全清理候选，当前只是预览，没有删除。",
            details: details.isEmpty ? ["没有扫描到安全清理候选"] : details,
            cleanupPlan: plan.totalBytes > 0 ? plan : nil,
            recommendations: recommendations
        )
    }

    private static func organizePreview() throws -> MacCareReport {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        let entries = try fileEntries(in: [downloads], recursive: false, itemLimit: 20_000)
        var groups: [String: Int] = [:]
        var moves: [FileOrganizationMove] = []
        for entry in entries {
            let ext = entry.url.pathExtension.lowercased()
            let category: String
            if ["png", "jpg", "jpeg", "gif", "heic", "webp", "svg"].contains(ext) { category = "图片" }
            else if ["mp4", "mov", "mkv", "avi", "mp3", "wav", "m4a"].contains(ext) { category = "影音" }
            else if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md"].contains(ext) { category = "文档" }
            else if ["zip", "rar", "7z", "dmg", "pkg"].contains(ext) { category = "安装包与压缩包" }
            else { category = "其他" }
            groups[category, default: 0] += 1
            moves.append(.init(source: entry.url, destinationDirectory: downloads.appendingPathComponent(category, isDirectory: true)))
        }
        let details = groups.sorted { $0.key < $1.key }.map { "\($0.key)：\($0.value) 个" }
        let recommendations: [MacCareRecommendation] = moves.isEmpty ? [] : [.init(
            title: "按类型整理下载文件夹",
            benefit: "将 \(moves.count) 个文件归入图片、影音、文档、安装包与其他分类，查找文件更快。",
            risk: "会创建分类文件夹并移动文件；不会改名、覆盖同名文件或删除内容。",
            buttonTitle: "确认整理",
            action: .organizeDownloads(moves)
        )]
        return .init(
            tool: .organize,
            headline: "下载文件夹共有 \(entries.count) 个文件，可按类型生成文件夹；当前没有移动。",
            details: details.isEmpty ? ["下载文件夹当前没有可整理文件"] : details,
            recommendations: recommendations
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
        let recommendations: [MacCareRecommendation] = entries.isEmpty ? [] : [.init(
            title: "逐个检查大型文件",
            benefit: "在 Finder 中定位体积最大的文件，删除或转移不需要的项目可以直接释放空间。",
            risk: "浮屿不会自动删除个人文件；请确认内容和备份后自行处理。",
            buttonTitle: "在 Finder 中显示",
            action: .revealFiles(Array(entries.prefix(20).map(\.url)))
        )]
        return .init(
            tool: .largeFiles,
            headline: "找到 \(entries.count) 个超过 200 MB 的文件，合计 \(format(total))。",
            details: details.isEmpty ? ["常用目录中没有超过 200 MB 的文件"] : details,
            recommendations: recommendations
        )
    }

    private static func duplicateScan() throws -> MacCareReport {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
        let entries = try fileEntries(in: roots, recursive: true, itemLimit: 60_000)
            .filter { $0.size >= 1_024 * 1_024 }
        let candidates = Dictionary(grouping: entries, by: \FileEntry.size).values.filter { $0.count > 1 }
        var hashes: [String: [FileEntry]] = [:]
        var hashedFiles = 0
        for group in candidates {
            for entry in group.prefix(20) {
                guard hashedFiles < 600 else { break }
                try Task.checkCancellation()
                if let digest = sha256(entry.url) { hashes[digest, default: []].append(entry) }
                hashedFiles += 1
            }
            if hashedFiles >= 600 { break }
        }
        let duplicateGroups = hashes.values.filter { $0.count > 1 }
        let reclaimable = duplicateGroups.reduce(Int64(0)) { total, group in
            total + Int64(group.count - 1) * (group.first?.size ?? 0)
        }
        let details = duplicateGroups.prefix(10).map { group in
            let locations = group.prefix(3).map { $0.url.deletingLastPathComponent().lastPathComponent }.joined(separator: "、")
            return "\(group.first?.url.lastPathComponent ?? "重复文件")：\(group.count) 份，单份 \(format(group.first?.size ?? 0)) · \(locations)"
        }
        let duplicateURLs = duplicateGroups.flatMap { $0.map(\.url) }
        let recommendations: [MacCareRecommendation] = duplicateURLs.isEmpty ? [] : [.init(
            title: "核对哈希一致的重复文件",
            benefit: "预计最多可释放 \(format(reclaimable))，同时保留每组至少一份原文件。",
            risk: "不同文件夹中的同名副本可能都有用途；浮屿只负责定位，不自动删除。",
            buttonTitle: "在 Finder 中核对",
            action: .revealFiles(Array(duplicateURLs.prefix(30)))
        )]
        return .init(
            tool: .duplicates,
            headline: "用文件哈希确认 \(duplicateGroups.count) 组重复项，预计可释放 \(format(reclaimable))。",
            details: details.isEmpty ? ["常用目录中暂未发现明确重复项"] : details,
            recommendations: recommendations
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
        let details = files.map { $0.deletingPathExtension().lastPathComponent }
        let recommendations: [MacCareRecommendation] = files.isEmpty ? [] : [.init(
            title: "检查并关闭不需要的登录项",
            benefit: "减少不必要的后台常驻，可能缩短开机时间、降低内存占用和待机耗电。",
            risk: "关闭同步、驱动或安全软件的启动项可能影响对应功能；请按名称逐项确认。",
            buttonTitle: "打开登录项设置",
            action: .openLoginItems
        )]
        return .init(
            tool: .loginItems,
            headline: "本机发现 \(files.count) 个后台启动配置，当前没有停用。",
            details: details.isEmpty ? ["没有发现 LaunchAgent 或 LaunchDaemon 配置"] : details,
            recommendations: recommendations
        )
    }

    private static func hotProcessScan() throws -> MacCareReport {
        let processes = try topProcesses(limit: 10)
        let recommendations: [MacCareRecommendation] = processes.isEmpty ? [] : [.init(
            title: "在活动监视器中确认高负载",
            benefit: "持续高负载应用退出后通常可以降低温度、风扇噪声和耗电。",
            risk: "强制退出可能丢失未保存内容；系统进程不建议随意结束。",
            buttonTitle: "打开活动监视器",
            action: .openActivityMonitor
        )]
        return .init(
            tool: .hotProcesses,
            headline: "已直接读取当前 CPU 与内存占用，没有结束任何进程。",
            details: processes.isEmpty ? ["当前未取得进程快照"] : processes,
            recommendations: recommendations
        )
    }

    private static func appLeftoverScan() throws -> MacCareReport {
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: cache,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let sized = urls.prefix(60).map { ($0, directorySize($0, itemLimit: 4_000)) }.sorted { $0.1 > $1.1 }
        let details = sized.prefix(10).map { "\($0.0.lastPathComponent)：约 \(format($0.1))" }
        let total = sized.reduce(Int64(0)) { $0 + $1.1 }
        let candidateURLs = sized.prefix(20).map(\.0)
        let recommendations: [MacCareRecommendation] = candidateURLs.isEmpty ? [] : [.init(
            title: "检查体积最大的应用缓存",
            benefit: "确认已经卸载或不再使用的应用后，可针对性释放缓存空间。",
            risk: "缓存目录不等于卸载残留；直接删除仍在使用的缓存可能导致重新下载或状态丢失，因此只定位不自动清理。",
            buttonTitle: "在 Finder 中检查",
            action: .revealFiles(candidateURLs)
        )]
        return .init(
            tool: .appLeftovers,
            headline: "已列出体积最大的应用缓存候选（合计约 \(format(total))），需确认应用来源后才能删除。",
            details: details.isEmpty ? ["没有发现应用缓存目录"] : details,
            recommendations: recommendations
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
        var recommendations: [MacCareRecommendation] = []
        if cache > 0 {
            recommendations.append(.init(
                title: "先扫描安全缓存",
                benefit: "定位可安全移到废纸篓的缓存和日志，预计释放空间并减少临时文件堆积。",
                risk: "下一步只扫描，清理前仍会显示具体容量并再次确认。",
                buttonTitle: "扫描可清理项",
                action: .runTool(.junkScan)
            ))
        }
        if !oldDownloads.isEmpty {
            recommendations.append(.init(
                title: "检查长期未使用的下载文件",
                benefit: "清理或归档 \(oldDownloads.count) 个 90 天以上文件，可释放空间并减少下载目录混乱。",
                risk: "不会自动删除个人文件，只在 Finder 中定位供你确认。",
                buttonTitle: "在 Finder 中显示",
                action: .revealFiles(Array(oldDownloads.prefix(20).map(\.url)))
            ))
        }
        recommendations.append(.init(
            title: "确认当前高负载进程",
            benefit: "识别持续耗电或发热的应用，关闭不需要的任务可改善续航和温度。",
            risk: "只打开活动监视器；结束应用前请保存正在处理的内容。",
            buttonTitle: "打开活动监视器",
            action: .openActivityMonitor
        ))
        return .init(
            tool: .optimization,
            headline: "本机快速优化分析完成，以下项目按收益优先检查。",
            details: details,
            recommendations: recommendations
        )
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
