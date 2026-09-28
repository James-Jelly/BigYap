import SwiftData
import SwiftUI

struct RecordView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #if os(macOS)
    /// A take started with the global shortcut runs on the controller's own
    /// recorder and session, so the window mirrors its state rather than
    /// duplicating the pipeline.
    @Environment(HotKeyDictationController.self) private var hotKeyController: HotKeyDictationController?
    #endif

    @State private var recorder = AudioRecorder()
    @State private var isProcessing = false
    @State private var lastTranscript: String?
    /// The saved entry for the latest transcript, so manual edits update the
    /// same history row rather than creating a new one.
    @State private var lastEntry: TranscriptEntry?
    /// The transcript text as it was when the user started editing, used to tell
    /// a real edit from a focus tap so we only persist when something changed.
    @State private var editingBaseline: String?
    @FocusState private var editorFocused: Bool
    @State private var errorMessage: String?
    /// Live analysis running alongside the recorder; nil when it couldn't start
    /// (no model, simulator) — then we fall back to batch transcription on stop.
    @State private var liveSession: LiveTranscriptionSession?
    /// A pre-built session with the model already loaded, armed at launch and
    /// after each take, so pressing record only has to start the microphone.
    @State private var standbySession: LiveTranscriptionSession?
    @State private var liveTranscript = ""
    /// The last recording's samples, kept in memory only, so a failed
    /// transcription can be retried instead of losing the take. Never written
    /// to disk; cleared on success or when a new recording starts.
    @State private var retryAudio: RecordedAudio?
    @State private var pressStarted = false
    @State private var pressStartDate: Date?
    @State private var didStopOnPress = false
    @State private var toggleActive = false
    @State private var transientStatus: String?
    /// Recording starts on its own the first time the view appears, so opening
    /// the app is enough — one tap on the big button stops the take.
    @State private var didAutoStart = false
    /// First-run explainer shown before the system microphone prompt, so the
    /// permission request has context instead of ambushing the user at launch.
    @State private var showPermissionPrimer = false
    /// Set when the microphone permission is denied, so the error banner can
    /// offer a route into the system Settings app.
    @State private var micDenied = false

    private let latestStore = LatestTranscriptStore()

    /// A press shorter than this is a tap (toggle on/off); longer is a hold
    /// (push-to-talk, records until released).
    private static let holdThreshold: TimeInterval = 0.35

    /// A dictation take driven by the global shortcut, if one is running.
    private var hotKeyPhase: RecordPhase? {
        #if os(macOS)
        guard let hotKeyController else { return nil }
        if hotKeyController.isDictating { return .recording }
        if hotKeyController.isFinalizing { return .processing }
        return nil
        #else
        return nil
        #endif
    }

    private var phase: RecordPhase {
        if let hotKeyPhase { return hotKeyPhase }
        if isProcessing { return .processing }
        return recorder.isRecording ? .recording : .idle
    }

    /// The button pulse and meter follow whichever recorder holds the
    /// microphone — the window's own, or the shortcut's.
    private var displayLevel: Float {
        #if os(macOS)
        if let hotKeyController, hotKeyController.isDictating { return hotKeyController.level }
        #endif
        return recorder.level
    }

    private var displayLiveTranscript: String {
        #if os(macOS)
        if hotKeyPhase != nil { return hotKeyController?.liveTranscript ?? "" }
        #endif
        return liveTranscript
    }

    private var statusText: String {
        if let transientStatus { return transientStatus }
        #if os(macOS)
        if hotKeyController?.isDictating == true {
            return "Dictating with \(settings.dictationShortcut.label) — press again to finish"
        }
        #endif
        switch phase {
        case .processing: return "Transcribing on device…"
        case .recording: return pressStarted ? "Release to finish" : "Tap to finish"
        case .idle: return "Hold or tap to record"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.canvas.ignoresSafeArea()

                Group {
                    if verticalSizeClass == .compact {
                        landscapeContent
                    } else {
                        portraitContent
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: lastTranscript == nil)
                .animation(.easeInOut(duration: 0.2), value: errorMessage)
                .animation(.easeInOut(duration: 0.2), value: showsLiveCard)
                .animation(.easeInOut(duration: 0.2), value: phase)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: editorFocused)
            }
            .inlineNavigationTitle()
            .canvasToolbarBackground()
        }
        .task {
            await AppleSpeechTranscriberEngine.prepare()
            armStandby()
            // Start recording as soon as the app opens — the big button then
            // acts as the stop control for this first take. On the very first
            // launch the explainer runs first so the mic prompt has context.
            if !didAutoStart {
                didAutoStart = true
                // macOS deliberately does *not* auto-record: the Mac app sits
                // open in the background waiting for the dictation hot key, and a
                // window that opens the microphone on launch would both be a
                // surprise and hold the input the hot key needs.
                #if os(iOS)
                if settings.hasSeenPermissionPrimer {
                    toggleActive = true
                    await startRecording()
                } else {
                    showPermissionPrimer = true
                }
                #else
                if !settings.hasSeenPermissionPrimer { showPermissionPrimer = true }
                #endif
            }
        }
        // A shortcut take finishes outside the window, so its result is pulled
        // into the Latest card here — same editing and copy affordances as a
        // take started on the button.
        #if os(macOS)
        .onChange(of: hotKeyController?.deliveryCount) { _, _ in
            guard let entry = hotKeyController?.lastEntry else { return }
            lastEntry = entry
            lastTranscript = entry.text
            transientStatus = hotKeyController?.lastDelivery
        }
        #endif
        .sheet(isPresented: $showPermissionPrimer) {
            PermissionPrimerView {
                settings.hasSeenPermissionPrimer = true
                showPermissionPrimer = false
                Task {
                    toggleActive = true
                    await startRecording()
                }
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Layouts

    /// Portrait / regular height: brand on top, the record control centered, and
    /// the latest transcript flowing beneath it.
    private var portraitContent: some View {
        VStack(spacing: Spacing.xl) {
            header

            // While the transcript is being edited the record cluster gets out
            // of the way so the card sits above the keyboard with room to work.
            if !editorFocused {
                Spacer(minLength: 0)

                recordCluster(buttonSize: 208)
            }

            if showsLiveCard {
                liveCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if lastTranscript != nil {
                latestCard(transcriptBinding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let errorMessage {
                errorBanner(errorMessage)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.lg)
    }

    /// Landscape / compact height: the record control on the left, the latest
    /// transcript (and any error) in a scrollable panel on the right so nothing
    /// clips in the short vertical space.
    private var landscapeContent: some View {
        HStack(spacing: Spacing.xl) {
            recordCluster(buttonSize: 150)
                .frame(maxWidth: .infinity)

            if lastTranscript != nil || errorMessage != nil || showsLiveCard {
                ScrollView {
                    VStack(spacing: Spacing.md) {
                        if showsLiveCard {
                            liveCard
                        } else if lastTranscript != nil {
                            latestCard(transcriptBinding)
                        }
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
                .frame(maxWidth: .infinity)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md)
    }

    /// The record button, level meter, and status line — shared by both layouts.
    private func recordCluster(buttonSize: CGFloat) -> some View {
        VStack(spacing: Spacing.lg) {
            RecordButton(phase: phase, level: displayLevel, size: buttonSize)
                .gesture(recordGesture)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Record")
                .accessibilityValue(accessibilityValue)
                .accessibilityHint("Double-tap to start, double-tap again to finish")
                .accessibilityAction {
                    Task {
                        if recorder.isRecording {
                            toggleActive = false
                            await stopRecording()
                        } else {
                            toggleActive = true
                            await startRecording()
                        }
                    }
                }

            LevelMeter(level: displayLevel, active: phase == .recording)

            Text(statusText)
                .font(.brand(.headline))
                .foregroundStyle(phase == .idle ? Brand.ink : Brand.inkSecondary)
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: statusText)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            Text("bigyap")
                .font(.brandDisplay)
                .foregroundStyle(Brand.ink)
        }
        .padding(.top, Spacing.sm)
    }

    /// The live card shows while speech is being analyzed — during recording and
    /// through the brief finalize step after stopping.
    private var showsLiveCard: Bool {
        !displayLiveTranscript.isEmpty && (phase == .recording || phase == .processing)
    }

    /// Read-only card showing the transcript as it forms while recording.
    /// Volatile text firms up in place as the analyzer finalizes each phrase.
    private var liveCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(title: "Live")
                Spacer()
                Image(systemName: "waveform")
                    .font(.caption)
                    .foregroundStyle(Brand.blush)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .accessibilityHidden(true)
            }
            ScrollView {
                Text(displayLiveTranscript)
                    .font(.brandBody)
                    .foregroundStyle(Brand.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 150)
            .defaultScrollAnchor(.bottom)
        }
        .softCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Live transcript. \(displayLiveTranscript)")
    }

    /// Tap to edit — fix a misheard word or tweak spacing in place. Edits are
    /// saved to history (and re-copied to the clipboard) when the keyboard is
    /// dismissed.
    private func latestCard(_ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                SectionHeader(title: "Latest")
                Spacer()
                if editorFocused {
                    Button("Done") { editorFocused = false }
                        .font(.brand(.subheadline, weight: .semibold))
                        .foregroundStyle(Brand.blush)
                        .buttonStyle(.plain)
                } else {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(Brand.sage)
                        .accessibilityHidden(true)
                }
            }
            TextEditor(text: text)
                .font(.brandBody)
                .foregroundStyle(Brand.ink)
                .tint(Brand.blush)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 72, maxHeight: editorFocused ? .infinity : 150)
                .focused($editorFocused)
                .onChange(of: editorFocused) { _, focused in
                    if focused {
                        editingBaseline = text.wrappedValue
                    } else {
                        commitEditIfChanged()
                    }
                }
        }
        .softCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest transcript, editable. \(text.wrappedValue)")
    }

    /// Binding over `lastTranscript` so the editor can write back into it while
    /// the rest of the view keeps treating it as the source of truth.
    private var transcriptBinding: Binding<String> {
        Binding(
            get: { lastTranscript ?? "" },
            set: { lastTranscript = $0 }
        )
    }

    /// Persists a manual edit to the saved entry, the latest-transcript store,
    /// and the clipboard (when auto-copy is on). No-op when nothing changed or
    /// the box was cleared to whitespace.
    private func commitEditIfChanged() {
        guard let edited = lastTranscript,
              let text = TranscriptEditPolicy.committedText(edited: edited, previous: editingBaseline ?? "")
        else { return }

        lastEntry?.text = text
        try? modelContext.save()
        latestStore.save(text)

        if settings.copyToClipboard {
            Clipboard.copy(text)
            transientStatus = "Edit copied"
        } else {
            transientStatus = "Edit saved"
        }
        Haptics.tap()
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Brand.rose)
                Text(message)
                    .font(.brand(.footnote))
                    .foregroundStyle(Brand.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if retryAudio != nil {
                Button {
                    retryTranscription()
                } label: {
                    Label("Retry transcription", systemImage: "arrow.clockwise")
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(Brand.blush)
                }
                .buttonStyle(.plain)
                .disabled(isProcessing || recorder.isRecording)
            }
            if micDenied {
                Button {
                    SystemSettings.openMicrophonePrivacy()
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.brand(.footnote, weight: .semibold))
                        .foregroundStyle(Brand.blush)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.md)
        .background(Brand.blushSoft, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private var accessibilityValue: String {
        switch phase {
        case .recording: return "Recording"
        case .processing: return "Transcribing"
        case .idle: return "Ready"
        }
    }

    // MARK: - Gesture

    /// One control, two natural gestures — no mode switch. A quick **tap**
    /// toggles recording on, and a later tap stops it. A **hold** records only
    /// while the finger is down (push-to-talk) and stops on release. We tell
    /// them apart by how long the press lasts.
    private var recordGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !pressStarted, !isProcessing else { return }
                pressStarted = true
                pressStartDate = Date()
                if recorder.isRecording && toggleActive {
                    // A tap to stop an active toggle recording.
                    didStopOnPress = true
                    toggleActive = false
                    Task { await stopRecording() }
                } else if !recorder.isRecording {
                    didStopOnPress = false
                    Task { await startRecording() }
                }
            }
            .onEnded { _ in
                pressStarted = false
                let stoppedOnPress = didStopOnPress
                didStopOnPress = false
                let held = pressStartDate.map { Date().timeIntervalSince($0) } ?? 0
                pressStartDate = nil
                guard !stoppedOnPress else { return }

                if held >= Self.holdThreshold {
                    // Long press → push-to-talk: stop now that the finger lifted.
                    toggleActive = false
                    Task { await stopRecording() }
                } else {
                    // Quick tap → stay recording; the next tap finishes it.
                    toggleActive = true
                }
            }
    }

    // MARK: - Flow

    private func startRecording() async {
        guard !recorder.isRecording, !isProcessing else { return }
        // On macOS the global hot key may already hold the microphone.
        guard !AudioRecorder.isCapturing else {
            errorMessage = "A hot-key dictation take is already recording."
            return
        }
        editorFocused = false
        errorMessage = nil
        transientStatus = nil
        retryAudio = nil
        liveTranscript = ""

        let granted = await recorder.requestPermission()
        guard granted else {
            micDenied = true
            errorMessage = AudioRecorderError.microphoneDenied.localizedDescription
            Haptics.warning()
            return
        }
        micDenied = false

        // Take the hot standby (armed at launch / after the previous take) so
        // the model is already loaded; build one on the spot only when the
        // standby is missing or the vocabulary changed since it was armed.
        // A nil session means live analysis isn't available (no model,
        // simulator) — recording continues and the batch path transcribes on stop.
        if let standby = standbySession, standby.vocabulary == currentVocabulary {
            liveSession = standby
        } else {
            standbySession?.cancel()
            liveSession = try? await makeSession()
        }
        standbySession = nil

        do {
            let session = liveSession
            try await recorder.start(
                pausingPlayback: settings.pausePlaybackWhileRecording,
                onChunk: { session?.feed($0) }
            )
            Haptics.tap(.medium)
        } catch {
            liveSession?.cancel()
            liveSession = nil
            errorMessage = error.localizedDescription
        }
    }

    private var currentVocabulary: [String] {
        settings.correctWithVocabulary ? settings.customVocabulary : []
    }

    private func makeSession() async throws -> LiveTranscriptionSession {
        try await LiveTranscriptionSession(
            vocabulary: currentVocabulary,
            onUpdate: { liveTranscript = $0 }
        )
    }

    /// Builds the next hot session in the background so the following record
    /// press skips model setup entirely.
    private func armStandby() {
        Task {
            guard standbySession == nil else { return }
            standbySession = try? await makeSession()
        }
    }

    private func stopRecording() async {
        guard recorder.isRecording else { return }
        let audio = await recorder.stop()

        guard audio.duration > 0.25 else {
            liveSession?.cancel()
            liveSession = nil
            liveTranscript = ""
            armStandby()
            return
        }

        isProcessing = true
        defer { isProcessing = false }
        await finishTranscription(audio)
        armStandby()
    }

    /// Prefers the live session's already-analyzed transcript; falls back to a
    /// batch transcription of the captured samples when live analysis wasn't
    /// available or failed mid-stream.
    private func finishTranscription(_ audio: RecordedAudio) async {
        defer { liveTranscript = "" }

        if let session = liveSession {
            liveSession = nil
            do {
                let text = try await session.finish()
                processAndSave(
                    TranscriptionResult(
                        text: text,
                        source: TranscriptSource.appleSpeechTranscriber,
                        duration: audio.duration
                    ),
                    audio: audio
                )
                return
            } catch {
                session.cancel()
            }
        }

        await transcribeBatch(audio)
    }

    /// The non-live path: VAD trim + one-shot transcription. Used when live
    /// analysis couldn't run, and for manual retries.
    private func transcribeBatch(_ audio: RecordedAudio) async {
        var working = audio
        if settings.trimSilence {
            let result = VoiceActivityTrimmer().trim(audio.samples, sampleRate: audio.sampleRate)
            working = RecordedAudio(samples: result.samples, sampleRate: audio.sampleRate, duration: audio.duration)
        }

        do {
            let result = try await AppleSpeechTranscriberEngine.transcribe(
                working,
                vocabulary: currentVocabulary
            )
            processAndSave(result, audio: audio)
        } catch {
            errorMessage = error.localizedDescription
            retryAudio = audio
            Haptics.warning()
        }
    }

    private func processAndSave(_ result: TranscriptionResult, audio: RecordedAudio) {
        guard let text = TranscriptFinalizer(settings: settings).finalize(result.text) else {
            errorMessage = "No speech was detected."
            retryAudio = audio
            return
        }

        let copied = settings.copyToClipboard
        if copied {
            Clipboard.copy(text)
        }

        let entry = TranscriptEntry(
            text: text,
            duration: result.duration,
            source: result.source,
            copiedToClipboard: copied
        )
        modelContext.insert(entry)
        try? modelContext.save()

        latestStore.save(text)
        lastEntry = entry
        lastTranscript = text
        retryAudio = nil
        Haptics.success()
        transientStatus = copied ? "Copied to clipboard" : "Saved to history"
    }

    private func retryTranscription() {
        guard let audio = retryAudio, !isProcessing, !recorder.isRecording else { return }
        retryAudio = nil
        errorMessage = nil
        Task {
            isProcessing = true
            defer { isProcessing = false }
            await transcribeBatch(audio)
        }
    }
}

#Preview {
    RecordView()
        .environment(AppSettings())
        .modelContainer(for: TranscriptEntry.self, inMemory: true)
}
