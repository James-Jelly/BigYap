#if os(macOS)
import AppKit
import Carbon.HIToolbox

/// A system-wide hot key, registered while the app is running.
///
/// Deliberately Carbon's `RegisterEventHotKey` rather than
/// `NSEvent.addGlobalMonitorForEvents`: the NSEvent route needs Accessibility
/// permission to see key-downs in other apps, and asking for that just to
/// notice a key press would be a heavy first-run ask. Carbon hot keys need no
/// permission at all, work from a sandboxed app, and are the mechanism the
/// system's own shortcut UI is built on. The API is old, not deprecated.
///
/// Only one key combination can own a given registration system-wide — if
/// another app already holds it, registration fails and `isRegistered` stays
/// false rather than silently doing nothing.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let identifier: UInt32

    private(set) var isRegistered = false

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_Space`.
    ///   - modifiers: Carbon modifier mask, e.g. `optionKey`.
    ///   - onPress: run on the main actor each time the combination is pressed.
    init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping @MainActor () -> Void) {
        GlobalHotKey.installDispatcherIfNeeded()

        identifier = GlobalHotKey.nextIdentifier
        GlobalHotKey.nextIdentifier += 1
        GlobalHotKey.handlers[identifier] = onPress

        // 'BYap' — the signature only has to be stable and unlikely to collide.
        let hotKeyID = EventHotKeyID(signature: 0x42596170, id: identifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            GlobalHotKey.handlers[identifier] = nil
            return nil
        }
        hotKeyRef = ref
        isRegistered = true
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
        GlobalHotKey.handlers[identifier] = nil
        isRegistered = false
    }

    // No `deinit` cleanup: a nonisolated `deinit` can't touch the main-actor
    // Carbon handle under Swift 6, and this object lives for the life of the
    // app anyway. Callers unregister explicitly.

    // MARK: - Shared Carbon dispatcher

    // Touched only from the main actor (the Carbon handler hops there before
    // reading), which is what makes the unchecked mutable global safe.
    fileprivate static var handlers: [UInt32: @MainActor () -> Void] = [:]
    private static var nextIdentifier: UInt32 = 1
    private static var dispatcherInstalled = false

    private static func installDispatcherIfNeeded() {
        guard !dispatcherInstalled else { return }
        dispatcherInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), hotKeyDispatcher, 1, &spec, nil, nil)
    }
}

/// Carbon calls this on the main thread, but as a plain C function pointer it
/// carries no actor isolation, so the hop is made explicit.
private let hotKeyDispatcher: EventHandlerUPP = { _, event, _ in
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let identifier = hotKeyID.id
    DispatchQueue.main.async {
        MainActor.assumeIsolated {
            GlobalHotKey.handlers[identifier]?()
        }
    }
    return noErr
}
#endif
