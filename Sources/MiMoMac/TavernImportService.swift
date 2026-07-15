import Foundation

struct TavernImportField: Identifiable, Equatable {
    let id: String
    let title: String
    let text: String
}

struct ImportedTavernPersona {
    let sourceURL: URL
    let format: String
    let name: String
    let background: String
    let traits: String
    let style: String
    let fields: [TavernImportField]
    let warnings: [String]

    var displayName: String {
        name.isEmpty ? sourceURL.deletingPathExtension().lastPathComponent : name
    }
}

struct ImportedTavernPreset {
    let sourceURL: URL
    let name: String
    let sections: [TavernImportField]

    var composedPrompt: String {
        sections.map { "[\($0.title)]\n\($0.text)" }.joined(separator: "\n\n")
    }
}

enum TavernImportPreview: Identifiable {
    case character(ImportedTavernPersona)
    case preset(ImportedTavernPreset)

    var id: String {
        switch self {
        case let .character(value): "character-\(value.sourceURL.path)"
        case let .preset(value): "preset-\(value.sourceURL.path)"
        }
    }
}

enum TavernImportError: LocalizedError {
    case unsupportedFile
    case missingCardData
    case invalidPreset

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "无法识别这个文件。支持酒馆角色卡 V1/V2 JSON 和带 chara 数据的 PNG 角色卡。"
        case .missingCardData: "角色卡中没有找到可导入的人物字段。"
        case .invalidPreset: "预设中没有找到可用的提示词字段。"
        }
    }
}

enum TavernImportService {
    static func importCharacter(from url: URL) throws -> ImportedTavernPersona {
        let data = try Data(contentsOf: url)
        let jsonData: Data
        let sourceFormat: String
        if url.pathExtension.lowercased() == "png" {
            guard let embedded = embeddedCharacterJSON(in: data) else {
                throw TavernImportError.unsupportedFile
            }
            jsonData = embedded
            sourceFormat = "PNG 角色卡"
        } else {
            jsonData = data
            sourceFormat = "JSON 角色卡"
        }

        guard let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw TavernImportError.unsupportedFile
        }
        let isV2 = (root["spec"] as? String)?.lowercased().contains("chara_card_v2") == true
            || root["data"] is [String: Any]
        let payload = root["data"] as? [String: Any] ?? root
        func string(_ key: String) -> String {
            (payload[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        let name = string("name")
        let description = string("description")
        let scenario = string("scenario")
        let personality = string("personality")
        let firstMessage = string("first_mes")
        let examples = string("mes_example")
        let systemPrompt = string("system_prompt")
        let postHistory = string("post_history_instructions")
        guard !name.isEmpty || !description.isEmpty || !personality.isEmpty else {
            throw TavernImportError.missingCardData
        }

        let available: [(String, String, String)] = [
            ("name", "角色名称", name),
            ("description", "人物描述", description),
            ("personality", "性格", personality),
            ("scenario", "场景", scenario),
            ("first_mes", "开场白", firstMessage),
            ("mes_example", "对话示例", examples),
            ("system_prompt", "角色系统提示", systemPrompt),
            ("post_history_instructions", "历史后置提示", postHistory)
        ]
        let fields = available.compactMap { key, title, text in
            text.isEmpty ? nil : TavernImportField(id: key, title: title, text: text)
        }
        var warnings: [String] = []
        if name.isEmpty { warnings.append("角色卡没有名称，将使用文件名。") }
        if firstMessage.isEmpty { warnings.append("角色卡没有开场白，不影响后续对话。") }
        if payload["character_book"] != nil {
            warnings.append("检测到角色知识库；当前版本不会导入知识库条目。")
        }

        let background = [description, scenario]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
        let style = [
            firstMessage.isEmpty ? "" : "开场方式：\(firstMessage)",
            examples.isEmpty ? "" : "对话示例：\(examples)",
            systemPrompt.isEmpty ? "" : "角色系统设定：\(systemPrompt)",
            postHistory.isEmpty ? "" : "对话后置设定：\(postHistory)"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        return ImportedTavernPersona(
            sourceURL: url,
            format: "\(sourceFormat) · Character Card \(isV2 ? "V2" : "V1")",
            name: name,
            background: background,
            traits: personality,
            style: style,
            fields: fields,
            warnings: warnings
        )
    }

    static func previewPreset(from url: URL) throws -> ImportedTavernPreset {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        let acceptedKeys: Set<String> = [
            "main_prompt", "system_prompt", "jailbreak_prompt", "nsfw_prompt",
            "post_history_instructions", "impersonation_prompt", "new_chat_prompt",
            "new_group_chat_prompt", "scenario_format", "personality_format", "wi_format"
        ]
        var values: [(String, String)] = []
        collectStrings(object, acceptedKeys: acceptedKeys, into: &values)
        let unique = values.reduce(into: [(String, String)]()) { result, item in
            guard !result.contains(where: { $0.1 == item.1 }) else { return }
            result.append(item)
        }
        guard !unique.isEmpty else { throw TavernImportError.invalidPreset }
        let fields = unique.map {
            TavernImportField(id: $0.0, title: readablePresetKey($0.0), text: $0.1)
        }
        return ImportedTavernPreset(
            sourceURL: url,
            name: url.deletingPathExtension().lastPathComponent,
            sections: fields
        )
    }

    static func importPreset(from url: URL) throws -> String {
        try previewPreset(from: url).composedPrompt
    }

    private static func readablePresetKey(_ key: String) -> String {
        let names = [
            "main_prompt": "主提示词", "system_prompt": "系统提示词",
            "jailbreak_prompt": "辅助提示词", "nsfw_prompt": "内容提示词",
            "post_history_instructions": "历史后置提示", "impersonation_prompt": "扮演提示",
            "new_chat_prompt": "新对话提示", "new_group_chat_prompt": "群聊提示",
            "scenario_format": "场景格式", "personality_format": "性格格式", "wi_format": "世界信息格式"
        ]
        return names[key] ?? key
    }

    private static func collectStrings(
        _ value: Any,
        acceptedKeys: Set<String>,
        into output: inout [(String, String)]
    ) {
        if let dictionary = value as? [String: Any] {
            for (key, child) in dictionary {
                if acceptedKeys.contains(key),
                   let text = child as? String,
                   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    output.append((key, text))
                } else {
                    collectStrings(child, acceptedKeys: acceptedKeys, into: &output)
                }
            }
        } else if let array = value as? [Any] {
            for child in array { collectStrings(child, acceptedKeys: acceptedKeys, into: &output) }
        }
    }

    private static func embeddedCharacterJSON(in png: Data) -> Data? {
        let bytes = [UInt8](png)
        guard bytes.count > 20,
              Array(bytes.prefix(8)) == [137, 80, 78, 71, 13, 10, 26, 10] else { return nil }
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(bytes[offset]) << 24
                | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8
                | Int(bytes[offset + 3])
            guard length >= 0, offset + 12 + length <= bytes.count else { return nil }
            let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii) ?? ""
            let payload = Array(bytes[(offset + 8)..<(offset + 8 + length)])
            if type == "tEXt", let separator = payload.firstIndex(of: 0) {
                let keyword = String(bytes: payload[..<separator], encoding: .isoLatin1)
                if keyword == "chara" {
                    let encoded = String(bytes: payload[(separator + 1)...], encoding: .isoLatin1) ?? ""
                    if let decoded = Data(base64Encoded: encoded) { return decoded }
                }
            }
            offset += 12 + length
        }
        return nil
    }
}
