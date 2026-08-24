import Darwin
import Foundation
import SpatialAgentBridgeKit
import SpatialRuntimeKit

enum AgentHarness: String, Codable {
    case claude
    case codex
#if DEBUG
    case diagnostic
    case diagnosticSleep
    case diagnosticEnvironment
    case diagnosticDelayedOutput
#endif
}

enum RuntimeStatus: String {
    case starting
    case running
    case completed
    case failed
    case cancelled
}

struct RuntimeRun: Identifiable {
    let id: UUID
    let nodeID: UUID
    let harness: AgentHarness
    var status: RuntimeStatus
    var processIdentifier: Int32?
    var exitCode: Int32?
}

struct SessionDiagnostic: Equatable {
    var isReady: Bool
    var title: String
    var detail: String
    var executablePath: String?
    var checkedAt = Date()
}

final class UTF8LineDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    func append(_ data: Data) -> String? {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        var complete = Data()
        while let newline = buffer.firstIndex(of: 0x0A) {
            let end = buffer.index(after: newline)
            complete.append(buffer[..<end])
            buffer.removeSubrange(..<end)
        }
        return complete.isEmpty ? nil : String(decoding: complete, as: UTF8.self)
    }

    func finish(with data: Data = Data()) -> String? {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        guard !buffer.isEmpty else { return nil }
        defer { buffer.removeAll(keepingCapacity: false) }
        return String(decoding: buffer, as: UTF8.self)
    }
}

@MainActor
final class RuntimeSupervisor: ObservableObject {
    @Published private(set) var runs: [UUID: RuntimeRun] = [:]

    private var processesByNode: [UUID: Process] = [:]
    private var durableRunByNode: [UUID: UUID] = [:]
    private var durableObservationTasks: [UUID: Task<Void, Never>] = [:]
    private var durableCredentials: [UUID: AgentBridgeCredential] = [:]
    private let agentBridge: any SpatialAgentBridgeSessionProviding
    private let durableRoot: URL
    private let workerURL: URL?
    private let durableHarnesses: Set<AgentHarness>

    init(
        agentBridge: any SpatialAgentBridgeSessionProviding = SpatialAgentBridgeRuntime.shared,
        durableRoot: URL? = nil,
        workerURL: URL? = nil,
        durableHarnesses: Set<AgentHarness> = [.claude, .codex]
    ) {
        self.agentBridge = agentBridge
        self.durableRoot = durableRoot ?? Self.defaultDurableRoot()
        self.workerURL = workerURL ?? Self.defaultWorkerURL()
        self.durableHarnesses = durableHarnesses
    }

