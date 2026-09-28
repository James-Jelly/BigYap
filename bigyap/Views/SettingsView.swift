import AVFoundation
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var microphoneStatus = "Unknown"
    #if os(macOS)
    @Environment(HotKeyDictationController.self) private var hotKeyController: HotKeyDictationController?
    /// Accessibility can be granted or revoked in System Settings while the app
    /// runs, so this is re-read whenever the window becomes active rather than
    /// cached at launch.
    @State private var accessibilityGranted = false
    @State private var showAccessibilityPrimer = false
    #endif

    var body: some View {
        @Bindable var settings = settings
        return NavigationStack {
            Form {
                #if os(macOS)
                Section {
                    Toggle("Dictate with \(settings.dictationShortcut.label) anywhere", isOn: $settings.globalHotKeyEnabled)
                        .onChange(of: settings.globalHotKeyEnabled) { _, enabled in
                            if enabled { hotKeyController?.register() } else { hotKeyController?.unregister() }
                        }

                    LabeledContent("Shortcut") {
                        ShortcutRecorderView(shortcut: $settings.dictationShortcut) { _ in
                            hotKeyController?.reregister()
                        }
                    }
                    LabeledContent("Status", value: hotKeyStatus)

                    LabeledContent("Paste into other apps", value: accessibilityStatus)
                    if !accessibilityGranted {
                        Button("Set up pasting…") { showAccessibilityPrimer = true }
                    }
                } header: {
                    Text("System-wide dictation")
                } footer: {
                    Text("Press your shortcut in any app to start a take, and again to stop. BigYap must be running. Without Accessibility access the transcript still lands on your clipboard — you press ⌘V yourself.")
                }
                #endif

                Section {
                    Toggle("Trim silence", isOn: $settings.trimSilence)
                } header: {
                    Text("Recording")
                } footer: {
                    Text("Removes silent gaps before transcription, on device — so pauses and dead air don't get processed.")
                }

                #if os(macOS)
                Section {
                    Toggle("Pause music while recording", isOn: $settings.pausePlaybackWhileRecording)
                    // Without Accessibility the media key is silently dropped,
                    // so say so here rather than let the switch look like it works.
                    if settings.pausePlaybackWhileRecording && !accessibilityGranted {
                        LabeledContent("Status", value: "Needs Accessibility")
                        Button("Set up Accessibility…") { showAccessibilityPrimer = true }
                    }
                } header: {
                    Text("Playback")
                } footer: {
                    Text("When a take starts, whatever is playing (Music, Spotify, a video in your browser) pauses. It carries on when you finish. This uses the same Accessibility access as pasting.")
                }
                #endif

                Section {
                    Toggle("Remove filler words", isOn: $settings.removeFillerWords)
                    NavigationLink {
                        StringListEditor(
                            title: "Filler words",
                            prompt: "Add a word to remove",
                            footer: "These words are stripped from new transcripts when “Remove filler words” is on.",
                            items: $settings.fillerWords,
                            resetDefaults: AppSettings.defaultFillerWords
                        )
                    } label: {
                        LabeledContent("Filler words", value: "\(settings.fillerWords.count)")
                    }

                    Toggle("Correct with vocabulary", isOn: $settings.correctWithVocabulary)
                    NavigationLink {
                        StringListEditor(
                            title: "Custom vocabulary",
                            prompt: "Add a name or term",
                            footer: "Names and jargon you add here are matched against new transcripts and corrected — great for brand names, people, and technical terms.",
                            items: $settings.customVocabulary
                        )
                    } label: {
                        LabeledContent("Custom vocabulary", value: "\(settings.customVocabulary.count)")
                    }
                } header: {
                    Text("Transcript cleanup")
                } footer: {
                    Text("Strip filler words and correct names or jargon in new transcripts — all on device.")
                }

                Section {
                    Toggle("Copy transcript automatically", isOn: $settings.copyToClipboard)
                    Toggle("New line per sentence", isOn: $settings.paragraphPerSentence)
                    Toggle("Append trailing space", isOn: $settings.appendTrailingSpace)
                } header: {
                    Text("Output")
                } footer: {
                    Text("“New line per sentence” puts each sentence on its own line with a blank line between, so a pasted transcript is already formatted. “Append trailing space” adds a space to the end of each transcript, so when you dictate several in a row the words don't run together.")
                }

                Section("Privacy") {
                    LabeledContent("Microphone", value: microphoneStatus)
                    Text("Recording and transcription happen entirely on this device. Transcripts are stored locally with SwiftData and never leave your \(DeviceNaming.thisDevice).")
                        .font(.brand(.footnote))
                        .foregroundStyle(Brand.inkSecondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Brand.canvas)
            .contentMargins(.bottom, Spacing.xl, for: .scrollContent)
            .navigationTitle("Settings")
            .canvasToolbarBackground()
            .tint(Brand.blush)
            .task {
                microphoneStatus = microphonePermissionStatus()
                #if os(macOS)
                accessibilityGranted = SystemTextInjector.canInjectKeystrokes
                #endif
            }
            // Refresh when returning from the system Settings app, where the
            // user may just have changed the permission.
            #if os(macOS)
            .sheet(isPresented: $showAccessibilityPrimer) {
                AccessibilityPrimerView {
                    settings.hasSeenAccessibilityPrimer = true
                    accessibilityGranted = SystemTextInjector.canInjectKeystrokes
                    showAccessibilityPrimer = false
                }
            }
            #endif
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    microphoneStatus = microphonePermissionStatus()
                    #if os(macOS)
                    accessibilityGranted = SystemTextInjector.canInjectKeystrokes
                    #endif
                }
            }
        }
    }

    #if os(macOS)
    private var hotKeyStatus: String {
        guard settings.globalHotKeyEnabled else { return "Off" }
        guard let hotKeyController else { return "Starting…" }
        return hotKeyController.isHotKeyRegistered
            ? "Listening"
            : "Unavailable — in use by another app"
    }

    private var accessibilityStatus: String {
        accessibilityGranted ? "Granted" : "Clipboard only"
    }
    #endif

    private func microphonePermissionStatus() -> String {
        switch MicPermission.current {
        case .granted: return "Granted"
        case .denied: return "Denied"
        case .undetermined: return "Not requested"
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}
