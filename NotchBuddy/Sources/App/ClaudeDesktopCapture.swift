import Foundation

/// A bounded, read-only accessibility snapshot. Kept independent of AppKit for fixtures.
struct ClaudeAXNode: Sendable {
    var role: String
    var label: String = ""
    var value: String = ""
    var url: String = ""
    var children: [ClaudeAXNode] = []
}

struct ClaudeDesktopReply: Equatable, Sendable {
    var url: URL
    var title: String
    var messageKey: String
    var text: String
    var isComplete: Bool
}

enum ClaudeDesktopParser {
    static func conversationURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme == "https", url.host == "claude.ai",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              var canonical = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let prefixes = ["/chat/", "/epitaxy/", "/cowork/"]
        guard prefixes.contains(where: { url.path.hasPrefix($0) && url.path.count > $0.count }) else { return nil }
        canonical.query = nil; canonical.fragment = nil
        return canonical.url
    }

    static func parse(_ root: ClaudeAXNode) -> ClaudeDesktopReply? {
        var webAreas: [ClaudeAXNode] = []
        func findAreas(_ node: ClaudeAXNode) {
            if node.role == "AXWebArea", conversationURL(node.url) != nil { webAreas.append(node); return }
            for child in node.children { findAreas(child) }
        }
        findAreas(root)
        // A split view must not accidentally merge two conversations.
        guard webAreas.count == 1, let area = webAreas.first, let url = conversationURL(area.url) else { return nil }
        var flat: [(node: ClaudeAXNode, message: String)] = []
        func flatten(_ node: ClaudeAXNode, message: String, isRoot: Bool = false) {
            if node.role == "AXWebArea" && !isRoot { return }
            let own = node.label
            let next = own.range(of: #"^Message \d+$"#, options: .regularExpression) != nil ? own : message
            flat.append((node, next))
            for child in node.children { flatten(child, message: next) }
        }
        flatten(area, message: "", isRoot: true)
        func assistant(_ label: String) -> Bool {
            ["Claude a répondu :", "Claude responded:", "Claude said:"].contains { label.hasPrefix($0) }
        }
        func user(_ label: String) -> Bool {
            ["Vous avez dit :", "You said:"].contains { label.hasPrefix($0) }
        }
        // The explicit speaker heading is required; arbitrary text isn't a reply.
        guard let start = flat.lastIndex(where: { $0.node.role == "AXHeading" && assistant($0.node.label) }) else { return nil }
        let busy = flat.contains { item in
            let n = item.node
            return (n.role == "AXButton" && ["Arrêter", "Stop", "Stop response", "Stop generating"].contains(n.label))
                || (n.role == "AXStaticText" && ["Claude répond.", "Claude is responding", "Réflexion en cours", "Thinking…"].contains(n.value.isEmpty ? n.label : n.value))
        }
        var lines: [String] = []
        var complete = false
        for item in flat[(start + 1)...] {
            let n = item.node
            if n.role == "AXHeading" && (user(n.label) || assistant(n.label)) { break }
            if (n.role == "AXToolbar" && ["Actions du message", "Message actions"].contains(n.label))
                || (n.role == "AXButton" && ["Afficher les actions du message pour Claude a répondu :", "Show message actions for Claude responded:"].contains(where: { n.label.hasPrefix($0) })) {
                complete = true; break
            }
            // The transcript ends before the composer/repository controls.
            if n.role == "AXTextArea" || n.label == "Contrôles du dépôt et des pull requests" { break }
            if n.role == "AXHeading" { continue }
            guard n.role == "AXStaticText" else { continue }
            let text = n.value.isEmpty ? n.label : n.value
            if assistant(text) { continue } // duplicate announcement below the speaker heading
            if user(text) { break }
            if text.isEmpty { continue }
            lines.append(text)
        }
        // Flattened siblings are intentional: Claude Code places the final answer outside Message N.
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 200_000 else { return nil }
        var title = area.label
        for suffix in [" - Claude Code", " - Claude"] where title.hasSuffix(suffix) { title.removeLast(suffix.count) }
        guard !title.isEmpty, title.count <= 300 else { return nil }
        // Never key by visible ordinal alone: pagination can renumber Message N.
        return ClaudeDesktopReply(url: url, title: title, messageKey: flat[start].message,
                                  text: text, isComplete: complete && !busy)
    }
}

/// Waits for multiple identical, explicitly completed snapshots. A switch or failure resets the wait.
struct ClaudeCaptureStability {
    private var previous: ClaudeDesktopReply?
    private var since = Date.distantPast
    private var observations = 0
    mutating func reset() { previous = nil; observations = 0 }
    mutating func ready(_ reply: ClaudeDesktopReply?, now: Date = Date()) -> ClaudeDesktopReply? {
        guard let reply, reply.isComplete else { reset(); return nil }
        if reply != previous { previous = reply; since = now; observations = 1; return nil }
        observations += 1
        return observations >= 3 && now.timeIntervalSince(since) >= 6 ? reply : nil
    }
}
