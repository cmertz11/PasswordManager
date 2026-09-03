import SwiftUI

@main
@MainActor
struct PasswordManagerApp: App {
    @State private var store = VaultStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .frame(minWidth: 340, minHeight: 440)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Lock Vault") {
                    store.lock()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .disabled(store.mode != .unlocked)
            }
        }
    }
}
