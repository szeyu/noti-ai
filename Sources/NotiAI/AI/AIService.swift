import Foundation

/// The one entry point the rest of the app uses: routes to the right client.
enum AIService {
    /// Sent with a screenshot, since the instructions talk about highlighted text.
    static let screenshotNote = "This is a screenshot of an area of my screen. Treat what it shows as the text I highlighted."

    static func ask(_ text: String, image: EncodedImage? = nil, config: Config) async throws -> String {
        let settings = config.settings(for: config.provider)
        do {
            switch config.provider {
            case .anthropic:
                guard !settings.apiKey.isEmpty else { throw AIError.missingKey(.anthropic) }
                return try await AnthropicClient.ask(text, image: image, settings: settings, config: config)
            default:
                return try await OpenAIClient.ask(text, image: image, provider: config.provider,
                                                  settings: settings, config: config)
            }
        } catch AIError.http(let status, let message) where image != nil && (400..<500).contains(status) && status != 401 && status != 429 {
            // The usual cause: a text-only model. Say so instead of only echoing the server.
            let sep = message.hasSuffix(".") ? " " : ". "
            throw AIError.http(status, message + sep + "If this model can't read images, choose one that can.")
        }
    }

    static func models(provider: Provider, settings: ProviderSettings) async throws -> [String] {
        switch provider {
        case .anthropic:
            guard !settings.apiKey.isEmpty else { throw AIError.missingKey(.anthropic) }
            return try await AnthropicClient.models(settings: settings)
        default:
            return try await OpenAIClient.models(provider: provider, settings: settings)
        }
    }
}
