#if os(macOS)
import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a combination to set the dictation hot key.
///
/// Capture uses a **local** event monitor, which only sees events aimed at
/// BigYap's own window — no Accessibility permission involved, unlike a global
/// monitor. That's fine here because the user is by definition looking at this
/// control when they set it.
struct ShortcutRecorderView: View {
    @Binding var shortcut: DictationShortcut
    /// Reported when a new combination can't be registered, so the UI can say
    /// so instead of silently keeping a hot key that does nothing.
    var onRecorded: (DictationShortcut) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejection: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Press keys…" : shortcut.label)
                    .font(.brand(.body, weight: .semibold))
                    .foregroundStyle(isRecording ? Brand.blush : Brand.ink)
                    .frame(minWidth: 96)
                    .padding(.vertical, Spacing.xs)
                    .padding(.horizontal, Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(isRecording ? Brand.blushSoft : Brand.surfaceMuted)
                    )
            }
            .buttonStyle(.plain)

            if isRecording {
                Text("Esc to cancel")
                    .font(.brand(.caption))
                    .foregroundStyle(Brand.inkTertiary)
            } else if shortcut != .default {
                Button("Reset") {
                    shortcut = .default
                    onRecorded(.default)
                }
                .buttonStyle(.plain)
                .font(.brand(.caption, weight: .semibold))
                .foregroundStyle(Brand.blush)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let rejection {
                Text(rejection)
                    .font(.brand(.caption))
                    .foregroundStyle(Brand.rose)
                    .offset(y: 18)
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        guard monitor == nil else { return }
        isRecording = true
        rejection = nil

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if Int(event.keyCode) == kVK_Escape {
                stopRecording()
                return nil
            }

            if let candidate = DictationShortcut(event: event) {
                shortcut = candidate
                onRecorded(candidate)
                stopRecording()
            } else {
                rejection = "Include ⌘, ⌥, ⌃ or ⇧ — a plain key would stop working everywhere."
            }
            // Swallowed either way, so recording a shortcut never types into
            // whatever was focused behind this control.
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
#endif
