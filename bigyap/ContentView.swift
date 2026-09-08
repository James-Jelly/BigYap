import SwiftData
import SwiftUI

struct ContentView: View {
    private enum Tab: Hashable {
        case record
        case history
        case settings
    }

    @State private var selectedTab = Tab.record
    #if os(macOS)
    @Environment(AppSettings.self) private var settings
    @State private var showAccessibilityPrimer = false
    #endif

    var body: some View {
        TabView(selection: $selectedTab) {
            RecordView()
                .tabItem {
                    Label("Record", systemImage: "mic.fill")
                }
                .tag(Tab.record)

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(Tab.history)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .tint(Brand.blush)
        #if os(macOS)
        .sheet(isPresented: $showAccessibilityPrimer) {
            AccessibilityPrimerView {
                settings.hasSeenAccessibilityPrimer = true
                showAccessibilityPrimer = false
            }
        }
        .task {
            // Offered once, and only when it would actually change something:
            // the hot key is on, and pasting isn't possible yet. Sequenced
            // after the microphone primer so the user isn't handed two
            // permission screens at once on a first launch.
            guard settings.globalHotKeyEnabled,
                  settings.hasSeenPermissionPrimer,
                  !settings.hasSeenAccessibilityPrimer,
                  !SystemTextInjector.canInjectKeystrokes else { return }
            showAccessibilityPrimer = true
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environment(AppSettings())
        .modelContainer(for: TranscriptEntry.self, inMemory: true)
}
