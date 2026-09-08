import AVFoundation
import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case emptyAudio
    case audioFormatUnavailable
    case bufferAllocationFailed
    case conversionFailed(String)
    case modelInstallFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyAudio:
            return "No speech audio was captured."
        case .audioFormatUnavailable:
            return "No compatible audio format is available for the speech analyzer."
        case .bufferAllocationFailed:
            return "Unable to allocate the audio buffer for analysis."
        case .conversionFailed(let reason):
            return "Audio conversion failed: \(reason)"
        case .modelInstallFailed(let reason):
            #if targetEnvironment(simulator)
            return "Apple's speech model isn't available in the iOS Simulator. Run BigYap on a real device to transcribe."
            #else
            return "Couldn't download Apple's offline speech model. Check your internet connection and free storage, then try again. (\(reason))"
            #endif
        }
    }
}

struct TranscriptionResult: Sendable {
    var text: String
    var source: String
    var duration: TimeInterval
}

/// BigYap's transcription engine: Apple's on-device SpeechTranscriber model
/// (iOS 26 SpeechAnalyzer API). Runs fully offline; the model assets are
/// system-managed and shared with apps like Notes and Voice Memos.
enum AppleSpeechTranscriberEngine {
    static let locale = Locale(identifier: "en_US")

    /// Set once the assets are confirmed installed, so later transcriptions
    /// skip the AssetInventory XPC round-trip (it added startup latency to
    /// every recording).
    private static var modelEnsured = false

    /// Downloads the system speech model assets if they aren't already on
    /// device. Safe to call repeatedly; no-op once installed.
    static func ensureModelInstalled() async throws {
        if modelEnsured { return }
        let transcriber = Speech.SpeechTranscriber(locale: locale, preset: .transcription)
        do {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            modelEnsured = true
        } catch {
            throw TranscriptionError.modelInstallFailed(error.localizedDescription)
        }
    }

    /// Best-effort warm-up for app launch.
    static func prepare() async {
        try? await ensureModelInstalled()
    }

    static func transcribe(_ audio: RecordedAudio, vocabulary: [String] = []) async throws -> TranscriptionResult {
        guard !audio.samples.isEmpty else { throw TranscriptionError.emptyAudio }
        try await ensureModelInstalled()

        let transcriber = Speech.SpeechTranscriber(locale: locale, preset: .transcription)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.audioFormatUnavailable
        }

        let sourceBuffer = try makeSourceBuffer(samples: audio.samples, sampleRate: audio.sampleRate)
        let analyzerBuffer = try convert(sourceBuffer, to: analyzerFormat)

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        if !vocabulary.isEmpty {
            let context = AnalysisContext()
            context.contextualStrings = [.general: vocabulary]
            // Biasing is best-effort: a failure here should never block transcription.
            try? await analyzer.setContext(context)
        }

        let collector = Task {
            var text = ""
            for try await result in transcriber.results {
                if result.isFinal {
                    text += String(result.text.characters)
                }
            }
            return text
        }

        inputBuilder.yield(AnalyzerInput(buffer: analyzerBuffer))
        inputBuilder.finish()

        let lastSampleTime = try await analyzer.analyzeSequence(inputSequence)
        if let lastSampleTime {
            try await analyzer.finalizeAndFinish(through: lastSampleTime)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let text = try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
        return TranscriptionResult(
            text: text,
            source: TranscriptSource.appleSpeechTranscriber,
            duration: audio.duration
        )
    }

    /// Wraps raw mono Float32 samples in a PCM buffer. Also used by
    /// `LiveTranscriptionSession` to package streaming chunks.
    static func makeSourceBuffer(samples: [Float], sampleRate: Double) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TranscriptionError.bufferAllocationFailed
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        if buffer.format == format {
            return buffer
        }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            throw TranscriptionError.conversionFailed("No converter for \(format)")
        }
        guard let converted = convertBuffer(buffer, using: converter, to: format, terminalStatus: .endOfStream, extraFrames: 32) else {
            throw TranscriptionError.conversionFailed("The audio converter produced no output.")
        }
        return converted
    }
}
