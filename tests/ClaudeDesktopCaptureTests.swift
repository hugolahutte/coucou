import Foundation

@main struct ClaudeDesktopCaptureTests {
    static func main() throws {
        func text(_ value: String) -> ClaudeAXNode { ClaudeAXNode(role: "AXStaticText", value: value) }
        func heading(_ label: String) -> ClaudeAXNode { ClaudeAXNode(role: "AXHeading", label: label, children: [text(label)]) }
        precondition(ClaudeDesktopParser.accessibleLabel(description: "", title: "Conversation - Claude") == "Conversation - Claude")
        precondition(ClaudeDesktopParser.accessibleLabel(description: "  ", title: nil, value: "Texte") == "Texte")
        let sidebar = ClaudeAXNode(role: "AXGroup", label: "Barre latérale", children: [
            ClaudeAXNode(role: "AXButton", label: "En cours Première tâche"),
            ClaudeAXNode(role: "AXButton", label: "En cours Première tâche"),
            ClaudeAXNode(role: "AXButton", label: "En attente de saisie Deuxième tâche"),
            ClaudeAXNode(role: "AXButton", label: "Réponse non lue Troisième tâche"),
            ClaudeAXNode(role: "AXButton", label: "Inactif Ancienne tâche")])
        let activityRoot = ClaudeAXNode(role: "AXWindow", children: [sidebar,
            ClaudeAXNode(role: "AXButton", label: "En cours Texte hors de la barre latérale")])
        let activities = ClaudeDesktopParser.activities(activityRoot)!
        precondition(activities.map(\.state) == [.working, .waiting, .unread])
        precondition(activities.count == 3)
        precondition(ClaudeDesktopParser.activities(ClaudeAXNode(role: "AXWindow")) == nil)
        precondition(ClaudeDesktopParser.activities(ClaudeAXNode(role: "AXGroup", label: "Sidebar")) == [])
        let actions = ClaudeAXNode(role: "AXToolbar", label: "Actions du message", children: [ClaudeAXNode(role: "AXButton", label: "Copier")])
        let answer = ClaudeAXNode(role: "AXGroup", label: "Message 21", children: [heading("Claude a répondu : Début"), text("Début")])
        let transcript = ClaudeAXNode(role: "AXGroup", label: "Messages de la conversation", children: [
            answer,
            ClaudeAXNode(role: "AXGroup", children: [text("Suite après les outils"), text("Conclusion"), actions]),
            ClaudeAXNode(role: "AXGroup", label: "Message 22", children: [heading("Vous avez dit : Question"), text("Question")])
        ])
        var area = ClaudeAXNode(role: "AXWebArea", label: "Session exemple - Claude Code", url: "https://claude.ai/epitaxy/local_test?artifact=demo", children: [transcript])
        var root = ClaudeAXNode(role: "AXWindow", children: [area])
        let reply = ClaudeDesktopParser.parse(root)!
        precondition(reply.text == "Début\nSuite après les outils\nConclusion", "Assistant continuation must be preserved without user text/announcement")
        precondition(reply.url.absoluteString == "https://claude.ai/epitaxy/local_test")
        precondition(reply.title == "Session exemple" && reply.isComplete)
        precondition(ConversationSpace.claudeCobra.accepts(url: reply.url))
        precondition(!ConversationSpace.claudeHL.accepts(url: reply.url), "Native paths must not widen HL browser routing")
        var collapsed = transcript
        collapsed.children[1].children[2] = ClaudeAXNode(role: "AXButton", label: "Afficher les actions du message pour Claude a répondu : Début")
        var collapsedArea = area; collapsedArea.children = [collapsed]
        precondition(ClaudeDesktopParser.parse(ClaudeAXNode(role: "AXWindow", children: [collapsedArea]))?.isComplete == true)
        area.children.append(ClaudeAXNode(role: "AXButton", label: "Arrêter"))
        root.children = [area]
        precondition(ClaudeDesktopParser.parse(root)?.isComplete == false, "A previous reply must not be captured during a new generation")
        root.children = [area, area]
        precondition(ClaudeDesktopParser.parse(root) == nil, "Ambiguous split views must be rejected")
        for bad in ["https://claude.ai.evil/chat/a", "https://x@claude.ai/chat/a", "http://claude.ai/chat/a", "https://claude.ai:4000/chat/a", "https://claude.ai/new", "https://claude.ai/code/artifact/a"] {
            precondition(ClaudeDesktopParser.conversationURL(bad) == nil)
        }
        var incomplete = reply; incomplete.isComplete = false
        var stability = ClaudeCaptureStability()
        let now = Date(timeIntervalSince1970: 100)
        precondition(stability.ready(reply, now: now) == nil)
        precondition(stability.ready(reply, now: now.addingTimeInterval(3)) == nil)
        precondition(stability.ready(reply, now: now.addingTimeInterval(6)) == reply)
        precondition(stability.ready(incomplete, now: now.addingTimeInterval(9)) == nil)
        precondition(stability.ready(reply, now: now.addingTimeInterval(12)) == nil)
        precondition(stability.ready(nil, now: now.addingTimeInterval(15)) == nil)
        var switched = reply; switched.url = URL(string: "https://claude.ai/chat/other")!
        precondition(stability.ready(switched, now: now.addingTimeInterval(18)) == nil)
        var changed = switched; changed.text = "Réponse modifiée"
        precondition(stability.ready(changed, now: now.addingTimeInterval(24)) == nil)
        var inbox = ConversationInbox()
        let id = try inbox.conversation(space: .claudeCobra, title: reply.title, externalID: reply.url.path, url: reply.url)
        try inbox.receive(conversationID: id, messageID: "native-test", text: reply.text)
        inbox.replies[0].status = .done
        let duplicate = try inbox.receive(conversationID: id, messageID: "native-test", text: reply.text)
        precondition(!duplicate)
        precondition(inbox.replies.count == 1 && inbox.replies[0].status == .done)
        let snapshot = try JSONDecoder().decode(ConversationInbox.self, from: JSONEncoder().encode(inbox))
        precondition(snapshot == inbox)
        var artifact = ClaudeAXNode(role: "AXWebArea", url: "https://claude.ai/code/artifact/demo", children: [heading("Claude a répondu : Faux"), text("Pas une réponse"), actions])
        area.children = [transcript, artifact]
        root.children = [area]
        precondition(ClaudeDesktopParser.parse(root)?.text == reply.text, "Artifact content must not be interpreted as transcript")
        artifact.url = "https://claude.ai/chat/other"
        area.children.append(artifact); root.children = [area]
        // The outer conversation area is the single selected root; nested previews stay excluded.
        precondition(ClaudeDesktopParser.parse(root)?.text == reply.text)
        print("Claude desktop capture tests passed")
    }
}
