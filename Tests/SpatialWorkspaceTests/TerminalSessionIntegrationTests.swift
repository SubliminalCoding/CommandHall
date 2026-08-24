import Darwin
import XCTest
import SpatialAgentBridgeKit
@testable import SpatialWorkspaceApp

@MainActor
final class TerminalSessionIntegrationTests: XCTestCase {
    private final class FailingBridge: SpatialAgentBridgeSessionProviding {
        func issueSession(
            nodeID: UUID,
            provider: String,
            scopes: Set<AgentBridgeOperation>
        ) throws -> AgentBridgeCredential {
            throw NSError(domain: "AgentBridgeTests", code: 2)
        }

        func revoke(_ credential: AgentBridgeCredential?) {}

        func environment(for credential: AgentBridgeCredential) -> [String: String] {
            XCTFail("No environment should be created after credential issuance fails")
            return [:]
        }
    }

    func testRealPTYAcceptsInputAndStreamsShellOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TerminalSession(id: UUID(), workingDirectory: directory)

        session.start()
        session.send("printf '\\x5f\\x5fPTY_EXECUTED\\x5f\\x5f\\n'\r")

        for _ in 0..<100 where !session.output.contains("__PTY_EXECUTED__") {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(session.output.contains("__PTY_EXECUTED__"), session.output)
        if case .running = session.state {
            session.terminate()
        } else {
            XCTFail("PTY shell exited before the command completed: \(session.state)")
        }
    }

    func testRegistryReplacesTerminalWhenWorkingFolderChanges() throws {
        let firstDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let secondDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let registry = TerminalRegistry()
        let id = UUID()

        let first = registry.session(id: id, workingDirectory: firstDirectory)
        let second = registry.session(id: id, workingDirectory: secondDirectory)

        XCTAssertFalse(first === second)
        XCTAssertEqual(second.workingDirectory, secondDirectory.resolvingSymlinksInPath().standardizedFileURL)
        registry.terminateAll()
    }

    func testTerminalReceivesProviderNeutralScopedBridgeIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let session = TerminalSession(id: id, workingDirectory: directory)

        session.start()
        session.send("printf '__BRIDGE_ENV__%s|%s|%s|%s\\n' \"$SPATIAL_AGENT_NODE_ID\" \"$SPATIAL_AGENT_PROVIDER\" \"$SPATIAL_AGENT_SESSION_ID\" \"$SPATIAL_AGENT_BRIDGE_SOCKET\"\r")

        for _ in 0..<100 where !session.output.contains("__BRIDGE_ENV__\(id.uuidString.lowercased())|terminal|") {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(
            session.output.lowercased().contains("__bridge_env__\(id.uuidString.lowercased())|terminal|"),
            session.output
        )
        XCTAssertTrue(session.output.contains("bridge.sock"), session.output)
        if case .running = session.state { session.terminate() }
    }

    func testTerminalRefusesMissingWorkingFolder() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let session = TerminalSession(id: UUID(), workingDirectory: missing)

        session.start()

        guard case .failed(let message) = session.state else {
            return XCTFail("Expected a failed terminal state, got \(session.state)")
        }
        XCTAssertTrue(message.contains("Working folder"))
    }

    func testCredentialIssuanceFailureScrubsInheritedBridgeIdentityFromRealPTY() async throws {
        let key = AgentBridgeEnvironment.sessionToken
        let previous = ProcessInfo.processInfo.environment[key]
        Darwin.setenv(key, "stale-terminal-token", 1)
        defer {
            if let previous {
                Darwin.setenv(key, previous, 1)
            } else {
                Darwin.unsetenv(key)
            }
        }

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TerminalSession(id: UUID(), workingDirectory: directory, agentBridge: FailingBridge())

        session.start()
        session.send("printf '\\x5f\\x5fBRIDGE_SCRUB\\x5f\\x5f%s\\n' \"${SPATIAL_AGENT_SESSION_TOKEN-unset}\"\r")
        for _ in 0..<100 where !session.output.contains("__BRIDGE_SCRUB__") {
            try await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertTrue(session.output.contains("__BRIDGE_SCRUB__unset"), session.output)
        XCTAssertFalse(session.output.contains("stale-terminal-token"), session.output)
        if case .running = session.state { session.terminate() }
    }
}
