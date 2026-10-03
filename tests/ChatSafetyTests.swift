import Foundation

@main
struct ChatSafetyTests {
    static func check(_ condition: Bool) throws { precondition(condition) }
    static func main() throws {
        let content: [[String: Any]] = [
            ["type": "text", "text": "I’ll search"],
            ["type": "server_tool_use", "name": "web_search"],
            ["type": "text", "text": "Here is the actual answer"],
        ]
        precondition(ChatSafety.text(from: content) == "I’ll search\n\nHere is the actual answer")
        precondition(ChatSafety.text(from: [["type": "tool_use"]]) == "")
        precondition(ChatSafety.approvalTarget(tool: "Edit", input: ["file_path": "/project/.env"]) == "Edit · /project/.env")
        precondition(ChatSafety.approvalTarget(tool: "WebFetch", input: ["url": "https://example.com"]) == "WebFetch · https://example.com")
        precondition(ChatSafety.approvalTarget(tool: "Bash", input: ["command": "echo hi"]) == "Bash · echo hi")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("coucou-attachment-tests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("note.txt")
        try Data("first".utf8).write(to: source)
        let first = try ChatSafety.copyAttachment(source, to: dir.appendingPathComponent("inbox"))
        try Data("second".utf8).write(to: source)
        let second = try ChatSafety.copyAttachment(source, to: dir.appendingPathComponent("inbox"))
        precondition(first != second)
        try check(String(contentsOf: first, encoding: .utf8) == "first")
        try check(String(contentsOf: second, encoding: .utf8) == "second")
        print("Chat safety: complete responses, approval targets and distinct attachments passed")
    }
}
