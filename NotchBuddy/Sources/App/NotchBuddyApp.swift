import SwiftUI
import AppKit

@main
struct NotchBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Mes réponses à traiter…") {
                    NotificationCenter.default.post(name: .openConversationInbox, object: nil)
                }.keyboardShortcut("i", modifiers: .command)
            }
        }
    }
}
