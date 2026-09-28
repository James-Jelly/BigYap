#if os(macOS)
import SwiftUI

/// Explains why BigYap wants Accessibility access before the system prompt
/// appears, and walks the grant to completion.
///
/// Worth the dedicated screen because this permission is the one people
/// reasonably hesitate over — "control your computer" is alarming phrasing for
/// what is, here, a ⌘V and the Play/Pause key. It also has awkward mechanics:
/// the grant usually doesn't reach an already-running process, so the flow has
/// to offer a relaunch; and a grant made for a differently signed copy of
/// BigYap still shows as switched on while no longer applying, so the steps
/// say how to clear it rather than leaving the user staring at a switch that's
/// already on.
struct AccessibilityPrimerView: View {
    var onDismiss: () -> Void

    @Environment(AppSettings.self) private var settings

    @State private var isGranted = SystemTextInjector.canInjectKeystrokes
    @State private var didRequest = false

    var body: some View {
        VStack(spacing: Spacing.xl) {
            ZStack {
                Circle()
                    .fill(isGranted ? Brand.sage.opacity(0.18) : Brand.blushSoft)
                    .frame(width: 96, height: 96)
                Image(systemName: isGranted ? "checkmark" : "text.cursor")
                    .font(.brand(.largeTitle, weight: .regular))
                    .foregroundStyle(isGranted ? Brand.sage : Brand.blush)
            }

            VStack(spacing: Spacing.sm) {
                Text(isGranted ? "Ready to paste" : "Let BigYap paste for you")
                    .font(.brandTitle)
                    .foregroundStyle(Brand.ink)
                Text(explanation)
                    .font(.brandBody)
                    .foregroundStyle(Brand.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Spacing.lg)

            if !isGranted {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    step(1, "Open Privacy & Security › Accessibility")
                    step(2, "If BigYap isn't in the list, click + and add it")
                    step(3, "Switch BigYap on")
                    step(4, "Relaunch BigYap so the change takes effect")
                    Text("Already switched on? macOS can hold on to an older copy of BigYap. Select it, remove it with −, then add BigYap again with +.")
                        .font(.brand(.caption))
                        .foregroundStyle(Brand.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Spacing.xs)
                }
                .padding(Spacing.md)
                .background(Brand.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
                .padding(.horizontal, Spacing.lg)
            }

            VStack(spacing: Spacing.sm) {
                if isGranted {
                    Button(action: onDismiss) {
                        primaryLabel("Done")
                    }
                    .buttonStyle(.plain)
                } else if didRequest {
                    Button {
                        SystemTextInjector.relaunch()
                    } label: {
                        primaryLabel("Relaunch BigYap")
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: Spacing.md) {
                        Button("Open System Settings again") {
                            SystemSettings.openAccessibilityPrivacy()
                        }
                        .buttonStyle(.plain)
                        // Step 2 means finding the app in Finder, and BigYap
                        // knows where it lives — so the file picker opens on it
                        // rather than the user hunting for the bundle.
                        Button("Show BigYap in Finder") {
                            SystemSettings.revealAppInFinder()
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.brand(.footnote, weight: .semibold))
                    .foregroundStyle(Brand.blush)
                } else {
                    Button {
                        didRequest = true
                        // The system prompt and the direct deep link do the same
                        // job, but the prompt alone is easy to dismiss by
                        // accident, so the pane is opened as well.
                        SystemTextInjector.requestAccessibilityAccess()
                        SystemSettings.openAccessibilityPrivacy()
                    } label: {
                        primaryLabel("Open System Settings")
                    }
                    .buttonStyle(.plain)
                }

                Button("Not now — just use the clipboard") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .font(.brand(.footnote))
                .foregroundStyle(Brand.inkTertiary)
            }
            .padding(.horizontal, Spacing.lg)
        }
        .padding(.vertical, Spacing.xl)
        .frame(width: 420)
        .background(Brand.canvas)
        .task {
            // Catches the case where the grant does reach this process, so the
            // screen flips to "Ready" on its own instead of stranding the user.
            isGranted = await SystemTextInjector.waitForAccessibility()
        }
    }

    private var explanation: String {
        if isGranted {
            return "BigYap can now paste straight into whatever you're typing in. Press \(settings.dictationShortcut.label) anywhere to start a take."
        }
        return "BigYap sends ⌘V to drop your words into the app you're typing in and presses Play/Pause to pause your music while you talk. macOS counts both as controlling your computer, so they need Accessibility access. Nothing is read from other apps and nothing leaves your Mac."
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text("\(number)")
                .font(.brand(.caption, weight: .semibold))
                .foregroundStyle(Brand.blush)
                .frame(width: 16)
            Text(text)
                .font(.brand(.footnote))
                .foregroundStyle(Brand.inkSecondary)
            Spacer(minLength: 0)
        }
    }

    private func primaryLabel(_ title: String) -> some View {
        Text(title)
            .font(.brand(.headline, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(Brand.blush, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
    }
}
#endif
