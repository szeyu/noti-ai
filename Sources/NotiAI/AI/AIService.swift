import Foundation

/// The one entry point the rest of the app uses: routes to the right client.
enum AIService {
    static func ask(_ text: String, config: Config) async throws -> String {
        let settings = config.settings(for: config.provider)
        switch config.provider {
        case .anthropic:
            guard !settings.apiKey.isEmpty else { throw AIError.missingKey(.anthropic) }
            return try await AnthropicClient.ask(text, settings: settings, config: config)
        default:
            return try await OpenAIClient.ask(text, provider: config.provider, settings: settings, config: config)
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
