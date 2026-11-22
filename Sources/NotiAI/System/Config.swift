import Foundation
import CoreGraphics

/// What Noti AI remembers for one provider, so switching providers keeps each key.
struct ProviderSettings: Codable, Equatable {
    var apiKey = ""
    var model = ""
    var baseURL = ""
}

/// The part of the screen the screenshot shortcut reads. Stored relative to one display
/// (points, top-left origin) so it stays put when other displays are added or moved.
struct ScreenRegion: Codable, Equatable {
    var displayID: UInt32
    var displayName: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    /// e.g. "640 × 400 on Built-in Retina Display"
    var label: String { "\(Int(width)) × \(Int(height)) on \(displayName)" }
}

/// User settings, stored in ~/.config/noti-ai/config.json (mode 600: it holds API keys).
struct Config: Codable {
    var provider: Provider = .anthropic
    var providers: [String: ProviderSettings] = [:]
    /// Anthropic only. low | medium | high
    var effort = "low"
    /// e.g. "cmd+option+a", "ctrl+shift+space"
    var hotkey = "cmd+option+a"
    /// Sends the saved screen area instead of highlighted text.
    var regionHotkey = "cmd+option+shift+a"
    var region: ScreenRegion?
    /// Outline the area briefly when it's captured. Off = nothing on screen shows it was read.
    var flashRegion = true
    /// Seconds before a notification removes itself (also from Notification Center). 0 = never.
    var dismissAfter: Double = 5
    /// macOS notification, or Noti AI's own floating card.
    var answerStyle: AnswerStyle = .notification
    /// Floating card only: 0.15 (barely there) … 1 (solid).
    var cardOpacity: Double = 0.9
    /// Hide answers as soon as you press any key.
    var dismissOnKey = true
    var systemPrompt = Config.defaultSystemPrompt

    static let defaultSystemPrompt = """
    The user highlighted some text on their Mac and pressed a shortcut to ask you about it. \
    Work out what they most likely want: answer it if it is a question, explain it if it is a \
    term, code, error or concept, translate it to English if it is in another language, and \
    fact-check or summarise it otherwise. Your reply is shown in a macOS notification, so write \
    plain text with no markdown, and keep it short: ideally under 60 words. If a longer answer \
    is truly needed, make the first sentence a complete answer on its own.
    """

    func settings(for p: Provider) -> ProviderSettings {
        var s = providers[p.rawValue] ?? ProviderSettings()
        if s.model.isEmpty { s.model = p.defaultModel }
        return s
    }

    mutating func set(_ s: ProviderSettings, for p: Provider) { providers[p.rawValue] = s }

    /// True when the active provider can't work until the user adds a key.
    var needsKey: Bool { provider.key == .required && settings(for: provider).apiKey.isEmpty }

    /// e.g. "claude-sonnet-5-5 · Anthropic"
    var modelLabel: String {
        let m = settings(for: provider).model
        return m.isEmpty ? provider.shortName : "\(m) · \(provider.shortName)"
    }

    // MARK: - Storage

    /// `NOTI_AI_CONFIG=/path/to/config.json` overrides the location (used for testing).
    static let file: URL = ProcessInfo.processInfo.environment["NOTI_AI_CONFIG"].map {
        URL(fileURLWithPath: $0)
    } ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/noti-ai/config.json")
    static var dir: URL { file.deletingLastPathComponent() }

    func save() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Config.dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try enc.encode(self).write(to: Config.file, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.file.path)
    }

    /// Loads settings, tolerating missing fields and the older single-provider format.
    static func load() -> Config {
        var cfg = Config()
        guard let data = try? Data(contentsOf: file),
              let f = try? JSONDecoder().decode(StoredConfig.self, from: data) else {
            if !FileManager.default.fileExists(atPath: file.path) { try? cfg.save() }
            return cfg.withEnvironmentKey()
        }
        if let v = f.provider { cfg.provider = v }
        if let v = f.providers { cfg.providers = v }
        // v0.1 stored one Anthropic key and model at the top level.
        if f.providers == nil, f.apiKey != nil || f.model != nil {
            cfg.providers[Provider.anthropic.rawValue] =
                ProviderSettings(apiKey: f.apiKey ?? "", model: f.model ?? "", baseURL: "")
        }
        if let v = f.effort, !v.isEmpty { cfg.effort = v }
        if let v = f.hotkey, !v.isEmpty { cfg.hotkey = v }
        if let v = f.regionHotkey, !v.isEmpty { cfg.regionHotkey = v }
        cfg.region = f.region
        if let v = f.flashRegion { cfg.flashRegion = v }
        if let v = f.dismissAfter, v >= 0 { cfg.dismissAfter = v }
        if let v = f.systemPrompt, !v.isEmpty { cfg.systemPrompt = v }
        if let v = f.answerStyle { cfg.answerStyle = v }
        if let v = f.cardOpacity { cfg.cardOpacity = min(max(v, 0.15), 1) }
        if let v = f.dismissOnKey { cfg.dismissOnKey = v }
        return cfg.withEnvironmentKey()
    }

    /// Handy when running the binary from a terminal (`--ask`); GUI launches don't see shell env.
    private func withEnvironmentKey() -> Config {
        var c = self
        let env = ProcessInfo.processInfo.environment
        for (p, name) in [(Provider.anthropic, "ANTHROPIC_API_KEY"), (.openai, "OPENAI_API_KEY"),
                          (.openrouter, "OPENROUTER_API_KEY")] {
            var s = c.settings(for: p)
            if s.apiKey.isEmpty, let k = env[name], !k.isEmpty { s.apiKey = k; c.set(s, for: p) }
        }
        return c
    }
}

/// Every field optional so a hand-edited or older file still loads.
private struct StoredConfig: Decodable {
    var provider: Provider?
    var providers: [String: ProviderSettings]?
    var apiKey: String?   // v0.1
    var model: String?    // v0.1
    var effort: String?
    var hotkey: String?
    var regionHotkey: String?
    var region: ScreenRegion?
    var flashRegion: Bool?
    var dismissAfter: Double?
    var systemPrompt: String?
    var answerStyle: AnswerStyle?
    var cardOpacity: Double?
    var dismissOnKey: Bool?
}
