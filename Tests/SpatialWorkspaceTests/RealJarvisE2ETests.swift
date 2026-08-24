import XCTest
@testable import SpatialWorkspaceApp

final class RealJarvisE2ETests: XCTestCase {
    @MainActor
    func testHQJarvisCanUseObsidianContextWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_JARVIS_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_JARVIS_E2E=1 to exercise HQ Jarvis over Tailscale")
        }

        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: true)
        store.speaksCompletionNotices = false
        let novaID = store.createSession(provider: .codex, name: "Nova", purpose: "Build and verify the interface")
        store.minimizeNode(novaID)
        let jarvisID = store.createSession(provider: .jarvis, name: "Jarvis", purpose: "Blunt strategic advisor")
        let prompt = "Use your Obsidian vault search tool to check whether there is a note mentioning SpatialWorkspace or Spatial Workspace. Do not quote private content. Then tell me Nova's provider and whether she is minimized, and confirm whether the remote Spark briefing is reachable by naming its reported host."

        XCTAssertTrue(store.sendTask(prompt, to: jarvisID))
        let deadline = Date().addingTimeInterval(90)
        while store.activeWorkspace.nodes.first(where: { $0.id == jarvisID })?.status == .working,
              Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        let jarvis = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == jarvisID }))
        XCTAssertEqual(store.latestRun(for: jarvisID)?.state, .verified)
        XCTAssertFalse(jarvis.content.isEmpty)
        XCTAssertTrue(jarvis.content.localizedCaseInsensitiveContains("vault"), jarvis.content)
        XCTAssertTrue(
            jarvis.content.localizedCaseInsensitiveContains("found")
                || jarvis.content.localizedCaseInsensitiveContains("no spatial workspace note"),
            "Jarvis should report either result of its vault lookup: \(jarvis.content)"
        )
        XCTAssertTrue(jarvis.content.localizedCaseInsensitiveContains("nova"), jarvis.content)
        XCTAssertTrue(jarvis.content.localizedCaseInsensitiveContains("codex"), jarvis.content)
        XCTAssertTrue(jarvis.content.localizedCaseInsensitiveContains("minimized"), jarvis.content)
        XCTAssertTrue(jarvis.content.localizedCaseInsensitiveContains("spark"), jarvis.content)
        XCTAssertNotNil(jarvis.sessionID)
        XCTAssertEqual(jarvis.chatHistory?.map(\.role), [.user, .assistant])
        XCTAssertEqual(store.jarvisVoiceState, .idle)
    }

    func testHQJarvisProducesAValidatedDelegationProposalWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_JARVIS_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_JARVIS_E2E=1 to exercise HQ Jarvis over Tailscale")
        }

        let request = "I want Nova to inspect the voice room and report the files that would need changes."
        let prompt = """
        <matt_request>
        \(request)
        </matt_request>

        \(JarvisDelegationProtocol.instructions(candidates: [
            JarvisDelegationCandidate(name: "Nova", provider: "Codex", isAvailable: true),
        ]))
        """
        let reply = try await HQJarvisClient().reply(
            to: [WorkspaceChatMessage(role: .user, content: prompt)],
            sessionID: nil,
            onUpdate: { _ in }
        )
        let parsed = JarvisDelegationProtocol.parse(reply.content)
        let delegations = parsed.controlError == nil
            ? JarvisDelegationProtocol.resolvedDelegations(
                proposed: parsed.delegations,
                userRequest: request,
                visibleResponse: parsed.visibleContent,
                candidates: [
                    JarvisDelegationCandidate(name: "Nova", provider: "Codex", isAvailable: true),
                ]
            )
            : []

        XCTAssertNil(parsed.controlError, reply.content)
        XCTAssertEqual(delegations.count, 1, reply.content)
        XCTAssertEqual(delegations.first?.agent, "Nova")
        XCTAssertTrue(JarvisDelegationProtocol.requestAuthorizesDelegation(request))
        XCTAssertFalse(parsed.visibleContent.contains(JarvisDelegationProtocol.openingTag))
    }

    @MainActor
    func testJarvisDelegatesToARealCodexSessionWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_JARVIS_DELEGATION_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_JARVIS_DELEGATION_E2E=1 to verify a real Jarvis-to-Codex handoff")
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("jarvis-delegation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let persistence = root.appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: true)
        store.speaksCompletionNotices = false
        store.createWorkspace(name: "Delegation E2E", rootPath: root.path)
        let novaID = store.createSession(provider: .codex, name: "Nova", purpose: "Delegation proof")
        let jarvisID = store.createSession(provider: .jarvis, name: "Jarvis", purpose: "Agent liaison")
        let prompt = "I want Nova to create jarvis-delegation-proof.txt in the current workspace containing exactly JARVIS_DELEGATION_OK, then read the file back to verify it."

        XCTAssertTrue(store.sendTask(prompt, to: jarvisID))
        let jarvisDeadline = Date().addingTimeInterval(90)
        while store.activeWorkspace.nodes.first(where: { $0.id == jarvisID })?.status == .working,
              Date() < jarvisDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }

        let dispatchDeadline = Date().addingTimeInterval(20)
        while store.latestRun(for: novaID) == nil, Date() < dispatchDeadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        let agentDeadline = Date().addingTimeInterval(180)
        while store.activeWorkspace.nodes.first(where: { $0.id == novaID })?.status == .working,
              Date() < agentDeadline {
            try await Task.sleep(for: .milliseconds(150))
        }

        let proof = root.appendingPathComponent("jarvis-delegation-proof.txt")
        XCTAssertEqual(store.latestRun(for: jarvisID)?.state, .verified)
        XCTAssertEqual(store.latestRun(for: novaID)?.state, .readyToReview)
        XCTAssertEqual(try String(contentsOf: proof, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), "JARVIS_DELEGATION_OK")
        XCTAssertEqual(store.latestRun(for: novaID)?.parentRunID, store.latestRun(for: jarvisID)?.id)
    }
}
