import XCTest
@testable import SpatialWorkspaceApp

final class JarvisDelegationTests: XCTestCase {
    func testValidControlBlockIsHiddenAndParsed() {
        let response = """
        Nova has it. I'll report back with the proof.
        <spatial_delegations>
        {"version":1,"delegations":[{"agent":"Nova","task":"Build the preview and run its tests."}]}
        </spatial_delegations>
        """

        let parsed = JarvisDelegationProtocol.parse(response)

        XCTAssertEqual(parsed.visibleContent, "Nova has it. I'll report back with the proof.")
        XCTAssertEqual(
            parsed.delegations,
            [JarvisDelegation(agent: "Nova", task: "Build the preview and run its tests.")]
        )
        XCTAssertNil(parsed.controlError)
    }

    func testMalformedControlBlockCannotLaunchWork() {
        let parsed = JarvisDelegationProtocol.parse(
            "Fine.\n<spatial_delegations>{not-json}</spatial_delegations>"
        )

        XCTAssertEqual(parsed.visibleContent, "Fine.")
        XCTAssertTrue(parsed.delegations.isEmpty)
        XCTAssertNotNil(parsed.controlError)
    }

    func testDelegationRequiresExecutionIntent() {
        XCTAssertFalse(JarvisDelegationProtocol.requestAuthorizesDelegation("How does Nova build the preview?"))
        XCTAssertFalse(JarvisDelegationProtocol.requestAuthorizesDelegation("Give me a status on Nova."))
        XCTAssertTrue(JarvisDelegationProtocol.requestAuthorizesDelegation("I want Nova to build the preview and test it."))
        XCTAssertTrue(JarvisDelegationProtocol.requestAuthorizesDelegation("Get someone on the voice bug."))
    }

    func testNaturalCommitmentFallbackUsesExactAvailableNameAndOriginalRequest() {
        let request = "I want Nova to inspect the voice room and report the files that need changes."
        let delegations = JarvisDelegationProtocol.fallbackDelegations(
            userRequest: request,
            visibleResponse: "Nova's on it. I'm having her inspect the voice room.",
            candidates: [
                JarvisDelegationCandidate(name: "Nova", provider: "Codex", isAvailable: true),
                JarvisDelegationCandidate(name: "Maya", provider: "Claude Code", isAvailable: true),
            ]
        )

        XCTAssertEqual(delegations, [JarvisDelegation(agent: "Nova", task: request)])
    }

    func testNaturalFallbackRefusesQuestionsBusyAgentsAndNegatedCommitments() {
        let roster = [JarvisDelegationCandidate(name: "Nova", provider: "Codex", isAvailable: false)]

        XCTAssertTrue(
            JarvisDelegationProtocol.fallbackDelegations(
                userRequest: "What is Nova doing?",
                visibleResponse: "Nova's on it.",
                candidates: roster
            ).isEmpty
        )
        XCTAssertTrue(
            JarvisDelegationProtocol.fallbackDelegations(
                userRequest: "I want Nova to fix it.",
                visibleResponse: "Nova is not on it because she is busy.",
                candidates: roster
            ).isEmpty
        )
    }

    func testInvalidProviderAliasOnlyRecoversToSingleAgentNamedByUser() {
        let request = "I want Nova to inspect the voice room."
        let candidates = [
            JarvisDelegationCandidate(name: "Nova", provider: "Codex", isAvailable: true),
            JarvisDelegationCandidate(name: "Marshall", provider: "Codex", isAvailable: true),
        ]

        let resolved = JarvisDelegationProtocol.resolvedDelegations(
            proposed: [JarvisDelegation(agent: "codex", task: "Inspect it")],
            userRequest: request,
            visibleResponse: "I'll handle it.",
            candidates: candidates
        )
        let ambiguous = JarvisDelegationProtocol.resolvedDelegations(
            proposed: [JarvisDelegation(agent: "codex", task: "Inspect it")],
            userRequest: "I want this inspected.",
            visibleResponse: "I'll handle it.",
            candidates: candidates
        )

        XCTAssertEqual(resolved, [JarvisDelegation(agent: "Nova", task: request)])
        XCTAssertTrue(ambiguous.isEmpty)
    }

    @MainActor
    func testAuthorizedDelegationLaunchesExactNamedIdleAgent() throws {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: false)
        let novaID = store.createSession(provider: .codex, name: "Nova", purpose: "Builder")
        let parentRunID = UUID()

        let dispatches = store.dispatchJarvisDelegations(
            [JarvisDelegation(agent: "Nova", task: "Build the preview and run its tests.")],
            authorizedBy: "I want Nova to build the preview and test it.",
            parentRunID: parentRunID
        )

        XCTAssertEqual(dispatches.count, 1)
        XCTAssertTrue(dispatches[0].launched)
        XCTAssertEqual(dispatches[0].nodeID, novaID)
        XCTAssertEqual(store.activeWorkspace.nodes.first(where: { $0.id == novaID })?.status, .working)
        let run = try XCTUnwrap(store.latestRun(for: novaID))
        XCTAssertEqual(run.request, "Build the preview and run its tests.")
        XCTAssertEqual(run.parentRunID, parentRunID)
    }

    @MainActor
    func testInformationalRequestAndUnknownAgentAreRefused() {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: false)
        _ = store.createSession(provider: .codex, name: "Nova", purpose: "Builder")

        let informational = store.dispatchJarvisDelegations(
            [JarvisDelegation(agent: "Nova", task: "Change files")],
            authorizedBy: "What is Nova working on?"
        )
        let invented = store.dispatchJarvisDelegations(
            [JarvisDelegation(agent: "Someone Else", task: "Change files")],
            authorizedBy: "Please fix the issue."
        )

        XCTAssertFalse(informational[0].launched)
        XCTAssertTrue(informational[0].detail.contains("did not authorize"))
        XCTAssertFalse(invented[0].launched)
        XCTAssertTrue(invented[0].detail.contains("exact name"))
    }
}
