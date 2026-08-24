import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class WorkspaceCommandPlanTests: XCTestCase {
    func testPlanningCompoundCommandDoesNotMutateWorkspace() {
        let store = makeStore()
        let before = store.state

        let plan = store.commandPlan(for: "Switch to Test App and refresh the browser")

        XCTAssertTrue(plan.isExecutable)
        XCTAssertFalse(plan.requiresConfirmation)
        XCTAssertEqual(plan.operations.count, 2)
        XCTAssertEqual(store.state, before)
        XCTAssertTrue(plan.detail.contains("Switch to Test App"))
        XCTAssertTrue(plan.detail.contains("Refresh previews"))
    }

    func testDestructiveCommandStagesFrozenPlanBeforeMutation() throws {
        let store = makeStore()
        let marshallID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })?.id)

        XCTAssertTrue(store.submitCommand("Close Marshall"))
        XCTAssertNotNil(store.stagedCommandPlan)
        XCTAssertTrue(store.activeWorkspace.nodes.contains(where: { $0.id == marshallID }))

        XCTAssertTrue(store.confirmStagedCommand())
        XCTAssertNil(store.stagedCommandPlan)
        XCTAssertFalse(store.activeWorkspace.nodes.contains(where: { $0.id == marshallID }))
    }

    func testCancellingStagedPlanReturnsCommandToComposer() {
        let store = makeStore()

        XCTAssertTrue(store.submitCommand("Close Marshall"))
        store.cancelStagedCommand()

        XCTAssertNil(store.stagedCommandPlan)
        XCTAssertEqual(store.commandText, "Close Marshall")
        XCTAssertTrue(store.activeWorkspace.nodes.contains(where: { $0.title == "Marshall" }))
    }

    func testStagedPlanCannotRunAfterWorkspaceContextChanges() {
        let store = makeStore()
        let sourceWorkspaceID = store.activeWorkspace.id
        let targetWorkspaceID = store.state.workspaces.first(where: { $0.id != sourceWorkspaceID })!.id

        XCTAssertTrue(store.submitCommand("Close Marshall"))
        store.switchWorkspace(to: targetWorkspaceID)

        XCTAssertFalse(store.confirmStagedCommand())
        XCTAssertEqual(store.commandText, "Close Marshall")
        store.switchWorkspace(to: sourceWorkspaceID)
        XCTAssertTrue(store.activeWorkspace.nodes.contains(where: { $0.title == "Marshall" }))
    }

    func testSelectedAgentTaskProducesTypedDirectTaskPlan() throws {
        let store = makeStore()
        let marshallID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.title == "Marshall" })?.id)
        store.select(marshallID)

        let plan = store.commandPlan(for: "Review the persistence layer")

        XCTAssertEqual(
            plan.operations,
            [.sendTask(nodeID: marshallID, nodeName: "Marshall", task: "Review the persistence layer")]
        )
        XCTAssertEqual(plan.title, "Send task to Marshall")
    }

    func testUnknownCommandReturnsAnHonestNonExecutablePlan() {
        let store = makeStore()
        store.select(nil)

        let plan = store.commandPlan(for: "Something ambiguous")

        XCTAssertFalse(plan.isExecutable)
        XCTAssertTrue(plan.operations.isEmpty)
        XCTAssertTrue(plan.title.contains("No matching workspace action"))
    }

    private func makeStore() -> WorkspaceStore {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        return WorkspaceStore(persistenceURL: persistence)
    }
}
