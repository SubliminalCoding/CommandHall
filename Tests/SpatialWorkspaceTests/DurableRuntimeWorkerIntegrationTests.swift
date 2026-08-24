import Darwin
import Foundation
import XCTest
import SpatialRuntimeKit

final class DurableRuntimeWorkerIntegrationTests: XCTestCase {
    func testDetachedWorkerConsumesManifestAndRecordsRealCompletion() throws {
        guard ProcessInfo.processInfo.environment["RUN_DURABLE_WORKER_E2E"] == "1" else {
            throw XCTSkip("Set RUN_DURABLE_WORKER_E2E=1 after building spatial-runtime-worker")
        }

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let worker = projectRoot.appendingPathComponent(".build/debug/spatial-runtime-worker")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: worker.path), worker.path)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-runtime-tests-\(UUID().uuidString)", isDirectory: true)
        let runID = UUID()
        let nodeID = UUID()
        let paths = DurableRuntimeRunDirectory(root: root, runID: runID)
        try FileManager.default.createDirectory(at: paths.directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = chmod(root.path, 0o700)
        _ = chmod(paths.directory.path, 0o700)

        let manifest = DurableRuntimeManifest(
            runID: runID,
            nodeID: nodeID,
            harness: "diagnostic-detached",
            executablePath: "/bin/sh",
            arguments: ["-c", "sleep 0.35; printf 'DURABLE_WORKER_OK\\n'"],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            environment: ["PATH": "/usr/bin:/bin"],
            goal: ""
        )
        try DurableRuntimeCodec.encoder().encode(manifest).write(to: paths.manifest, options: .atomic)
        _ = chmod(paths.manifest.path, 0o600)

        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = ["-c", "exec \"$SPATIAL_TEST_WORKER\" \"$SPATIAL_TEST_MANIFEST\" >/dev/null 2>&1 &"]
        var environment = ProcessInfo.processInfo.environment
        environment["SPATIAL_RUNTIME_ALLOW_DIAGNOSTIC"] = "1"
        environment["SPATIAL_TEST_WORKER"] = worker.path
        environment["SPATIAL_TEST_MANIFEST"] = paths.manifest.path
        launcher.environment = environment
        try launcher.run()
        launcher.waitUntilExit()
        XCTAssertEqual(launcher.terminationStatus, 0)

        let deadline = Date().addingTimeInterval(5)
        var status: DurableRuntimeStatus?
        while Date() < deadline {
            if let data = try? Data(contentsOf: paths.status),
               let candidate = try? DurableRuntimeCodec.decoder().decode(DurableRuntimeStatus.self, from: data),
               candidate.state.isTerminal {
                status = candidate
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        let completed = try XCTUnwrap(status)
        XCTAssertEqual(completed.runID, runID)
        XCTAssertEqual(completed.nodeID, nodeID)
        XCTAssertEqual(completed.state, .completed)
        XCTAssertEqual(completed.exitCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.manifest.path))
        XCTAssertEqual(try String(contentsOf: paths.output, encoding: .utf8), "DURABLE_WORKER_OK\n")

        let attributes = try FileManager.default.attributesOfItem(atPath: paths.status.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }
}
