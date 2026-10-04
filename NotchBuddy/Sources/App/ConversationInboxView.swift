import SwiftUI
import AppKit

/// The notch stays compact; reading and composing happen in a normal Mac window.
struct ConversationInboxView: View {
    @ObservedObject var store = ConversationInboxStore.shared
    @ObservedObject private var appState = AppState.shared
    @State private var selectedConversation: UUID?
    @State private var selectedSpace: ConversationSpace?
    @State private var filter: InboxStatus = .pending
    @State private var draft = ""
    @State private var importing = false
    @State private var connectingClaude = false
    @State private var copiedDraft: UUID?

    private var conversations: [TrackedConversation] { store.inbox.conversations }
    private var conversation: TrackedConversation? { conversations.first { $0.id == selectedConversation } }
    private var replies: [InboxReply] {
        store.inbox.replies.filter { reply in
            reply.status == filter && (selectedConversation == nil || reply.conversationID == selectedConversation)
                && (selectedSpace == nil || conversations.contains { $0.id == reply.conversationID && $0.space == selectedSpace })
        }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mes conversations").font(.headline)
                Toggle("Afficher mes trois espaces dans la barre", isOn: $appState.permanentConversationBar)
                List(selection: $selectedConversation) {
                    ForEach(ConversationSpace.allCases) { space in
                        Section(space.label) {
                            ForEach(conversations.filter { $0.space == space }) { chat in
                                HStack {
                                    Text(chat.title).lineLimit(2)
                                    Spacer()
                                    let count = store.inbox.replies.filter { $0.conversationID == chat.id && $0.status == .pending }.count
                                    if count > 0 { Text("\(count)").foregroundStyle(.orange) }
                                }.tag(chat.id)
                            }
                        }
                    }
                }
                Button("Toutes les conversations") { selectedConversation = nil; selectedSpace = nil }
                Button("Ajouter une réponse…", systemImage: "plus") { importing = true }
                Button("Connecter Claude Mac…", systemImage: "link") { connectingClaude = true }
                Text("Claude Mac : suivi des conversations choisies. ChatGPT Mac : import d’une réponse copiée. HL : connecteur Chrome.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding().frame(minWidth: 230, idealWidth: 260, maxWidth: 320)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(conversation?.title ?? selectedSpace?.label ?? "Mes réponses à traiter").font(.title2.bold())
                    Spacer()
                    if let conversation { Button(conversation.url == nil ? "Ouvrir l’application" : "Ouvrir le chat") { open(conversation) } }
                }
                Picker("Afficher", selection: $filter) {
                    ForEach(InboxStatus.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(.red).textSelection(.enabled)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if replies.isEmpty {
                            ContentUnavailableView("Aucune réponse ici", systemImage: "tray",
                                                   description: Text("Les réponses restent dans la liste jusqu’à ce que tu les marques comme traitées."))
                        }
                        ForEach(replies) { reply in
                            VStack(alignment: .leading, spacing: 10) {
                                if let chat = conversations.first(where: { $0.id == reply.conversationID }) {
                                    Text("\(chat.space.label) · \(chat.title)").font(.headline)
                                }
                                Text(reply.receivedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                                Text(reply.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                HStack {
                                    if filter != .done { statusButton("Traité", reply, .done) }
                                    if filter != .deferred { statusButton("Plus tard", reply, .deferred) }
                                    if filter != .pending { statusButton("À traiter", reply, .pending) }
                                }
                            }.padding().background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                if let conversation {
                    Divider()
                    Text("Mes prochains messages").font(.headline)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.inbox.drafts.filter { $0.conversationID == conversation.id }) { item in
                                HStack(alignment: .top) {
                                    Text(item.text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    Button(copiedDraft == item.id ? "Copié" : "Copier") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.text, forType: .string)
                                        copiedDraft = item.id
                                    }
                                    Button("Retirer") { _ = store.change { $0.drafts.removeAll { $0.id == item.id } } }
                                }.padding(8)
                            }
                        }
                    }.frame(maxHeight: 120)
                    TextEditor(text: $draft).frame(height: 65).border(.secondary.opacity(0.3))
                    HStack {
                        Button("Garder ce message") {
                            if store.change({ try $0.addDraft(conversationID: conversation.id, text: draft) }) { draft = "" }
                        }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Text("Copie le brouillon puis envoie-le dans le chat d’origine.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.padding().frame(minWidth: 450)
        }
        .frame(minWidth: 760, minHeight: 540)
        .sheet(isPresented: $importing) { ImportConversationReplyView(store: store, selectedConversation: $selectedConversation) }
        .sheet(isPresented: $connectingClaude) { ClaudeDesktopConnectionView() }
        .onChange(of: selectedConversation) { _, id in
            draft = ""; copiedDraft = nil
            if let id { selectedSpace = conversations.first { $0.id == id }?.space }
        }
        .onReceive(store.$requestedSpace) { space in
            if let space { selectedSpace = space; selectedConversation = store.requestedConversation; filter = .pending }
        }
        .onAppear {
            if let space = store.requestedSpace { selectedSpace = space; selectedConversation = store.requestedConversation }
        }
    }

    private func statusButton(_ title: String, _ reply: InboxReply, _ status: InboxStatus) -> some View {
        Button(title) { _ = store.change { inbox in
            if let index = inbox.replies.firstIndex(where: { $0.id == reply.id }) { inbox.replies[index].status = status }
        } }
    }

    private func open(_ chat: TrackedConversation) {
        if let url = chat.url, chat.space.accepts(url: url) {
            if chat.space == .claudeHL, let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
                NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
            } else if chat.space == .claudeCobra, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
                NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } else { NSWorkspace.shared.open(url) }
        } else {
            let bundles = chat.space == .chatgptMac ? ["com.openai.chat", "com.openai.codex"] : ["com.anthropic.claudefordesktop"]
            if let app = bundles.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
                NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            } else { store.errorMessage = "Application introuvable. Ouvre le chat depuis son application." }
        }
    }
}

