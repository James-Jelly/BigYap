import SwiftUI

/// One-time first-run explainer shown before the system microphone prompt, so
/// the permission request arrives with context instead of ambushing the user
/// the moment the app opens (auto-record starts right after this).
struct PermissionPrimerView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            Brand.canvas.ignoresSafeArea()

            VStack(spacing: Spacing.xl) {
                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(Brand.blushSoft)
                        .frame(width: 120, height: 120)
                    Image(systemName: "mic.fill")
                        .font(.brand(.largeTitle, weight: .regular))
                        .foregroundStyle(Brand.blush)
                }

                VStack(spacing: Spacing.sm) {
                    Text("Your voice, your device")
                        .font(.brandTitle)
                        .foregroundStyle(Brand.ink)
                    Text("BigYap turns your speech into text using the microphone and Apple's on-device speech model. Recording and transcription happen entirely on this \(DeviceNaming.thisDevice) — audio never leaves your device.")
                        .font(.brandBody)
                        .foregroundStyle(Brand.inkSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Spacing.xl)

                Text("Next, \(DeviceNaming.systemName) will ask for microphone access.")
                    .font(.brand(.footnote))
                    .foregroundStyle(Brand.inkTertiary)

                Spacer(minLength: 0)

                Button {
                    Haptics.tap()
                    onContinue()
                } label: {
                    Text("Enable microphone")
                        .font(.brand(.headline, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Spacing.md)
                        .background(Brand.blush, in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xl)
            }
        }
    }
}

#Preview {
    PermissionPrimerView {}
}
