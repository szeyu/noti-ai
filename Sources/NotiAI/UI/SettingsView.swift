import SwiftUI

/// State for the Settings window. Changes save as you make them, like other Mac apps.
/// Each provider keeps its own key/model/URL, so switching providers never loses what you typed.
final class SettingsModel: ObservableObject {
    @Published var provider: Provider { didSet { if provider != oldValue { switchProvider(from: oldValue) } } }
    @Published var apiKey = ""
    @Published var model = ""
    @Published var baseURL = ""
    @Published var effort: String
    @Published var hotkey: String
    @Published var regionHotkey: String
    /// Set by the area picker; saved like every other setting so autosave never drops it.
    @Published var region: ScreenRegion?
    @Published var flashRegion: Bool
    @Published var dismissAfter: Double
    @Published var answerStyle: AnswerStyle
    @Published var cardOpacity: Double
    @Published var dismissOnKey: Bool
    @Published var systemPrompt: String
    @Published var tab: SettingsTab = .general
    @Published var models: [String] = []
    @Published var status: (text: String, ok: Bool)?
    @Published var busy = false

    private var drafts: [Provider: ProviderSettings] = [:]
    private var base: Config
    /// The shortcut currently registered. Typing in the field doesn't change it until you press Return.
    private var appliedHotkey: String
    private var appliedRegionHotkey: String
    /// Applies the config; returns a message to show if it couldn't.
    var onSave: (Config) -> String? = { _ in nil }
    /// Opens the screen-area picker.
    var onPickRegion: () -> Void = {}

    init(_ config: Config) {
        base = config
        provider = config.provider
        effort = config.effort
        hotkey = config.hotkey
        regionHotkey = config.regionHotkey
        region = config.region
        flashRegion = config.flashRegion
        dismissAfter = config.dismissAfter
        answerStyle = config.answerStyle
        cardOpacity = config.cardOpacity
        dismissOnKey = config.dismissOnKey
        systemPrompt = config.systemPrompt
        appliedHotkey = config.hotkey
        appliedRegionHotkey = config.regionHotkey
        for p in Provider.allCases { drafts[p] = config.settings(for: p) }
        load(config.provider)
    }

    private func load(_ p: Provider) {
        let s = drafts[p] ?? ProviderSettings()
        apiKey = s.apiKey
        model = s.model
        baseURL = s.baseURL
        models = []
        status = nil
    }

    private func switchProvider(from old: Provider) {
        drafts[old] = current
        load(provider)
    }

    private var current: ProviderSettings { ProviderSettings(apiKey: apiKey.trimmed, model: model.trimmed, baseURL: baseURL.trimmed) }

    /// The config as shown in the window, with the shortcut that is actually registered.
    var config: Config { build(hotkey: appliedHotkey, regionHotkey: appliedRegionHotkey) }

    private func build(hotkey: String, regionHotkey: String) -> Config {
        var c = base
        drafts[provider] = current
        for (p, s) in drafts { c.set(s, for: p) }
        c.provider = provider
        c.effort = effort
        c.hotkey = hotkey
        c.regionHotkey = regionHotkey
        c.region = region
        c.flashRegion = flashRegion
        c.dismissAfter = dismissAfter
        c.answerStyle = answerStyle
        c.cardOpacity = cardOpacity
        c.dismissOnKey = dismissOnKey
        // An empty box means "use the default", so the model always gets instructions.
        c.systemPrompt = systemPrompt.trimmed.isEmpty ? Config.defaultSystemPrompt : systemPrompt
        return c
    }

    /// Saves and applies everything except an unconfirmed shortcut. Called on every change.
    func autosave() {
        let cfg = config
        _ = onSave(cfg)
        do { try cfg.save(); base = cfg }
        catch { status = ("Couldn't save settings: \(error.localizedDescription)", false) }
    }

