import Foundation

enum ChatSafety {
    static func text(from content: [[String: Any]]) -> String {
        content.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func approvalTarget(tool: String, input: [String: Any]) -> String {
        for field in ["command", "file_path", "path", "url", "query", "pattern", "prompt"] {
            if let value = input[field] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "\(tool) · \(value)"
            }
        }
        return tool
    }

    /// Unique destinations preserve old attachments and survive simultaneous drops.
    static func copyAttachment(_ source: URL, to inbox: URL) throws -> URL {
        let dir = inbox.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let destination = dir.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        } catch { try? FileManager.default.removeItem(at: dir); throw error }
    }
}
