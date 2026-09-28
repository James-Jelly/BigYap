import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let copyToClipboard = "copyToClipboard"
        static let appendTrailingSpace = "appendTrailingSpace"
        static let paragraphPerSentence = "paragraphPerSentence"
        static let trimSilence = "trimSilence"
        static let removeFillerWords = "removeFillerWords"
        static let correctWithVocabulary = "correctWithVocabulary"
        static let customVocabulary = "customVocabulary"
        static let fillerWords = "fillerWords"
        static let hasSeenPermissionPrimer = "hasSeenPermissionPrimer"
        static let globalHotKeyEnabled = "globalHotKeyEnabled"
        static let hasSeenAccessibilityPrimer = "hasSeenAccessibilityPrimer"
        static let hotKeyKeyCode = "hotKeyKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyLabel = "hotKeyLabel"
        static let pausePlaybackWhileRecording = "pausePlaybackWhileRecording"
    }

    /// A conservative default filler list. Words people rarely mean to keep —
    /// deliberately excludes ambiguous ones like "like"/"actually" so the user
    /// opts those in themselves.
    static let defaultFillerWords = ["um", "uh", "umm", "uhh", "erm", "er", "ah", "hmm", "mm"]

    // MARK: Output
    var copyToClipboard: Bool {
        didSet { defaults.set(copyToClipboard, forKey: Key.copyToClipboard) }
    }

    var appendTrailingSpace: Bool {
        didSet { defaults.set(appendTrailingSpace, forKey: Key.appendTrailingSpace) }
    }

    /// Break each sentence onto its own line (blank line between) so the
    /// transcript pastes into a chat already formatted.
    var paragraphPerSentence: Bool {
        didSet { defaults.set(paragraphPerSentence, forKey: Key.paragraphPerSentence) }
    }

    // MARK: Transcription cleanup
    /// Trim silence from the recording before transcription (native VAD).
    var trimSilence: Bool {
        didSet { defaults.set(trimSilence, forKey: Key.trimSilence) }
    }

    /// Strip filler words ("um", "uh", …) from the transcript.
    var removeFillerWords: Bool {
        didSet { defaults.set(removeFillerWords, forKey: Key.removeFillerWords) }
    }

    /// Apply custom-vocabulary fuzzy correction to the transcript.
    var correctWithVocabulary: Bool {
        didSet { defaults.set(correctWithVocabulary, forKey: Key.correctWithVocabulary) }
    }

    /// Names / jargon the user wants recognized and corrected.
    var customVocabulary: [String] {
        didSet { defaults.set(customVocabulary, forKey: Key.customVocabulary) }
    }

    /// The user-editable filler list applied when `removeFillerWords` is on.
    var fillerWords: [String] {
        didSet { defaults.set(fillerWords, forKey: Key.fillerWords) }
    }

    /// Whether the first-run explainer (shown before the system microphone
    /// prompt) has been dismissed. Recording auto-starts only after this.
    var hasSeenPermissionPrimer: Bool {
        didSet { defaults.set(hasSeenPermissionPrimer, forKey: Key.hasSeenPermissionPrimer) }
    }

    /// macOS only: whether the dictation hot key starts and stops a take from
    /// anywhere in the system. Ignored on iOS, where there is no such concept.
    var globalHotKeyEnabled: Bool {
        didSet { defaults.set(globalHotKeyEnabled, forKey: Key.globalHotKeyEnabled) }
    }

    /// macOS only: pause whatever is playing (Music, Spotify, a browser tab)
    /// for the length of a take and resume it afterwards. Needs Accessibility,
    /// like pasting. Ignored on iOS, where the audio session ducks instead.
    var pausePlaybackWhileRecording: Bool {
        didSet { defaults.set(pausePlaybackWhileRecording, forKey: Key.pausePlaybackWhileRecording) }
    }

    /// macOS only: whether the Accessibility explainer has been shown once.
    /// Only gates the automatic appearance — Settings can always reopen it.
    var hasSeenAccessibilityPrimer: Bool {
        didSet { defaults.set(hasSeenAccessibilityPrimer, forKey: Key.hasSeenAccessibilityPrimer) }
    }

    #if os(macOS)
    /// The key combination for system-wide dictation. Stored as its three
    /// parts because `RegisterEventHotKey` wants the code and mask, and the
    /// label is captured rather than derived (see `DictationShortcut`).
    var dictationShortcut: DictationShortcut {
        didSet {
            defaults.set(Int(dictationShortcut.keyCode), forKey: Key.hotKeyKeyCode)
            defaults.set(Int(dictationShortcut.carbonModifiers), forKey: Key.hotKeyModifiers)
            defaults.set(dictationShortcut.label, forKey: Key.hotKeyLabel)
        }
    }
    #endif

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        copyToClipboard = defaults.object(forKey: Key.copyToClipboard) as? Bool ?? true
        appendTrailingSpace = defaults.object(forKey: Key.appendTrailingSpace) as? Bool ?? true
        paragraphPerSentence = defaults.object(forKey: Key.paragraphPerSentence) as? Bool ?? true
        trimSilence = defaults.object(forKey: Key.trimSilence) as? Bool ?? true
        removeFillerWords = defaults.object(forKey: Key.removeFillerWords) as? Bool ?? false
        correctWithVocabulary = defaults.object(forKey: Key.correctWithVocabulary) as? Bool ?? true
        customVocabulary = defaults.stringArray(forKey: Key.customVocabulary) ?? []
        fillerWords = defaults.stringArray(forKey: Key.fillerWords) ?? AppSettings.defaultFillerWords
        hasSeenPermissionPrimer = defaults.bool(forKey: Key.hasSeenPermissionPrimer)
        globalHotKeyEnabled = defaults.object(forKey: Key.globalHotKeyEnabled) as? Bool ?? true
        hasSeenAccessibilityPrimer = defaults.bool(forKey: Key.hasSeenAccessibilityPrimer)
        pausePlaybackWhileRecording = defaults.object(forKey: Key.pausePlaybackWhileRecording) as? Bool ?? true
        #if os(macOS)
        // All three parts must be present, or the stored shortcut is
        // incoherent and the default is safer than a half-read one.
        if let code = defaults.object(forKey: Key.hotKeyKeyCode) as? Int,
           let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int,
           let label = defaults.string(forKey: Key.hotKeyLabel) {
            dictationShortcut = DictationShortcut(
                keyCode: UInt32(code),
                carbonModifiers: UInt32(modifiers),
                label: label
            )
        } else {
            dictationShortcut = .default
        }
        #endif
    }
}