    /// Registers the typed shortcuts. Returns false (and explains) if they can't be used.
    @discardableResult
    func commitHotkey() -> Bool {
        func clean(_ s: String, _ fallback: String) -> String {
            let t = s.trimmed.lowercased()
            return t.isEmpty ? fallback : t
        }
        let text = clean(hotkey, Config().hotkey)
        let shot = clean(regionHotkey, Config().regionHotkey)
        guard text != appliedHotkey || shot != appliedRegionHotkey else {
            hotkey = text; regionHotkey = shot; return true
        }
        guard Hotkey.symbols(for: text) != Hotkey.symbols(for: shot) else {
            status = ("The two shortcuts must be different.", false)
            return false
        }
        let cfg = build(hotkey: text, regionHotkey: shot)
        if let problem = onSave(cfg) { status = (problem, false); return false }
        let changed = shot != appliedRegionHotkey ? shot : text
        appliedHotkey = text
        appliedRegionHotkey = shot
        hotkey = text
        regionHotkey = shot
        do { try cfg.save(); base = cfg } catch {}
        status = ("Shortcut set to \(Hotkey.symbols(for: changed)).", true)
        return true
    }

    func fetchModels() {
        busy = true
        status = nil
        let (p, s) = (provider, current)
        Task { @MainActor in
            defer { busy = false }
            do {
                models = try await AIService.models(provider: p, settings: s)
                status = models.isEmpty ? ("The server listed no models.", false)
                                        : ("Found \(models.count) models.", true)
            } catch {
                status = (error.localizedDescription, false)
            }
        }
    }

    func test() {
        busy = true
        status = ("Sending a test question…", true)
        let cfg = config
        Task { @MainActor in
            defer { busy = false }
            do {
                let reply = try await AIService.ask("Reply with just the word: ready", config: cfg)
                status = ("Connected. The model replied “\(reply.prefix(40))”.", true)
            } catch {
                status = (error.localizedDescription, false)
            }
        }
    }

}

