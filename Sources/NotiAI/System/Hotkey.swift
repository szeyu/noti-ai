import Carbon
import Foundation

/// A system-wide shortcut via Carbon's RegisterEventHotKey (needs no special permission).
final class Hotkey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let id: UInt32
    let display: String

    /// Every shortcut gets its own ID, because each handler sees every hotkey press.
    private static var nextID: UInt32 = 1

    /// Parses strings like "cmd+option+a" and registers them. Returns nil if invalid or taken.
    init?(_ spec: String, action: @escaping () -> Void) {
        self.action = action
        id = Hotkey.nextID
        Hotkey.nextID += 1
        var mods: UInt32 = 0
        var key: UInt32?
        for raw in spec.lowercased().split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            switch part {
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "opt", "option", "alt": mods |= UInt32(optionKey)
            case "ctrl", "control": mods |= UInt32(controlKey)
            case "shift": mods |= UInt32(shiftKey)
            default:
                guard let code = Hotkey.keyCodes[part] else { return nil }
                key = code
            }
        }
        guard let key, mods != 0 else { return nil }
        display = Hotkey.symbols(for: spec)

        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let got = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let me = Unmanaged<Hotkey>.fromOpaque(userData).takeUnretainedValue()
            appLog.notice("hotkey event: got \(got) id \(pressed.id), handler for id \(me.id) (\(me.display, privacy: .public))")
            // Not ours: let the other shortcut's handler have it.
            guard got == noErr, pressed.signature == Hotkey.signature, pressed.id == me.id else {
                return OSStatus(eventNotHandledErr)
            }
            me.action()
            return noErr
        }, 1, &type, me, &handler)

        let hotkeyID = EventHotKeyID(signature: Hotkey.signature, id: id)
        let status = RegisterEventHotKey(key, mods, hotkeyID, GetApplicationEventTarget(), 0, &ref)
        appLog.notice("register \(spec, privacy: .public) as id \(self.id): status \(status)")
        guard status == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    /// "cmd+option+a" → "⌥⌘A" (macOS order ⌃⌥⇧⌘). Unknown parts are shown as typed.
    static func symbols(for spec: String) -> String {
        var mods = Set<Character>()
        var key = ""
        for raw in spec.lowercased().split(separator: "+") {
            switch raw.trimmingCharacters(in: .whitespaces) {
            case "cmd", "command": mods.insert("⌘")
            case "opt", "option", "alt": mods.insert("⌥")
            case "ctrl", "control": mods.insert("⌃")
            case "shift": mods.insert("⇧")
            case "space": key = "Space"
            case "return": key = "↩"
            case let k: key = k.uppercased()
            }
        }
        return "⌃⌥⇧⌘".filter { mods.contains($0) } + key
    }

    private static let signature = OSType(0x4E4F5449) // 'NOTI'

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    private static let keyCodes: [String: UInt32] = {
        var m: [String: UInt32] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19,
            "7": 0x1A, "8": 0x1C, "0": 0x1D, "o": 0x1F, "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
            "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E, "space": 0x31, "return": 0x24,
            "/": 0x2C, ";": 0x29, "'": 0x27, ",": 0x2B, ".": 0x2F, "`": 0x32,
        ]
        let fkeys: [UInt32] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for (i, code) in fkeys.enumerated() { m["f\(i + 1)"] = code }
        return m
    }()
}
