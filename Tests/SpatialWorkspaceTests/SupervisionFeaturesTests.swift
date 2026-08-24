import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class SupervisionFeaturesTests: XCTestCase {
    private func store(at url: URL? = nil) -> WorkspaceStore {
        let persistenceURL = url ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        return WorkspaceStore(persistenceURL: persistenceURL)
    }

    private func empty(_ store: WorkspaceStore) {
        for node in store.activeWorkspace.nodes { store.removeNode(node.id) }
    }

    func testStageProjectionKeepsStableOrderWithinStatusGroups() {
        let idleA = WorkspaceNode(kind: .agent, title: "A", subtitle: "Claude", position: .zero, size: CGSize(width: 400, height: 300), zIndex: 1, provider: .claude)
        let working = WorkspaceNode(kind: .agent, title: "B", subtitle: "Codex", position: .zero, size: CGSize(width: 400, height: 300), zIndex: 2, status: .working, provider: .codex, runtimeState: .working)
        let idleC = WorkspaceNode(kind: .agent, title: "C", subtitle: "Claude", position: .zero, size: CGSize(width: 400, height: 300), zIndex: 3, provider: .claude)
        let blocked = WorkspaceNode(kind: .agent, title: "D", subtitle: "Codex", position: .zero, size: CGSize(width: 400, height: 300), zIndex: 4, status: .needsAttention, provider: .codex, runtimeState: .needsYou)

        let ordered = StageProjection.ordered(nodes: [idleA, working, idleC, blocked], missions: []) { $0.resolvedRuntimeState }

        XCTAssertEqual(ordered.map(\.title), ["D", "B", "A", "C"])
    }

    func testMissionRollsWorkerAttentionIntoOneMissionItem() {
        let worker = WorkspaceNode(kind: .agent, title: "Marshall", subtitle: "Claude", position: .zero, size: CGSize(width: 400, height: 300), zIndex: 1, status: .needsAttention, provider: .claude, runtimeState: .needsYou)
        let missionID = UUID()
        let missionNode = WorkspaceNode(kind: .mission, title: "Launch", subtitle: "Mission", position: .zero, size: CGSize(width: 400, height: 300), zIndex: 2, status: .needsAttention, runtimeState: .needsYou, missionID: missionID)
        let mission = WorkspaceMission(
            id: missionID,
            nodeID: missionNode.id,
            title: "Launch",
            objective: "Ship the site",
            state: .needsAttention,
            tasks: [MissionTask(title: "Build", role: .worker, assigneeNodeID: worker.id, state: .blocked)]
        )

        XCTAssertEqual(StageProjection.group(for: worker, runtimeState: .needsYou, missions: [mission]), .agentsAndMissions)
        XCTAssertEqual(StageProjection.group(for: missionNode, runtimeState: .needsYou, missions: [mission]), .needsYou)
    }

    func testMissionPersistsWorkersReviewerAndDependencyGate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = store(at: url)
        empty(store)
        let marshall = store.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let skye = store.createSession(provider: .codex, name: "Skye", purpose: "tests")
        let ada = store.createSession(provider: .claude, name: "Ada", purpose: "review")

        let missionID = try XCTUnwrap(store.createMission(
            title: "Launch",
            objective: "Build and verify the landing page",
            workerIDs: [marshall, skye],
            reviewerID: ada
        ))
        let mission = try XCTUnwrap(store.mission(withID: missionID))
        let workerTasks = mission.tasks.filter { $0.role == .worker }
        let reviewer = try XCTUnwrap(mission.tasks.first(where: { $0.role == .reviewer }))

        XCTAssertEqual(workerTasks.count, 2)
        XCTAssertEqual(Set(reviewer.dependencyIDs), Set(workerTasks.map(\.id)))
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.missionID == missionID })?.kind, .mission)

        let reloaded = self.store(at: url)
        XCTAssertEqual(reloaded.mission(withID: missionID)?.objective, "Build and verify the landing page")
        XCTAssertEqual(reloaded.mission(withID: missionID)?.tasks.count, 3)
    }

    func testMissionLaunchesReviewerOnlyAfterWorkersFinish() throws {
        let store = store()
        empty(store)
        let marshall = store.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let skye = store.createSession(provider: .codex, name: "Skye", purpose: "tests")
        let ada = store.createSession(provider: .claude, name: "Ada", purpose: "review")
        let missionID = try XCTUnwrap(store.createMission(
            title: "Launch",
            objective: "Build and verify the landing page",
            workerIDs: [marshall, skye],
            reviewerID: ada
        ))

        store.startMission(missionID)
        var mission = try XCTUnwrap(store.mission(withID: missionID))
        let workers = mission.tasks.filter { $0.role == .worker }
        XCTAssertTrue(workers.allSatisfy { $0.state == .working })
        XCTAssertEqual(mission.tasks.first(where: { $0.role == .reviewer })?.state, .planned)

        store.recordMissionTaskOutcome(workers[0].id, state: .readyForReview, detail: "Implementation ready")
        mission = try XCTUnwrap(store.mission(withID: missionID))
        XCTAssertEqual(mission.tasks.first(where: { $0.role == .reviewer })?.state, .planned)

        store.recordMissionTaskOutcome(workers[1].id, state: .readyForReview, detail: "Tests ready")
        mission = try XCTUnwrap(store.mission(withID: missionID))
        let reviewer = try XCTUnwrap(mission.tasks.first(where: { $0.role == .reviewer }))
        XCTAssertEqual(reviewer.state, .working)
        XCTAssertNotNil(reviewer.runID)

        store.recordMissionTaskOutcome(reviewer.id, state: .readyForReview, detail: "Review passed")
        XCTAssertEqual(store.mission(withID: missionID)?.state, .readyForReview)
        store.verifyMission(missionID)
        XCTAssertEqual(store.mission(withID: missionID)?.state, .verified)
    }

    func testInterruptedSessionCanBeDismissedBackToIdle() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let first = store(at: url)
        let agent = try XCTUnwrap(first.activeWorkspace.nodes.first(where: { $0.kind == .agent }))
        XCTAssertTrue(first.sendTask("Inspect the project", to: agent.id))

        let relaunched = store(at: url)
        let interrupted = try XCTUnwrap(relaunched.activeWorkspace.nodes.first(where: { $0.id == agent.id }))
        XCTAssertEqual(interrupted.resolvedRuntimeState, .interrupted)
        XCTAssertEqual(interrupted.status, .needsAttention)

        relaunched.dismissSessionIssue(agent.id)
        let dismissed = try XCTUnwrap(relaunched.activeWorkspace.nodes.first(where: { $0.id == agent.id }))
        XCTAssertEqual(dismissed.resolvedRuntimeState, .idle)
        XCTAssertEqual(dismissed.status, .idle)
    }

    func testReviewResolverShowsWorkspaceFileAndRejectsOutsidePath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("result.txt")
        try Data("reviewable result".utf8).write(to: file)
        let inside = WorkspaceArtifact(kind: .text, title: "result.txt", location: file.path, verified: true, modifiedAt: Date())
        XCTAssertEqual(ReviewResolver.detail(for: inside, rootPath: root.path), "reviewable result")

        let outside = WorkspaceArtifact(kind: .text, title: "outside.txt", location: "/tmp/outside.txt", verified: false, modifiedAt: nil)
        XCTAssertTrue(ReviewResolver.detail(for: outside, rootPath: root.path).contains("outside the workspace"))
    }

    func testReviewResolverRejectsWorkspaceSymlinkThatEscapesRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("secret-\(UUID().uuidString).txt")
        try Data("not workspace evidence".utf8).write(to: outside)
        let link = root.appendingPathComponent("evidence.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let artifact = WorkspaceArtifact(kind: .text, title: "evidence.txt", location: link.path, verified: true, modifiedAt: Date())

        XCTAssertTrue(ReviewResolver.detail(for: artifact, rootPath: root.path).contains("outside the workspace"))
        XCTAssertNil(ReviewResolver.previewURL(for: artifact, rootPath: root.path))
    }

    func testReviewResolverDrainsAndBoundsLargeGitDiff() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try run("/usr/bin/git", ["init", "-q"], in: root)
        let file = root.appendingPathComponent("large.txt")
        try Data((String(repeating: "a", count: 240_000) + "\n").utf8).write(to: file)
        try run("/usr/bin/git", ["add", "large.txt"], in: root)
        try run("/usr/bin/git", ["-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-qm", "baseline"], in: root)
        try Data((String(repeating: "b", count: 240_000) + "\n").utf8).write(to: file)
        let artifact = WorkspaceArtifact(kind: .text, title: "large.txt", location: file.path, verified: true, modifiedAt: Date())

        let detail = ReviewResolver.detail(for: artifact, rootPath: root.path)

        XCTAssertTrue(detail.contains("Git output truncated"))
        XCTAssertLessThan(detail.utf8.count, 181_000)
    }

    func testAgentDraftSurvivesRelaunch() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let first = store(at: url)
        let agent = try XCTUnwrap(first.activeWorkspace.nodes.first(where: { $0.kind == .agent }))
        first.updateNodeDraft(agent.id, draft: "Keep this revision note")

        let relaunched = self.store(at: url)
        XCTAssertEqual(relaunched.activeWorkspace.nodes.first(where: { $0.id == agent.id })?.draft, "Keep this revision note")
    }

    func testMissionFailureRollsUpToMissionAttention() throws {
        let store = store()
        empty(store)
        let workerID = store.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let missionID = try XCTUnwrap(store.createMission(
            title: "Launch",
            objective: "Ship the verified build",
            workerIDs: [workerID],
            reviewerID: nil
        ))
        store.startMission(missionID)
        let taskID = try XCTUnwrap(store.mission(withID: missionID)?.tasks.first?.id)

        store.recordMissionTaskOutcome(taskID, state: .failed, detail: "Build failed")

        XCTAssertEqual(store.mission(withID: missionID)?.state, .needsAttention)
        let missionNode = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.missionID == missionID }))
        XCTAssertEqual(missionNode.status, .needsAttention)
        XCTAssertEqual(missionNode.resolvedRuntimeState, .needsYou)
        XCTAssertEqual(
            StageProjection.group(for: missionNode, runtimeState: missionNode.resolvedRuntimeState, missions: store.activeWorkspace.missionHistory),
            .needsYou
        )

        store.startMission(missionID)
        XCTAssertEqual(store.mission(withID: missionID)?.state, .working)
        XCTAssertEqual(store.mission(withID: missionID)?.tasks.first?.state, .working)
    }

    func testDuplicateWorkspaceRemapsMissionGraphAndResetsExecution() throws {
        let store = store()
        empty(store)
        let workerID = store.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let reviewerID = store.createSession(provider: .codex, name: "Ada", purpose: "review")
        let originalMissionID = try XCTUnwrap(store.createMission(
            title: "Launch",
            objective: "Build and review",
            workerIDs: [workerID],
            reviewerID: reviewerID
        ))
        let original = try XCTUnwrap(store.mission(withID: originalMissionID))

        store.duplicateActiveWorkspace()

        let copy = store.activeWorkspace
        let copiedMission = try XCTUnwrap(copy.missionHistory.first)
        XCTAssertNotEqual(copiedMission.id, original.id)
        XCTAssertNotEqual(copiedMission.nodeID, original.nodeID)
        XCTAssertEqual(copiedMission.state, .drafted)
        XCTAssertTrue(copiedMission.tasks.allSatisfy { $0.state == .planned && $0.runID == nil })
        let copiedWorker = try XCTUnwrap(copiedMission.tasks.first(where: { $0.role == .worker }))
        let copiedReviewer = try XCTUnwrap(copiedMission.tasks.first(where: { $0.role == .reviewer }))
        XCTAssertEqual(copiedReviewer.dependencyIDs, [copiedWorker.id])
        XCTAssertNotEqual(copiedWorker.assigneeNodeID, workerID)
        XCTAssertNotEqual(copiedReviewer.assigneeNodeID, reviewerID)
        XCTAssertEqual(copy.nodes.first(where: { $0.id == copiedMission.nodeID })?.missionID, copiedMission.id)
        XCTAssertEqual(copy.nodes.first(where: { $0.id == copiedMission.nodeID })?.status, .idle)
        XCTAssertEqual(copy.nodes.first(where: { $0.id == copiedMission.nodeID })?.resolvedRuntimeState, .idle)
    }

    func testReviewerCannotAlsoBeMissionWorker() throws {
        let store = store()
        empty(store)
        let agentID = store.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let missionID = try XCTUnwrap(store.createMission(
            title: "Launch",
            objective: "Build and review",
            workerIDs: [agentID],
            reviewerID: agentID
        ))

        XCTAssertEqual(store.mission(withID: missionID)?.tasks.filter { $0.role == .worker }.count, 1)
        XCTAssertNil(store.mission(withID: missionID)?.tasks.first(where: { $0.role == .reviewer }))
    }

    func testDuplicateWorkerIDsCreateOneMissionAssignment() throws {
        let store = store()
        empty(store)
        let agentID = store.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let missionID = try XCTUnwrap(store.createMission(
            title: "Launch",
            objective: "Build once",
            workerIDs: [agentID, agentID],
            reviewerID: nil
        ))

        XCTAssertEqual(store.mission(withID: missionID)?.tasks.filter { $0.role == .worker }.count, 1)
    }

    func testCancelledMissionCannotBeReactivatedByLateTaskCompletion() throws {
        let store = store()
        empty(store)
        let agentID = store.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let missionID = try XCTUnwrap(store.createMission(
            title: "Launch",
            objective: "Build once",
            workerIDs: [agentID],
            reviewerID: nil
        ))
        store.startMission(missionID)
        let taskID = try XCTUnwrap(store.mission(withID: missionID)?.tasks.first?.id)

        store.cancelMission(missionID)
        store.recordMissionTaskOutcome(taskID, state: .cancelled, detail: "Process stopped")

        XCTAssertEqual(store.mission(withID: missionID)?.state, .cancelled)
        let missionNode = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.missionID == missionID }))
        XCTAssertNotEqual(missionNode.status, .needsAttention)
    }

    func testInterruptedMissionBecomesRestartableAfterRelaunch() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let first = store(at: url)
        empty(first)
        let workerID = first.createSession(provider: .claude, name: "Marshall", purpose: "implementation")
        let reviewerID = first.createSession(provider: .codex, name: "Ada", purpose: "review")
        let missionID = try XCTUnwrap(first.createMission(
            title: "Launch",
            objective: "Build and review",
            workerIDs: [workerID],
            reviewerID: reviewerID
        ))
        first.startMission(missionID)

        let relaunched = self.store(at: url)
        var mission = try XCTUnwrap(relaunched.mission(withID: missionID))
        XCTAssertEqual(mission.state, .needsAttention)
        XCTAssertEqual(mission.tasks.first(where: { $0.role == .worker })?.state, .blocked)

        relaunched.startMission(missionID)
        mission = try XCTUnwrap(relaunched.mission(withID: missionID))
        XCTAssertEqual(mission.state, .working)
        XCTAssertEqual(mission.tasks.first(where: { $0.role == .worker })?.state, .working)
        XCTAssertEqual(mission.tasks.first(where: { $0.role == .reviewer })?.state, .planned)
    }

    private func run(_ executable: String, _ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "\(executable) \(arguments.joined(separator: " ")) failed")
    }
}
