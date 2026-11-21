import Foundation

enum AIError: LocalizedError {
    case missingKey(Provider)
    case missingModel
    case missingBaseURL
    case http(Int, String)
    case refused(String)
    case empty(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .missingKey(let p):
            return "No \(p.shortName) API key yet. Open Settings from the Noti AI menu bar icon and paste one."
        case .missingModel:
            return "No model chosen. Open Settings, click Fetch, and pick a model."
        case .missingBaseURL:
            return "No server address. Open Settings and enter the base URL."
        case .http(let code, let msg):
            return "The AI service returned an error (\(code)): \(msg)"
        case .refused(let why):
            return "The model declined to answer. \(why)"
        case .empty(let reason):
            return "The model returned no text (stopped because: \(reason))."
        case .network(let msg):
            return "Couldn't reach the AI service: \(msg)"
        }
    }
}

/// Shared HTTP plumbing for the clients.
enum HTTP {
    static func send(_ req: URLRequest) async throws -> (Int, [String: Any], Data) {
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            return ((response as? HTTPURLResponse)?.statusCode ?? 0, json, data)
        } catch {
            throw AIError.network(error.localizedDescription)
        }
    }

    /// Pulls a readable message out of the usual `{"error": {"message": …}}` shapes.
    static func errorMessage(_ json: [String: Any], _ data: Data) -> String {
        if let e = json["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let e = json["error"] as? String { return e }
        let raw = String(data: data, encoding: .utf8) ?? ""
        return raw.isEmpty ? "no details" : String(raw.prefix(300))
    }
}
