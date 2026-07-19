import Foundation

struct VoiceboxHealth: Decodable, Sendable {
    let status: String
    let modelLoaded: Bool
    let gpuAvailable: Bool
    let gpuType: String?
    let backendType: String?

    enum CodingKeys: String, CodingKey {
        case status
        case modelLoaded = "model_loaded"
        case gpuAvailable = "gpu_available"
        case gpuType = "gpu_type"
        case backendType = "backend_type"
    }
}

private struct VoiceboxProfile: Decodable, Sendable {
    let id: String
    let name: String
}

private struct VoiceboxTranscription: Decodable, Sendable {
    let text: String
    let duration: Double
}

enum VoiceboxClientError: LocalizedError {
    case invalidEndpoint
    case unavailable
    case noVoiceProfile
    case requestFailed(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "Voicebox 服务地址无效。"
        case .unavailable: "Voicebox 本地服务尚未启动。"
        case .noVoiceProfile: "Voicebox 里还没有可用的声音档案。"
        case let .requestFailed(code, detail): "Voicebox 请求失败（\(code)）：\(detail)"
        case .invalidResponse: "Voicebox 返回了无法识别的数据。"
        }
    }
}

actor VoiceboxClient {
    func health(baseURL: String) async throws -> VoiceboxHealth {
        let request = try makeRequest(baseURL: baseURL, path: "/health")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(VoiceboxHealth.self, from: data)
    }

    func transcribe(
        fileURL: URL,
        baseURL: String,
        model: String,
        language: String = "zh"
    ) async throws -> String {
        var request = try makeRequest(baseURL: baseURL, path: "/transcribe")
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        let boundary = "FuYuVoicebox\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let audio = try Data(contentsOf: fileURL)
        var body = Data()
        body.appendFormField(name: "language", value: language, boundary: boundary)
        body.appendFormField(name: "model", value: model, boundary: boundary)
        body.appendFileField(
            name: "file",
            filename: fileURL.lastPathComponent,
            mimeType: "audio/wav",
            data: audio,
            boundary: boundary
        )
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let result = try JSONDecoder().decode(VoiceboxTranscription.self, from: data)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func synthesize(
        text: String,
        baseURL: String,
        profileNameOrID: String,
        modelSize: String,
        instructions: String
    ) async throws -> Data {
        let profileID = try await resolveProfileID(baseURL: baseURL, preferred: profileNameOrID)
        var request = try makeRequest(baseURL: baseURL, path: "/generate/stream")
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "profile_id": profileID,
            "text": text,
            "language": "zh",
            "model_size": modelSize,
            "instruct": String(instructions.prefix(500)),
            "normalize": true,
            "max_chunk_chars": 500,
            "crossfade_ms": 45
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        guard data.count > 44 else { throw VoiceboxClientError.invalidResponse }
        return data
    }

    func unloadModel(named modelName: String, baseURL: String) async throws {
        var request = try makeRequest(
            baseURL: baseURL,
            path: "/models/\(modelName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelName)/unload"
        )
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
    }

    nonisolated static func isThreadAffinityFailure(_ error: Error) -> Bool {
        error.localizedDescription.contains("There is no Stream")
            && error.localizedDescription.contains("current thread")
    }

    private func resolveProfileID(baseURL: String, preferred: String) async throws -> String {
        let request = try makeRequest(baseURL: baseURL, path: "/profiles")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let profiles = try JSONDecoder().decode([VoiceboxProfile].self, from: data)
        let value = preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        if let matched = profiles.first(where: { $0.id == value || $0.name == value }) {
            return matched.id
        }
        guard let first = profiles.first else { throw VoiceboxClientError.noVoiceProfile }
        return first.id
    }

    private func makeRequest(baseURL: String, path: String) throws -> URLRequest {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + path),
              url.scheme == "http" || url.scheme == "https" else {
            throw VoiceboxClientError.invalidEndpoint
        }
        return URLRequest(url: url)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw VoiceboxClientError.unavailable
        }
        guard (200..<300).contains(http.statusCode) else {
            let detail = String(data: data, encoding: .utf8).map { String($0.prefix(240)) } ?? ""
            throw VoiceboxClientError.requestFailed(http.statusCode, detail)
        }
    }
}

private extension Data {
    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }

    mutating func appendFileField(
        name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }
}
