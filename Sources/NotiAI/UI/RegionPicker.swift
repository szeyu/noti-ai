import AppKit

/// Dims every screen and lets you drag out the area the screenshot shortcut will read.
/// Esc cancels. The area is stored relative to the screen it was drawn on.
final class RegionPicker {
    private var windows: [PickerWindow] = []
    private var done: ((ScreenRegion?) -> Void)?
    /// The app you were in, if Noti AI wasn't. Focus goes back to it afterwards.
    private var previousApp: NSRunningApplication?

    var isPicking: Bool { !windows.isEmpty }

    func pick(current: ScreenRegion?, completion: @escaping (ScreenRegion?) -> Void) {
        guard windows.isEmpty else { return }
        done = completion
        previousApp = NSApp.isActive ? nil : NSWorkspace.shared.frontmostApplication
        for screen in NSScreen.screens {
            let w = PickerWindow(screen: screen, current: current) { [weak self] region in
                self?.finish(region)
            }
            windows.append(w)
            w.orderFrontRegardless()
        }
        // Key events (Esc) need the app active; the caller hides Settings first.
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        (windows.first { NSMouseInRect(mouse, $0.frame, false) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.push()
    }

    private func finish(_ region: ScreenRegion?) {
        guard let done else { return }
        self.done = nil
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        // Picking had to make Noti AI active (for Esc); hand focus back so your app keeps
        // typing focus and "hide when I press any key" keeps working.
        if let app = previousApp, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            app.activate(options: [])
        }
        previousApp = nil
        done(region)
    }
}

private final class PickerWindow: NSWindow {
    init(screen: NSScreen, current: ScreenRegion?, onDone: @escaping (ScreenRegion?) -> Void) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        // Set explicitly: otherwise clicks on fully clear pixels (the saved area's hole)
        // fall through to the app underneath.
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let saved = current?.displayID == id ? current?.rect : nil
        contentView = PickerView(screen: screen, displayID: id, saved: saved, onDone: onDone)
    }

    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    private let screenName: String
    private let displayID: UInt32
    private let saved: CGRect?   // display-local, top-left origin
    private let onDone: (ScreenRegion?) -> Void
    private var start: NSPoint?
    private var selection: NSRect?

    init(screen: NSScreen, displayID: UInt32, saved: CGRect?, onDone: @escaping (ScreenRegion?) -> Void) {
        screenName = screen.localizedName
        self.displayID = displayID
        self.saved = saved
        self.onDone = onDone
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDone(nil) } // Esc
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        start = convert(event.locationInWindow, from: nil)
        selection = nil
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = convert(event.locationInWindow, from: nil)
        selection = NSRect(x: min(start.x, p.x), y: min(start.y, p.y),
                           width: abs(p.x - start.x), height: abs(p.y - start.y)).intersection(bounds)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil }
        guard let r = selection, r.width >= 12, r.height >= 12 else {
            selection = nil
            needsDisplay = true
            return
        }
        // View coordinates are bottom-left; the stored area is top-left, like the display.
        onDone(ScreenRegion(displayID: displayID, displayName: screenName,
                            x: r.minX.rounded(), y: (bounds.height - r.maxY).rounded(),
                            width: r.width.rounded(), height: r.height.rounded()))
    }

    override func draw(_ dirty: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        let shown = selection ?? saved.map {
            NSRect(x: $0.minX, y: bounds.height - $0.maxY, width: $0.width, height: $0.height)
        }
        if let r = shown {
            // See the real screen through the area. Not fully clear, so it still takes clicks.
            NSColor.black.withAlphaComponent(0.02).setFill()
            r.fill(using: .copy)
            let border = NSBezierPath(rect: r.insetBy(dx: -1, dy: -1))
            border.lineWidth = 2
            if selection == nil { border.setLineDash([6, 4], count: 2, phase: 0) }
            Theme.markerNS.setStroke()
            border.stroke()
            label("\(Int(r.width)) × \(Int(r.height))", at: NSPoint(x: r.minX, y: r.maxY + 6), size: 12)
        }

        let hint = selection == nil
            ? (saved == nil ? "Drag to choose the area Noti AI reads.  Esc to cancel."
                            : "Drag to choose a new area.  Esc keeps the current one.")
            : "Release to save this area."
        label(hint, at: NSPoint(x: bounds.midX, y: bounds.maxY - 120), size: 15, centered: true)
    }

    private func label(_ text: String, at p: NSPoint, size: CGFloat, centered: Bool = false) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        let origin = NSPoint(x: centered ? p.x - sz.width / 2 : p.x, y: p.y)
        let pill = NSRect(origin: origin, size: sz).insetBy(dx: -10, dy: -5)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        s.draw(at: origin)
    }
}

/// A brief outline around the area after it's captured, so you can see what was read.
enum RegionFlash {
    static func show(_ region: ScreenRegion) {
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID
        }) else { return }
        let f = screen.frame
        let rect = NSRect(x: f.minX + region.x, y: f.maxY - region.y - region.height,
                          width: region.width, height: region.height).insetBy(dx: -3, dy: -3)
        let w = NSPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .statusBar
        w.isOpaque = false
        w.backgroundColor = .clear
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let v = NSView(frame: NSRect(origin: .zero, size: rect.size))
        v.wantsLayer = true
        v.layer?.borderColor = Theme.markerNS.cgColor
        v.layer?.borderWidth = 3
        v.layer?.cornerRadius = 4
        w.contentView = v
        w.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; w.animator().alphaValue = 0 },
                                                 completionHandler: { w.orderOut(nil) })
        }
    }
}
