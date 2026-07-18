import Foundation

/// A local, layered memory system inspired by mature agent runtimes:
/// working task focus + full episodic archive + relevance retrieval.
final class FuYuMemorySystem {
    struct TaskFocus: Codable, Equatable {
        enum Status: String, Codable {
            case discussing
            case awaitingApproval
            case executing
            case paused
            case completed
            case failed
            case cancelled
        }

        var request: String
        var lastAssistantContext: String
        var status: Status
        var createdAt: Date?
        var updatedAt: Date
    }

    private let archiveURL: URL
    private let focusURL: URL
    private(set) var focus: TaskFocus?
    private var archiveItems: [AppState.ConversationItem] = []

    init(historyURL: URL) {
        let stem = historyURL.deletingPathExtension()
        archiveURL = stem.appendingPathExtension("archive.jsonl")
        focusURL = stem.appendingPathExtension("task-focus.json")
        if let data = try? Data(contentsOf: focusURL) {
            focus = try? JSONDecoder().decode(TaskFocus.self, from: data)
        }
        archiveItems = Self.loadArchive(from: archiveURL)
    }

    func bootstrapArchiveIfNeeded(with items: [AppState.ConversationItem]) {
        guard !FileManager.default.fileExists(atPath: archiveURL.path) else {
            if archiveItems.isEmpty { archiveItems = Self.loadArchive(from: archiveURL) }
            return
        }
        do {
            try FileManager.default.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let payload = try items.map { item -> Data in
                var line = try JSONEncoder().encode(item)
                line.append(0x0A)
                return line
            }.reduce(into: Data(), { $0.append($1) })
            try payload.write(to: archiveURL, options: .atomic)
            archiveItems = items
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
        } catch {
            // Conversation history remains the fallback and bootstrap retries next launch.
        }
    }

    func bootstrapWorkingFocusIfNeeded(with items: [AppState.ConversationItem]) {
        guard focus == nil,
              let userIndex = items.lastIndex(where: {
                  $0.kind == .user
                      && $0.text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4
                      && !Self.isContextDependent($0.text)
              }) else { return }
        let request = items[userIndex].text
        let tail = items.suffix(from: items.index(after: userIndex))
        let assistantContext = tail.last(where: { $0.kind == .assistant })?.text ?? ""
        let status: TaskFocus.Status
        if tail.contains(where: { $0.kind == .error }) {
            status = .failed
        } else if tail.contains(where: { $0.kind == .action && $0.text.contains("等待确认") }) {
            status = .awaitingApproval
        } else if tail.contains(where: { $0.kind == .action && ($0.text.contains("正在执行") || $0.text.contains("本机执行")) }) {
            status = .executing
        } else {
            status = .discussing
        }
        focus = .init(
            request: String(request.prefix(1_500)),
            lastAssistantContext: String(assistantContext.prefix(1_500)),
            status: status,
            createdAt: items[userIndex].createdAt,
            updatedAt: Date()
        )
        persistFocus()
    }

