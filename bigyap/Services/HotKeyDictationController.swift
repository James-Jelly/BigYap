#if os(macOS)
import AppKit
import Carbon.HIToolbox
import Observation
import SwiftData

/// Drives a dictation take from anywhere in the system: press the shortcut in any
/// app to start, press it again to stop. The finished text is pasted into
/// whatever text field had focus, and the take is saved to history exactly as
/// an in-app recording would be.
///
/// This is a second entry point into the same pipeline `RecordView` drives, not
/// a second pipeline: it uses the same `AudioRecorder`, `LiveTranscriptionSession`
/// and `TranscriptFinalizer`. Only the orchestration differs, because there is
/// no UI here to show a live preview, offer a retry, or let the user edit.
@MainActor
@Observable
final class HotKeyDictationController {
    /// True from the moment the hot key starts a take until the text has been
    /// delivered — the window's status row and the Dock bounce both follow it.
    private(set) var isDictating = false
    /// True while the take is being finalized after the second press, so the
    /// window can keep showing the transcribing state until text lands.
    private(set) var isFinalizing = false
    /// The transcript as it forms, mirrored into the window's Live card so a
    /// hot-key take looks the same on screen as one started in the app.
    private(set) var liveTranscript = ""
    /// The entry the last take saved, plus a counter the window observes to
    /// pick it up — a bare object reference isn't `Equatable` for `onChange`.
    private(set) var lastEntry: TranscriptEntry?
    private(set) var deliveryCount = 0
    private(set) var lastDelivery: String?
    private(set) var errorMessage: String?
    private(set) var isHotKeyRegistered = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let latestStore = LatestTranscriptStore()
    @ObservationIgnored private let recorder = AudioRecorder()

    @ObservationIgnored private var hotKey: GlobalHotKey?
    @ObservationIgnored private var session: LiveTranscriptionSession?
    @ObservationIgnored private var isFinishing = false

    /// The input level of the hot-key take's own recorder, so the window's
    /// meter and button pulse follow a dictation started from another app.
    /// `AudioRecorder` is itself `@Observable`, so reading through this
    /// computed property still updates the view.
    var level: Float { recorder.level }

    init(settings: AppSettings, container: ModelContainer) {
        self.settings = settings
        self.container = container
    }

    // MARK: - Registration

    func register() {
        guard hotKey == nil else { return }
        let shortcut = settings.dictationShortcut
        hotKey = GlobalHotKey(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.carbonModifiers,
            onPress: { [weak self] in self?.toggle() }
        )
        isHotKeyRegistered = hotKey?.isRegistered ?? false
        if !isHotKeyRegistered {
            hotKey = nil
            errorMessage = "Another app is already using \(shortcut.label)."
        } else {
            errorMessage = nil
        }
    }

    /// Re-registers after the user picks a different combination. The old one
    /// is released first — holding both would leave a stale hot key live.
    func reregister() {
        unregister()
        guard settings.globalHotKeyEnabled else { return }
        register()
    }

    func unregister() {
        hotKey?.unregister()
        hotKey = nil
        isHotKeyRegistered = false
    }

    // MARK: - Flow

    func toggle() {
        guard settings.globalHotKeyEnabled else { return }
        // A press landing mid-transcription would otherwise start a new take
        // on top of the one still finishing.
        guard !isFinishing else { return }

        if isDictating {
            Task { await stop() }
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        // The window's own recorder may already hold the microphone.
        guard !AudioRecorder.isCapturing else {
            errorMessage = "BigYap is already recording in its window."
            NSSound.beep()
            return
        }
        errorMessage = nil
        liveTranscript = ""

        guard await recorder.requestPermission() else {
            errorMessage = AudioRecorderError.microphoneDenied.localizedDescription
            NSSound.beep()
            return
        }

        session = try? await LiveTranscriptionSession(
            vocabulary: settings.correctWithVocabulary ? settings.customVocabulary : [],
            onUpdate: { [weak self] text in self?.liveTranscript = text }
        )

        do {
            let session = session
            try await recorder.start(onChunk: { session?.feed($0) })
            isDictating = true
            showRecordingIndicator()
        } catch {
            session?.cancel()
            self.session = nil
            errorMessage = error.localizedDescription
            NSSound.beep()
        }
    }

    private func stop() async {
        guard isDictating else { return }
        isFinishing = true
        defer { isFinishing = false }

        let audio = await recorder.stop()
        isDictating = false
        isFinalizing = true
        defer {
            isFinalizing = false
            liveTranscript = ""
        }
        hideRecordingIndicator()

        guard audio.duration > 0.25 else {
            session?.cancel()
            session = nil
            return
        }

        let raw: String
        if let session {
            self.session = nil
            do {
                raw = try await session.finish()
            } catch {
                session.cancel()
                raw = (try? await batchTranscribe(audio)) ?? ""
            }
        } else {
            raw = (try? await batchTranscribe(audio)) ?? ""
        }

        deliver(raw, duration: audio.duration)
    }

    /// Fallback for when live analysis wasn't available (no model yet) or the
    /// stream failed. Same VAD-then-transcribe path the window uses.
    private func batchTranscribe(_ audio: RecordedAudio) async throws -> String {
        var working = audio
        if settings.trimSilence {
            let trimmed = VoiceActivityTrimmer().trim(audio.samples, sampleRate: audio.sampleRate)
            working = RecordedAudio(samples: trimmed.samples, sampleRate: audio.sampleRate, duration: audio.duration)
        }
        return try await AppleSpeechTranscriberEngine.transcribe(
            working,
            vocabulary: settings.correctWithVocabulary ? settings.customVocabulary : []
        ).text
    }

    private func deliver(_ raw: String, duration: TimeInterval) {
        guard let text = TranscriptFinalizer(settings: settings).finalize(raw) else {
            errorMessage = "No speech was detected."
            NSSound.beep()
            return
        }

        let delivery = SystemTextInjector.deliver(text)
        switch delivery {
        case .pasted:
            lastDelivery = "Pasted into the frontmost app"
            errorMessage = nil
        case .clipboardOnly(let reason):
            lastDelivery = "Copied to clipboard — press ⌘V to paste"
            errorMessage = reason
        }

        let entry = TranscriptEntry(
            text: text,
            duration: duration,
            source: TranscriptSource.appleSpeechTranscriber,
            copiedToClipboard: true
        )
        let context = container.mainContext
        context.insert(entry)
        try? context.save()
        latestStore.save(text)
        lastEntry = entry
        deliveryCount += 1
    }

    // MARK: - Dock feedback

    /// A badge on the Dock tile for the length of the take. Deliberately not
    /// `requestUserAttention` — a bouncing icon is loud for something the user
    /// started on purpose, and it does nothing at all while BigYap is
    /// frontmost, so the badge is both quieter and more consistent.
    private func showRecordingIndicator() {
        NSApp.dockTile.badgeLabel = "●"
    }

    private func hideRecordingIndicator() {
        NSApp.dockTile.badgeLabel = nil
    }
}
#endif