enum SettingsTab: Hashable { case general, instructions }

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onClose: () -> Void = {}
    /// The window is 780pt tall and the form scrolls; snapshots can ask for more to show everything.
    var height: CGFloat = 780

    private let hideChoices: [(Double, String)] = [
        (3, "After 3 seconds"), (5, "After 5 seconds"), (8, "After 8 seconds"),
        (15, "After 15 seconds"), (0, "Never"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("Section", selection: $model.tab) {
                Text("General").tag(SettingsTab.general)
                Text("Instructions").tag(SettingsTab.instructions)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.top, 10)
            .padding(.bottom, 2)

            switch model.tab {
            case .general: general
            case .instructions: instructions
            }

            footer
        }
        .frame(width: 520, height: height)
        // Save as you go, like System Settings.
        .onChange(of: model.provider) { _ in model.autosave() }
        .onChange(of: model.apiKey) { _ in model.autosave() }
        .onChange(of: model.model) { _ in model.autosave() }
        .onChange(of: model.baseURL) { _ in model.autosave() }
        .onChange(of: model.effort) { _ in model.autosave() }
        .onChange(of: model.dismissAfter) { _ in model.autosave() }
        .onChange(of: model.answerStyle) { _ in model.autosave() }
        .onChange(of: model.cardOpacity) { _ in model.autosave() }
        .onChange(of: model.dismissOnKey) { _ in model.autosave() }
        .onChange(of: model.systemPrompt) { _ in model.autosave() }
        .onChange(of: model.region) { _ in model.autosave() }
        .onChange(of: model.flashRegion) { _ in model.autosave() }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tell the AI how to answer. The text you highlight is sent after these instructions.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextEditor(text: $model.systemPrompt)
                .font(.system(size: 13))
                .lineSpacing(2)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            HStack(alignment: .top) {
                Text("Ideas: always answer in Chinese, explain like I'm new to programming, or reply with only a translation.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 16)
                Button("Reset to default") { model.systemPrompt = Config.defaultSystemPrompt }
                    .disabled(model.systemPrompt == Config.defaultSystemPrompt)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
    }

    private var general: some View {
            Form {
                Section {
                    Picker("Provider", selection: $model.provider) {
                        ForEach(Provider.allCases) { Text($0.displayName).tag($0) }
                    }
                    if model.provider.editableBaseURL {
                        TextField("Server URL", text: $model.baseURL,
                                  prompt: Text(model.provider.defaultBaseURL.isEmpty
                                               ? "https://example.com/v1" : model.provider.defaultBaseURL))
                    }
                    if model.provider.key != .none {
                        SecureField("API key", text: $model.apiKey, prompt: Text(model.provider.keyPlaceholder))
                    }
                    LabeledContent("Model") {
                        HStack(spacing: 6) {
                            TextField("Model", text: $model.model, prompt: Text("Type a name or fetch the list"))
                                .labelsHidden()
                            if !model.models.isEmpty {
                                Menu {
                                    ForEach(model.models, id: \.self) { id in Button(id) { model.model = id } }
                                } label: { Image(systemName: "chevron.up.chevron.down") }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                                .help("Choose from the fetched models")
                            }
                            Button("Fetch") { model.fetchModels() }
                                .disabled(model.busy)
                                .help("List the models this provider offers")
                        }
                    }
                    if model.provider == .anthropic {
                        Picker("Thinking", selection: $model.effort) {
                            Text("Quick").tag("low")
                            Text("Balanced").tag("medium")
                            Text("Thorough").tag("high")
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("AI model")
                } footer: {
                    Text(model.provider.hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section {
                    Picker("Show answers as", selection: $model.answerStyle) {
                        Text("macOS notification").tag(AnswerStyle.notification)
                        Text("Floating card").tag(AnswerStyle.card)
                    }
                    if model.answerStyle == .card {
                        LabeledContent("Card opacity") {
                            HStack(spacing: 10) {
                                Slider(value: $model.cardOpacity, in: 0.15...1)
                                    .frame(width: 180)
                                Text("\(Int((model.cardOpacity * 100).rounded()))%")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                    Picker("Hide answers", selection: $model.dismissAfter) {
                        ForEach(hideChoices, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    Toggle("Hide when I press any key", isOn: $model.dismissOnKey)
                } header: {
                    Text("Answers")
                } footer: {
                    Text(model.answerStyle == .card
                         ? "The card fades in at the top right and becomes solid when you point at it. Click it to read the full answer."
                         : "macOS notifications can't be made see-through. Choose Floating card if you want that.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Section {
                    shortcutRow("Ask about text", text: $model.hotkey, placeholder: "cmd+option+a")
                    shortcutRow("Ask about screen area", text: $model.regionHotkey,
                                placeholder: "cmd+option+shift+a")
                    LabeledContent("Screen area") {
                        HStack(spacing: 8) {
                            Text(model.region?.label ?? "Not set")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            if model.region != nil {
                                Button("Clear") { model.region = nil }
                            }
                            Button(model.region == nil ? "Set area…" : "Change…") { model.onPickRegion() }
                        }
                    }
                    Toggle("Outline the area when it's read", isOn: $model.flashRegion)
                } header: {
                    Text("Shortcuts")
                } footer: {
                    Text("Type a shortcut and press Return. The screen area shortcut sends a picture of the area you set, which never gets saved to disk. It needs Screen Recording permission and a model that can read images.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
    }

    private func shortcutRow(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField(title, text: text, prompt: Text(placeholder))
                    .labelsHidden()
                    .frame(width: 170)
                    .onSubmit { model.commitHotkey() }
                    .help("Type a shortcut and press Return")
                Text(Hotkey.symbols(for: text.wrappedValue))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Noti AI").font(.system(size: 20, weight: .semibold))
                Text("Highlight any text, press \(Hotkey.symbols(for: model.hotkey)), and the answer arrives as a notification.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let s = model.status {
                Image(systemName: s.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(s.ok ? Color.green : Color.orange)
                Text(s.text)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Test connection") { model.test() }
                .disabled(model.busy)
            Button("Done") { if model.commitHotkey() { onClose() } }
                .buttonStyle(MarkerButtonStyle())
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }
}
