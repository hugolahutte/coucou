import SwiftUI

extension Notification.Name {
    static let openConversationInbox = Notification.Name("openConversationInbox")
}

struct InboxNotchButton: View {
    @ObservedObject private var store = ConversationInboxStore.shared
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openConversationInbox, object: nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tray.full")
                if store.inbox.pendingCount > 0 { Text("\(store.inbox.pendingCount)").font(.system(size: 10, weight: .semibold)) }
            }.font(.system(size: 13)).foregroundColor(Color(hex: "#B0B5BE"))
        }.buttonStyle(.plain).help("Mes réponses à traiter")
    }
}
