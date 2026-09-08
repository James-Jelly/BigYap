import Accelerate
import Foundation

/// Native, dependency-free voice-activity detection used to trim silence from a
/// recording before transcription. Energy-based with an adaptive noise floor,
/// hangover padding around speech, and collapsing of over-long internal pauses.
///
/// This kills the "transcribed 4 seconds of silence" problem and means the
/// speech model never has to chew through dead air — all on-device, no model
/// download, no ONNX runtime.
nonisolated struct VoiceActivityTrimmer: Sendable {
    /// 0 = keep almost everything, 1 = trim aggressively. Maps to how far above
    /// the noise floor a frame must rise to count as speech.
    var sensitivity: Double = 0.5
    /// Analysis frame length in seconds.
    var frameDuration: Double = 0.03
    /// Padding kept on each side of detected speech so word edges aren't clipped.
    var hangover: Double = 0.12
    /// Internal pauses longer than this are collapsed down to this length.
    var maxInternalSilence: Double = 0.6

    struct Result: Sendable {
        var samples: [Float]
        var sampleRate: Double
        var originalDuration: Double
        var trimmedDuration: Double
        var didTrim: Bool

        var removedDuration: Double { max(0, originalDuration - trimmedDuration) }
    }

    func trim(_ samples: [Float], sampleRate: Double) -> Result {
        let originalDuration = sampleRate > 0 ? Double(samples.count) / sampleRate : 0
        let frameSize = max(1, Int(sampleRate * frameDuration))

        // Too short to meaningfully analyze — return as-is.
        guard samples.count > frameSize * 3 else {
            return Result(samples: samples, sampleRate: sampleRate,
                          originalDuration: originalDuration, trimmedDuration: originalDuration, didTrim: false)
        }

        let energies = frameEnergies(samples, frameSize: frameSize)
        let peak = energies.max() ?? 0
        let floor = percentile(energies, 0.1)

        // Effectively silent throughout — nothing useful to keep, but don't
        // destroy the recording; hand back the original.
        guard peak > 1e-5, peak > floor else {
            return Result(samples: samples, sampleRate: sampleRate,
                          originalDuration: originalDuration, trimmedDuration: originalDuration, didTrim: false)
        }

        let thresholdFraction = 0.04 + sensitivity * 0.16
        let threshold = floor + (peak - floor) * Float(thresholdFraction)

        var voiced = energies.map { $0 >= threshold }
        applyHangover(&voiced, frames: max(0, Int((hangover / frameDuration).rounded())))

        let keptMask = collapseInternalSilence(voiced, frameSize: frameSize, sampleRate: sampleRate)

        // Assemble kept samples.
        var output: [Float] = []
        output.reserveCapacity(samples.count)
        for (frameIndex, keep) in keptMask.enumerated() where keep {
            let start = frameIndex * frameSize
            let end = min(start + frameSize, samples.count)
            if start < end {
                output.append(contentsOf: samples[start..<end])
            }
        }

        // Safety: never return empty — fall back to the original.
        guard !output.isEmpty else {
            return Result(samples: samples, sampleRate: sampleRate,
                          originalDuration: originalDuration, trimmedDuration: originalDuration, didTrim: false)
        }

        let trimmedDuration = Double(output.count) / sampleRate
        let didTrim = output.count < samples.count
        return Result(samples: output, sampleRate: sampleRate,
                      originalDuration: originalDuration, trimmedDuration: trimmedDuration, didTrim: didTrim)
    }

    // MARK: - Internals

    private func frameEnergies(_ samples: [Float], frameSize: Int) -> [Float] {
        let frameCount = samples.count / frameSize
        var energies = [Float](repeating: 0, count: frameCount)
        samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            for frame in 0..<frameCount {
                var rms: Float = 0
                vDSP_rmsqv(base + frame * frameSize, 1, &rms, vDSP_Length(frameSize))
                energies[frame] = rms
            }
        }
        return energies
    }

    private func percentile(_ values: [Float], _ p: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * p)))
        return sorted[index]
    }

    private func applyHangover(_ voiced: inout [Bool], frames: Int) {
        guard frames > 0 else { return }
        let original = voiced
        for index in original.indices where original[index] {
            let lower = max(0, index - frames)
            let upper = min(voiced.count - 1, index + frames)
            for j in lower...upper { voiced[j] = true }
        }
    }

    /// Keeps all voiced frames, trims leading/trailing silence entirely, and
    /// caps internal silent runs at `maxInternalSilence`.
    private func collapseInternalSilence(_ voiced: [Bool], frameSize: Int, sampleRate: Double) -> [Bool] {
        guard let first = voiced.firstIndex(of: true),
              let last = voiced.lastIndex(of: true) else {
            return voiced
        }

        let maxSilentFrames = max(1, Int((maxInternalSilence / frameDuration).rounded()))
        var kept = [Bool](repeating: false, count: voiced.count)

        var index = first
        while index <= last {
            if voiced[index] {
                kept[index] = true
                index += 1
            } else {
                // Run of silence between two voiced regions: keep up to the cap.
                var runEnd = index
                while runEnd <= last, !voiced[runEnd] { runEnd += 1 }
                let runLength = runEnd - index
                let keepCount = min(runLength, maxSilentFrames)
                for j in index..<(index + keepCount) { kept[j] = true }
                index = runEnd
            }
        }
        return kept
    }
}
