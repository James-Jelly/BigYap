@preconcurrency import AVFoundation
import Foundation
import Speech

/// A live `SpeechAnalyzer` session that transcribes audio while it is still
/// being recorded. Chunks of 16 kHz samples stream in from the recorder's tap
/// via `feed(_:)`, volatile (in-progress) results drive a live preview via
/// `onUpdate`, and `finish()` returns the finalized transcript — so by the
/// time the user stops recording, most of the audio has already been analyzed
/// and the remaining wait is near zero.
///
/// Construction is the expensive part (model check, format negotiation,
/// analyzer start), so RecordView keeps a **hot standby** session built at
/// launch and re-armed after each take: pressing record then only has to start
/// the microphone. An idle session just waits on its empty input stream.
@MainActor
final class LiveTranscriptionSession {
    /// The vocabulary this session was built with, so a standby can be
    /// invalidated when the user edits their custom vocabulary.
    let vocabulary: [String]

    private let analyzer: SpeechAnalyzer
    private let chunkContinuation: AsyncStream<[Float]>.Continuation
    private let feederTask: Task<Void, Never>
    private let collectorTask: Task<String, Error>

    init(
        vocabulary: [String],
        onUpdate: @escaping @MainActor (String) -> Void
    ) async throws {
        self.vocabulary = vocabulary
        try await AppleSpeechTranscriberEngine.ensureModelInstalled()

        let transcriber = Speech.SpeechTranscriber(
            locale: AppleSpeechTranscriberEngine.locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: vocabulary]
            // Biasing is best-effort: a failure here should never block recording.
            try? await analyzer.setContext(context)
        }

        // Collect results before any audio is fed so no result can be missed.
        // Volatile text is replaced wholesale on each update until the analyzer
        // finalizes that stretch of audio, at which point it moves to `finalized`.
        collectorTask = Task {
            var finalized = ""
            var volatile = ""
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    finalized += text
                    volatile = ""
                } else {
                    volatile = text
                }
                onUpdate(finalized + volatile)
            }
            return finalized
        }

        let (chunks, chunkContinuation) = AsyncStream.makeStream(of: [Float].self)
        self.chunkContinuation = chunkContinuation

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        feederTask = Task {
            var converter: AVAudioConverter?
            for await chunk in chunks {
                guard let buffer = try? AppleSpeechTranscriberEngine.makeSourceBuffer(
                    samples: chunk,
                    sampleRate: 16_000
                ) else { continue }

                if buffer.format == analyzerFormat {
                    inputBuilder.yield(AnalyzerInput(buffer: buffer))
                } else {
                    if converter == nil {
                        converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
                    }
                    guard let converter,
                          let converted = convertBuffer(buffer, using: converter, to: analyzerFormat)
                    else { continue }
                    inputBuilder.yield(AnalyzerInput(buffer: converted))
                }
            }
            inputBuilder.finish()
        }

        try await analyzer.start(inputSequence: inputSequence)
        self.analyzer = analyzer
    }

    /// Accepts a chunk of 16 kHz mono samples. Called from the realtime audio
    /// thread — it only yields into a buffered stream, so it's cheap and safe.
    nonisolated func feed(_ chunk: [Float]) {
        chunkContinuation.yield(chunk)
    }

    /// Ends the audio stream, finalizes the analysis, and returns the complete
    /// transcript.
    func finish() async throws -> String {
        chunkContinuation.finish()
        await feederTask.value
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await collectorTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Abandons the session without producing a transcript.
    func cancel() {
        chunkContinuation.finish()
        feederTask.cancel()
        collectorTask.cancel()
        let analyzer = analyzer
        Task { await analyzer.cancelAndFinishNow() }
    }
}
