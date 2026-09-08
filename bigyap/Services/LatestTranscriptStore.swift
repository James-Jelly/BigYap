import Foundation

/// Stores the most recent transcript text so the "Copy Latest" App Shortcut /
/// Siri command can reach it. Local to the app — standard UserDefaults, no
/// app group, no sharing with any extension.
struct LatestTranscriptStore {
    private enum Key {
        static let latestText = "latestTranscriptText"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ text: String) {
        defaults.set(text, forKey: Key.latestText)
    }

    func load() -> String? {
        let text = defaults.string(forKey: Key.latestText)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty == false) ? text : nil
    }
}