private struct ImportConversationReplyView: View {
    @ObservedObject var store: ConversationInboxStore
    @Binding var selectedConversation: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var space: ConversationSpace = .chatgptMac
    @State private var existingID: UUID?
    @State private var title = ""
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ajouter une réponse à traiter").font(.title2.bold())
            Picker("Espace", selection: $space) { ForEach(ConversationSpace.allCases) { Text($0.label).tag($0) } }
            Picker("Conversation", selection: $existingID) {
                Text("Nouvelle conversation").tag(Optional<UUID>.none)
                ForEach(store.inbox.conversations.filter { $0.space == space }) { Text($0.title).tag(Optional($0.id)) }
            }
            if existingID == nil { TextField("Titre de la conversation", text: $title) }
            Button("Coller la réponse copiée") { text = NSPasteboard.general.string(forType: .string) ?? "" }
            TextEditor(text: $text).frame(height: 210).border(.secondary.opacity(0.3))
            if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Annuler") { dismiss() }
                Spacer()
                Button("Ajouter à ma liste") {
                    var id = existingID
                    let saved = store.change { inbox in
                        if id == nil { id = try inbox.conversation(space: space, title: title, externalID: "manual:\(UUID().uuidString)") }
                        guard let id else { throw InboxError.unknownConversation }
                        try inbox.receive(conversationID: id, messageID: UUID().uuidString, text: text)
                    }
                    if saved { selectedConversation = id; dismiss() }
                }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (existingID == nil && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            }
        }.padding(24).frame(width: 560)
            .onChange(of: space) { _, _ in existingID = nil }
    }
}


private struct ClaudeDesktopConnectionView: View {
    @ObservedObject private var monitor = ClaudeDesktopMonitor.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connecter Claude · Cobra").font(.title2.bold())
            Text("Coucou lit les réponses visibles de Claude Mac avec l’autorisation Accessibilité. Vérifie que Claude utilise ton compte Cobra. Les données restent dans la liste sur ce Mac.")
            Toggle("Activer le suivi Claude Mac", isOn: Binding(get: { monitor.enabled }, set: { monitor.setEnabled($0) }))
            if monitor.enabled {
                Button("Autoriser dans les réglages macOS…") { monitor.requestPermission() }
                Text("1. Ouvre la conversation dans Claude. 2. Reviens ici et repère-la. 3. Active son suivi puis retourne dans Claude.").font(.callout)
                Button("Repérer la conversation ouverte dans Claude") { Task { await monitor.discover() } }
                    .disabled(monitor.reading)
                if let chat = monitor.candidate {
                    Text(chat.title).font(.headline)
                    Text(chat.url.path).font(.caption).foregroundStyle(.secondary)
                    if monitor.followed.contains(chat.url.absoluteString) {
                        Button("Arrêter le suivi de cette conversation") { monitor.unfollow(chat.url.absoluteString) }
                    } else {
                        Button("Suivre cette conversation dans Claude · Cobra") { monitor.followCandidate() }
                    }
                }
            }
            Text(monitor.status).font(.callout).foregroundStyle(.secondary)
            Text("Les tâches présentes dans la barre latérale de Claude apparaissent dans l’encoche. Pour les réponses, laisse la conversation choisie au premier plan. L’historique complet et les chats cachés ne sont pas importés ; vérifie la première capture.")
                .font(.caption).foregroundStyle(.secondary)
            if !monitor.activities.isEmpty {
                Text("Claude · \(monitor.activities.count) activité(s)").font(.headline)
                ForEach(monitor.activities, id: \.title) { item in
                    Text("\(item.title) — \(item.label)").font(.caption)
                }
            }
            if !monitor.diagnostic.isEmpty {
                DisclosureGroup("Détails du diagnostic") {
                    Text(monitor.diagnostic).font(.caption).textSelection(.enabled)
                }
            }
            if !monitor.followed.isEmpty {
                Text("Conversations suivies : \(monitor.followed.count)").font(.headline)
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(monitor.followed, id: \.self) { url in
                            HStack {
                                Text(ConversationInboxStore.shared.inbox.conversations.first { $0.space == .claudeCobra && $0.url?.absoluteString == url }?.title ?? URL(string: url)?.path ?? url).lineLimit(2)
                                Spacer()
                                Button("Arrêter") { monitor.unfollow(url) }
                            }.padding(.vertical, 4)
                        }
                    }
                }.frame(maxHeight: 100)
            }
            HStack { Spacer(); Button("Fermer") { dismiss() } }
        }.padding(24).frame(width: 560)
    }
}
