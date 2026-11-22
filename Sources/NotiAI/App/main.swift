import Cocoa
import SwiftUI

// Entry point. Besides the normal menu bar app there are two developer modes:
//   NotiAI --ask "some text"   send text to the configured model, print + notify the answer
//   NotiAI --ask-image <file>  send an image the way the screen area shortcut does, print the answer
//   NotiAI --check-config      show the loaded settings and the provider's model list
//   NotiAI --snapshot <dir>    render the Settings and answer views to PNGs (light + dark)

let args = CommandLine.arguments
let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon

if let i = args.firstIndex(of: "--ask"), i + 1 < args.count {
    let question = args[(i + 1)...].joined(separator: " ")
    let cfg = Config.load()
    Notifier.shared.setUp()
    Notifier.shared.configure(cfg)
    Task {
        do {
            let answer = try await AIService.ask(question, config: cfg)
            print(answer)
            Notifier.shared.answer(answer, question: question, source: cfg.modelLabel)
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
            Notifier.shared.error(error.localizedDescription)
        }
        // Stay alive long enough for the auto-dismiss timer to fire.
        try? await Task.sleep(nanoseconds: UInt64((cfg.dismissAfter + 1) * 1_000_000_000))
        exit(0)
    }
    app.run()
} else if let i = args.firstIndex(of: "--ask-image"), i + 1 < args.count {
    let cfg = Config.load()
    Task {
        do {
            guard let src = NSImage(contentsOfFile: args[i + 1])?
                .cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CaptureError.failed("couldn't read \(args[i + 1])")
            }
            let image = try ScreenCapture.encode(src)
            print("sending \(image.pixelWidth)x\(image.pixelHeight) \(image.mediaType), \(image.data.count) bytes")
            print(try await AIService.ask(AIService.screenshotNote, image: image, config: cfg))
        } catch {
            FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
        }
        exit(0)
    }
    app.run()
} else if args.contains("--check-config") {
    // Prints what was loaded (never the key itself) and asks the provider for its model list.
    let cfg = Config.load()
    let s = cfg.settings(for: cfg.provider)
    print("config:   \(Config.file.path)")
    print("provider: \(cfg.provider.displayName)")
    print("model:    \(s.model.isEmpty ? "(none)" : s.model)")
    print("key:      \(s.apiKey.isEmpty ? "(none)" : "set, \(s.apiKey.count) characters")")
    print("shortcut: \(Hotkey.symbols(for: cfg.hotkey))   screen area: \(Hotkey.symbols(for: cfg.regionHotkey))   hide after: \(cfg.dismissAfter)s")
    print("area:     \(cfg.region?.label ?? "(not set)")   screen recording: \(ScreenCapture.hasPermission ? "on" : "off")")
    Task {
        do {
            let models = try await AIService.models(provider: cfg.provider, settings: s)
            print("models:   \(models.count) available, e.g. \(models.prefix(4).joined(separator: ", "))")
        } catch {
            print("models:   \(error.localizedDescription)")
        }
        exit(0)
    }
    app.run()
} else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    let dir = URL(fileURLWithPath: args[i + 1])
    Task { @MainActor in
        Snapshot.run(into: dir)
        exit(0)
    }
    app.run()
} else {
    // Only one copy may run: two copies would both answer the shortcut (double notifications).
    let me = ProcessInfo.processInfo.processIdentifier
    if let other = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        .first(where: { $0.processIdentifier != me }) {
        other.activate()
        exit(0)
    }
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

/// Renders the SwiftUI views offscreen so the design can be reviewed without clicking around.
@MainActor
enum Snapshot {
    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var cfg = Config()
        cfg.provider = .openrouter
        cfg.set(ProviderSettings(apiKey: "sk-or-demo", model: "anthropic/claude-sonnet-5.5", baseURL: ""), for: .openrouter)
        cfg.answerStyle = .card
        cfg.cardOpacity = 0.6
        cfg.region = ScreenRegion(displayID: 1, displayName: "Built-in Retina Display",
                                  x: 200, y: 160, width: 640, height: 400)
        let answer = AnswerView(
            question: "What does idempotent mean in an HTTP API, and why does PUT have it but POST doesn't?",
            answer: "Idempotent means sending the same request twice leaves the server in the same state as sending it once. PUT replaces a resource with what you send, so repeating it changes nothing further. POST usually creates something new each time, so repeating it makes duplicates.",
            source: "claude-sonnet-5-5 · Anthropic")
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            // Taller than the window so the README shows every section without scrolling.
            render(SettingsView(model: SettingsModel(cfg), height: 960), appearance, dir.appendingPathComponent("settings-\(name).png"))
            render(answer, appearance, dir.appendingPathComponent("answer-\(name).png"))
            let advanced = SettingsModel(cfg)
            advanced.tab = .instructions
            render(SettingsView(model: advanced), appearance, dir.appendingPathComponent("settings-instructions-\(name).png"))
            render(ToastView(title: "Why is the sky blue?", message: "Sunlight scatters off air molecules, and shorter blue wavelengths scatter far more than red ones, so blue light reaches your eyes from every direction.", isError: false),
                   appearance, dir.appendingPathComponent("card-\(name).png"))
        }

        // ImageRenderer draws SwiftUI effects (blur) that AppKit's cacheDisplay skips.
        let renderer = ImageRenderer(content: OpacityDemo().environment(\.colorScheme, .light))
        renderer.scale = 2
        if let cg = renderer.cgImage {
            try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?
                .write(to: dir.appendingPathComponent("card-opacity.png"))
        }

        // The real windows, as the app shows them (title bar insets, panels, card).
        // Translucent materials render as their fallback colour here.
        let settings = SettingsWindowController()
        settings.show(reason: "snapshot")
        let answers = AnswerWindowController()
        answers.show(question: answer.question, answer: answer.answer, source: answer.source)
        let toast = ToastController()
        toast.show(title: "Why is the sky blue?", message: "Sunlight scatters off air molecules, and shorter blue wavelengths scatter far more than red ones, so blue light reaches your eyes from every direction.", isError: false, opacity: 1, hideAfter: 0)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        capture(settings.window, dir.appendingPathComponent("window-settings.png"))
        capture(answers.panel, dir.appendingPathComponent("window-answer.png"))
        capture(toast.panel, dir.appendingPathComponent("window-card.png"))
    }

    private static func capture(_ window: NSWindow?, _ url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func render<V: View>(_ view: V, _ appearance: NSAppearance.Name, _ url: URL) {
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        host.appearance = NSAppearance(named: appearance)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

/// README illustration: the card at full and low opacity over a page of text.
/// (The real card dims the whole window the same way.)
private struct OpacityDemo: View {
    private let page = """
    The Industrial Revolution began in Britain in the late eighteenth century. Water power, \
    and later steam, moved work from homes and small workshops into factories. Cities grew \
    quickly as people followed the jobs, and new canals and railways carried coal, cotton \
    and finished goods across the country. Historians still argue about why it started \
    where it did: cheap coal, high wages, a stable banking system and a large empire to sell \
    to all played a part.
    """

    var body: some View {
        HStack(spacing: 24) {
            panel(opacity: 1, label: "Opacity 100%")
            panel(opacity: 0.6, label: "Opacity 60%")
        }
        .padding(24)
        .background(Color(white: 0.9))
    }

    /// The page behind the card: 440 × 300.
    private var pageView: some View {
        Text(page + "\n\n" + page)
            .font(.system(size: 13, design: .serif))
            .lineSpacing(4)
            .foregroundColor(Color(white: 0.15))
            .padding(22)
            .frame(width: 440, height: 300, alignment: .topLeading)
            .background(Color.white)
    }

    private func panel(opacity: Double, label: String) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                pageView
                // Like the real card: the page behind is blurred and tinted, and the whole
                // card (blur included) is faded to the chosen opacity.
                ToastView(title: "steam engine",
                          message: "A machine that turns the heat from burning fuel into motion by letting expanding steam push a piston.",
                          isError: false)
                    .background(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            pageView.offset(x: -70, y: -10).blur(radius: 7)
                            Color(white: 0.97).opacity(0.7)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: .black.opacity(0.18 * opacity), radius: 10, y: 4)
                    .opacity(opacity)
                    .padding(10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(Color(white: 0.3))
        }
    }
}
