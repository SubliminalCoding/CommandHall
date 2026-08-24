import Foundation
import XCTest
import SpatialRuntimeKit

final class DurableRuntimeProtocolTests: XCTestCase {
    func testManifestRoundTripsWithoutLosingIdentityOrGoal() throws {
        let manifest = DurableRuntimeManifest(
            runID: UUID(),
            nodeID: UUID(),
            harness: "codex",
            executablePath: "/opt/homebrew/bin/codex",
            arguments: ["exec", "--json", "-"],
            workingDirectory: "/tmp/project",
            environment: ["PATH": "/opt/homebrew/bin:/usr/bin"],
            goal: "Review the workspace",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try DurableRuntimeCodec.encoder().encode(manifest)
        let decoded = try DurableRuntimeCodec.decoder().decode(DurableRuntimeManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
        XCTAssertNoThrow(try decoded.validate())
    }

    func testManifestRejectsArbitraryExecutableEvenWhenHarnessNameLooksValid() {
        let manifest = DurableRuntimeManifest(
            runID: UUID(),
            nodeID: UUID(),
            harness: "codex",
            executablePath: "/bin/sh",
            arguments: [],
            workingDirectory: "/tmp",
            environment: [:],
            goal: "unsafe"
        )

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(error as? DurableRuntimeProtocolError, .executableNotAllowed)
        }
    }

    func testStatusTerminalityIsExplicit() {
        XCTAssertFalse(DurableRuntimeState.preparing.isTerminal)
        XCTAssertFalse(DurableRuntimeState.running.isTerminal)
        XCTAssertTrue(DurableRuntimeState.completed.isTerminal)
        XCTAssertTrue(DurableRuntimeState.failed.isTerminal)
        XCTAssertTrue(DurableRuntimeState.cancelled.isTerminal)
        XCTAssertTrue(DurableRuntimeState.interrupted.isTerminal)
    }

    func testManifestRejectsRelativeWorkingDirectory() {
        let manifest = DurableRuntimeManifest(
            runID: UUID(),
            nodeID: UUID(),
            harness: "codex",
            executablePath: "/opt/homebrew/bin/codex",
            arguments: [],
            workingDirectory: "relative/project",
            environment: [:],
            goal: "review"
        )

        XCTAssertThrowsError(try manifest.validate()) { error in
            XCTAssertEqual(error as? DurableRuntimeProtocolError, .invalidWorkingDirectory)
        }
    }

    func testRunDirectoryUsesExistingWorkspaceRunIdentity() {
        let runID = UUID()
        let paths = DurableRuntimeRunDirectory(root: URL(fileURLWithPath: "/tmp/runtime"), runID: runID)

        XCTAssertEqual(paths.directory.lastPathComponent, runID.uuidString.lowercased())
        XCTAssertEqual(paths.manifest.lastPathComponent, "launch.json")
        XCTAssertEqual(paths.output.lastPathComponent, "output.log")
        XCTAssertEqual(paths.status.lastPathComponent, "status.json")
        XCTAssertEqual(paths.cancellationRequest.lastPathComponent, "cancel")
    }
}
