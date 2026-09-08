#if os(macOS)
import AppKit
import ApplicationServices

/// Delivers finished text into whatever text field the user is actually in,
/// by putting it on the pasteboard and synthesising ⌘V into the frontmost app.
///
/// **This needs Accessibility permission**, because posting events into another
/// process is exactly what that permission governs. Without it the text still
/// lands on the clipboard and the user pastes it themselves — the feature
/// degrades, it doesn't break.
///
/// Note the app never activates itself around this: the target app has to stay
/// frontmost or the keystroke goes to the wrong window.
enum SystemTextInjector {
    /// Whether this process may post events into other apps *right now*.
    /// Re-read it each time rather than caching — the user can revoke it in
    /// System Settings while the app is running.
    static var canInjectKeystrokes: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system's "grant Accessibility" prompt, which deep-links the
    /// user to the right pane. Returns the status as of right now, which is
    /// almost always false: the user grants it after this call returns, and on
    /// some macOS versions the app must be relaunched before the grant takes.
    @discardableResult
    static func requestAccessibilityAccess() -> Bool {
        // `kAXTrustedCheckOptionPrompt` is an imported global `var`, which
        // Swift 6 won't let us touch across isolation. The key's value is a
        // documented, stable string, so it's spelled out instead.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Polls until the Accessibility grant appears, or the task is cancelled.
    ///
    /// Polling rather than observing because there is no notification for a TCC
    /// change. Worth noting the grant often does **not** take effect for an
    /// already-running process, which is why the UI offers a relaunch as well
    /// as waiting — this returning false is not proof the user said no.
    static func waitForAccessibility(timeout: Duration = .seconds(120)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if canInjectKeystrokes { return true }
            do {
                try await Task.sleep(for: .milliseconds(600))
            } catch {
                return canInjectKeystrokes
            }
        }
        return canInjectKeystrokes
    }

    /// Relaunches BigYap, which is how a fresh TCC grant is picked up. The
    /// replacement is started with a short delay so it opens *after* this
    /// process has exited and macOS doesn't treat it as already running.
    @MainActor
    static func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    enum Delivery {
        /// Pasted straight into the focused text field.
        case pasted
        /// On the clipboard only — the user presses ⌘V. Carries why.
        case clipboardOnly(reason: String)
    }

    /// Puts `text` on the pasteboard, then tries to paste it. The pasteboard
    /// write always happens, so the text is never lost even when the keystroke
    /// can't be sent.
    ///
    /// The previous clipboard contents are **not** restored afterwards. Racing
    /// a restore against the target app's own paste is how these features end
    /// up pasting the wrong thing, and BigYap already treats the clipboard as
    /// an output it owns.
    @discardableResult
    static func deliver(_ text: String) -> Delivery {
        Clipboard.copy(text)

        guard canInjectKeystrokes else {
            return .clipboardOnly(reason: "BigYap doesn't have Accessibility permission.")
        }

        // A private event source keeps the synthetic keystroke from inheriting
        // modifier keys the user still happens to be holding — without this, a
        // hot key released a moment late turns ⌘V into ⌥⌘V in the target app.
        guard let source = CGEventSource(stateID: .privateState) else {
            return .clipboardOnly(reason: "Couldn't create an event source.")
        }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let vKeyCode: CGKeyCode = 0x09 // kVK_ANSI_V
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return .clipboardOnly(reason: "Couldn't build the paste keystroke.")
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
        return .pasted
    }
}
#endif
