import Foundation

/// OpenAI chat-completions client. Also serves OpenRouter, Ollama, LM Studio and any
/// other server that implements the same endpoint.
enum OpenAIClient {
    static func ask(_ text: String, provider: Provider, settings: ProviderSettings,
                    config: Config) async throws -> String {
        var req = try request(provider: provider, settings: settings, path: "chat/completions")
        guard !settings.model.isEmpty else { throw AIError.missingModel }
        req.httpMethod = "POST"
        req.timeoutInterval = 180 // local models can be slow to load
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        // Deliberately no token limit or reasoning options: their names differ between
        // servers and models, and the defaults are fine for short answers.
        let body: [String: Any] = [
            "model": settings.model,
            "messages": [
                ["role": "system", "content": config.systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (status, json, data) = try await HTTP.send(req)
        // Some servers (OpenRouter) report failures inside a 200 response.
        guard status == 200, json["error"] == nil else {
            throw AIError.http(status, HTTP.errorMessage(json, data))
        }

        let choice = (json["choices"] as? [[String: Any]])?.first
        let finish = choice?["finish_reason"] as? String ?? "unknown"
        let message = choice?["message"] as? [String: Any]
        if let refusal = message?["refusal"] as? String, !refusal.isEmpty {
            throw AIError.refused(refusal)
        }

        let answer = stripThinking(content(of: message?["content"]))
        guard !answer.isEmpty else { throw AIError.empty(finish) }
        return finish == "length" ? answer + " …(cut off)" : answer
    }

    static func models(provider: Provider, settings: ProviderSettings) async throws -> [String] {
        var req = try request(provider: provider, settings: settings, path: "models")
        req.timeoutInterval = 20
        let (status, json, data) = try await HTTP.send(req)
        guard status == 200 else { throw AIError.http(status, HTTP.errorMessage(json, data)) }
        return (json["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: - Helpers

    private static func request(provider: Provider, settings: ProviderSettings,
                                path: String) throws -> URLRequest {
        if provider.key == .required && settings.apiKey.isEmpty { throw AIError.missingKey(provider) }
        let base = normalize(settings.baseURL.isEmpty ? provider.defaultBaseURL : settings.baseURL)
        guard !base.isEmpty, let url = URL(string: base + "/" + path) else { throw AIError.missingBaseURL }
        var req = URLRequest(url: url)
        if !settings.apiKey.isEmpty {
            req.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        }
        if provider == .openrouter { req.setValue("Noti AI", forHTTPHeaderField: "X-Title") }
        return req
    }

    /// Accepts "localhost:11434", "http://host/v1/", or a pasted ".../chat/completions" URL.
    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        if !s.contains("://") { s = (s.hasPrefix("localhost") || s.hasPrefix("127.") ? "http://" : "https://") + s }
        while s.hasSuffix("/") { s.removeLast() }
        for suffix in ["/chat/completions", "/completions", "/models"] where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
        }
        // A bare host ("http://localhost:11434") almost always means the /v1 API.
        if let url = URL(string: s), url.path.isEmpty || url.path == "/" { s += "/v1" }
        return s
    }

    /// `content` may be a string, null, or an array of `{type: "text", text: …}` parts.
    private static func content(of value: Any?) -> String {
        if let s = value as? String { return s }
        if let parts = value as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }

    /// Local reasoning models often inline their chain of thought as <think>…</think>.
    static func stripThinking(_ text: String) -> String {
        var s = text
        while let open = s.range(of: "<think>") {
            if let close = s.range(of: "</think>", range: open.upperBound..<s.endIndex) {
                s.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                s.removeSubrange(open.lowerBound..<s.endIndex) // never closed: drop the rest
            }
        }
        // Some servers strip the opening tag but keep the closing one.
        if let close = s.range(of: "</think>") { s.removeSubrange(s.startIndex..<close.upperBound) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