    func append(_ item: AppState.ConversationItem) {
        do {
            let manager = FileManager.default
            try manager.createDirectory(at: archiveURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !manager.fileExists(atPath: archiveURL.path) { manager.createFile(atPath: archiveURL.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: archiveURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            var data = try JSONEncoder().encode(item)
            data.append(0x0A)
            try handle.write(contentsOf: data)
            archiveItems.append(item)
            try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: archiveURL.path)
        } catch {
            // The bounded UI history remains available; later messages retry archival.
        }
    }

    func relevantHistory(
        for query: String,
        excluding excludedIDs: Set<UUID>,
        limit: Int = 8
    ) -> [AppState.ConversationItem] {
        let queryTerms = Self.terms(query)
        let temporalRange = Self.temporalRange(for: query, now: Date())
        guard !queryTerms.isEmpty || temporalRange != nil else { return [] }

        return archiveItems
            .filter { !excludedIDs.contains($0.id) }
            .enumerated()
            .map { index, item in
                let overlap = queryTerms.intersection(Self.terms(item.text)).count
                let taskBonus = item.kind == .action ? 1 : 0
                let recencyBonus = index / 150
                let temporalBonus: Int
                if let temporalRange, temporalRange.contains(item.createdAt) {
                    temporalBonus = 40
                } else {
                    temporalBonus = 0
                }
                return (index: index, item: item, score: overlap * 5 + taskBonus + recencyBonus + temporalBonus)
            }
            .filter { $0.score > 0 }
            .sorted {
                if $0.score == $1.score { return $0.index > $1.index }
                return $0.score > $1.score
            }
            .prefix(limit)
            .sorted { $0.index < $1.index }
            .map(\.item)
    }

    static func temporalRange(for query: String, now: Date) -> Range<Date>? {
        let compact = query.filter { $0.isLetter || $0.isNumber }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let dayOffset: Int?
        if compact.contains("前天") {
            dayOffset = -2
        } else if compact.contains("昨天") || compact.contains("昨日") {
            dayOffset = -1
        } else if compact.contains("今天") || compact.contains("今日") {
            dayOffset = 0
        } else {
            dayOffset = nil
        }
        guard let dayOffset,
              let start = calendar.date(byAdding: .day, value: dayOffset, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
        return start..<end
    }

    func observeUserMessage(_ text: String) {
        guard !Self.isContextDependent(text) else {
            touchFocus()
            return
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 4 else { return }
        let now = Date()
        focus = .init(
            request: String(value.prefix(1_500)),
            lastAssistantContext: "",
            status: .discussing,
            createdAt: now,
            updatedAt: now
        )
        persistFocus()
    }

    func observeAssistantReply(_ text: String) {
        guard var current = focus else { return }
        current.lastAssistantContext = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1_500))
        current.updatedAt = Date()
        focus = current
        persistFocus()
    }

    func markFocus(_ status: TaskFocus.Status) {
        guard var current = focus else { return }
        current.status = status
        current.updatedAt = Date()
        focus = current
        persistFocus()
    }

    func contextualizedRequest(_ text: String) -> String {
        let commandTime = AppState.memoryTimestamp(for: Date())
        guard Self.isContextDependent(text), let focus else {
            return "[当前命令时间：\(commandTime)]\n用户命令：\(text)"
        }
        let taskTime = AppState.memoryTimestamp(for: focus.createdAt ?? focus.updatedAt)
        return """
        [当前命令时间：\(commandTime)]
        用户命令：\(text)

        [浮屿工作记忆：这是一句承接上文的短指令，不是新会话。]
        当前任务（创建于 \(taskTime)）：\(focus.request)
        当前状态：\(focus.status.rawValue)
        浮屿上一轮关于该任务的说明：\(focus.lastAssistantContext.isEmpty ? "无" : focus.lastAssistantContext)
        请直接承接这个任务，不要要求用户重新解释。
        """
    }

    var focusPrompt: String {
        guard let focus else { return "当前没有已记录的工作任务。" }
        let created = AppState.memoryTimestamp(for: focus.createdAt ?? focus.updatedAt)
        let updated = AppState.memoryTimestamp(for: focus.updatedAt)
        return "当前任务（创建于 \(created)）：\(focus.request)\n状态：\(focus.status.rawValue)\n最后更新：\(updated)\n上一轮任务说明：\(focus.lastAssistantContext.isEmpty ? "无" : focus.lastAssistantContext)"
    }

    func clear() throws {
        focus = nil
        archiveItems.removeAll()
        let manager = FileManager.default
        for url in [archiveURL, focusURL] where manager.fileExists(atPath: url.path) {
            try manager.removeItem(at: url)
        }
    }

    static func isContextDependent(_ text: String) -> Bool {
        let compact = text.filter { $0.isLetter || $0.isNumber }.lowercased()
        let signals = [
            "去吧", "继续", "继续吧", "执行吧", "就这个", "就这样", "现在呢", "然后呢", "这个呢",
            "刚才那个", "上一个", "为什么", "为啥", "怎么不行", "现在知道了吗", "我刚让你干嘛",
            "按这个来", "照这个做", "确认", "可以", "好的", "没记忆", "没有记忆", "失忆",
            "你还记得", "记得我刚才"
        ]
        return compact.count <= 24 && signals.contains(where: compact.contains)
    }

    private func touchFocus() {
        guard var current = focus else { return }
        current.updatedAt = Date()
        focus = current
        persistFocus()
    }

    private func persistFocus() {
        guard let focus else { return }
        do {
            try FileManager.default.createDirectory(at: focusURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(focus).write(to: focusURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: focusURL.path)
        } catch {
            // Working focus remains available for the current process.
        }
    }

    private static func terms(_ text: String) -> Set<String> {
        let normalized = text.lowercased().filter { $0.isLetter || $0.isNumber }
        let characters = Array(normalized)
        var result = Set<String>()
        for index in characters.indices {
            if index + 1 < characters.count { result.insert(String(characters[index...index + 1])) }
            if index + 2 < characters.count { result.insert(String(characters[index...index + 2])) }
        }
        return result
    }

    private static func loadArchive(from url: URL) -> [AppState.ConversationItem] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            try? JSONDecoder().decode(AppState.ConversationItem.self, from: Data(line.utf8))
        }
    }
}
