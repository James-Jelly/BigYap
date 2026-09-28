#if os(macOS)
import AppKit
import CoreAudio
import IOKit.hidsystem

/// The two system pieces behind pausing music for a take: reading which apps
/// are sending audio out right now, and pressing the Play/Pause media key.
///
/// Both are public API and work inside the App Sandbox. macOS has no public
/// way to ask what is playing or to pause another app directly (MediaRemote
/// can, but it is private and refuses third-party callers since macOS 15.4),
/// so the media key is the one route that reaches Music, Spotify and browser
/// tabs alike: macOS hands it to whichever app owns Now Playing.
enum SystemPlayback {
    /// The processes currently sending audio to any output device. Only those
    /// are read in full, since they are the only ones the pause decision looks
    /// at, and each property read is a round trip to the audio server.
    static func audioOutputProcesses() -> [AudioProcessActivity] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = propertyAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else {
            return []
        }

        return objects.compactMap { object in
            guard readUInt32(kAudioProcessPropertyIsRunningOutput, of: object) == 1 else { return nil }
            return AudioProcessActivity(
                pid: Int32(bitPattern: readUInt32(kAudioProcessPropertyPID, of: object) ?? 0),
                bundleID: readString(kAudioProcessPropertyBundleID, of: object) ?? "",
                isRunningOutput: true,
                isRunningInput: readUInt32(kAudioProcessPropertyIsRunningInput, of: object) == 1
            )
        }
    }

    /// Presses and releases Play/Pause, exactly as the key on the keyboard
    /// would. Posting an event needs Accessibility; without it macOS drops the
    /// event silently, so callers check first.
    static func pressPlayPause() {
        postMediaKey(down: true)
        postMediaKey(down: false)
    }

    /// Media keys travel as system-defined events of subtype 8: the key code
    /// sits in the top 16 bits of `data1` and the key state (0xA down, 0xB up)
    /// in the byte below it.
    private static func postMediaKey(down: Bool) {
        let state = down ? 0xA : 0xB
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: (Int(NX_KEYTYPE_PLAY) << 16) | (state << 8),
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    // MARK: - Core Audio reads

    private static func propertyAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func readUInt32(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var address = propertyAddress(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func readString(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }
}
#endif
