import Foundation

enum ConversationSpace: String, Codable, CaseIterable, Identifiable, Sendable {
    case chatgptMac, claudeCobra, claudeHL
    var id: String { rawValue }
    var label: String {
        switch self {
        case .chatgptMac: "ChatGPT · Mac"
        case .claudeCobra: "Claude · Cobra"
        case .claudeHL: "Claude · HL · Chrome"
        }
    }
    func accepts(url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443 else { return false }
        switch self {
        case .chatgptMac: return url.host == "chatgpt.com" && url.path.hasPrefix("/c/") && url.path.count > 3 && url.query == nil && url.fragment == nil
        case .claudeCobra: return url.host == "claude.ai" && ["/chat/", "/epitaxy/", "/cowork/"].contains { url.path.hasPrefix($0) && url.path.count > $0.count } && url.query == nil && url.fragment == nil
        case .claudeHL:
            let isChat = url.path.hasPrefix("/chat/") && url.path.count > 6
            let isCowork = url.path.range(of: #"^/cowork/cse_[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
            return url.host == "claude.ai" && (isChat || isCowork) && url.query == nil && url.fragment == nil
        }
    }
}

struct TrackedConversation: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var space: ConversationSpace
    var title: String
    var externalID: String
    var url: URL?
}

enum InboxStatus: String, Codable, CaseIterable, Sendable {
    case pending, deferred, done
    var label: String {
        switch self { case .pending: "À traiter"; case .deferred: "Plus tard"; case .done: "Traité" }
    }
}

struct InboxReply: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var conversationID: UUID
    var externalMessageID: String
    var text: String
    var receivedAt = Date()
    var status: InboxStatus = .pending
}

struct ConversationDraft: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var conversationID: UUID
    var text: String
    var createdAt = Date()
}

enum InboxError: LocalizedError {
    case invalidEvent, unknownConversation, unsupportedVersion
    var errorDescription: String? {
        switch self {
        case .invalidEvent: "La réponse ou son lien est invalide."
        case .unknownConversation: "Cette conversation n’existe plus."
        case .unsupportedVersion: "Cette liste vient d’une version plus récente de Coucou."
        }
    }
}

/// Shared by browser captures, manual imports and tests. No provider credentials or API calls.
struct ConversationInbox: Codable, Equatable, Sendable {
    var version = 1
    var conversations: [TrackedConversation] = []
    var replies: [InboxReply] = []
    var drafts: [ConversationDraft] = []

    var pendingCount: Int { replies.filter { $0.status == .pending }.count }

    mutating func conversation(space: ConversationSpace, title: String, externalID: String,
                               url: URL? = nil) throws -> UUID {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 300, !externalID.isEmpty, externalID.count <= 500,
              url.map({ space.accepts(url: $0) && $0.path == externalID }) ?? true else {
            throw InboxError.invalidEvent
        }
        if let index = conversations.firstIndex(where: { $0.space == space && $0.externalID == externalID }) {
            conversations[index].title = title
            if let url { conversations[index].url = url }
            return conversations[index].id
        }
        let item = TrackedConversation(space: space, title: title, externalID: externalID, url: url)
        conversations.append(item)
        return item.id
    }

    @discardableResult
    mutating func receive(conversationID: UUID, messageID: String, text: String) throws -> Bool {
        guard conversations.contains(where: { $0.id == conversationID }) else { throw InboxError.unknownConversation }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 200_000, !messageID.isEmpty, messageID.count <= 500 else {
            throw InboxError.invalidEvent
        }
        // Reopening an old tab must never resurrect a completed item.
        guard !replies.contains(where: { $0.conversationID == conversationID && $0.externalMessageID == messageID }) else {
            return false
        }
        replies.append(InboxReply(conversationID: conversationID, externalMessageID: messageID, text: text))
        return true
    }

    mutating func addDraft(conversationID: UUID, text: String) throws {
        guard conversations.contains(where: { $0.id == conversationID }) else { throw InboxError.unknownConversation }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 200_000 else { throw InboxError.invalidEvent }
        drafts.append(ConversationDraft(conversationID: conversationID, text: text))
    }

    /// Account identity is deliberately explicit: Cobra and HL must never be merged.
    mutating func receiveBrowserEvent(_ payload: [String: Any]) throws -> Bool {
        guard payload["coucou_kind"] as? String == "conversation_response",
              let raw = payload["space"] as? String, let space = ConversationSpace(rawValue: raw),
              let title = payload["title"] as? String, let externalID = payload["conversation_id"] as? String,
              let rawURL = payload["url"] as? String, let url = URL(string: rawURL),
              space.accepts(url: url), url.path == externalID,
              let messageID = payload["message_id"] as? String, let text = payload["text"] as? String else {
            throw InboxError.invalidEvent
        }
        // Validate the whole event in a copy so malformed text cannot create an empty conversation.
        var next = self
        let id = try next.conversation(space: space, title: title, externalID: externalID, url: url)
        let added = try next.receive(conversationID: id, messageID: messageID, text: text)
        self = next
        return added
    }
}

/// Private atomic snapshot. A failed save leaves the last valid snapshot intact.
struct InboxPersistence {
    let url: URL
    func load() throws -> ConversationInbox {
        guard FileManager.default.fileExists(atPath: url.path) else { return ConversationInbox() }
        let inbox = try JSONDecoder().decode(ConversationInbox.self, from: Data(contentsOf: url))
        guard inbox.version == 1 else { throw InboxError.unsupportedVersion }
        return inbox
    }
    func save(_ inbox: ConversationInbox) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let data = try JSONEncoder().encode(inbox)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
