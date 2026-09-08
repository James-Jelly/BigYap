@preconcurrency import AVFoundation
import Accelerate
import Foundation
import Observation

struct RecordedAudio: Sendable {
    var samples: [Float]
    var sampleRate: Double
    var duration: TimeInterval
}

enum AudioRecorderError: LocalizedError {
    case microphoneDenied
    case missingInput
    case converterUnavailable

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is required to record speech."
        case .missingInput:
            return "No microphone input was found."
        case .converterUnavailable:
            return "Unable to prepare the 16 kHz audio converter."
        }
    }
}

/// Thread-safe sink that owns the realtime audio conversion and the growing
/// sample buffer. Everything mutable lives behind a single lock and the
/// converter/format are immutable after `init`, so the realtime audio thread
/// can call `append(_:)` while another thread reads `level` or `drain()`s —
/// with no `nonisolated(unsafe)` and no data race.
nonisolated final class AudioTapSink: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let onChunk: (@Sendable ([Float]) -> Void)?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var latestLevel: Float = 0

    init(converter: AVAudioConverter, targetFormat: AVAudioFormat, onChunk: (@Sendable ([Float]) -> Void)? = nil) {
        self.converter = converter
        self.targetFormat = targetFormat
        self.onChunk = onChunk
        samples.reserveCapacity(16_000 * 30)
    }

    /// Most recent normalized input level (0...1). Safe to read from any thread.
    var level: Float {
        lock.withLock { latestLevel }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = convertBuffer(buffer, using: converter, to: targetFormat),
              let channel = converted.floatChannelData?[0] else { return }
        let frameLength = Int(converted.frameLength)
        guard frameLength > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channel, 1, &rms, vDSP_Length(frameLength))

        let chunk = Array(UnsafeBufferPointer(start: channel, count: frameLength))
        lock.lock()
        samples.append(contentsOf: chunk)
        latestLevel = min(1, rms * 24)
        lock.unlock()
        onChunk?(chunk)
    }

    /// Returns everything captured so far and clears the buffer.
    func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        return captured
    }
}

/// Owns the `AVAudioEngine` and audio-session lifecycle off the main actor.
/// Activating an `AVAudioSession` or starting the engine on the main thread
/// risks UI hangs (and the Thread Performance Checker turns it into a crash),
/// so all of it runs on this actor's executor instead.
actor AudioEngineController {
    private let engine = AVAudioEngine()
    private let targetSampleRate: Double = 16_000

    func start(onChunk: (@Sendable ([Float]) -> Void)? = nil) throws -> AudioTapSink {
        // macOS has no `AVAudioSession`; `AVAudioEngine` reads the system
        // default input directly, so there is nothing to configure or activate.
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setPreferredSampleRate(targetSampleRate)
        try session.setActive(true)
        #endif

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else { throw AudioRecorderError.missingInput }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioRecorderError.converterUnavailable
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioRecorderError.converterUnavailable
        }

        let sink = AudioTapSink(converter: converter, targetFormat: targetFormat, onChunk: onChunk)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            sink.append(buffer)
        }

        engine.prepare()
        try engine.start()
        return sink
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        #endif
    }
}

@MainActor
@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var level: Float = 0

    /// True while *any* recorder in the process holds the input device. macOS
    /// has two ways in — the app window and the global hot key — and they must
    /// not both open the microphone, so each checks this before starting.
    private(set) static var isCapturing = false

    @ObservationIgnored private let controller = AudioEngineController()
    @ObservationIgnored private var sink: AudioTapSink?
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var levelTask: Task<Void, Never>?

    func requestPermission() async -> Bool {
        await MicPermission.request()
    }

    /// Starts capture. `onChunk` receives each converted 16 kHz sample chunk on
    /// the realtime audio thread — keep it cheap (e.g. yield into a stream).
    func start(onChunk: (@Sendable ([Float]) -> Void)? = nil) async throws {
        guard !isRecording else { return }
        let sink = try await controller.start(onChunk: onChunk)
        self.sink = sink
        startedAt = .now
        isRecording = true
        AudioRecorder.isCapturing = true
        startLevelUpdates()
    }

    func stop() async -> RecordedAudio {
        guard isRecording else {
            return RecordedAudio(samples: [], sampleRate: 16_000, duration: 0)
        }

        await controller.stop()

        isRecording = false
        AudioRecorder.isCapturing = false
        level = 0
        levelTask?.cancel()
        levelTask = nil

        let captured = sink?.drain() ?? []
        sink = nil

        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        startedAt = nil
        return RecordedAudio(samples: captured, sampleRate: 16_000, duration: duration)
    }

    /// Mirrors the sink's level onto the main actor at ~16 Hz so the audio
    /// thread never touches observable UI state.
    private func startLevelUpdates() {
        levelTask?.cancel()
        levelTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let sink = self.sink {
                    self.level = sink.level
                }
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }
}
