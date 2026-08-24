import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class SessionAuthorityTests: XCTestCase {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-authority-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("workspace.json")
    }

    func testAuthorityAssessmentUsesSmallestPlausibleBoundary() {
        XCTAssertEqual(SessionAuthorityAssessment.assess("Explain the architecture").requiredProfile, .readOnly)
        XCTAssertEqual(SessionAuthorityAssessment.assess("Edit the terminal layout").requiredProfile, .workspaceEdits)
        XCTAssertEqual(SessionAuthorityAssessment.assess("Run Swift tests").requiredProfile, .localCommands)
        XCTAssertEqual(SessionAuthorityAssessment.assess("Deploy over SSH to spark").requiredProfile, .unrestricted)
    }

    func testNewCodingSessionsDefaultToUnrestrictedAuthority() {
        XCTAssertEqual(AgentCapabilitySettings.defaultProfile, .unrestricted)
    }

    func testSessionsPersistIndependentAuthorityProfiles() throws {
        let url = temporaryURL()
        let store = WorkspaceStore(persistenceURL: url)
        let claude = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.resolvedProvider == .claude }))
        let codex = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.resolvedProvider == .codex }))

        store.setAuthorityProfile(.readOnly, for: claude.id)
        store.setAuthorityProfile(.localCommands, for: codex.id)

        let reloaded = WorkspaceStore(persistenceURL: url)
        XCTAssertEqual(reloaded.activeWorkspace.nodes.first(where: { $0.id == claude.id })?.authorityProfile, .readOnly)
        XCTAssertEqual(reloaded.activeWorkspace.nodes.first(where: { $0.id == codex.id })?.authorityProfile, .localCommands)
    }

    func testBoundaryExpansionQueuesOneApprovalWithoutLaunching() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL(), runtimeEnabled: false)
        let agent = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.resolvedProvider == .codex }))
        store.setAuthorityProfile(.readOnly, for: agent.id)

        XCTAssertTrue(store.sendTask("Run Swift tests", to: agent.id))
        XCTAssertTrue(store.sendTask("Run Swift tests", to: agent.id))

        XCTAssertNil(store.latestRun(for: agent.id))
        XCTAssertEqual(store.pendingAuthorityApprovals.count, 1)
        XCTAssertEqual(store.pendingAuthorityApprovals.first?.currentProfile, .readOnly)
        XCTAssertEqual(store.pendingAuthorityApprovals.first?.requestedProfile, .localCommands)
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == agent.id })?.status, .idle)
    }

    func testApproveOnceLaunchesFrozenElevatedRunWithoutChangingSession() throws {
        let url = temporaryURL()
        let store = WorkspaceStore(persistenceURL: url, runtimeEnabled: false)
        let agent = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.resolvedProvider == .claude }))
        store.setAuthorityProfile(.workspaceEdits, for: agent.id)
        XCTAssertTrue(store.sendTask("Run the build and tests", to: agent.id))
        let approval = try XCTUnwrap(store.pendingAuthorityApprovals.first)

        XCTAssertTrue(store.approveAuthorityRequest(approval.id))

        let run = try XCTUnwrap(store.latestRun(for: agent.id))
        XCTAssertEqual(run.authorityProfile, .localCommands)
        XCTAssertEqual(run.approvalID, approval.id)
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == agent.id })?.authorityProfile, .workspaceEdits)
        XCTAssertTrue(store.pendingAuthorityApprovals.isEmpty)

        let reloaded = WorkspaceStore(persistenceURL: url)
        XCTAssertEqual(reloaded.runRecord(withID: run.id)?.authorityProfile, .localCommands)
        XCTAssertEqual(reloaded.activeWorkspace.approvalHistory.first(where: { $0.id == approval.id })?.state, .approved)
    }

    func testRejectLeavesSessionIdleAndRecordsDecision() throws {
        let store = WorkspaceStore(persistenceURL: temporaryURL(), runtimeEnabled: false)
        let agent = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.resolvedProvider == .codex }))
        store.setAuthorityProfile(.readOnly, for: agent.id)
        XCTAssertTrue(store.sendTask("Deploy the build over SSH", to: agent.id))
        let approval = try XCTUnwrap(store.pendingAuthorityApprovals.first)

        store.rejectAuthorityRequest(approval.id)

        XCTAssertNil(store.latestRun(for: agent.id))
        XCTAssertTrue(store.pendingAuthorityApprovals.isEmpty)
        XCTAssertEqual(store.activeWorkspace.approvalHistory.first(where: { $0.id == approval.id })?.state, .rejected)
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == agent.id })?.status, .idle)
    }
}
