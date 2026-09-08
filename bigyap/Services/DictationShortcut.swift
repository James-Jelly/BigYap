#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// The key combination that starts and stops a system-wide dictation take.
///
/// Carbon modifier masks are stored rather than `NSEvent.ModifierFlags`,
/// because Carbon is what `RegisterEventHotKey` speaks and converting once at
/// capture time beats converting on every registration.
///
/// `label` is captured from the key press rather than derived from `keyCode`.
/// Deriving it means translating through the active keyboard layout, and the
/// result would be wrong for anyone whose layout differs from the one they
/// recorded on — storing what the user actually saw themselves press is both
/// simpler and more honest.
struct DictationShortcut: Equatable, Sendable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var label: String

    static let `default` = DictationShortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey),
        label: "⌥Space"
    )

    /// Builds a shortcut from a captured key-down, or `nil` when the press
    /// isn't usable as a global hot key.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }

        // At least one modifier is required. A bare key would be swallowed
        // system-wide — the user could never type that letter again.
        guard carbon != 0 else { return nil }

        keyCode = UInt32(event.keyCode)
        carbonModifiers = carbon
        label = DictationShortcut.label(for: event, flags: flags)
    }

    init(keyCode: UInt32, carbonModifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.label = label
    }

    private static func label(for event: NSEvent, flags: NSEvent.ModifierFlags) -> String {
        var parts = ""
        // Apple's canonical modifier order, so the label matches every menu
        // and shortcut the user has ever seen.
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        return parts + keyName(for: event)
    }

    /// Keys with no printable character, plus a fallback to whatever the layout
    /// produced when the modifiers are ignored.
    private static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            let characters = event.charactersIgnoringModifiers ?? ""
            return characters.isEmpty ? "Key \(event.keyCode)" : characters.uppercased()
        }
    }
}
#endif
