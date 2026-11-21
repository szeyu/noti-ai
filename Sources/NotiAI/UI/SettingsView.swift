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
    @Published var dismissAfter: Double
    @Published var answerStyle: AnswerStyle
    @Published var cardOpacity: Double
    @Published var dismissOnKey: Bool
    @Published var systemPrompt: String
    @Published var showAdvanced = false
    @Published var models: [String] = []
    @Published var status: (text: String, ok: Bool)?
    @Published var busy = false

    private var drafts: [Provider: ProviderSettings] = [:]
    private var base: Config
    /// The shortcut currently registered. Typing in the field doesn't change it until you press Return.
    private var appliedHotkey: String
    /// Applies the config; returns a message to show if it couldn't.
    var onSave: (Config) -> String? = { _ in nil }

    init(_ config: Config) {
        base = config
        provider = config.provider
        effort = config.effort
        hotkey = config.hotkey
        dismissAfter = config.dismissAfter
        answerStyle = config.answerStyle
        cardOpacity = config.cardOpacity
        dismissOnKey = config.dismissOnKey
        systemPrompt = config.systemPrompt
        appliedHotkey = config.hotkey
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
    var config: Config { build(hotkey: appliedHotkey) }

    private func build(hotkey: String) -> Config {
        var c = base
        drafts[provider] = current
        for (p, s) in drafts { c.set(s, for: p) }
        c.provider = provider
        c.effort = effort
        c.hotkey = hotkey
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

    /// Registers the typed shortcut. Returns false (and explains) if it can't be used.
    @discardableResult
    func commitHotkey() -> Bool {
        let typed = hotkey.trimmed.lowercased()
        let wanted = typed.isEmpty ? Config().hotkey : typed
        guard wanted != appliedHotkey else { hotkey = wanted; return true }
        let cfg = build(hotkey: wanted)
        if let problem = onSave(cfg) { status = (problem, false); return false }
        appliedHotkey = wanted
        hotkey = wanted
        do { try cfg.save(); base = cfg } catch {}
        status = ("Shortcut set to \(Hotkey.symbols(for: wanted)).", true)
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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    var onClose: () -> Void = {}
    /// The window is 720pt tall and the form scrolls; snapshots can ask for more to show everything.
    var height: CGFloat = 720

    private let hideChoices: [(Double, String)] = [
        (3, "After 3 seconds"), (5, "After 5 seconds"), (8, "After 8 seconds"),
        (15, "After 15 seconds"), (0, "Never"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
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

                Section("Shortcut") {
                    LabeledContent("Shortcut") {
                        HStack(spacing: 8) {
                            TextField("Shortcut", text: $model.hotkey, prompt: Text("cmd+option+a"))
                                .labelsHidden()
                                .frame(width: 150)
                                .onSubmit { model.commitHotkey() }
                                .help("Type a shortcut and press Return")
                            Text(Hotkey.symbols(for: model.hotkey))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }

                Section {
                    DisclosureGroup("Instructions for the AI", isExpanded: $model.showAdvanced) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $model.systemPrompt)
                                .font(.system(size: 12))
                                .frame(height: 150)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(nsColor: .textBackgroundColor)))
                                .overlay(RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25)))
                            HStack {
                                Text("Your highlighted text is sent after these instructions.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Reset to default") { model.systemPrompt = Config.defaultSystemPrompt }
                                    .disabled(model.systemPrompt == Config.defaultSystemPrompt)
                            }
                        }
                        .padding(.top, 6)
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("For example: always answer in Chinese, explain like I'm new to programming, or reply with only a translation.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
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

            footer
        }
        .frame(width: 520, height: height)
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
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
    }
}
