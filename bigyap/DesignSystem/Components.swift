import SwiftUI

/// The single, unified record-button state — replaces the old design's two
/// inconsistent recording looks.
enum RecordPhase: Equatable {
    case idle
    case recording
    case processing
}

/// The primary record control. Pure visual: callers attach the gesture.
/// Blush at rest, deep rose while recording, with a level-driven halo that
/// stays still under Reduce Motion. No text inside, so it never clips at large
/// Dynamic Type sizes.
struct RecordButton: View {
    var phase: RecordPhase
    var level: Float
    /// Halo diameter. The core and glyph scale proportionally, so callers can
    /// shrink the whole control (e.g. in landscape) by passing a smaller size.
    var size: CGFloat = 208

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var coreColor: Color {
        phase == .recording ? Brand.rose : Brand.blush
    }

    private var haloColor: Color {
        phase == .recording ? Brand.rose.opacity(0.20) : Brand.blushSoft
    }

    var body: some View {
        let pulse: CGFloat = (phase == .recording && !reduceMotion)
            ? 1 + CGFloat(min(level, 0.45)) * 0.72
            : 1
        let scale = size / 208
        let core = 140 * scale

        ZStack {
            Circle()
                .fill(haloColor)
                .frame(width: size, height: size)
                .scaleEffect(pulse)

            Circle()
                .fill(coreColor)
                .frame(width: core, height: core)

            Group {
                switch phase {
                case .processing:
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                case .recording:
                    Image(systemName: "stop.fill")
                        .font(.system(size: 38 * scale, weight: .medium))
                case .idle:
                    Image(systemName: "mic.fill")
                        .font(.system(size: 44 * scale, weight: .medium))
                }
            }
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: phase)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
    }
}

/// A delicate row of capsules that breathe with the input level while recording.
struct LevelMeter: View {
    var level: Float
    var active: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let weights: [CGFloat] = [0.45, 0.7, 1.0, 0.82, 0.55, 0.92, 0.5]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(weights.indices, id: \.self) { index in
                Capsule()
                    .fill(active ? Brand.rose : Brand.inkTertiary.opacity(0.45))
                    .frame(width: 6, height: barHeight(at: index))
            }
        }
        .frame(height: 48)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
        .accessibilityHidden(true)
    }

    private func barHeight(at index: Int) -> CGFloat {
        let base: CGFloat = 8
        guard active else { return base }
        let clamped = CGFloat(min(max(level, 0), 1))
        return base + clamped * 38 * weights[index % weights.count]
    }
}

/// Small uppercase section label used above grouped content.
struct SectionHeader: View {
    var title: String

    var body: some View {
        Text(title.uppercased())
            .font(.brand(.caption2, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Brand.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
