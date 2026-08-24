import XCTest
@testable import SpatialWorkspaceApp

final class StageSessionBridgeTests: XCTestCase {
    func testSnapshotEventCountingIsStableAndBenchmarkable() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mixedLineEndings = "alpha\nbeta\r\ngamma\rdelta\n"
        let proofNode = WorkspaceNode(
            kind: .agent,
            title: "Proof",
            subtitle: "Codex",
            position: .zero,
            size: CGSize(width: 400, height: 300),
            zIndex: 1,
            provider: .codex,
            activityLog: mixedLineEndings
        )
        let proofWorkspace = WorkspaceDocument(
            id: UUID(),
            name: "Proof",
            theme: "nocturne",
            rootPath: nil,
            camera: CameraTransform(),
            nodes: [proofNode]
        )
        let proofCount = StageLocalSessionSnapshot(workspace: proofWorkspace, now: now).sessions[0].eventCount
        XCTAssertEqual(proofCount, 3, "CRLF is one grapheme and does not match a standalone newline Character")
        print("STAGE_EVENT_COUNT_GOLDEN=\(proofCount)")

        guard ProcessInfo.processInfo.environment["RUN_STAGE_SNAPSHOT_BENCHMARK"] == "1" else { return }
        let activityLog = String(repeating: "event\n", count: 40_000)
        let nodes = (0 ..< 8).map { index in
            WorkspaceNode(
                kind: .agent,
                title: "Agent \(index)",
                subtitle: "Codex",
                position: .zero,
                size: CGSize(width: 400, height: 300),
                zIndex: index,
                provider: .codex,
                activityLog: activityLog
            )
        }
        let workspace = WorkspaceDocument(
            id: UUID(),
            name: "Benchmark",
            theme: "nocturne",
            rootPath: nil,
            camera: CameraTransform(),
            nodes: nodes
        )
        let clock = ContinuousClock()
        var samples: [Double] = []
        var checksum = 0
        for _ in 0 ..< 20 {
            let elapsed = clock.measure {
                checksum &+= StageLocalSessionSnapshot(workspace: workspace, now: now)
                    .sessions.reduce(0) { $0 + $1.eventCount }
            }
            let components = elapsed.components
            samples.append(
                Double(components.seconds) * 1_000
                    + Double(components.attoseconds) / 1_000_000_000_000_000
            )
        }
        samples.sort()
        let percentile: (Double) -> Double = { percentile in
            samples[min(samples.count - 1, Int(Double(samples.count - 1) * percentile))]
        }
        print(
            String(
                format: "STAGE_SNAPSHOT_PERF_MS p50=%.3f p95=%.3f p99=%.3f checksum=%d",
                percentile(0.50),
                percentile(0.95),
                percentile(0.99),
                checksum
            )
        )
        XCTAssertEqual(checksum, 6_400_160)
    }

    func testSnapshotIncludesOnlySessionPresenceAndNoPrivateContent() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let nodes = [
            WorkspaceNode(
                kind: .agent,
                title: "Nova",
                subtitle: "Codex",
                position: .zero,
                size: CGSize(width: 400, height: 300),
                zIndex: 1,
                provider: .codex,
                runtimeState: .working,
                runtimeUpdatedAt: now,
                activityLog: "private prompt\n/Users/example/secret"
            ),
            WorkspaceNode(
                kind: .browser,
                title: "Browser 6",
                subtitle: "Browser",
                position: .zero,
                size: CGSize(width: 400, height: 300),
                zIndex: 2,
                url: "https://youtube.com/watch?v=secret",
                provider: .browser
            ),
            WorkspaceNode(
                kind: .note,
                title: "Private note",
                subtitle: "Note",
                position: .zero,
                size: CGSize(width: 400, height: 300),
                zIndex: 3,
                content: "do not publish",
                provider: .note
            ),
        ]
        let workspace = WorkspaceDocument(
            id: UUID(), name: "Main", theme: "nocturne", rootPath: "/Users/example/Projects/private",
            camera: CameraTransform(), nodes: nodes
        )

        let snapshot = StageLocalSessionSnapshot(workspace: workspace, now: now)
        let json = String(decoding: try snapshot.encoded(), as: UTF8.self)

        XCTAssertEqual(snapshot.source, "mac-mini")
        XCTAssertEqual(snapshot.sessions.count, 1)
        XCTAssertEqual(snapshot.sessions.first?.title, "Nova")
        XCTAssertEqual(snapshot.sessions.first?.provider, "codex")
        XCTAssertEqual(snapshot.sessions.first?.runtimeState, "working")
        XCTAssertFalse(json.contains("private prompt"))
        XCTAssertFalse(json.contains("/Users/example"))
        XCTAssertFalse(json.contains("youtube.com"))
        XCTAssertFalse(json.contains("do not publish"))
    }

    func testSelectedStandaloneTerminalIsIncludedAndIdentified() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let workspace = WorkspaceDocument(
            id: UUID(), name: "Main", theme: "nocturne", rootPath: nil,
            camera: CameraTransform(), nodes: []
        )
        let selected = StageLocalPublishedSession(
            id: StageLocalPublishedSession.standaloneID(for: "/dev/ttys002"),
            title: "Release terminal",
            provider: "shell",
            runtimeState: "attached",
            sessionId: nil,
            lastActivityAt: now,
            eventCount: 12,
            minimized: false,
            activitySummary: "The selected terminal is building"
        )

        let snapshot = StageLocalSessionSnapshot(
            workspace: workspace,
            selectedSession: selected,
            now: now
        )

        XCTAssertEqual(snapshot.selectedSessionId, "terminal-app-dev-ttys002")
        XCTAssertEqual(snapshot.sessions.first?.title, "Release terminal")
        XCTAssertEqual(snapshot.sessions.first?.eventCount, 12)
        XCTAssertEqual(snapshot.sessions.first?.activitySummary, "The selected terminal is building")
    }

    func testConfigurationUsesBatchSSHAndDedicatedRemoteHelper() {
        let config = StageServiceConfiguration()
        XCTAssertTrue(config.remoteSessionIngestArguments.contains("BatchMode=yes"))
        XCTAssertTrue(config.remoteSessionIngestArguments.contains("/usr/bin/node"))
        XCTAssertTrue(config.remoteSessionIngestArguments.contains(config.remoteSessionIngestScript))
        XCTAssertFalse(config.remoteSessionIngestArguments.joined(separator: " ").contains("sh -c"))
    }
}
