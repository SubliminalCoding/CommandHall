import Darwin
import Foundation
import SpatialAgentBridgeKit
import XCTest

final class AgentBridgeIntegrationTests: XCTestCase {
    private final class TestAudioHandler: AgentAudioControlHandling, @unchecked Sendable {
        func handle(_ command: AgentAudioCommand, for identity: AgentBridgeSessionIdentity) async throws -> AgentAudioResult {
            let now = Int64(Date().timeIntervalSince1970 * 1_000)
            switch command {
            case .status:
                return .status(
                    AgentAudioStatus(
                        capturedAtEpochMilliseconds: now,
                        revision: 7,
                        mutationMode: .live,
                        configuredProfileID: "streaming",
                        activeProfileID: "streaming",
                        streamState: .preview,
                        sources: [
                            AgentAudioSourceStatus(
                                id: "browser-6",
                                label: "Browser 6",
                                monitorEnabled: true,
                                streamEnabled: false,
                                verified: true
                            ),
                        ]
                    )
                )
            case .plan(let request):
                let target = request.sourceID ?? request.profileID ?? request.busID ?? "audio"
                return .plan(
                    AgentAudioPlan(
                        id: "plan-1",
                        intent: request.intent,
                        summary: "Prepared \(request.intent.rawValue) for \(target)",
                        expectedRevision: 7,
                        expiresAtEpochMilliseconds: now + 60_000,
                        requiresConfirmation: request.intent == .includeInStream,
                        changes: [
                            AgentAudioChange(
                                targetKind: request.profileID == nil ? "source" : "profile",
                                targetID: target,
                                field: "streamEnabled",
                                fromValue: "false",
                                toValue: request.intent == .includeInStream ? "true" : "false"
                            ),
                        ]
                    )
                )
            case .apply(let request):
                return .applied(
                    AgentAudioMutationReceipt(
                        receiptID: "receipt-apply",
                        operation: .apply,
                        planID: request.planID,
                        configuredRevision: request.expectedRevision + 1,
                        activeRevision: request.expectedRevision + 1,
                        appliedToEngine: true,
                        verified: true,
                        summary: "Applied and verified",
                        completedAtEpochMilliseconds: now
                    )
                )
            case .panic:
                return .panic(
                    AgentAudioMutationReceipt(
                        receiptID: "receipt-panic",
                        operation: .panic,
                        configuredRevision: 9,
                        activeRevision: 9,
                        appliedToEngine: true,
                        verified: true,
                        summary: "Panic mute verified",
                        completedAtEpochMilliseconds: now
                    )
                )
            }
        }
    }

    private struct Harness {
        let directory: URL
        let socketURL: URL
        let registry: AgentBridgeSessionRegistry
        let broker: AgentBridgeBroker
        let credential: AgentBridgeCredential

        func stop() {
            broker.stop()
            registry.revokeAll()
        }
    }

    func testRealUnixSocketCLIExercisesStatusPlanApplyAndPanic() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let environment = environment(for: harness)

        let status = runCLI(["audio", "status"], environment: environment)
        XCTAssertEqual(status.exitCode, 0, status.errorText)
        XCTAssertTrue(status.outputText.contains("browser-6"))

        let plan = runCLI(
            ["audio", "plan", "--intent", "listen-privately", "--source", "browser-6", "--reason", "private monitoring"],
            environment: environment
        )
        XCTAssertEqual(plan.exitCode, 0, plan.errorText)
        XCTAssertTrue(plan.outputText.contains("plan-1"))

        let apply = runCLI(
            ["audio", "apply", "--plan", "plan-1", "--revision", "7", "--idempotency", "apply-test-1"],
            environment: environment
        )
        XCTAssertEqual(apply.exitCode, 0, apply.errorText)
        XCTAssertTrue(apply.outputText.contains("receipt-apply"))

        let panic = runCLI(
            ["audio", "panic", "--idempotency", "panic-test-1", "--reason", "privacy safety"],
            environment: environment
        )
        XCTAssertEqual(panic.exitCode, 0, panic.errorText)
        XCTAssertTrue(panic.outputText.contains("receipt-panic"))

        for output in [status.outputText, plan.outputText, apply.outputText, panic.outputText] {
            XCTAssertFalse(output.contains(harness.credential.token), "CLI output must never disclose its session credential")
        }

