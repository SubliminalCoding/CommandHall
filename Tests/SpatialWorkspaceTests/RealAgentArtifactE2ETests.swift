import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class RealAgentArtifactE2ETests: XCTestCase {
    func testCodexCreatesArtifactReceiptAndLinkedPreview() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_AGENT_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_AGENT_E2E=1 to exercise the installed Codex service")
        }

        let project = FileManager.default.temporaryDirectory.appendingPathComponent("workspace-real-agent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let persistence = project.appendingPathComponent("state/workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: true)
        store.createWorkspace(name: "Artifact E2E", rootPath: project.path)
        let agentID = store.createSession(provider: .codex, name: "Proof Builder", purpose: "artifact acceptance")

        XCTAssertTrue(store.execute(
            "Proof Builder, create one file named proof.html in the current directory. It must contain a valid HTML page with the visible text ARTIFACT_E2E_OK. Do not modify any other file. Report the exact file path when finished."
        ))

        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            if store.latestRun(for: agentID)?.state.isTerminal == true { break }
            try await Task.sleep(for: .milliseconds(250))
        }

        let run = try XCTUnwrap(store.latestRun(for: agentID))
        XCTAssertTrue(run.request.hasPrefix("create one file named proof.html"))
        XCTAssertEqual(run.state, .readyToReview)
        let artifact = try XCTUnwrap(run.artifacts.first(where: { $0.title == "proof.html" }))
        XCTAssertEqual(artifact.kind, .html)
        XCTAssertTrue(artifact.verified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.location))
        let agent = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == agentID }))
        let activityLog = try XCTUnwrap(agent.activityLog)
        XCTAssertTrue(activityLog.contains("Full Capability"))
        XCTAssertTrue(activityLog.contains("proof.html"))
        XCTAssertTrue(activityLog.contains("◆") || activityLog.contains("$"))
        XCTAssertTrue(store.activeWorkspace.nodes.contains(where: {
            $0.kind == .browser && $0.linkedRunID == run.id && $0.url == artifact.previewURL
        }))
    }
}
