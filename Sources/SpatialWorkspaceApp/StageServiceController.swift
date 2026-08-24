import AppKit
import Foundation

enum StageConnectionState: Equatable {
    case stopped
    case startingRemote
    case openingTunnel
    case waitingForStage
    case ready
    case degraded
    case failed(String)

    var label: String {
        switch self {
        case .stopped: "Offline"
        case .startingRemote: "Starting Spark"
        case .openingTunnel: "Opening tunnel"
        case .waitingForStage: "Waiting for Stage"
        case .ready: "Live"
        case .degraded: "Reconnecting"
        case .failed: "Needs attention"
        }
    }
}

struct StageServiceConfiguration: Equatable {
    var sshHost = AgentCapabilitySettings.sparkHost
    var localPort = 55_173
    var remoteWebPort = 5_173
    var serviceName = "spatial-stage.service"
    var remoteSessionIngestScript = "the-stage/scripts/spatial-workspace-ingest.mjs"

    var operatorURL: URL {
        URL(string: "http://127.0.0.1:\(localPort)/")!
    }

    var healthURL: URL {
        operatorURL.appendingPathComponent("api/health")
    }

    var obsSourceURL: String {
        "http://127.0.0.1:\(remoteWebPort)/?overlay=1"
    }

    var remoteStartArguments: [String] {
        [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            sshHost,
            "systemctl", "--user", "start", serviceName,
        ]
    }

    var tunnelArguments: [String] {
        [
            "-N", "-T",
            "-o", "ControlMaster=no",
            "-o", "ControlPath=none",
            "-o", "ControlPersist=no",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=2",
            "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remoteWebPort)",
            sshHost,
        ]
    }

    var remoteSessionIngestArguments: [String] {
        [
            "-T",
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=5",
            sshHost,
            "/usr/bin/node", remoteSessionIngestScript,
        ]
    }
}

@MainActor
final class StageServiceController: ObservableObject {
    @Published private(set) var state: StageConnectionState = .stopped
    @Published private(set) var detail = "The Stage runs on Spark"
    @Published private(set) var webRevision = 0

    let configuration: StageServiceConfiguration

    private var tunnelProcess: Process?
    private var startTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var sessionPublishTask: Task<Void, Never>?
    private var selectedLocalSession: StageLocalPublishedSession?
    private var selectedLocalSessionRevision = 0
    private var lastSessionPublishAt: Date?
    private var generation = 0
    private var stopping = false

    init(configuration: StageServiceConfiguration = StageServiceConfiguration()) {
        self.configuration = configuration
    }

    func start() {
        guard startTask == nil else { return }
        if tunnelProcess?.isRunning == true { return }

        stopping = false
        generation += 1
        let attempt = generation
        state = .startingRemote
        detail = "Checking the Stage service on Spark"
        reconnectTask?.cancel()
        reconnectTask = nil

        startTask = Task { [weak self] in
            guard let self else { return }
            await self.connect(generation: attempt)
            self.startTask = nil
        }
    }

    func reconnect() {
        stopTunnel()
        state = .stopped
        detail = "Reconnecting to Spark"
        start()
    }

    func stop() {
        stopping = true
        generation += 1
        startTask?.cancel()
        startTask = nil
        healthTask?.cancel()
        healthTask = nil
        reconnectTask?.cancel()
        reconnectTask = nil
        sessionPublishTask?.cancel()
        sessionPublishTask = nil
        stopTunnel()
        state = .stopped
        detail = "The Stage is disconnected"
    }

    func selectLocalSession(
        _ session: StageLocalPublishedSession?,
        workspace: WorkspaceDocument,
        now: Date = Date()
    ) {
        let changed = selectedLocalSession?.id != session?.id
        selectedLocalSession = session
        if changed { selectedLocalSessionRevision &+= 1 }
        publishLocalSessions(workspace: workspace, now: now, force: changed)
    }

