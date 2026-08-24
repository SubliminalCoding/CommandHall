import Darwin
import XCTest
import SpatialAgentBridgeKit
@testable import SpatialWorkspaceApp

@MainActor
final class RuntimeSupervisorIntegrationTests: XCTestCase {
    private func builtWorkerURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/debug/spatial-runtime-worker")
    }

    private func temporaryRuntimeRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-supervisor-\(UUID().uuidString)", isDirectory: true)
    }

    private func withDiagnosticWorkerEnabled<T>(_ body: () async throws -> T) async rethrows -> T {
        let key = "SPATIAL_RUNTIME_ALLOW_DIAGNOSTIC"
        let previous = ProcessInfo.processInfo.environment[key]
        Darwin.setenv(key, "1", 1)
        defer {
            if let previous { Darwin.setenv(key, previous, 1) }
            else { Darwin.unsetenv(key) }
        }
        return try await body()
    }

    private final class FailingBridge: SpatialAgentBridgeSessionProviding {
        func issueSession(
            nodeID: UUID,
            provider: String,
            scopes: Set<AgentBridgeOperation>
        ) throws -> AgentBridgeCredential {
            throw NSError(domain: "AgentBridgeTests", code: 1)
        }

        func revoke(_ credential: AgentBridgeCredential?) {}

        func environment(for credential: AgentBridgeCredential) -> [String: String] {
            XCTFail("No environment should be created after credential issuance fails")
            return [:]
        }
    }

    func testRealProcessReceivesGoalOverStdinAndReportsExit() async {
        let supervisor = RuntimeSupervisor()
        let completed = expectation(description: "process completed")
        let goal = "__SUPERVISOR_STDIN_OK__"
        var output = ""
        var succeeded = false

        let runID = supervisor.start(
            nodeID: UUID(),
            harness: .diagnostic,
            goal: goal,
            workingDirectory: FileManager.default.temporaryDirectory,
            onOutput: { output += $0 },
            onCompletion: { result, _ in
                succeeded = result
                completed.fulfill()
            }
        )

        XCTAssertNotNil(runID)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertTrue(succeeded)
        XCTAssertEqual(output, goal)
        XCTAssertEqual(supervisor.runs[runID!]?.status, .completed)
        XCTAssertEqual(supervisor.runs[runID!]?.exitCode, 0)
    }

    func testCancellationInterruptsARealChildProcess() async {
        let supervisor = RuntimeSupervisor()
        let completed = expectation(description: "cancelled process completed")
        let nodeID = UUID()
        var succeeded = true
        var completionError: String?

        let runID = supervisor.start(
            nodeID: nodeID,
            harness: .diagnosticSleep,
            goal: "unused",
            workingDirectory: FileManager.default.temporaryDirectory,
            onOutput: { _ in },
            onCompletion: { result, error in
                succeeded = result
                completionError = error
                completed.fulfill()
            }
        )

        XCTAssertNotNil(runID)
        supervisor.cancel(nodeID: nodeID)
        await fulfillment(of: [completed], timeout: 4)
        XCTAssertFalse(succeeded)
        XCTAssertEqual(completionError, "Cancelled")
        XCTAssertEqual(supervisor.runs[runID!]?.status, .cancelled)
    }

    func testMissingWorkingDirectoryDoesNotLaunchAProcess() {
        let supervisor = RuntimeSupervisor()
        var result: Bool?
        var completionError: String?

        let runID = supervisor.start(
            nodeID: UUID(),
            harness: .diagnostic,
            goal: "must not run",
            workingDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            onOutput: { _ in XCTFail("No output expected") },
            onCompletion: { succeeded, error in
                result = succeeded
                completionError = error
            }
        )

        XCTAssertNil(runID)
        XCTAssertEqual(result, false)
        XCTAssertEqual(completionError, "Working folder does not exist or is not a directory")
        XCTAssertTrue(supervisor.runs.isEmpty)
    }

    func testLargeGoalDoesNotBlockCallerWhenChildDoesNotReadStdin() async {
        let supervisor = RuntimeSupervisor()
        let completed = expectation(description: "large-input process cancelled")
        let nodeID = UUID()
        let startedAt = Date()

        let runID = supervisor.start(
            nodeID: nodeID,
            harness: .diagnosticSleep,
            goal: String(repeating: "x", count: 1_000_000),
            workingDirectory: FileManager.default.temporaryDirectory,
            onOutput: { _ in },
            onCompletion: { _, _ in completed.fulfill() }
        )

        XCTAssertNotNil(runID)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        supervisor.cancel(nodeID: nodeID)
        await fulfillment(of: [completed], timeout: 4)
    }

    func testUTF8DecoderPreservesScalarSplitAcrossChunks() {
        let decoder = UTF8LineDecoder()
        let bytes = Array("before 🧭 after\n".utf8)
        let split = bytes.firstIndex(of: 0xF0)!

        XCTAssertNil(decoder.append(Data(bytes[..<(split + 2)])))
        XCTAssertEqual(decoder.append(Data(bytes[(split + 2)...])), "before 🧭 after\n")
        XCTAssertNil(decoder.finish())
    }

    func testSelectedModelBecomesOneProcessArgument() {
        XCTAssertEqual(RuntimeSupervisor.modelArguments(for: "opus"), ["--model", "opus"])
        XCTAssertEqual(RuntimeSupervisor.modelArguments(for: "gpt-5.6-sol"), ["--model", "gpt-5.6-sol"])
        XCTAssertEqual(RuntimeSupervisor.modelArguments(for: nil), [])
        XCTAssertEqual(RuntimeSupervisor.modelArguments(for: "bad;model"), [])
    }

    func testCredentialIssuanceFailureScrubsInheritedBridgeIdentityFromRealChild() async {
        let key = AgentBridgeEnvironment.sessionToken
        let previous = ProcessInfo.processInfo.environment[key]
        Darwin.setenv(key, "stale-parent-session-token", 1)
        defer {
            if let previous {
                Darwin.setenv(key, previous, 1)
            } else {
                Darwin.unsetenv(key)
            }
        }

        let supervisor = RuntimeSupervisor(agentBridge: FailingBridge())
        let completed = expectation(description: "environment process completed")
        var output = ""
        var succeeded = false

        let runID = supervisor.start(
            nodeID: UUID(),
            harness: .diagnosticEnvironment,
            goal: "unused",
            workingDirectory: FileManager.default.temporaryDirectory,
            onOutput: { output += $0 },
            onCompletion: { result, _ in
                succeeded = result
                completed.fulfill()
            }
        )

        XCTAssertNotNil(runID)
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertTrue(succeeded)
        XCTAssertFalse(output.contains("SPATIAL_AGENT_"), output)
        XCTAssertFalse(output.contains("stale-parent-session-token"), output)
    }

    func testDurableSupervisorStreamsOutputAndUsesWorkspaceRunIdentity() async {
        await withDiagnosticWorkerEnabled {
            let root = temporaryRuntimeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let worker = builtWorkerURL()
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: worker.path))
            let supervisor = RuntimeSupervisor(
                durableRoot: root,
                workerURL: worker,
                durableHarnesses: [.diagnosticDelayedOutput]
            )
            let completed = expectation(description: "durable process completed")
            let runID = UUID()
            var output = ""
            var succeeded = false

            let startedID = supervisor.start(
                runID: runID,
                nodeID: UUID(),
                harness: .diagnosticDelayedOutput,
                goal: "DURABLE_SUPERVISOR_OK\n",
                workingDirectory: FileManager.default.temporaryDirectory,
                onOutput: { output += $0 },
                onCompletion: { result, _ in
                    succeeded = result
                    completed.fulfill()
                }
            )

            XCTAssertEqual(startedID, runID)
            await fulfillment(of: [completed], timeout: 4)
            XCTAssertTrue(succeeded)
            XCTAssertEqual(output, "DURABLE_SUPERVISOR_OK\n")
            XCTAssertEqual(supervisor.runs[runID]?.status, .completed)
            XCTAssertEqual(supervisor.durableStatus(runID: runID, nodeID: supervisor.runs[runID]!.nodeID)?.state, .completed)
        }
    }

    func testSecondSupervisorReattachesAndCancelsDetachedRun() async throws {
        try await withDiagnosticWorkerEnabled {
            let root = temporaryRuntimeRoot()
            defer { try? FileManager.default.removeItem(at: root) }
            let worker = builtWorkerURL()
            let runID = UUID()
            let nodeID = UUID()
            var launchingSupervisor: RuntimeSupervisor? = RuntimeSupervisor(
                durableRoot: root,
                workerURL: worker,
                durableHarnesses: [.diagnosticSleep]
            )
            XCTAssertEqual(
                launchingSupervisor?.start(
                    runID: runID,
                    nodeID: nodeID,
                    harness: .diagnosticSleep,
                    goal: "",
                    workingDirectory: FileManager.default.temporaryDirectory,
                    onOutput: { _ in },
                    onCompletion: { _, _ in }
                ),
                runID
            )
            launchingSupervisor = nil

            let attachedSupervisor = RuntimeSupervisor(
                durableRoot: root,
                workerURL: worker,
                durableHarnesses: [.diagnosticSleep]
            )
            let runningDeadline = Date().addingTimeInterval(2)
            while attachedSupervisor.durableStatus(runID: runID, nodeID: nodeID)?.state != .running,
                  Date() < runningDeadline {
                try await Task.sleep(for: .milliseconds(50))
            }

            let completed = expectation(description: "reattached process cancelled")
            var completionError: String?
            XCTAssertTrue(attachedSupervisor.attach(
                runID: runID,
                nodeID: nodeID,
                harness: .diagnosticSleep,
                onOutput: { _ in },
                onCompletion: { succeeded, error in
                    XCTAssertFalse(succeeded)
                    completionError = error
                    completed.fulfill()
                }
            ))
            attachedSupervisor.cancel(nodeID: nodeID)

            await fulfillment(of: [completed], timeout: 5)
            XCTAssertEqual(completionError, "Cancelled")
            XCTAssertEqual(attachedSupervisor.runs[runID]?.status, .cancelled)
        }
    }
}
