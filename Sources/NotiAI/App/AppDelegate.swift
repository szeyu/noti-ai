import Cocoa
import ServiceManagement

/// Owns the menu bar item, the shortcut, and the highlight → ask → notify flow.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var config = Config.load()
    private var hotkey: Hotkey?
    private var statusItem: NSStatusItem!
    private let answers = AnswerWindowController()
    private let settings = SettingsWindowController()
    private var inFlight = 0 { didSet { updateIcon() } }
    private var last: (q: String, a: String, s: String)?
    private var notificationsAllowed = true

    func applicationDidFinishLaunching(_ note: Notification) {
        installEditMenu()

        Notifier.shared.setUp()
        Notifier.shared.configure(config)
        Notifier.shared.onOpen = { [weak self] q, a, s in self?.answers.show(question: q, answer: a, source: s) }
        Notifier.shared.onBlocked = { [weak self] q, a, s in self?.answers.show(question: q, answer: a, source: s) }

        settings.onSave = { [weak self] cfg in self?.apply(cfg) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        registerHotkey()
        rebuildMenu()
        refreshNotificationStatus()

        if !Selection.isTrusted { Selection.requestTrust() }
        if config.needsKey { settings.show() }
    }

    /// Opening the app again (Finder, Spotlight) while it runs shows Settings,
    /// since a menu bar app has no window of its own.
    /// A notification click sends the same event, so wait a moment and skip it then.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            if let click = Notifier.shared.lastClick, abs(click.timeIntervalSinceNow) < 2 { return }
            self?.settings.show()
        }
        return false
    }

    // MARK: - Main flow

    @objc func askAboutSelection() {
        guard Selection.isTrusted else {
            Notifier.shared.error("Noti AI needs Accessibility access to read your selection. Turn it on in System Settings › Privacy & Security › Accessibility.")
            Selection.requestTrust()
            return
        }
        let cfg = config
        inFlight += 1
        Task.detached {
            defer { Task { @MainActor in self.inFlight -= 1 } }
            guard let text = Selection.grab() else {
                Notifier.shared.error("Nothing selected. Highlight some text, then press the shortcut.")
                return
            }
            do {
                let answer = try await AIService.ask(text, config: cfg)
                let source = cfg.modelLabel
                await MainActor.run { self.last = (text, answer, source); self.rebuildMenu() }
                Notifier.shared.answer(answer, question: text, source: source)
            } catch {
                Notifier.shared.error(error.localizedDescription)
            }
        }
    }

    /// Applies new settings from the Settings window. Returns a message if it can't.
    private func apply(_ cfg: Config) -> String? {
        if cfg.hotkey != config.hotkey {
            // Release the old shortcut first so re-registering can't collide with itself.
            hotkey = nil
            guard let hk = makeHotkey(cfg.hotkey) else {
                hotkey = makeHotkey(config.hotkey)
                return "The shortcut \(Hotkey.symbols(for: cfg.hotkey)) is invalid or already used by another app."
            }
            hotkey = hk
        }
        config = cfg
        Notifier.shared.configure(cfg)
        rebuildMenu()
        return nil
    }

    // MARK: - Shortcut

    private func makeHotkey(_ spec: String) -> Hotkey? {
        Hotkey(spec) { [weak self] in DispatchQueue.main.async { self?.askAboutSelection() } }
    }

    private func registerHotkey() {
        hotkey = nil
        hotkey = makeHotkey(config.hotkey)
        if hotkey == nil {
            Notifier.shared.error("Couldn't set the shortcut \(Hotkey.symbols(for: config.hotkey)). It may be invalid or used by another app. Pick another in Settings.")
        }
    }

    // MARK: - Menu bar

    private func updateIcon() {
        let name = inFlight > 0 ? "ellipsis.bubble" : "highlighter"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Noti AI")
            ?? NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "Noti AI")
        img?.isTemplate = true
        statusItem?.button?.image = img
        if img == nil { statusItem?.button?.title = "Noti" } // never leave the item invisible
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        func add(_ title: String, _ action: Selector?, key: String = "", enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.isEnabled = enabled
            menu.addItem(item)
            return item
        }

        let ask = add("Ask about selection", #selector(askAboutSelection))
        if let hotkey { ask.title += "    \(hotkey.display)" }
        _ = add("Show last answer", #selector(showLast), enabled: last != nil)
        menu.addItem(.separator())

        _ = add(config.modelLabel, nil, enabled: false)
        _ = add("Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())

        _ = add(Selection.isTrusted ? "Accessibility is on" : "Turn on Accessibility…",
                #selector(openAccessibility))
        _ = add(notificationsAllowed ? "Notifications are on" : "Turn on notifications…",
                #selector(openNotifications))
        let login = add("Start at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Noti AI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshNotificationStatus()
        // Accessibility can change while we run; refresh the label for next time.
        let showsOn = menu.items.contains { $0.title == "Accessibility is on" }
        if showsOn != Selection.isTrusted { DispatchQueue.main.async { self.rebuildMenu() } }
    }

    private func refreshNotificationStatus() {
        Notifier.shared.isAllowed { ok in
            DispatchQueue.main.async {
                if ok != self.notificationsAllowed { self.notificationsAllowed = ok; self.rebuildMenu() }
            }
        }
    }

    /// Without a main menu, ⌘V/⌘C/⌘A do nothing in text fields (e.g. pasting an API key).
    private func installEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: - Actions

    @objc private func showLast() {
        if let last { answers.show(question: last.q, answer: last.a, source: last.s) }
    }

    @objc private func openSettings() { settings.show() }

    @objc private func openAccessibility() {
        Selection.requestTrust()
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func openNotifications() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            Notifier.shared.error("Couldn't change Start at login: \(error.localizedDescription)")
        }
        rebuildMenu()
    }
}