        var socketInfo = stat()
        XCTAssertEqual(Darwin.lstat(harness.socketURL.path, &socketInfo), 0)
        XCTAssertEqual(socketInfo.st_mode & mode_t(S_IRWXG | S_IRWXO), 0, "socket must be owner-only")
        var directoryInfo = stat()
        XCTAssertEqual(Darwin.lstat(harness.directory.path, &directoryInfo), 0)
        XCTAssertEqual(directoryInfo.st_mode & mode_t(S_IRWXG | S_IRWXO), 0, "socket directory must be owner-only")
    }

    func testCompiledCLIProcessUsesTheRealOwnerOnlySocket() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let executable = Bundle(for: Self.self).bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("spatial-agent")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: executable.path), executable.path)

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = ["audio", "status"]
        process.environment = environment(for: harness)
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let outputText = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        XCTAssertEqual(process.terminationStatus, 0, errorText)
        XCTAssertTrue(outputText.contains("browser-6"), outputText)
        XCTAssertFalse(outputText.contains(harness.credential.token))
    }

    func testSpoofedTokenIsRejectedOverRealSocket() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let replacement = harness.credential.token.first == "A" ? "B" : "A"
        let spoofedToken = replacement + harness.credential.token.dropFirst()
        let auth = AgentBridgeAuthentication(
            sessionID: harness.credential.sessionID,
            token: spoofedToken,
            nodeID: harness.credential.nodeID,
            provider: harness.credential.provider
        )

        assertBridgeError(.invalidSession) {
            _ = try AgentBridgeClient(socketURL: harness.socketURL).send(AgentBridgeRequest(auth: auth, command: .status))
        }
    }

    func testSpoofedNodeAndProviderAreRejectedOverRealSocket() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let client = AgentBridgeClient(socketURL: harness.socketURL)
        let wrongNode = AgentBridgeAuthentication(
            sessionID: harness.credential.sessionID,
            token: harness.credential.token,
            nodeID: UUID(),
            provider: harness.credential.provider
        )
        assertBridgeError(.identityMismatch) {
            _ = try client.send(AgentBridgeRequest(auth: wrongNode, command: .status))
        }
        let wrongProvider = AgentBridgeAuthentication(
            sessionID: harness.credential.sessionID,
            token: harness.credential.token,
            nodeID: harness.credential.nodeID,
            provider: "claude"
        )
        assertBridgeError(.identityMismatch) {
            _ = try client.send(AgentBridgeRequest(auth: wrongProvider, command: .status))
        }
    }

    func testRevokedAndExpiredSessionsAreRejected() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let client = AgentBridgeClient(socketURL: harness.socketURL)
        harness.registry.revoke(sessionID: harness.credential.sessionID)
        assertBridgeError(.invalidSession) {
            _ = try client.send(AgentBridgeRequest(auth: harness.credential.authentication, command: .status))
        }

        let issuedAt = Date(timeIntervalSince1970: 1_000)
        let expired = try harness.registry.issue(
            nodeID: UUID(),
            provider: "codex",
            lifetime: 1,
            now: issuedAt
        )
        XCTAssertThrowsError(
            try harness.registry.authorize(expired.authentication, operation: .status, now: issuedAt.addingTimeInterval(2))
        ) { error in
            XCTAssertEqual((error as? AgentBridgeErrorPayload)?.code, .sessionExpired)
        }
    }

    func testActivityBeforeIdleDeadlineRenewsSessionWithoutChangingCredential() throws {
        let registry = AgentBridgeSessionRegistry()
        let issuedAt = Date(timeIntervalSince1970: 2_000)
        let credential = try registry.issue(
            nodeID: UUID(),
            provider: "codex",
            lifetime: 10,
            absoluteLifetime: 100,
            now: issuedAt
        )

        let renewed = try registry.authorize(
            credential.authentication,
            operation: .status,
            now: issuedAt.addingTimeInterval(9)
        )
        XCTAssertEqual(renewed.expiresAtEpochMilliseconds, milliseconds(issuedAt.addingTimeInterval(19)))

        XCTAssertNoThrow(try registry.authorize(
            credential.authentication,
            operation: .status,
            now: issuedAt.addingTimeInterval(15)
        ))
        XCTAssertEqual(credential.authentication.token, credential.token)
    }

    func testIdleSessionExpiresWithoutActivity() throws {
        let registry = AgentBridgeSessionRegistry()
        let issuedAt = Date(timeIntervalSince1970: 3_000)
        let credential = try registry.issue(
            nodeID: UUID(),
            provider: "claude",
            lifetime: 10,
            absoluteLifetime: 100,
            now: issuedAt
        )

        XCTAssertThrowsError(try registry.authorize(
            credential.authentication,
            operation: .status,
            now: issuedAt.addingTimeInterval(10)
        )) { error in
            XCTAssertEqual((error as? AgentBridgeErrorPayload)?.code, .sessionExpired)
        }
    }

    func testSlidingActivityCannotRenewPastAbsoluteLifetime() throws {
        let registry = AgentBridgeSessionRegistry()
        let issuedAt = Date(timeIntervalSince1970: 4_000)
        let credential = try registry.issue(
            nodeID: UUID(),
            provider: "terminal",
            lifetime: 10,
            absoluteLifetime: 25,
            now: issuedAt
        )

        _ = try registry.authorize(credential.authentication, operation: .status, now: issuedAt.addingTimeInterval(9))
        let capped = try registry.authorize(
            credential.authentication,
            operation: .status,
            now: issuedAt.addingTimeInterval(18)
        )
        XCTAssertEqual(capped.expiresAtEpochMilliseconds, milliseconds(issuedAt.addingTimeInterval(25)))
        let stillCapped = try registry.authorize(
            credential.authentication,
            operation: .status,
            now: issuedAt.addingTimeInterval(24)
        )
        XCTAssertEqual(stillCapped.expiresAtEpochMilliseconds, milliseconds(issuedAt.addingTimeInterval(25)))

        XCTAssertThrowsError(try registry.authorize(
            credential.authentication,
            operation: .status,
            now: issuedAt.addingTimeInterval(25)
        )) { error in
            XCTAssertEqual((error as? AgentBridgeErrorPayload)?.code, .sessionExpired)
        }
    }

    func testOperationScopeAndUnknownJSONFieldsAreRejected() throws {
        let directory = temporaryDirectory()
        let socketURL = directory.appendingPathComponent("bridge.sock")
        let registry = AgentBridgeSessionRegistry()
        let router = AgentAudioControlRouter(handler: TestAudioHandler())
        let broker = AgentBridgeBroker(socketURL: socketURL, registry: registry, router: router)
        try broker.start()
        defer { broker.stop() }
        let credential = try registry.issue(nodeID: UUID(), provider: "codex", scopes: [.status])
        assertBridgeError(.forbidden) {
            _ = try AgentBridgeClient(socketURL: socketURL).send(
                AgentBridgeRequest(
                    auth: credential.authentication,
                    command: .panic(AgentAudioPanicRequest(idempotencyKey: "panic-forbidden"))
                )
            )
        }

        let valid = try AgentBridgeWireCodec.encodeRequest(
            AgentBridgeRequest(auth: credential.authentication, command: .status)
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        object["arbitraryGraphMutation"] = true
        let unbounded = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try AgentBridgeWireCodec.decodeRequest(unbounded)) { error in
            XCTAssertEqual((error as? AgentBridgeErrorPayload)?.code, .invalidRequest)
        }
    }

    func testMCPFacadeListsOnlyBoundedToolsAndCallsStatusOverSocket() throws {
        let harness = try makeHarness()
        defer { harness.stop() }
        let input = Pipe()
        let output = Pipe()
        let requests = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"audio_status","arguments":{}}}"#,
        ].joined(separator: "\n") + "\n"
        input.fileHandleForWriting.write(Data(requests.utf8))
        try input.fileHandleForWriting.close()

        let exitCode = AgentBridgeCLI.run(
            arguments: ["mcp"],
            environment: environment(for: harness),
            input: input.fileHandleForReading,
            output: output.fileHandleForWriting,
            errorOutput: FileHandle.nullDevice
        )
        try output.fileHandleForWriting.close()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        XCTAssertEqual(exitCode, 0)
        XCTAssertTrue(text.contains("audio_status"))
        XCTAssertTrue(text.contains("audio_plan"))
        XCTAssertTrue(text.contains("audio_apply"))
        XCTAssertTrue(text.contains("audio_panic"))
        XCTAssertTrue(text.contains("browser-6"))
        XCTAssertFalse(text.contains(harness.credential.token))
        XCTAssertFalse(text.contains("arbitrary"))
    }

    private func makeHarness() throws -> Harness {
        let directory = temporaryDirectory()
        let socketURL = directory.appendingPathComponent("bridge.sock")
        let registry = AgentBridgeSessionRegistry()
        let router = AgentAudioControlRouter(handler: TestAudioHandler())
        let broker = AgentBridgeBroker(socketURL: socketURL, registry: registry, router: router)
        try broker.start()
        let credential = try registry.issue(nodeID: UUID(), provider: "codex")
        return Harness(directory: directory, socketURL: socketURL, registry: registry, broker: broker, credential: credential)
    }

    private func temporaryDirectory() -> URL {
        URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("swab-\(UUID().uuidString.prefix(12))", isDirectory: true)
    }

    private func environment(for harness: Harness) -> [String: String] {
        [
            AgentBridgeEnvironment.socketPath: harness.socketURL.path,
            AgentBridgeEnvironment.sessionID: harness.credential.sessionID.uuidString,
            AgentBridgeEnvironment.sessionToken: harness.credential.token,
            AgentBridgeEnvironment.nodeID: harness.credential.nodeID.uuidString,
            AgentBridgeEnvironment.provider: harness.credential.provider,
        ]
    }

    private func runCLI(_ arguments: [String], environment: [String: String]) -> (exitCode: Int32, outputText: String, errorText: String) {
        let output = Pipe()
        let errors = Pipe()
        let exitCode = AgentBridgeCLI.run(
            arguments: arguments,
            environment: environment,
            input: FileHandle.nullDevice,
            output: output.fileHandleForWriting,
            errorOutput: errors.fileHandleForWriting
        )
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        return (
            exitCode,
            String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        )
    }

    private func assertBridgeError(
        _ expectedCode: AgentBridgeErrorCode,
        file: StaticString = #filePath,
        line: UInt = #line,
        operation: () throws -> Void
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual((error as? AgentBridgeErrorPayload)?.code, expectedCode, file: file, line: line)
        }
    }

    private func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }
}
