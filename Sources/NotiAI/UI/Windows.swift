import Cocoa
import SwiftUI

/// Settings window hosting `SettingsView`.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private var model: SettingsModel?
    var onSave: (Config) -> String? = { _ in nil }

    func windowWillClose(_ notification: Notification) { model?.commitHotkey() }

    func show() {
        let model = SettingsModel(Config.load())
        model.onSave = onSave
        self.model = model
        let view = SettingsView(model: model) { [weak self] in self?.window?.close() }

        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 780),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.isMovableByWindowBackground = true
            w.delegate = self
            window = w
            window?.center()
        }
        window?.contentView = NSHostingView(rootView: view)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// A floating, translucent card for the full answer. Esc closes it.
final class AnswerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

final class AnswerWindowController {
    private(set) var panel: AnswerPanel?

    func show(question: String, answer: String, source: String) {
        if panel == nil {
            let p = AnswerPanel(contentRect: .zero,
                                styleMask: [.titled, .closable, .fullSizeContentView],
                                backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isMovableByWindowBackground = true
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            panel = p
        }
        guard let panel else { return }

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        let host = NSHostingView(rootView: AnswerView(question: question, answer: answer, source: source) {
            [weak panel] in panel?.close()
        })
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur

        // Size to the content and drop in at the top right, where notifications appear.
        let size = host.fittingSize
        panel.setContentSize(size)
        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 18, y: screen.maxY - size.height - 18))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
}
