import Foundation

@main
struct ConversationInboxTests {
    static func check(_ condition: Bool, _ message: String = "Unexpected result") throws { precondition(condition, message) }
    static func main() throws {
        var inbox = ConversationInbox()
        let cobra = try inbox.conversation(space: .claudeCobra, title: "Même titre", externalID: "manual:cobra")
        let hl = try inbox.conversation(space: .claudeHL, title: "Même titre", externalID: "/chat/abc", url: URL(string: "https://claude.ai/chat/abc")!)
        precondition(cobra != hl, "Accounts with the same title must stay separate")
        try check(inbox.receive(conversationID: cobra, messageID: "1", text: "Cobra response"))
        try check(inbox.receive(conversationID: hl, messageID: "1", text: "HL response"))
        precondition(inbox.pendingCount == 2)
        inbox.replies[0].status = .done
        try check(!inbox.receive(conversationID: cobra, messageID: "1", text: "Cobra response"))
        precondition(inbox.pendingCount == 1, "A duplicate must not resurrect completed work")
        try inbox.addDraft(conversationID: cobra, text: "First instruction")
        try inbox.addDraft(conversationID: cobra, text: "Second instruction")
        try inbox.addDraft(conversationID: hl, text: "Different account")
        precondition(inbox.drafts.filter { $0.conversationID == cobra }.map(\.text) == ["First instruction", "Second instruction"])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("coucou-inbox-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let persistence = InboxPersistence(url: dir.appendingPathComponent("inbox.json"))
        try persistence.save(inbox)
        try check(persistence.load() == inbox, "Replies, statuses and drafts must survive restart")
        let permissions = try FileManager.default.attributesOfItem(atPath: persistence.url.path)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue == 0o600)
        var event: [String: Any] = ["coucou_kind": "conversation_response", "space": "claudeHL", "title": "HL", "conversation_id": "/chat/abc", "url": "https://claude.ai/chat/abc", "message_id": "2", "text": "New answer"]
        try check(inbox.receiveBrowserEvent(event))
        precondition(inbox.conversations.count == 2, "A new message should reuse the conversation")
        let beforeInvalid = inbox
        for url in ["https://evil.test/chat/abc", "https://claude.ai.evil.test/chat/abc", "javascript:alert(1)", "https://user:pass@claude.ai/chat/abc", "https://claude.ai:8080/chat/abc"] {
            event["url"] = url
            do { _ = try inbox.receiveBrowserEvent(event); preconditionFailure("Accepted untrusted URL") }
            catch { precondition(inbox == beforeInvalid) }
        }
        event["url"] = "https://claude.ai/chat/abc"
        event["space"] = "chatgptMac"
        do { _ = try inbox.receiveBrowserEvent(event); preconditionFailure("Mixed providers") } catch {}
        event["space"] = "claudeHL"
        event["text"] = String(repeating: "é", count: 100_001)
        do { _ = try inbox.receiveBrowserEvent(event); preconditionFailure("Accepted oversized content") } catch {}
        var future = inbox
        future.version = 2
        try persistence.save(future)
        do { _ = try persistence.load(); preconditionFailure("Loaded unsupported snapshot") } catch {}
        try Data("broken".utf8).write(to: persistence.url)
        do { _ = try persistence.load(); preconditionFailure("Silently discarded corrupt data") } catch {}
        print("Conversation inbox: account isolation, ordered drafts, persistence, deduplication and invalid inputs passed")
    }
}
