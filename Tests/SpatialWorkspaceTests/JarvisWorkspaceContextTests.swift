import XCTest
@testable import SpatialWorkspaceApp

final class JarvisWorkspaceContextTests: XCTestCase {
    @MainActor
    func testBriefingIncludesEverySessionProviderPlacementAndLatestRun() throws {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: false)
        let novaID = store.createSession(provider: .codex, name: "Nova", purpose: "Own visual QA")
        _ = store.createSession(provider: .claude, name: "Maya", purpose: "Review architecture")
        _ = store.createSession(provider: .shell, name: "Build Logs", purpose: "Run local checks")
        XCTAssertTrue(store.sendTask("Audit the voice room", to: novaID))
        store.minimizeNode(novaID)

        let briefing = store.jarvisWorkspaceContext(now: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertTrue(briefing.contains("Nova | Codex"))
        XCTAssertTrue(briefing.contains("Maya | Claude Code"))
        XCTAssertTrue(briefing.contains("Build Logs | Terminal"))
        XCTAssertTrue(briefing.contains("minimized"))
        XCTAssertTrue(briefing.contains("Latest request [working]: Audit the voice room"))
        XCTAssertTrue(briefing.contains("Each open coding session may have a different persisted profile"))
        XCTAssertLessThanOrEqual(briefing.count, 20_000)
    }

    @MainActor
    func testBriefingCanExcludeJarvisWithoutHidingOtherAgents() {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: false)
        let jarvisID = store.createSession(provider: .jarvis, name: "Jarvis", purpose: "Liaison")
        _ = store.createSession(provider: .codex, name: "Nova", purpose: "Builder")

        let briefing = store.jarvisWorkspaceContext(excluding: jarvisID)

        XCTAssertFalse(briefing.contains("1. Jarvis"))
        XCTAssertTrue(briefing.contains("Nova | Codex"))
    }

    @MainActor
    func testBriefingRedactsCredentialsFromObservedTerminalText() {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: false)
        let novaID = store.createSession(provider: .codex, name: "Nova", purpose: "Builder")
        XCTAssertTrue(store.sendTask("Check token gsk_example_not_a_real_key and OPENAI_API_KEY=sk-example-not-a-real-key", to: novaID))

        let briefing = store.jarvisWorkspaceContext()

        XCTAssertFalse(briefing.contains("gsk_abcdefghijklmnopqrstuvwxyz"))
        XCTAssertFalse(briefing.contains("sk-example-not-a-real-key"))
        XCTAssertTrue(briefing.contains("[REDACTED CREDENTIAL]"))
    }
}
