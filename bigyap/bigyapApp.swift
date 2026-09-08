//
//  bigyapApp.swift
//  bigyap
//
//  Created by James on 22/4/2026.
//

import SwiftUI
import SwiftData

@main
struct BigYapApp: App {
    @State private var settings = AppSettings()
    #if os(macOS)
    @State private var hotKeyController: HotKeyDictationController?
    #endif

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TranscriptEntry.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // A corrupt store or failed migration must not take down the whole
            // app at launch. Fall back to an in-memory store so recording and
            // transcription keep working; history just won't persist this run.
            let memoryOnly = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [memoryOnly])
            } catch {
                fatalError("Could not create even an in-memory ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                #if os(macOS)
                .environment(hotKeyController)
                .task {
                    // Built here rather than in an initialiser so it shares the
                    // same AppSettings and model container the UI is using —
                    // a hot-key take must land in the same history.
                    guard hotKeyController == nil else { return }
                    let controller = HotKeyDictationController(
                        settings: settings,
                        container: sharedModelContainer
                    )
                    if settings.globalHotKeyEnabled { controller.register() }
                    hotKeyController = controller
                }
                #endif
                #if DEBUG
                .task { seedSampleTranscriptIfRequested() }
                #endif
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        // The layout is a single phone-shaped column, so give the Mac window a
        // sensible portrait default and stop it being stretched into a shape
        // the design was never drawn for.
        .defaultSize(width: 420, height: 720)
        .windowResizability(.contentMinSize)
        .commands {
            // A single-window utility has no use for New Window, and leaving it
            // in would open a second window sharing one recorder.
            CommandGroup(replacing: .newItem) {}
        }
        #endif
    }

    #if DEBUG
    /// Speech transcription doesn't run in the Simulator, so UI verification of
    /// history features needs a way to get an entry into the store. Launching
    /// with `-seedSampleTranscript` inserts one sample row if history is empty.
    private func seedSampleTranscriptIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleTranscript") else { return }
        let context = sharedModelContainer.mainContext
        let count = (try? context.fetchCount(FetchDescriptor<TranscriptEntry>())) ?? 0
        guard count == 0 else { return }
        context.insert(TranscriptEntry(text: "This is a seeded sample transcript for simulator testing.", duration: 3))
        try? context.save()
    }
    #endif
}
