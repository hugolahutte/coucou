import Foundation

@main struct ConversationBarStateTests {
    @MainActor static func main() async throws {
        let fsm = IslandStateMachine()
        fsm.homeToPetitDelay = 0.01
        fsm.petitToHiddenDelay = 0.01
        fsm.keepsCompactVisible = { true }
        fsm.reveal()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(fsm.state == .petit, "Summary must remain visible")
        fsm.click()
        fsm.mouseLeft()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(fsm.state == .petit, "Visible summary must not pin the expanded panel")
        fsm.click()
        fsm.collapse()
        precondition(fsm.state == .petit, "Manual folding must still work")
        fsm.isHeldOpen = { true }
        fsm.click()
        fsm.mouseLeft()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(fsm.state == .home, "An approval must still keep its panel open")
        fsm.isHeldOpen = { false }
        fsm.collapse()
        fsm.keepsCompactVisible = { false }
        fsm.mouseLeft()
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(fsm.state == .hidden, "Disabling conversation mode restores hiding")
        print("Conversation bar: retained summary, automatic/manual folding and approval priority passed")
    }
}
