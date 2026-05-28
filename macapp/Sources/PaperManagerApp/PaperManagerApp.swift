import SwiftUI

@main
struct PaperManagerApp: App {
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        WindowGroup("PaperManager") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 900, minHeight: 560)
                .task {
                    await store.rescan()
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add paper…") {
                    NotificationCenter.default.post(name: .showAddSheet, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Refresh library") {
                    NotificationCenter.default.post(name: .refreshLibrary, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Link("Open repo README",
                     destination: URL(string: "https://github.com/abhiramm7")!)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 520, height: 320)
        }
    }
}

extension Notification.Name {
    static let showAddSheet = Notification.Name("PaperManager.showAddSheet")
    static let refreshLibrary = Notification.Name("PaperManager.refreshLibrary")
}