    func publishLocalSessions(
        workspace: WorkspaceDocument,
        now: Date = Date(),
        force: Bool = false
    ) {
        guard state == .ready, sessionPublishTask == nil else { return }
        if !force, let lastSessionPublishAt, now.timeIntervalSince(lastSessionPublishAt) < 15 { return }

        let payload: Data
        do {
            payload = try StageLocalSessionSnapshot(
                workspace: workspace,
                selectedSession: selectedLocalSession,
                now: now
            ).encoded()
        } catch {
            detail = "Mac session snapshot could not be encoded"
            return
        }

        let arguments = configuration.remoteSessionIngestArguments
        let selectionRevision = selectedLocalSessionRevision
        sessionPublishTask = Task { [weak self] in
            let succeeded = await Self.run(
                executable: "/usr/bin/ssh",
                arguments: arguments,
                standardInput: payload
            ) == 0
            guard let self, !Task.isCancelled else { return }
            self.lastSessionPublishAt = now
            self.sessionPublishTask = nil
            if self.selectedLocalSessionRevision != selectionRevision {
                self.lastSessionPublishAt = nil
            }
            if !succeeded, self.state == .ready {
                self.detail = "Stage connected; Mac session feed is retrying"
            }
        }
    }

    func reloadPage() {
        webRevision += 1
    }

    func openInBrowser() {
        NSWorkspace.shared.open(configuration.operatorURL)
    }

    func copyOBSSource() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration.obsSourceURL, forType: .string)
        detail = "OBS source copied for Spark"
    }

    private func connect(generation attempt: Int) async {
        if await endpointIsHealthy(), attempt == generation {
            becomeReady(detail: "Autonomous watch connected through a local tunnel")
            return
        }

        let exitCode = await Self.run(
            executable: "/usr/bin/ssh",
            arguments: configuration.remoteStartArguments
        )
        guard !Task.isCancelled, attempt == generation else { return }
        guard exitCode == 0 else {
            fail("Spark could not start The Stage")
            return
        }

        state = .openingTunnel
        detail = "Securing a loopback connection to Spark"
        guard launchTunnel(generation: attempt) else { return }

        state = .waitingForStage
        detail = "The Stage is warming up"
        for _ in 0 ..< 30 {
            guard !Task.isCancelled, attempt == generation else { return }
            if await endpointIsHealthy() {
                becomeReady(detail: "Autonomous watch connected to Spark")
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        fail("The tunnel opened, but The Stage did not answer")
    }

    private func launchTunnel(generation attempt: Int) -> Bool {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = configuration.tunnelArguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe
        process.terminationHandler = { [weak self, weak process] _ in
            let errorText = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                guard let self, self.tunnelProcess === process else { return }
                self.tunnelProcess = nil
                guard !self.stopping, attempt == self.generation else { return }
                self.state = .degraded
                self.detail = errorText.isEmpty ? "The Spark tunnel closed" : errorText
                self.scheduleReconnect()
            }
        }

        do {
            try process.run()
            tunnelProcess = process
            return true
        } catch {
            fail("The Spark tunnel could not open: \(error.localizedDescription)")
            return false
        }
    }

    private func becomeReady(detail readyDetail: String) {
        state = .ready
        detail = readyDetail
        webRevision += 1
        beginHealthMonitoring()
    }

    private func beginHealthMonitoring() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            var failures = 0
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                if await self.endpointIsHealthy() {
                    failures = 0
                    if self.state == .degraded {
                        self.state = .ready
                        self.detail = "Autonomous watch reconnected to Spark"
                        self.webRevision += 1
                    }
                } else {
                    failures += 1
                    if failures >= 2 {
                        self.state = .degraded
                        self.detail = "The Stage stopped answering"
                        self.stopTunnel()
                        self.scheduleReconnect()
                        return
                    }
                }
            }
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil, !stopping else { return }
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled, !self.stopping else { return }
            self.reconnectTask = nil
            self.start()
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        detail = message
        stopTunnel()
    }

    private func stopTunnel() {
        guard let process = tunnelProcess else { return }
        tunnelProcess = nil
        if process.isRunning { process.terminate() }
    }

    private func endpointIsHealthy() async -> Bool {
        var request = URLRequest(url: configuration.healthURL)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let body = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return body?["ok"] as? Bool == true
        } catch {
            return false
        }
    }

    nonisolated private static func run(executable: String, arguments: [String]) async -> Int32 {
        await run(executable: executable, arguments: arguments, standardInput: nil)
    }

    nonisolated private static func run(
        executable: String,
        arguments: [String],
        standardInput: Data?
    ) async -> Int32 {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let inputPipe = standardInput == nil ? nil : Pipe()
            if let inputPipe {
                process.standardInput = inputPipe
            } else {
                process.standardInput = FileHandle.nullDevice
            }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                if let standardInput, let inputPipe {
                    inputPipe.fileHandleForWriting.write(standardInput)
                    try? inputPipe.fileHandleForWriting.close()
                }
                process.waitUntilExit()
                return process.terminationStatus
            } catch {
                return -1
            }
        }.value
    }
}
