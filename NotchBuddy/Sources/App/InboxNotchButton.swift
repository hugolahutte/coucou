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
        .contextMenu {
            Toggle("Afficher mes trois espaces dans la barre", isOn: Binding(get: { AppState.shared.permanentConversationBar }, set: { AppState.shared.permanentConversationBar = $0 }))
        }
    }
}

extension Notification.Name {
    static let conversationBarModeChanged = Notification.Name("conversationBarModeChanged")
}

/// These spaces stay available even when a provider is closed or capture is unavailable.
struct PermanentConversationBar: View {
    @ObservedObject var state: AppState
    @ObservedObject private var store = ConversationInboxStore.shared
    @ObservedObject private var claude = ClaudeDesktopMonitor.shared

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(ConversationSpace.allCases) { space in
                VStack(alignment: .leading, spacing: 6) {
                    Button { showInbox(space: space) } label: {
                        HStack(spacing: 5) {
                            Circle().fill(space == .chatgptMac ? Color.green : Color.orange).frame(width: 6, height: 6)
                            Text(space == .chatgptMac ? "ChatGPT Mac" : space == .claudeCobra ? "Claude Cobra" : "Claude HL · Chrome")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer(minLength: 0)
                            let count = store.inbox.replies.filter { reply in
                                reply.status == .pending && store.inbox.conversations.contains { $0.id == reply.conversationID && $0.space == space }
                            }.count
                            Text("\(count)").font(.system(size: 10, weight: .bold)).foregroundStyle(count > 0 ? Color.orange : Color.gray)
                        }
                    }.buttonStyle(.plain).help("Ouvrir les réponses à traiter")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            let chats = store.inbox.conversations.filter { $0.space == space }
                            ForEach(chats) { chat in
                                Button { showInbox(space: space, conversation: chat.id) } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chat.title).font(.system(size: 10, weight: .medium)).lineLimit(2)
                                        let pending = store.inbox.replies.filter { $0.conversationID == chat.id && $0.status == .pending }.count
                                        let drafts = store.inbox.drafts.filter { $0.conversationID == chat.id }.count
                                        if space == .claudeCobra {
                                            Text(claude.activities.first { $0.title == chat.title }?.label ?? "État à vérifier dans Claude")
                                                .font(.system(size: 9)).foregroundStyle(.gray)
                                        }
                                        Text(pending > 0 ? "\(pending) réponse(s) à traiter" : drafts > 0 ? "\(drafts) message(s) préparé(s)" : "Conversation conservée")
                                            .font(.system(size: 9)).foregroundStyle(pending > 0 ? Color.orange : Color.gray)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain).help("Lire les réponses et préparer mes messages")
                            }
                            if space == .claudeCobra {
                                ForEach(claude.rememberedActivities.filter { activity in !chats.contains { $0.title == activity.title } }, id: \.title) { activity in
                                    Button { Task { @MainActor in await claude.openActivity(title: activity.title) } } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(activity.title).font(.system(size: 10, weight: .medium)).lineLimit(2)
                                            Text(claude.activities.first { $0.title == activity.title }?.label ?? "État à vérifier dans Claude")
                                                .font(.system(size: 9)).foregroundStyle(.gray)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).help("Ouvrir dans Claude")
                                }
                            }
                            if chats.isEmpty && (space != .claudeCobra || claude.rememberedActivities.isEmpty) {
                                Text(space == .chatgptMac ? "Import de réponses disponible" : space == .claudeCobra ? "Connecter Claude Mac" : "Connecteur Chrome à vérifier")
                                    .font(.system(size: 10)).foregroundStyle(.gray)
                            }
                        }
                    }.frame(height: 100)
                    Button("Ouvrir ma liste") { showInbox(space: space) }
                        .font(.system(size: 9)).buttonStyle(.plain).foregroundStyle(Color.orange)
                }
                .padding(9).frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
            }
        }.foregroundStyle(Color.white).frame(maxWidth: .infinity)
    }

    private func showInbox(space: ConversationSpace, conversation: UUID? = nil) {
        store.requestedConversation = conversation
        store.requestedSpace = space
        NotificationCenter.default.post(name: .openConversationInbox, object: nil)
    }
}


struct CompactConversationSummary: View {
    @ObservedObject private var store = ConversationInboxStore.shared
    var body: some View {
        HStack(spacing: 5) {
            ForEach(ConversationSpace.allCases) { space in
                VStack(spacing: 1) {
                    Text(space == .chatgptMac ? "GPT" : space == .claudeCobra ? "C" : "HL")
                        .font(.system(size: 7, weight: .semibold)).foregroundStyle(.gray)
                    let count = store.inbox.replies.filter { reply in
                        reply.status == .pending && store.inbox.conversations.contains { $0.id == reply.conversationID && $0.space == space }
                    }.count
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(count > 0 ? Color.orange : Color.gray)
                }
            }
        }.frame(width: 70, height: 26).help("ChatGPT Mac · Claude Cobra · Claude HL — cliquer pour déplier")
    }
}
