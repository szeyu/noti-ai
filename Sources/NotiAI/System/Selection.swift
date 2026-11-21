import Cocoa
import ApplicationServices

/// Reads whatever text is highlighted in the frontmost app.
enum Selection {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system "allow Accessibility" prompt if not yet trusted.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Call off the main thread: it may sleep while waiting for the copy to land.
    static func grab() -> String? {
        if let text = viaAccessibility(), !text.isEmpty { return text }
        return viaCopy()
    }

    /// Fast path: ask the focused element for its selected text.
    /// Works in native apps; Chrome, Electron and many web views return nothing.
    private static func viaAccessibility() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused else { return nil }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element as! AXUIElement,
                                            kAXSelectedTextAttribute as CFString,
                                            &selected) == .success else { return nil }
        return (selected as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fallback: press ⌘C for the user, read the clipboard, then put their clipboard back.
    private static func viaCopy() -> String? {
        let pb = NSPasteboard.general
        let saved = snapshot(pb)
        let before = pb.changeCount

        waitForModifierRelease()
        pressCommandC()

        // Wait up to ~0.8s for the app to write to the clipboard.
        var copied: String?
        for _ in 0..<40 {
            usleep(20_000)
            if pb.changeCount != before {
                usleep(30_000) // let multi-type writes finish
                copied = pb.string(forType: .string)
                break
            }
        }

        if pb.changeCount != before { restore(saved, to: pb) }
        let text = copied?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }

    /// The user is still holding the hotkey's modifiers (e.g. ⌥) when we fire.
    /// Give them up to 0.5s to let go so the app doesn't see ⌥⌘C instead of ⌘C.
    private static func waitForModifierRelease() {
        let mask: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        for _ in 0..<25 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty { return }
            usleep(20_000)
        }
    }

    private static func pressCommandC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8 // kVK_ANSI_C
        let down = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: cKey, keyDown: false)
        // Set flags explicitly so any still-held modifiers don't leak into the chord.
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    private static func snapshot(_ pb: NSPasteboard) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ saved: Snapshot, to pb: NSPasteboard) {
        pb.clearContents()
        guard !saved.isEmpty else { return }
        let items: [NSPasteboardItem] = saved.map { pairs in
            let item = NSPasteboardItem()
            for (type, data) in pairs { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }
}
