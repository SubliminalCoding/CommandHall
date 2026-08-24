import Foundation

enum HQParticleConnectionState: Equatable {
    case stopped
    case checking
    case startingRemote
    case openingTunnel
    case ready
    case failed(String)

    var label: String {
        switch self {
        case .stopped: "Offline"
        case .checking: "Checking HQ"
        case .startingRemote: "Starting HQ on Spark"
        case .openingTunnel: "Opening the HQ tunnel"
        case .ready: "HQ connected"
        case .failed: "HQ needs attention"
        }
    }
}

struct HQParticleServiceConfiguration: Equatable {
    var sshHost = "spark"
    var localPort = 3_200
    var remotePort = 3_200
    var serviceName = "hq.service"

    var voiceURL: URL {
        URL(string: "http://127.0.0.1:\(localPort)/voice")!
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
            "-o", "ServerAliveInterval=10",
            "-o", "ServerAliveCountMax=3",
            "-L", "127.0.0.1:\(localPort):127.0.0.1:\(remotePort)",
            sshHost,
        ]
    }
}

@MainActor
final class HQParticleServiceController: ObservableObject {
    @Published private(set) var state: HQParticleConnectionState = .stopped
    @Published private(set) var detail = "The original HQ particle field runs on Spark"
    @Published private(set) var webRevision = 0

    let configuration: HQParticleServiceConfiguration

    private var connectionTask: Task<Void, Never>?
    private var monitorTask: Task<Void, Never>?
    private var tunnelProcess: Process?
    private var generation = 0

    init(configuration: HQParticleServiceConfiguration = HQParticleServiceConfiguration()) {
        self.configuration = configuration
    }

    func start() {
        guard connectionTask == nil else { return }
        generation += 1
        let attempt = generation
        state = .checking
        detail = "Checking the existing localhost:3200 connection"
        connectionTask = Task { [weak self] in
            guard let self else { return }
            await self.connect(generation: attempt)
            self.connectionTask = nil
        }
    }

    func stop() {
        generation += 1
        connectionTask?.cancel()
        connectionTask = nil
        monitorTask?.cancel()
        monitorTask = nil
        if tunnelProcess?.isRunning == true {
            tunnelProcess?.terminate()
        }
        tunnelProcess = nil
        state = .stopped
        detail = "The HQ particle connection is paused"
    }

    func reconnect() {
        stop()
        webRevision += 1
        start()
    }

    func reloadPage() {
        webRevision += 1
    }

    private func connect(generation attempt: Int) async {
        if await endpointIsHealthy(), attempt == generation {
            becomeReady("Using the existing secure Spark tunnel")
            return
        }

        state = .startingRemote
        detail = "Starting HQ without disturbing other Spark workloads"
        let startCode = await Self.runSSH(arguments: configuration.remoteStartArguments)
        guard !Task.isCancelled, attempt == generation else { return }
        guard startCode == 0 else {
            fail("Spark did not accept the HQ start request")
            return
        }

        state = .openingTunnel
        detail = "Opening localhost:\(configuration.localPort) to Spark HQ"
        guard launchTunnel(generation: attempt) else { return }

        for _ in 0 ..< 30 {
            guard !Task.isCancelled, attempt == generation else { return }
            if await endpointIsHealthy() {
                becomeReady("HQ voice and particle rendering are connected")
                return
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        fail("The HQ tunnel opened, but the voice room did not answer")
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
            let message = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                guard let self, self.tunnelProcess === process, attempt == self.generation else { return }
                self.tunnelProcess = nil
                self.fail(message.isEmpty ? "The HQ tunnel closed" : message)
            }
        }
        do {
            try process.run()
            tunnelProcess = process
            return true
        } catch {
            fail("The HQ tunnel could not open: \(error.localizedDescription)")
            return false
        }
    }

    private func becomeReady(_ message: String) {
        state = .ready
        detail = message
        webRevision += 1
        startMonitoring()
    }

    private func fail(_ message: String) {
        state = .failed(message)
        detail = message
    }

    private func startMonitoring() {
        monitorTask?.cancel()
        let attempt = generation
        monitorTask = Task { [weak self] in
            while let self, !Task.isCancelled, attempt == self.generation {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled, attempt == self.generation else { return }
                if !(await self.endpointIsHealthy()) {
                    self.fail("HQ stopped answering on localhost:\(self.configuration.localPort)")
                    return
                }
            }
        }
    }

    private func endpointIsHealthy() async -> Bool {
        var request = URLRequest(url: configuration.voiceURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private static func runSSH(arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }
}
