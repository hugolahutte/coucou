import SwiftUI
import AppKit

/// The notch stays compact; reading and composing happen in a normal Mac window.
struct ConversationInboxView: View {
    @ObservedObject var store = ConversationInboxStore.shared
    @State private var selectedConversation: UUID?
    @State private var filter: InboxStatus = .pending
    @State private var draft = ""
    @State private var importing = false
    @State private var copiedDraft: UUID?

    private var conversations: [TrackedConversation] { store.inbox.conversations }
    private var conversation: TrackedConversation? { conversations.first { $0.id == selectedConversation } }
    private var replies: [InboxReply] {
        store.inbox.replies.filter { $0.status == filter && (selectedConversation == nil || $0.conversationID == selectedConversation) }
            .sorted { $0.receivedAt > $1.receivedAt }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mes conversations").font(.headline)
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
                Button("Toutes les conversations") { selectedConversation = nil }
                Button("Ajouter une réponse…", systemImage: "plus") { importing = true }
                Text("ChatGPT et Cobra sur Mac : importe une réponse copiée. HL dans Chrome : le connecteur peut suivre les conversations choisies.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding().frame(minWidth: 230, idealWidth: 260, maxWidth: 320)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(conversation?.title ?? "Mes réponses à traiter").font(.title2.bold())
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
        .onChange(of: selectedConversation) { _, _ in draft = ""; copiedDraft = nil }
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
