import Foundation

/// One process's audio activity at a moment in time, as Core Audio reports it.
nonisolated struct AudioProcessActivity: Sendable, Equatable {
    var pid: Int32
    var bundleID: String
    var isRunningOutput: Bool
    var isRunningInput: Bool
}

/// Decides whether something is playing before a take presses Play/Pause.
///
/// The media key is a toggle, so a wrong "yes" doesn't just fail to pause — it
/// *starts* whatever app owns Now Playing, in the middle of a dictation. Every
/// rule here therefore leans towards "no".
///
/// Output running is the only public signal macOS offers, and it is a coarse
/// one: players keep their output open for several seconds after being paused
/// (QuickTime Player measured about seven), so a take started right after a
/// manual pause can still read as playing.
nonisolated enum PlaybackPausePolicy {
    /// System processes that make sound without ever owning Now Playing: alert
    /// sounds, the charging chime, Siri's voice and spoken accessibility
    /// feedback. Their output says nothing about music.
    static let systemSoundSources: Set<String> = [
        "systemsoundserverd",
        "com.apple.PowerChime",
        "com.apple.sirittsd",
        "com.apple.accessibility.heard",
        "com.apple.VoiceOver",
        "com.apple.speech.speechsynthesisd",
    ]

    static func isOtherAudioPlaying(_ processes: [AudioProcessActivity], ownPID: Int32) -> Bool {
        processes.contains { process in
            process.isRunningOutput
                && process.pid != ownPID
                // Capturing as well as playing means a call (FaceTime, Zoom, a
                // Meet tab), not music. Pressing Play/Pause then would start
                // the user's music over the call.
                && !process.isRunningInput
                && !systemSoundSources.contains(process.bundleID)
        }
    }
}
