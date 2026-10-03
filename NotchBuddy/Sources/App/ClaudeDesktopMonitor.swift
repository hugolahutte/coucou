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
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value; revision += 1; stability.reset(); candidate = nil
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
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle else { stability.reset(); return }
        let token = revision
        let result = await snapshot()
        guard token == revision, enabled,
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
        let saved = store.change { inbox in
            let id = try inbox.conversation(space: .claudeCobra, title: ready.title,
                                            externalID: ready.url.path, url: ready.url)
            try inbox.receive(conversationID: id, messageID: "claude-mac:\(digest)", text: ready.text)
        }
        status = saved ? "Réponse enregistrée dans Claude · Cobra." : "Sauvegarde impossible : \(store.errorMessage ?? "réessaie")"
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
        let tree = await Task.detached(priority: .utility) { ClaudeDesktopAXReader.read(pid: pid) }.value
        guard enabled else { return nil }
        guard let tree, let reply = ClaudeDesktopParser.parse(tree) else {
            status = "Conversation non reconnue. Ouvre un chat contenant une réponse Claude et réessaie."
            return nil
        }
        return reply
    }
}

/// No clicks, keystrokes, clipboard, credential files, screenshots or network requests.
private enum ClaudeDesktopAXReader {
    static func read(pid: pid_t) -> ClaudeAXNode? {
        #if APPSTORE
        return nil
        #else
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let window = attribute(app, kAXFocusedWindowAttribute) else { return nil }
        guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let deadline = Date().addingTimeInterval(8)
        var remaining = 8000
        var failed = false
        func walk(_ element: AXUIElement, depth: Int) -> ClaudeAXNode? {
            guard !failed, depth < 80, remaining > 0, Date() < deadline else { failed = true; return nil }
            remaining -= 1
            guard let role = attribute(element, kAXRoleAttribute) as? String else { failed = true; return nil }
            let label = (attribute(element, kAXDescriptionAttribute) as? String)
                ?? (attribute(element, kAXTitleAttribute) as? String) ?? ""
            // Read values only for static text, never editable fields/passwords.
            let value = role == "AXStaticText" ? (attribute(element, kAXValueAttribute) as? String ?? "") : ""
            let rawURL = role == "AXWebArea" ? attribute(element, "AXURL") : nil
            let url = (rawURL as? URL)?.absoluteString ?? rawURL as? String ?? ""
            var node = ClaudeAXNode(role: role, label: label, value: value, url: url)
            if role == "AXTextArea" || role == "AXTextField" || role == "AXSecureTextField" { return node }
            // Unsupported children is valid for leaves; transient AX errors invalidate the entire read.
            var childrenRef: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            if error == .success, let children = childrenRef as? [AXUIElement] {
                for child in children {
                    guard let item = walk(child, depth: depth + 1) else { return nil }
                    node.children.append(item)
                }
            } else if error != .attributeUnsupported && error != .noValue && error != .success { failed = true; return nil }
            if node.label.isEmpty, role == "AXHeading", let first = node.children.first(where: { $0.role == "AXStaticText" }) {
                node.label = first.value.isEmpty ? first.label : first.value
            }
            return node
        }
        let result = walk(window as! AXUIElement, depth: 0)
        return failed ? nil : result
        #endif
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
