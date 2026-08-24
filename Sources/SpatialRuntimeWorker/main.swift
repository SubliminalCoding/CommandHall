import Darwin
import Foundation
import SpatialRuntimeKit

private enum WorkerFailure: Error {
    case missingManifestPath
    case invalidRunDirectory
}

private func setOwnerOnlyPermissions(_ url: URL, directory: Bool) {
    _ = chmod(url.path, directory ? 0o700 : 0o600)
}

private func writeStatus(_ status: DurableRuntimeStatus, to url: URL) throws {
    let data = try DurableRuntimeCodec.encoder().encode(status)
    try data.write(to: url, options: .atomic)
    setOwnerOnlyPermissions(url, directory: false)
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

do {
    guard CommandLine.arguments.count == 2 else { throw WorkerFailure.missingManifestPath }
    let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
    let runDirectoryURL = manifestURL.deletingLastPathComponent()
    guard manifestURL.lastPathComponent == "launch.json" else { throw WorkerFailure.invalidRunDirectory }

    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try DurableRuntimeCodec.decoder().decode(DurableRuntimeManifest.self, from: manifestData)
    #if DEBUG
    let allowDiagnostic = ProcessInfo.processInfo.environment["SPATIAL_RUNTIME_ALLOW_DIAGNOSTIC"] == "1"
    #else
    let allowDiagnostic = false
    #endif
    try manifest.validate(allowDiagnostic: allowDiagnostic)

    let paths = DurableRuntimeRunDirectory(root: runDirectoryURL.deletingLastPathComponent(), runID: manifest.runID)
    guard paths.directory.standardizedFileURL == runDirectoryURL else { throw WorkerFailure.invalidRunDirectory }
    try? FileManager.default.removeItem(at: manifestURL)
    setOwnerOnlyPermissions(runDirectoryURL, directory: true)
    _ = setsid()

    var status = DurableRuntimeStatus(
        runID: manifest.runID,
        nodeID: manifest.nodeID,
        harness: manifest.harness,
        state: .starting,
        workerPID: getpid()
    )
    try writeStatus(status, to: paths.status)

    if !FileManager.default.fileExists(atPath: paths.output.path) {
        FileManager.default.createFile(atPath: paths.output.path, contents: nil)
    }
    setOwnerOnlyPermissions(paths.output, directory: false)
    let outputHandle = try FileHandle(forWritingTo: paths.output)
    try outputHandle.seekToEnd()
    defer { try? outputHandle.close() }

    let process = Process()
    let input = Pipe()
    process.executableURL = URL(fileURLWithPath: manifest.executablePath)
    process.arguments = manifest.arguments
    process.currentDirectoryURL = URL(fileURLWithPath: manifest.workingDirectory)
    process.environment = manifest.environment
    process.standardInput = input
    process.standardOutput = outputHandle
    process.standardError = outputHandle

    do {
        try process.run()
    } catch {
        status.state = .failed
        status.detail = error.localizedDescription
        status.updatedAt = Date()
        try writeStatus(status, to: paths.status)
        exit(1)
    }

    status.state = .running
    status.childPID = process.processIdentifier
    status.updatedAt = Date()
    try writeStatus(status, to: paths.status)

    let goalData = Data(manifest.goal.utf8)
    DispatchQueue.global(qos: .utility).async {
        try? input.fileHandleForWriting.write(contentsOf: goalData)
        try? input.fileHandleForWriting.close()
    }

    let cancellationQueue = DispatchQueue(label: "spatial-runtime-worker.cancel")
    let cancellationTimer = DispatchSource.makeTimerSource(queue: cancellationQueue)
    cancellationTimer.schedule(deadline: .now(), repeating: .milliseconds(200))
    cancellationTimer.setEventHandler {
        guard process.isRunning,
              FileManager.default.fileExists(atPath: paths.cancellationRequest.path) else { return }
        try? FileManager.default.removeItem(at: paths.cancellationRequest)
        process.interrupt()
        cancellationQueue.asyncAfter(deadline: .now() + 2) {
            if process.isRunning { process.terminate() }
        }
    }
    cancellationTimer.resume()
    process.waitUntilExit()
    cancellationTimer.cancel()
    try? outputHandle.synchronize()

    status.exitCode = process.terminationStatus
    status.state = process.terminationReason == .uncaughtSignal && process.terminationStatus == SIGINT
        ? .cancelled
        : (process.terminationStatus == 0 ? .completed : .failed)
    status.updatedAt = Date()
    try writeStatus(status, to: paths.status)
    exit(process.terminationStatus == 0 ? 0 : 1)
} catch {
    fail("spatial-runtime-worker: \(error)")
}
