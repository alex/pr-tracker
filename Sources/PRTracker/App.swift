import SwiftUI

@main
struct PRTrackerApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1140, height: 700)
        .commands {
            CommandGroup(replacing: .pasteboard) {
                Button("Paste PR URL") { store.handlePaste() }
                    .keyboardShortcut("v", modifiers: .command)
                Button("Copy URL") { store.copySelectedURL() }
                    .keyboardShortcut("c", modifiers: .command)
                    .disabled(store.selection == nil)
            }
            CommandGroup(after: .toolbar) {
                Button("Refresh") { Task { await store.refreshAll() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
