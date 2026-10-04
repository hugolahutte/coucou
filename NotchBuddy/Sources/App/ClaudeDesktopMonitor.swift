import AppKit
@preconcurrency import ApplicationServices
import Combine
import CryptoKit

@MainActor
final class ClaudeDesktopMonitor: ObservableObject {
    static let shared = ClaudeDesktopMonitor()
    @Published private(set) var enabled: Bool
    @Published private(set) var status = "Suivi Claude Mac désactivé."
    @Published private(set) var candidate: ClaudeDesktopReply?
    @Published private(set) var reading = false
    @Published private(set) var activities: [ClaudeDesktopActivity] = []
    @Published private(set) var diagnostic = ""
    @Published private(set) var rememberedActivities: [ClaudeDesktopActivity] = []
    private var activityUpdatedAt = Date.distantPast
    @Published private(set) var followed: [String]
    private var timer: Timer?
    private var stability = ClaudeCaptureStability()
    private var revision = 0
    private let defaults: UserDefaults
    private let bundle = "com.anthropic.claudefordesktop"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "claudeDesktopCaptureEnabled")
        followed = defaults.stringArray(forKey: "claudeDesktopFollowedURLs") ?? []
        if let data = defaults.data(forKey: "claudeDesktopActivityHistory"),
           let items = try? JSONDecoder().decode([ClaudeDesktopActivity].self, from: data) { rememberedActivities = Array(items.prefix(50)) }
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value; revision += 1; stability.reset(); candidate = nil
        if !value { updateActivities([]) }
        defaults.set(value, forKey: "claudeDesktopCaptureEnabled")
        status = value ? "Ouvre une conversation dans Claude, puis choisis « Repérer la conversation »." : "Suivi Claude Mac désactivé."
    }

    var hasPermission: Bool {
        #if APPSTORE
        false
        #else
        AXIsProcessTrusted()
        #endif
    }

    func requestPermission() {
        #if !APPSTORE
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        status = "Autorise Coucou dans Accessibilité, puis réessaie."
        #endif
    }

    func discover() async {
        candidate = nil
        guard enabled else { return }
        let token = revision
        let result = await snapshot()
        guard token == revision, enabled else { return }
        candidate = result
        if let result { status = "Conversation repérée : \(result.title). Vérifie que le compte Claude est Cobra." }
    }

    func followCandidate() {
        guard enabled, let candidate else { return }
        if !followed.contains(candidate.url.absoluteString) { followed.append(candidate.url.absoluteString) }
        defaults.set(followed, forKey: "claudeDesktopFollowedURLs")
        stability.reset()
        status = "Suivi activé. Reviens dans Claude : sa dernière réponse terminée sera ajoutée à la liste."
    }

    func unfollow(_ url: String) {
        followed.removeAll { $0 == url }
        defaults.set(followed, forKey: "claudeDesktopFollowedURLs")
        revision += 1; stability.reset()
        status = "Suivi arrêté pour cette conversation. Les réponses déjà enregistrées restent dans la liste."
    }

    private func poll() async {
        guard enabled, !reading else { return }
        if Date().timeIntervalSince(activityUpdatedAt) > 30 { updateActivities([]) }
        let wasForeground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle
        let token = revision
        let result = await snapshot()
        guard token == revision, enabled, wasForeground,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle else { stability.reset(); return }
        guard let result, followed.contains(result.url.absoluteString) else {
            stability.reset()
            if result != nil { status = "Cette conversation n’est pas suivie. Choisis-la depuis Coucou." }
            return
        }
        guard let ready = stability.ready(result) else {
            status = result.isComplete ? "Vérification de la réponse terminée…" : "Claude travaille encore ; aucune réponse partielle n’est ajoutée."
            return
        }
        // Content hash persists across restarts and changing pagination. Repeated identical replies coalesce.
        let digest = SHA256.hash(data: Data(ready.text.utf8)).map { String(format: "%02x", $0) }.joined()
        let store = ConversationInboxStore.shared
        var inserted = false
        let saved = store.change { inbox in
            let id = try inbox.conversation(space: .claudeCobra, title: ready.title,
                                            externalID: ready.url.path, url: ready.url)
            inserted = try inbox.receive(conversationID: id, messageID: "claude-mac:\(digest)", text: ready.text)
        }
        if saved && inserted { NotificationCenter.default.post(name: .hookReveal, object: nil) }
        status = saved ? "Réponse enregistrée dans Claude · Cobra." : "Sauvegarde impossible : \(store.errorMessage ?? "réessaie")"
    }

    func openActivity(title: String) async {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            status = "Claude n’est plus ouvert."; return
        }
        app.activate(options: [.activateIgnoringOtherApps])
        guard hasPermission else { status = "Autorise Coucou dans Accessibilité pour ouvrir cette conversation."; return }
        let pid = app.processIdentifier
        let opened = await Task.detached(priority: .userInitiated) {
            ClaudeDesktopAXReader.selectActivity(pid: pid, title: title)
        }.value
        status = opened ? "Conversation ouverte dans Claude." : "Claude est ouvert, mais cette conversation n’est plus visible ou son titre est ambigu."
    }

    private func updateActivities(_ items: [ClaudeDesktopActivity]) {
        activityUpdatedAt = Date()
        activities = items
        if !items.isEmpty {
            let next = Array((items + rememberedActivities.filter { old in !items.contains { $0.title == old.title } }).prefix(50))
            if next != rememberedActivities {
                rememberedActivities = next
                if let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: "claudeDesktopActivityHistory") }
            }
        }
        let state = AppState.shared
        let prefix = "claude-mac-activity:"
        let ids = items.map { item in
            prefix + SHA256.hash(data: Data(item.title.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        let obsolete = state.tasks.filter { $0.id.hasPrefix(prefix) && !ids.contains($0.id) }.map(\.id)
        for id in obsolete { state.removeTask(id: id) }
        var added = false
        for (item, id) in zip(items, ids) {
            let botState: BotState = item.state == .working ? .working : item.state == .unread ? .finished : .idle
            let task = AgentTask(id: id, name: "Claude · \(item.title)", color: "#E07950",
                                 state: botState, steps: [item.label], source: .agent,
                                 pillBadge: item.state == .unread ? .finished : nil,
                                 claudeActivityTitle: item.title)
            if let index = state.tasks.firstIndex(where: { $0.id == id }) {
                if state.tasks[index] != task { state.tasks[index] = task }
            } else { state.addTask(task); added = true }
        }
        if added {
            if let id = ids.first, state.focusTask?.state == .idle { state.setFocus(id) }
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
    }

    private func snapshot() async -> ClaudeDesktopReply? {
        guard !reading else { return nil }
        guard hasPermission else { status = "L’autorisation Accessibilité est nécessaire."; return nil }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
            status = "Ouvre Claude Mac pour repérer une conversation."; return nil
        }
        reading = true
        defer { reading = false }
        let pid = app.processIdentifier
        let token = revision
        let result = await Task.detached(priority: .utility) { ClaudeDesktopAXReader.read(pid: pid) }.value
        guard enabled, token == revision else { return nil }
        diagnostic = result.diagnostic
        guard let tree = result.tree else {
            status = "Lecture de Claude interrompue. Réessaie une fois sa fenêtre affichée."
            return nil
        }
        if let activity = ClaudeDesktopParser.activities(tree) { updateActivities(activity) }
        guard let reply = ClaudeDesktopParser.parse(tree) else {
            status = "Conversation non reconnue. Ouvre un chat contenant une réponse Claude et réessaie."
            return nil
        }
        return reply
    }
}

private struct ClaudeDesktopAXRead: Sendable {
    var tree: ClaudeAXNode?
    var diagnostic: String
}

/// Polling is read-only. Sidebar navigation is permitted only by an explicit user click.
/// No keystrokes, clipboard, credential files, screenshots or network requests.
private enum ClaudeDesktopAXReader {
    static func read(pid: pid_t) -> ClaudeDesktopAXRead {
        #if APPSTORE
        return ClaudeDesktopAXRead(diagnostic: "App Store build: reader unavailable")
        #else
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var window = attribute(app, kAXFocusedWindowAttribute) ?? attribute(app, kAXMainWindowAttribute)
        if window == nil, let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement], windows.count == 1 { window = windows[0] }
        guard let window, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return ClaudeDesktopAXRead(diagnostic: "No accessible focused/main window")
        }
        let deadline = Date().addingTimeInterval(8)
        var remaining = 8000
        var failure: String?
        var areas = 0, links = 0, headings = 0, texts = 0
        func walk(_ element: AXUIElement, depth: Int) -> ClaudeAXNode? {
            guard failure == nil, depth < 80, remaining > 0, Date() < deadline else {
                failure = "Read limit reached"; return nil
            }
            remaining -= 1
            guard let role = attribute(element, kAXRoleAttribute) as? String else {
                failure = "Element role unavailable"; return nil
            }
            // Batch metadata/children without ever including values of editable fields.
            let names = [kAXDescriptionAttribute, kAXTitleAttribute, kAXChildrenAttribute] as CFArray
            var valuesRef: CFArray?
            let batchError = AXUIElementCopyMultipleAttributeValues(element, names, [], &valuesRef)
            guard batchError == .success, let values = valuesRef as? [Any], values.count == 3 else {
                failure = "Element metadata unavailable"; return nil
            }
            let value = role == "AXStaticText" ? (attribute(element, kAXValueAttribute) as? String ?? "") : ""
            let label = ClaudeDesktopParser.accessibleLabel(description: values[0] as? String, title: values[1] as? String, value: value)
            let rawURL = role == "AXWebArea" ? attribute(element, "AXURL") : nil
            let url = (rawURL as? URL)?.absoluteString ?? rawURL as? String ?? ""
            if role == "AXWebArea" { areas += 1; if ClaudeDesktopParser.conversationURL(url) != nil { links += 1 } }
            if role == "AXHeading" { headings += 1 }
            if role == "AXStaticText" { texts += 1 }
            var node = ClaudeAXNode(role: role, label: label, value: value, url: url)
            if ["AXTextArea", "AXTextField", "AXSecureTextField"].contains(role) { return node }
            if let children = values[2] as? [AXUIElement] {
                for child in children {
                    guard let item = walk(child, depth: depth + 1) else { return nil }
                    node.children.append(item)
                }
            } else if CFGetTypeID(values[2] as CFTypeRef) == AXValueGetTypeID() {
                let ax = values[2] as! AXValue
                if AXValueGetType(ax) == .axError {
                    var error = AXError.success
                    AXValueGetValue(ax, .axError, &error)
                    if error != .attributeUnsupported && error != .noValue {
                        failure = "Children unavailable: \(error.rawValue)"; return nil
                    }
                }
            }
            if node.label.isEmpty, role == "AXHeading", let first = node.children.first(where: { $0.role == "AXStaticText" }) {
                node.label = first.value.isEmpty ? first.label : first.value
            }
            return node
        }
        let result = walk(window as! AXUIElement, depth: 0)
        // Counts only: never include a title, URL, account identifier or reply in diagnostics.
        let diagnostic = "\(failure ?? "Read complete"); nodes=\(8000 - remaining); areas=\(areas); conversations=\(links); headings=\(headings); texts=\(texts)"
        return ClaudeDesktopAXRead(tree: failure == nil ? result : nil, diagnostic: diagnostic)
        #endif
    }

    static func selectActivity(pid: pid_t, title: String) -> Bool {
        #if APPSTORE
        return false
        #else
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let window = attribute(app, kAXFocusedWindowAttribute) ?? attribute(app, kAXMainWindowAttribute),
              CFGetTypeID(window) == AXUIElementGetTypeID() else { return false }
        var matches: [AXUIElement] = []
        var remaining = 8000
        var complete = true
        let deadline = Date().addingTimeInterval(8)
        func walk(_ element: AXUIElement, depth: Int, inSidebar: Bool) {
            guard depth < 80, remaining > 0, Date() < deadline else { complete = false; return }
            remaining -= 1
            guard let role = attribute(element, kAXRoleAttribute) as? String else { complete = false; return }
            if ["AXTextArea", "AXTextField", "AXSecureTextField"].contains(role) { return }
            let label = ClaudeDesktopParser.accessibleLabel(
                description: attribute(element, kAXDescriptionAttribute) as? String,
                title: attribute(element, kAXTitleAttribute) as? String)
            if !inSidebar && ["Messages de la conversation", "Conversation messages"].contains(label) { return }
            let sidebar = inSidebar || ["Barre latérale", "Sidebar"].contains(label)
            if sidebar, role == "AXButton" {
                let root = ClaudeAXNode(role: "AXGroup", label: "Sidebar", children: [ClaudeAXNode(role: role, label: label)])
                if ClaudeDesktopParser.activities(root)?.first?.title == title { matches.append(element) }
            }
            for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                walk(child, depth: depth + 1, inSidebar: sidebar)
            }
        }
        walk(window as! AXUIElement, depth: 0, inSidebar: false)
        guard complete, matches.count == 1 else { return false }
        return AXUIElementPerformAction(matches[0], kAXPressAction as CFString) == .success
        #endif
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
