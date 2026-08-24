import Darwin
import SpatialRuntimeKit
import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class DurableWorkspaceReattachmentTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-reattach-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func persistWorkingRun(at persistenceURL: URL, workingDirectory: URL) throws -> (nodeID: UUID, runID: UUID) {
        var state = WorkspaceStore.defaultState()
        let nodeIndex = try XCTUnwrap(
            state.workspaces[0].nodes.firstIndex(where: { $0.resolvedProvider == .codex })
        )
        let nodeID = state.workspaces[0].nodes[nodeIndex].id
        let runID = UUID()
        state.workspaces[0].nodes[nodeIndex].status = .working
        state.workspaces[0].nodes[nodeIndex].runtimeState = .working
        state.workspaces[0].nodes[nodeIndex].runtimeDetail = "Running before relaunch"
        state.workspaces[0].runs = [
            WorkspaceRun(
                id: runID,
                sessionNodeID: nodeID,
                request: "Continue after relaunch",
                state: .working,
                workingDirectory: workingDirectory.path
            )
        ]
        try WorkspacePersistence.save(state, to: persistenceURL)
        return (nodeID, runID)
    }

    private func writeStatus(
        root: URL,
        runID: UUID,
        nodeID: UUID,
        workerPID: Int32
    ) throws {
        let paths = DurableRuntimeRunDirectory(root: root, runID: runID)
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        let status = DurableRuntimeStatus(
            runID: runID,
            nodeID: nodeID,
            harness: AgentHarness.codex.rawValue,
            state: .running,
            workerPID: workerPID
        )
        try DurableRuntimeCodec.encoder().encode(status).write(to: paths.status, options: .atomic)
        FileManager.default.createFile(atPath: paths.output.path, contents: Data())
    }

    func testStoreRelaunchReattachesLivePersistedRun() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = directory.appendingPathComponent("workspace.json")
        let runtimeRoot = directory.appendingPathComponent("runtime", isDirectory: true)
        let identity = try persistWorkingRun(at: persistence, workingDirectory: directory)
        try writeStatus(root: runtimeRoot, runID: identity.runID, nodeID: identity.nodeID, workerPID: getpid())
        let supervisor = RuntimeSupervisor(durableRoot: runtimeRoot)

        let store = WorkspaceStore(
            persistenceURL: persistence,
            runtimeEnabled: true,
            runtimeSupervisor: supervisor
        )

        let node = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == identity.nodeID }))
        XCTAssertEqual(node.status, .working)
        XCTAssertEqual(node.runtimeState, .working)
        XCTAssertEqual(node.runtimeDetail, "Detached process reattached")
        XCTAssertEqual(store.latestRun(for: identity.nodeID)?.state, .working)
        XCTAssertEqual(store.supervisorMessage, "Reattached 1 active run")
        XCTAssertEqual(supervisor.runs[identity.runID]?.status, .running)
    }

    func testStoreRelaunchMarksRunInterruptedWhenWorkerIsGone() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = directory.appendingPathComponent("workspace.json")
        let runtimeRoot = directory.appendingPathComponent("runtime", isDirectory: true)
        let identity = try persistWorkingRun(at: persistence, workingDirectory: directory)
        try writeStatus(root: runtimeRoot, runID: identity.runID, nodeID: identity.nodeID, workerPID: Int32.max)

        let store = WorkspaceStore(
            persistenceURL: persistence,
            runtimeEnabled: true,
            runtimeSupervisor: RuntimeSupervisor(durableRoot: runtimeRoot)
        )

        let node = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == identity.nodeID }))
        XCTAssertEqual(node.status, .needsAttention)
        XCTAssertEqual(node.runtimeState, .interrupted)
        XCTAssertEqual(store.latestRun(for: identity.nodeID)?.state, .failed)
        XCTAssertTrue(node.content.contains("Run interrupted when the app closed"))
    }
}