    @discardableResult
    func start(
        runID requestedRunID: UUID? = nil,
        nodeID: UUID,
        harness: AgentHarness,
        goal: String,
        sessionID: String? = nil,
        workingDirectory: URL,
        authorityProfile: SessionAuthorityProfile = AgentCapabilitySettings.defaultProfile,
        modelID: String? = nil,
        onOutput: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String?) -> Void
    ) -> UUID? {
        guard processesByNode[nodeID] == nil else {
            onCompletion(false, "This agent is already running")
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            onCompletion(false, "Working folder does not exist or is not a directory")
            return nil
        }
        guard let invocation = Self.invocation(
            for: harness,
            sessionID: sessionID,
            workingDirectory: workingDirectory,
            authorityProfile: authorityProfile,
            modelID: modelID
        ) else {
            onCompletion(false, "\(harness.rawValue.capitalized) is not installed or configured")
            return nil
        }

        let runID = requestedRunID ?? UUID()
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let outputDecoder = UTF8LineDecoder()
        let bridgeCredential = try? agentBridge.issueSession(
            nodeID: nodeID,
            provider: harness.rawValue,
            scopes: AgentBridgeSessionRegistry.allAudioScopes
        )
        _ = Darwin.fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = invocation.executable
        process.arguments = invocation.arguments
        process.currentDirectoryURL = workingDirectory
        let bridgeEnvironment = bridgeCredential.map { agentBridge.environment(for: $0) } ?? [:]
        var processEnvironment = SpatialAgentBridgeRuntime.sanitizedChildEnvironment(
            AgentCapabilitySettings.processEnvironment(for: harness),
            bridgeEnvironment: bridgeEnvironment
        )
        if bridgeCredential != nil {
            if let cliPath = processEnvironment["SPATIAL_AGENT_CLI"] {
                let cliDirectory = URL(fileURLWithPath: cliPath).deletingLastPathComponent().path
                processEnvironment["PATH"] = "\(cliDirectory):\(processEnvironment["PATH"] ?? "")"
            }
        }

        if durableHarnesses.contains(harness),
           let workerURL,
           FileManager.default.isExecutableFile(atPath: workerURL.path) {
            return startDurable(
                runID: runID,
                nodeID: nodeID,
                harness: harness,
                goal: goal,
                workingDirectory: workingDirectory,
                invocation: invocation,
                environment: processEnvironment,
                bridgeCredential: bridgeCredential,
                workerURL: workerURL,
                onOutput: onOutput,
                onCompletion: onCompletion
            )
        }
        process.environment = processEnvironment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        runs[runID] = RuntimeRun(id: runID, nodeID: nodeID, harness: harness, status: .starting)
        processesByNode[nodeID] = process

        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = outputDecoder.append(data) else { return }
            Task { @MainActor in onOutput(text) }
        }

        process.terminationHandler = { [weak self] process in
            output.fileHandleForReading.readabilityHandler = nil
            let remaining = output.fileHandleForReading.readDataToEndOfFile()
            Task { @MainActor in
                if let text = outputDecoder.finish(with: remaining) {
                    onOutput(text)
                }
                guard let self else { return }
                self.agentBridge.revoke(bridgeCredential)
                let wasCancelled = self.runs[runID]?.status == .cancelled
                self.processesByNode[nodeID] = nil
                self.runs[runID]?.exitCode = process.terminationStatus
                self.runs[runID]?.status = wasCancelled ? .cancelled : (process.terminationStatus == 0 ? .completed : .failed)
                onCompletion(process.terminationStatus == 0 && !wasCancelled, wasCancelled ? "Cancelled" : nil)
            }
        }

        do {
            try process.run()
            runs[runID]?.status = .running
            runs[runID]?.processIdentifier = process.processIdentifier
            let goalData = Data(goal.utf8)
            DispatchQueue.global(qos: .utility).async {
                do {
                    try input.fileHandleForWriting.write(contentsOf: goalData)
                    try input.fileHandleForWriting.close()
                } catch {
                    try? input.fileHandleForWriting.close()
                }
            }
            return runID
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            agentBridge.revoke(bridgeCredential)
            processesByNode[nodeID] = nil
            runs[runID]?.status = .failed
            onCompletion(false, error.localizedDescription)
            return nil
        }
    }

    func cancel(nodeID: UUID) {
        if let runID = durableRunByNode[nodeID] {
            let paths = DurableRuntimeRunDirectory(root: durableRoot, runID: runID)
            FileManager.default.createFile(atPath: paths.cancellationRequest.path, contents: Data())
            _ = chmod(paths.cancellationRequest.path, 0o600)
            runs[runID]?.status = .cancelled
            return
        }
        guard let process = processesByNode[nodeID] else { return }
        if let runID = runs.first(where: { $0.value.nodeID == nodeID && $0.value.status == .running })?.key {
            runs[runID]?.status = .cancelled
        }
        process.interrupt()
        Task { @MainActor [weak self, weak process] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, let process, process.isRunning, self.processesByNode[nodeID] === process else { return }
            process.terminate()
        }
    }

    @discardableResult
    func attach(
        runID: UUID,
        nodeID: UUID,
        harness: AgentHarness,
        onOutput: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String?) -> Void
    ) -> Bool {
        guard durableObservationTasks[runID] == nil,
              let status = durableStatus(runID: runID, nodeID: nodeID),
              status.harness == harness.rawValue else { return false }
        if !status.state.isTerminal, !Self.processIsAlive(status.workerPID) { return false }

        runs[runID] = RuntimeRun(
            id: runID,
            nodeID: nodeID,
            harness: harness,
            status: status.state == .running ? .running : .starting,
            processIdentifier: status.workerPID,
            exitCode: status.exitCode
        )
        durableRunByNode[nodeID] = runID
        observeDurableRun(
            runID: runID,
            nodeID: nodeID,
            onOutput: onOutput,
            onCompletion: onCompletion
        )
        return true
    }

    func durableStatus(runID: UUID, nodeID: UUID) -> DurableRuntimeStatus? {
        let paths = DurableRuntimeRunDirectory(root: durableRoot, runID: runID)
        guard let data = try? Data(contentsOf: paths.status),
              let status = try? DurableRuntimeCodec.decoder().decode(DurableRuntimeStatus.self, from: data),
              status.schemaVersion == DurableRuntimeStatus.schemaVersion,
              status.runID == runID,
              status.nodeID == nodeID else { return nil }
        return status
    }

    private func startDurable(
        runID: UUID,
        nodeID: UUID,
        harness: AgentHarness,
        goal: String,
        workingDirectory: URL,
        invocation: (executable: URL, arguments: [String]),
        environment: [String: String],
        bridgeCredential: AgentBridgeCredential?,
        workerURL: URL,
        onOutput: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String?) -> Void
    ) -> UUID? {
        let paths = DurableRuntimeRunDirectory(root: durableRoot, runID: runID)
        do {
            try FileManager.default.createDirectory(
                at: paths.directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            _ = chmod(durableRoot.path, 0o700)
            _ = chmod(paths.directory.path, 0o700)
            let manifest = DurableRuntimeManifest(
                runID: runID,
                nodeID: nodeID,
                harness: harness.rawValue,
                executablePath: invocation.executable.path,
                arguments: invocation.arguments,
                workingDirectory: workingDirectory.path,
                environment: environment,
                goal: goal
            )
            try DurableRuntimeCodec.encoder().encode(manifest).write(to: paths.manifest, options: .atomic)
            _ = chmod(paths.manifest.path, 0o600)

            let worker = Process()
            worker.executableURL = workerURL
            worker.arguments = [paths.manifest.path]
            worker.currentDirectoryURL = workingDirectory
            let nullOutput = FileHandle(forWritingAtPath: "/dev/null")
            worker.standardOutput = nullOutput
            worker.standardError = nullOutput

            runs[runID] = RuntimeRun(id: runID, nodeID: nodeID, harness: harness, status: .starting)
            processesByNode[nodeID] = worker
            durableRunByNode[nodeID] = runID
            if let bridgeCredential { durableCredentials[runID] = bridgeCredential }
            try worker.run()
            runs[runID]?.status = .running
            runs[runID]?.processIdentifier = worker.processIdentifier
            observeDurableRun(
                runID: runID,
                nodeID: nodeID,
                onOutput: onOutput,
                onCompletion: onCompletion
            )
            return runID
        } catch {
            try? FileManager.default.removeItem(at: paths.manifest)
            agentBridge.revoke(bridgeCredential)
            processesByNode[nodeID] = nil
            durableRunByNode[nodeID] = nil
            durableCredentials[runID] = nil
            runs[runID]?.status = .failed
            onCompletion(false, error.localizedDescription)
            return nil
        }
    }

    private func observeDurableRun(
        runID: UUID,
        nodeID: UUID,
        onOutput: @escaping @MainActor (String) -> Void,
        onCompletion: @escaping @MainActor (Bool, String?) -> Void
    ) {
        let paths = DurableRuntimeRunDirectory(root: durableRoot, runID: runID)
        durableObservationTasks[runID]?.cancel()
        durableObservationTasks[runID] = Task { @MainActor [weak self] in
            var outputOffset: UInt64 = 0
            while !Task.isCancelled {
                if let handle = try? FileHandle(forReadingFrom: paths.output) {
                    try? handle.seek(toOffset: outputOffset)
                    if let data = try? handle.readToEnd(), !data.isEmpty {
                        outputOffset += UInt64(data.count)
                        onOutput(String(decoding: data, as: UTF8.self))
                    }
                    try? handle.close()
                }

                if let self,
                   let status = self.durableStatus(runID: runID, nodeID: nodeID),
                   status.state.isTerminal {
                    self.runs[runID]?.exitCode = status.exitCode
                    self.runs[runID]?.status = status.state == .completed
                        ? .completed
                        : (status.state == .cancelled ? .cancelled : .failed)
                    self.processesByNode[nodeID] = nil
                    self.durableRunByNode[nodeID] = nil
                    self.durableObservationTasks[runID] = nil
                    self.agentBridge.revoke(self.durableCredentials.removeValue(forKey: runID))
                    let succeeded = status.state == .completed && status.exitCode == 0
                    let error = succeeded ? nil : (status.state == .cancelled ? "Cancelled" : (status.detail ?? "Agent process failed"))
                    onCompletion(succeeded, error)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private static func defaultDurableRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpatialWorkspace/runtime/v1", isDirectory: true)
    }

    private static func defaultWorkerURL() -> URL? {
        guard let executable = Bundle.main.executableURL else { return nil }
        let candidate = executable.deletingLastPathComponent().appendingPathComponent("spatial-runtime-worker")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }

    static func diagnostic(for harness: AgentHarness, workingDirectory: URL) -> SessionDiagnostic {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: workingDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return SessionDiagnostic(
                isReady: false,
                title: "Working folder unavailable",
                detail: workingDirectory.path,
                executablePath: nil
            )
        }
#if DEBUG
        if harness == .diagnostic || harness == .diagnosticSleep || harness == .diagnosticEnvironment || harness == .diagnosticDelayedOutput {
            return SessionDiagnostic(isReady: true, title: "Diagnostic harness ready", detail: workingDirectory.path, executablePath: "/bin/cat")
        }
#endif
        let executableName = harness == .codex ? "codex" : "claude"
        guard let executable = resolveExecutable(named: executableName) else {
            return SessionDiagnostic(
                isReady: false,
                title: "\(executableName.capitalized) unavailable",
                detail: "Install or configure \(executableName) before starting this session.",
                executablePath: nil
            )
        }
        return SessionDiagnostic(
            isReady: true,
            title: "\(executableName.capitalized) ready",
            detail: "Working in \(workingDirectory.path)",
            executablePath: executable.path
        )
    }

    private static func invocation(
        for harness: AgentHarness,
        sessionID: String?,
        workingDirectory: URL,
        authorityProfile: SessionAuthorityProfile,
        modelID: String?
    ) -> (executable: URL, arguments: [String])? {
        let accessArguments = authorityProfile == .unrestricted
            ? AgentFilesystemAccess.commandArguments(for: harness, root: AgentFilesystemAccess.additionalRoot)
            : []
        let capabilityArguments = AgentCapabilitySettings.commandArguments(for: harness, profile: authorityProfile)
        let selectedModelArguments = Self.modelArguments(for: modelID)
        switch harness {
        case .codex:
            guard let executable = resolveExecutable(named: "codex") else { return nil }
            let baseArguments = ["exec"] + selectedModelArguments + capabilityArguments + accessArguments + ["--skip-git-repo-check", "--json"]
            if let sessionID {
                return (executable, baseArguments + ["resume", sessionID, "-"])
            }
            return (executable, baseArguments + ["-C", workingDirectory.path, "-"])
        case .claude:
            guard let executable = resolveExecutable(named: "claude") else { return nil }
            var arguments = ["-p", "--verbose", "--output-format", "stream-json", "--input-format", "text"] + selectedModelArguments + capabilityArguments + accessArguments
            if let sessionID { arguments += ["--resume", sessionID] }
            return (executable, arguments)
#if DEBUG
        case .diagnostic:
            return (URL(fileURLWithPath: "/bin/cat"), [])
        case .diagnosticSleep:
            return (URL(fileURLWithPath: "/bin/sleep"), ["30"])
        case .diagnosticEnvironment:
            return (URL(fileURLWithPath: "/usr/bin/env"), [])
        case .diagnosticDelayedOutput:
            return (URL(fileURLWithPath: "/bin/sh"), ["-c", "sleep 0.35; cat"])
#endif
        }
    }

    static func modelArguments(for modelID: String?) -> [String] {
        guard let modelID = AgentModelCatalog.normalizedModelID(modelID) else { return [] }
        return ["--model", modelID]
    }

    private static func resolveExecutable(named name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            NSString(string: "~/.local/bin/\(name)").expandingTildeInPath,
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }
}
