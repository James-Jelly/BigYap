import Foundation
import SwiftData

nonisolated enum TranscriptSource {
    static let mainApp = "main_app"
    static let appleSpeechTranscriber = "apple_speech_transcriber"
    static let keyboard = "keyboard"

    // Legacy sources kept so old history entries still display correctly.
    // The engines were removed; see docs/MOONSHINE_ARCHIVE.md.
    static let moonshineBase = "moonshine_base"
    static let moonshineFullPrecision = "moonshine_base_full_precision"
    static let fallback = "apple_on_device_fallback"
}

@Model
final class TranscriptEntry {
    var text: String
    var createdAt: Date
    var duration: TimeInterval
    var source: String
    var copiedToClipboard: Bool
    var favorite: Bool

    init(
        text: String,
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        source: String = TranscriptSource.mainApp,
        copiedToClipboard: Bool = false,
        favorite: Bool = false
    ) {
        self.text = text
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
        self.copiedToClipboard = copiedToClipboard
        self.favorite = favorite
    }
}
