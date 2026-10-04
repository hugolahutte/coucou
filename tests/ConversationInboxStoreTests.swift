import Foundation

// Standalone tests use only the store's default-path dependency as a stub.
enum HookServer { static var supportDir: URL { FileManager.default.temporaryDirectory } }

@main
struct StoreTests {
    @MainActor
    static func main() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("coucou-store-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("inbox.json")
        let store = ConversationInboxStore(url: url)
        precondition(store.change { inbox in
            _ = try inbox.conversation(space: .claudeCobra, title: "Cobra", externalID: "manual:cobra")
        })
        let saved = store.inbox
        precondition(ConversationInboxStore(url: url).inbox == saved)
        // Replacing the parent with a regular file simulates a persistent write failure.
        try FileManager.default.removeItem(at: dir)
        try Data("blocked".utf8).write(to: dir)
        precondition(!store.change { inbox in
            _ = try inbox.conversation(space: .claudeHL, title: "HL", externalID: "manual:hl")
        })
        precondition(store.inbox == saved, "A failed save must not commit an in-memory change")
        precondition(store.errorMessage != nil)
        try FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: url)
        let corruptStore = ConversationInboxStore(url: url)
        precondition(!corruptStore.change { $0 = ConversationInbox() })
        let preserved = try String(contentsOf: url, encoding: .utf8)
        precondition(preserved == "broken", "An unreadable snapshot must never be overwritten")
        print("Inbox store: restart, failed-save rollback and corrupt-data preservation passed")
    }
}
