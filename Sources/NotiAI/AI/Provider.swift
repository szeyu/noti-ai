import Foundation

/// The AI services Noti AI can talk to. Everything except Anthropic uses the
/// OpenAI chat-completions format, which OpenRouter, Ollama and LM Studio all speak.
enum Provider: String, Codable, CaseIterable, Identifiable {
    case anthropic, openai, openrouter, ollama, lmstudio, custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic (Claude)"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .ollama: return "Ollama (on this Mac)"
        case .lmstudio: return "LM Studio (on this Mac)"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    var shortName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .lmstudio: return "LM Studio"
        case .custom: return "Custom"
        }
    }

    enum KeyRequirement { case required, optional, none }

    var key: KeyRequirement {
        switch self {
        case .anthropic, .openai, .openrouter: return .required
        case .custom: return .optional
        case .ollama, .lmstudio: return .none
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .anthropic: return "https://api.anthropic.com/v1"
        case .openai: return "https://api.openai.com/v1"
        case .openrouter: return "https://openrouter.ai/api/v1"
        case .ollama: return "http://localhost:11434/v1"
        case .lmstudio: return "http://localhost:1234/v1"
        case .custom: return ""
        }
    }

    /// Whether the base URL is worth showing in Settings.
    var editableBaseURL: Bool { self != .anthropic && self != .openai }

    var defaultModel: String { self == .anthropic ? "claude-opus-5-5" : "" }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-…"
        case .openai: return "sk-…"
        case .openrouter: return "sk-or-…"
        default: return "Optional"
        }
    }

    var hint: String {
        switch self {
        case .anthropic: return "Create a key at platform.claude.com."
        case .openai: return "Create a key at platform.openai.com."
        case .openrouter: return "One key for hundreds of models. Create it at openrouter.ai/keys."
        case .ollama: return "Start Ollama, pull a model, then choose it here. No key needed."
        case .lmstudio: return "Load a model in LM Studio and start its local server. No key needed."
        case .custom: return "Any server with an OpenAI-style /chat/completions endpoint."
        }
    }
}
