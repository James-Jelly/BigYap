import Foundation

/// Decides whether a manual transcript edit should be persisted. Shared by the
/// Record tab's "Latest" card and the history detail view so both apply the
/// same rules: no-op when nothing changed, and never save a transcript down to
/// whitespace (the previous text is kept instead).
nonisolated enum TranscriptEditPolicy {
    /// Returns the text to persist, or `nil` when the edit should be discarded
    /// (unchanged, or cleared to whitespace-only).
    static func committedText(edited: String, previous: String) -> String? {
        guard edited != previous else { return nil }
        guard !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return edited
    }
}
