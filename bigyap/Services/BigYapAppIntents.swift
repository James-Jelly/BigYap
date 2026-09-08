import AppIntents

struct CopyLatestBigYapTranscriptIntent: AppIntent {
    static var title: LocalizedStringResource { "Copy Latest BigYap Transcript" }
    static var description: IntentDescription { IntentDescription("Copies the latest BigYap transcript to the clipboard.") }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let text = LatestTranscriptStore().load() else {
            return .result(dialog: "No BigYap transcript yet.")
        }
        Clipboard.copy(text)
        return .result(dialog: "Copied the latest BigYap transcript.")
    }
}

struct BigYapShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CopyLatestBigYapTranscriptIntent(),
            phrases: [
                "Copy latest \(.applicationName)",
                "Copy my \(.applicationName) transcript"
            ],
            shortTitle: "Copy Latest",
            systemImageName: "doc.on.doc"
        )
    }
}
