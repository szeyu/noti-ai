import Cocoa
import SwiftUI

/// Settings window hosting `SettingsView`.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private var model: SettingsModel?
    var onSave: (Config) -> String? = { _ in nil }
    var onPickRegion: () -> Void = {}

    /// The model behind the open Settings window, if it's open. Changes made elsewhere
    /// (the area picker) go through it, or its next autosave would undo them.
    var liveModel: SettingsModel? { window?.isVisible == true ? model : nil }

    func windowWillClose(_ notification: Notification) { model?.commitHotkey() }

    func show(reason: String) {
        appLog.notice("settings shown: \(reason, privacy: .public)")
        let model = SettingsModel(Config.load())
        model.onSave = onSave
        model.onPickRegion = onPickRegion
        self.model = model

        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.isMovableByWindowBackground = true
            w.delegate = self
            window = w
        }
        guard let w = window else { return }

        // Never taller than the free screen area, or Done ends up off the bottom edge on
        // smaller displays (and above the Dock). The form scrolls when it needs the room.
        let screen = w.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowHeight = min(780 + titlebarHeight(w), screen.height - 16)
        let viewHeight = max(420, windowHeight - titlebarHeight(w))
        w.contentView = NSHostingView(rootView: SettingsView(
            model: model, onClose: { [weak self] in self?.window?.close() }, height: viewHeight))

        var frame = NSRect(x: 0, y: 0, width: 520, height: viewHeight + titlebarHeight(w))
        if w.isVisible, screen.contains(NSRect(origin: NSPoint(x: w.frame.minX, y: w.frame.maxY - frame.height),
                                               size: frame.size)) {
            frame.origin = NSPoint(x: w.frame.minX, y: w.frame.maxY - frame.height) // keep the top edge
        } else {
            frame.origin = NSPoint(x: screen.midX - frame.width / 2, y: screen.midY - frame.height / 2)
        }
        w.setFrame(frame, display: true)

        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Height of the (transparent) title bar, which sits above the SwiftUI content.
    private func titlebarHeight(_ w: NSWindow) -> CGFloat {
        w.frame.height - w.contentLayoutRect.height
    }
}

/// A floating, translucent card for the full answer. Esc closes it.
final class AnswerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

final class AnswerWindowController: NSObject, NSWindowDelegate {
    private(set) var panel: AnswerPanel?
    private var clickMonitors: [Any] = []

    /// Clicking anywhere outside the answer closes it, like a popover.
    private func watchOutsideClicks() {
        stopWatching()
        let kinds: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps or on the desktop.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: kinds, handler: { [weak self] _ in
            self?.panel?.close()
        }) { clickMonitors.append(m) }
        // Clicks in Noti AI's own windows other than this one (Settings, the menu bar icon).
        if let m = NSEvent.addLocalMonitorForEvents(matching: kinds, handler: { [weak self] event in
            if let panel = self?.panel, event.window !== panel { panel.close() }
            return event
        }) { clickMonitors.append(m) }
    }

    private func stopWatching() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
    }

    func windowWillClose(_ notification: Notification) {
        appLog.notice("answer closed")
        stopWatching()
    }

    func show(question: String, answer: String, source: String) {
        appLog.notice("answer shown")
        if panel == nil {
            // Non-activating: showing the answer doesn't bring Noti AI to the front, which would
            // also raise an open Settings window from behind other apps.
            let p = AnswerPanel(contentRect: .zero,
                                styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            p.titlebarAppearsTransparent = true
            p.titleVisibility = .hidden
            p.isMovableByWindowBackground = true
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false
            p.delegate = self
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
        panel.orderFrontRegardless()
        panel.makeKey() // so Esc works
        watchOutsideClicks()
    }
}
