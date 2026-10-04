import Foundation
import Combine

extension Notification.Name {
    static let conversationInboxChanged = Notification.Name("conversationInboxChanged")
}

@MainActor
final class ConversationInboxStore: ObservableObject {
    static let shared = ConversationInboxStore()
    @Published private(set) var inbox = ConversationInbox()
    @Published var requestedConversation: UUID?
    @Published var requestedSpace: ConversationSpace?
    @Published var errorMessage: String?
    private let persistence: InboxPersistence
    private var loadFailed = false

    init(url: URL = HookServer.supportDir.appendingPathComponent("conversation-inbox.json")) {
        persistence = InboxPersistence(url: url)
        do { inbox = try persistence.load() }
        catch {
            loadFailed = true
            errorMessage = "Impossible de lire la liste existante. Elle a été conservée : \(error.localizedDescription)"
        }
    }

    @discardableResult
    func change(_ edit: (inout ConversationInbox) throws -> Void) -> Bool {
        // Do not overwrite an unreadable snapshot with a new empty list.
        guard !loadFailed else { return false }
        do {
            var next = inbox
            try edit(&next)
            guard next != inbox else { return true }
            try persistence.save(next)
            inbox = next
            NotificationCenter.default.post(name: .conversationInboxChanged, object: nil)
            errorMessage = nil
            return true
        } catch { errorMessage = error.localizedDescription; return false }
    }

    func receive(_ payload: [String: Any]) -> Bool {
        change { _ = try $0.receiveBrowserEvent(payload) }
    }
}
