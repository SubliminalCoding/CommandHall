import XCTest
@testable import SpatialWorkspaceApp

final class SparkSessionProbeTests: XCTestCase {
    func testBriefingRedactsRemoteCredentialsAndMarksOutputUntrusted() {
        let snapshot = SparkSessionSnapshot(
            observedAt: Date(timeIntervalSince1970: 1_700_000_000),
            output: "HOST|build-host\nPANE|work\nOPENAI_API_KEY=sk-example-not-a-real-key\nclaude --token example-private-value",
            error: nil,
            timedOut: false
        )

        let briefing = snapshot.briefing

        XCTAssertTrue(briefing.contains("HOST|build-host"))
        XCTAssertTrue(briefing.contains("read-only observation"))
        XCTAssertTrue(briefing.contains("OPENAI_API_KEY=[REDACTED]"))
        XCTAssertTrue(briefing.contains("--token [REDACTED]"))
        XCTAssertFalse(briefing.contains("sk-example-not-a-real-key"))
        XCTAssertFalse(briefing.contains("example-private-value"))
    }

    func testProbeUsesFixedNoninteractiveSSHContract() {
        let arguments = SparkSessionProbe.sshArguments(host: "build-host")

        XCTAssertTrue(arguments.contains("BatchMode=yes"))
        XCTAssertTrue(arguments.contains("ConnectTimeout=4"))
        XCTAssertTrue(arguments.contains("build-host"))
        XCTAssertTrue(arguments.last?.contains("tmux list-panes") == true)
        XCTAssertFalse(arguments.last?.contains("$1") == true)
    }

    func testUnavailableBriefingStatesFailureWithoutInventingSessions() {
        let snapshot = SparkSessionSnapshot(
            observedAt: Date(),
            output: "",
            error: "Host unreachable",
            timedOut: false
        )

        XCTAssertFalse(snapshot.isReachable)
        XCTAssertTrue(snapshot.briefing.contains("Connection: unavailable"))
        XCTAssertTrue(snapshot.briefing.contains("Host unreachable"))
        XCTAssertFalse(snapshot.briefing.contains("PANE|"))
    }

    func testLiveSparkSessionDiscoveryWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_SPARK_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_SPARK_E2E=1 to inspect live Spark sessions through ssh spark")
        }

        let snapshot = await SparkSessionProbe(cacheLifetime: 0).snapshot(forceRefresh: true)

        XCTAssertTrue(snapshot.isReachable, snapshot.error ?? "Spark returned no data")
        XCTAssertTrue(snapshot.output.contains("HOST|"))
        XCTAssertTrue(snapshot.output.contains("TMUX_BEGIN"))
        XCTAssertTrue(snapshot.output.contains("AGENTS_BEGIN"))
        XCTAssertLessThanOrEqual(snapshot.briefing.count, 17_000)
    }
}
