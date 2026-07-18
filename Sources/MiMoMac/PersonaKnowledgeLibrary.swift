import Foundation

struct PersonaKnowledgeSelection: Equatable {
    let indexPrompt: String
    let loadedPrompt: String
    let loadedIDs: [String]
    let loadedCharacterCount: Int
}

enum PersonaKnowledgeLibrary {
    static func select(for query: String, enabled: Bool, preset: PersonaPreset) -> PersonaKnowledgeSelection {
        guard enabled, preset == .wanNing else {
            return .init(indexPrompt: "无内置人格档案。", loadedPrompt: "未加载人物档案。", loadedIDs: [], loadedCharacterCount: 0)
        }
        let indexPrompt = "wan-ning-lore：绾宁的身世、穿越、关系、成长与世界观"
        guard shouldLoadLore(for: query), let lore = loadLore() else {
            return .init(
                indexPrompt: indexPrompt,
                loadedPrompt: "当前请求不涉及人物身世或剧情，只使用精简说话风格。",
                loadedIDs: [],
                loadedCharacterCount: 0
            )
        }
        return .init(
            indexPrompt: indexPrompt,
            loadedPrompt: "[已按需加载 wan-ning-lore]\n\(lore)",
            loadedIDs: ["wan-ning-lore"],
            loadedCharacterCount: lore.count
        )
    }

    static func shouldLoadLore(for query: String) -> Bool {
        let value = query.lowercased()
        let triggers = [
            "你是谁", "叫什么", "名字", "从哪来", "哪里人", "身世", "背景", "过去", "以前",
            "经历", "穿越", "古代", "王朝", "铜镜", "书楼", "故事", "世界观", "家人", "父亲",
            "为什么信任", "我们什么关系", "第一次见", "角色设定", "讲讲你"
        ]
        return triggers.contains(where: value.contains)
    }

    static func validationErrors() -> [String] {
        guard let lore = loadLore() else { return ["wan-ning-lore缺少SKILL.md"] }
        var errors: [String] = []
        if !lore.hasPrefix("---\nname:") || !lore.contains("\ndescription:") {
            errors.append("wan-ning-lore的frontmatter不完整")
        }
        return errors
    }

    private static func loadLore() -> String? {
        try? String(contentsOf: rootURL.appendingPathComponent("wan-ning-lore/SKILL.md"), encoding: .utf8)
    }

    private static var rootURL: URL {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("Personas", isDirectory: true),
           FileManager.default.fileExists(atPath: bundled.appendingPathComponent("wan-ning-lore/SKILL.md").path) {
            return bundled
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Personas", isDirectory: true)
    }
}
