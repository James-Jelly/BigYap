import Foundation

/// The last mile between a raw transcription and text worth handing to the
/// user: vocabulary correction, filler removal, tidy-up, and the trailing
/// space. Extracted from `RecordView` so the macOS global-hot-key path applies
/// exactly the same rules — two copies of these settings would drift the first
/// time one of them changed.
///
/// Deliberately dependency-free and `Sendable`, like the rest of the pure
/// pipeline (`TranscriptProcessor`, `FuzzyMatcher`, `VoiceActivityTrimmer`).
struct TranscriptFinalizer: Sendable {
    var vocabulary: [String]
    var fillerWords: [String]
    var correctVocabulary: Bool
    var removeFillers: Bool
    var paragraphPerSentence: Bool
    var appendTrailingSpace: Bool

    @MainActor
    init(settings: AppSettings) {
        vocabulary = settings.customVocabulary
        fillerWords = settings.fillerWords
        correctVocabulary = settings.correctWithVocabulary
        removeFillers = settings.removeFillerWords
        paragraphPerSentence = settings.paragraphPerSentence
        appendTrailingSpace = settings.appendTrailingSpace
    }

    /// Returns the finished text, or `nil` when nothing survived processing —
    /// which the callers treat as "no speech was detected" rather than saving
    /// an empty history row.
    func finalize(_ raw: String) -> String? {
        let processor = TranscriptProcessor(
            vocabulary: vocabulary,
            fillerWords: fillerWords,
            correctVocabulary: correctVocabulary,
            removeFillers: removeFillers,
            paragraphPerSentence: paragraphPerSentence
        )
        let trimmed = processor.process(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard appendTrailingSpace, !trimmed.hasSuffix(" ") else { return trimmed }
        return trimmed + " "
    }
}
