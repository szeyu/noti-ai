import Foundation

/// Claude Messages API over raw HTTP (there is no official Swift SDK).
enum AnthropicClient {
    /// Models that accept the server-side refusal fallback (`fallbacks: "default"`).
    private static let fallbackModels: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-2", "claude-fable-5-1",
    ]

    private static func request(_ path: String, key: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/\(path)")!)
        req.timeoutInterval = 120
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        return req
    }

    static func ask(_ text: String, settings: ProviderSettings, config: Config) async throws -> String {
        let model = settings.model.isEmpty ? Provider.anthropic.defaultModel : settings.model
        var req = request("messages", key: settings.apiKey)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")

        var body: [String: Any] = [
            "model": model,
            // Thinking is always on for current models and spends from this budget too,
            // so leave plenty of room; the prompt keeps the visible reply short.
            "max_tokens": 16000,
            "system": config.systemPrompt,
            "output_config": ["effort": config.effort],
            "messages": [["role": "user", "content": text]],
        ]
        if fallbackModels.contains(model) {
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
            body["fallbacks"] = "default"
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (status, json, data) = try await HTTP.send(req)
        guard status == 200 else { throw AIError.http(status, HTTP.errorMessage(json, data)) }

        let stopReason = json["stop_reason"] as? String ?? "unknown"
        if stopReason == "refusal" {
            let details = json["stop_details"] as? [String: Any]
            throw AIError.refused(details?["explanation"] as? String ?? "")
        }

        // Content may start with thinking blocks; keep only the text.
        let answer = (json["content"] as? [[String: Any]] ?? [])
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !answer.isEmpty else { throw AIError.empty(stopReason) }
        return stopReason == "max_tokens" ? answer + " …(cut off)" : answer
    }

    static func models(settings: ProviderSettings) async throws -> [String] {
        var req = request("models?limit=100", key: settings.apiKey)
        req.timeoutInterval = 20
        let (status, json, data) = try await HTTP.send(req)
        guard status == 200 else { throw AIError.http(status, HTTP.errorMessage(json, data)) }
        return (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
    }
}
