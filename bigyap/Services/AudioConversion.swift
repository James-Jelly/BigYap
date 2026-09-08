@preconcurrency import AVFoundation

/// Converts a single PCM buffer to `format` using `converter`, returning nil on
/// failure. `AVAudioConverter`'s pull-based input block is `@Sendable`, which
/// makes the usual `var didProvideBuffer` flag a Swift 6 data-race warning — so
/// the one-shot input state lives in a reference-typed provider instead, keeping
/// both call sites (live recording + final transcription) warning-free.
nonisolated func convertBuffer(
    _ input: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    to format: AVAudioFormat,
    terminalStatus: AVAudioConverterInputStatus = .noDataNow,
    extraFrames: AVAudioFrameCount = 8
) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / input.format.sampleRate
    let capacity = AVAudioFrameCount(max(1, Double(input.frameLength) * ratio + Double(extraFrames)))
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

    let provider = SingleBufferInput(buffer: input, terminalStatus: terminalStatus)
    var error: NSError?
    converter.convert(to: output, error: &error) { @Sendable count, status in
        provider.callback(count, status)
    }
    return error == nil ? output : nil
}

/// Feeds a single buffer exactly once, then reports the terminal status.
private nonisolated final class SingleBufferInput: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?
    private let terminalStatus: AVAudioConverterInputStatus

    init(buffer: AVAudioPCMBuffer, terminalStatus: AVAudioConverterInputStatus) {
        self.buffer = buffer
        self.terminalStatus = terminalStatus
    }

    func callback(_ count: AVAudioPacketCount, _ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        if let buffer {
            self.buffer = nil
            status.pointee = .haveData
            return buffer
        }
        status.pointee = terminalStatus
        return nil
    }
}
