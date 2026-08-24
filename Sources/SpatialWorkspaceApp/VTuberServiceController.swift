import AppKit
import Foundation

enum VTuberConnectionState: Equatable {
    case stopped
    case checking
    case ready
    case degraded
    case offline

    var label: String {
        switch self {
        case .stopped: "Offline"
        case .checking: "Checking Studio"
        case .ready: "Studio ready"
        case .degraded: "Needs attention"
        case .offline: "Studio unavailable"
        }
    }

    var canShowControls: Bool {
        self == .ready || self == .degraded
    }
}

struct VTuberServiceConfiguration: Equatable {
    var localPort = 5_174

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(localPort)/")!
    }

    var controlsURL: URL {
        URL(string: "?panel=1", relativeTo: baseURL)!.absoluteURL
    }

    var embeddedControlsURL: URL {
        URL(string: "?panel=1&host=spatial", relativeTo: baseURL)!.absoluteURL
    }

    var studioURL: URL {
        URL(string: "?tracker=1", relativeTo: baseURL)!.absoluteURL
    }

    var previewURL: URL {
        URL(string: "?output=1&relay=1&capture=1&preview=1", relativeTo: baseURL)!.absoluteURL
    }

    var healthURL: URL {
        baseURL.appendingPathComponent("api/v1/health")
    }

    var studioApplicationURLs: [URL] {
        [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Quads VTuber Studio.app"),
            URL(fileURLWithPath: "/Applications/Quads VTuber Studio.app")
        ]
    }

    func installedStudioApplicationURL(fileManager: FileManager = .default) -> URL? {
        studioApplicationURLs.first { fileManager.fileExists(atPath: $0.path) }
    }
}

struct VTuberHealthEnvelope: Decodable, Equatable {
    var data: VTuberHealth
}

struct VTuberHealth: Decodable, Equatable {
    struct Camera: Decodable, Equatable {
        var state: String
        var message: String
        var cameraLabel: String?
        var width: Int?
        var height: Int?
    }

    struct Enhancer: Decodable, Equatable {
        var supported: Bool
        var ready: Bool
        var engine: String?
        var processingMs: Double?
    }

    var service: String
    var status: String
    var trackerConnections: Int
    var rendererConnections: Int
    var controlConnections: Int
    var cameraStatus: Camera?
    var streamStatus: String
    var videoRelayStatus: String
    var enhancer: Enhancer?
}

@MainActor
final class VTuberServiceController: ObservableObject {
    @Published private(set) var state: VTuberConnectionState = .stopped
    @Published private(set) var detail = "VTuber Studio runs locally on this Mac"
    @Published private(set) var health: VTuberHealth?
    @Published private(set) var webRevision = 0
    @Published private(set) var stackPoweredOff = false

    let configuration: VTuberServiceConfiguration
    private var monitorTask: Task<Void, Never>?
    private var lastCameraOwnerLaunch = Date.distantPast

    var canLaunchStudio: Bool {
        configuration.installedStudioApplicationURL() != nil
    }

    init(configuration: VTuberServiceConfiguration = VTuberServiceConfiguration()) {
        self.configuration = configuration
    }

    func start() {
        guard monitorTask == nil else { return }
        state = .checking
        detail = "Checking the live camera and renderer relay"
        monitorTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshHealth()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        state = .stopped
        detail = "VTuber controls are paused"
    }

    func reconnect() {
        webRevision += 1
        if monitorTask == nil { start() }
        Task { await refreshHealth() }
    }

    func reloadPage() {
        webRevision += 1
    }

    func openStudioInBrowser() {
        NSWorkspace.shared.open(configuration.previewURL)
    }

    func openControlsInBrowser() {
        NSWorkspace.shared.open(configuration.controlsURL)
    }

    func launchStudio() {
        guard let applicationURL = configuration.installedStudioApplicationURL() else {
            state = .offline
            detail = "Install Quads VTuber Studio on this Mac, then try again"
            return
        }

        if monitorTask == nil { start() }
        state = .checking
        detail = "Starting Quads VTuber Studio and its camera tracker"

        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = false
        openConfiguration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(
            at: applicationURL,
            configuration: openConfiguration
        ) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.state = .offline
                    self.detail = "VTuber Studio could not start: \(error.localizedDescription)"
                    return
                }

                for _ in 0..<20 {
                    await self.refreshHealth()
                    if self.state.canShowControls {
                        self.webRevision += 1
                        return
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }

    /// Stops the whole local VTuber stack — the launchd-supervised studio
    /// server (and its upscaler child), plus the dedicated Chrome renderer —
    /// to free CPU and memory on stream nights that don't need the character.
    func powerOffStack() {
        state = .checking
        detail = "Powering the VTuber stack down"
        Task { @MainActor in
            await Self.runCommand("/bin/launchctl", ["bootout", "gui/\(getuid())/\(Self.studioAgentLabel)"])
            await Self.runCommand("/usr/bin/pkill", ["-f", "user-data-dir=\(NSHomeDirectory())/Library/Application Support/Quads VTuber Studio"])
            await Self.runCommand("/usr/bin/pkill", ["-f", "quads-vtuber-physics/server/studio-server.mjs"])
            await Self.runCommand("/usr/bin/pkill", ["-f", "vtuber-upscaler"])
            stackPoweredOff = true
            state = .offline
            detail = "VTuber stack is powered off to free CPU and memory"
        }
    }

    func powerOnStack() {
        state = .checking
        detail = "Powering the VTuber stack up"
        Task { @MainActor in
            let agentPlist = "\(NSHomeDirectory())/Library/LaunchAgents/\(Self.studioAgentLabel).plist"
            await Self.runCommand("/bin/launchctl", ["bootstrap", "gui/\(getuid())", agentPlist])
            stackPoweredOff = false
            launchStudio()
        }
    }

    private static let studioAgentLabel = "com.quads.vtuber-studio"

    private static func runCommand(_ path: String, _ arguments: [String]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.terminationHandler = { _ in continuation.resume() }
            do { try process.run() } catch { continuation.resume() }
        }
    }

    func refreshHealth() async {
        var request = URLRequest(url: configuration.healthURL)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            let snapshot = try JSONDecoder().decode(VTuberHealthEnvelope.self, from: data).data
            health = snapshot
            ensureCameraOwner(for: snapshot)
            if snapshot.status != "ready" {
                state = .degraded
                detail = "VTuber Studio answered, but is not ready"
            } else if snapshot.cameraStatus?.state != "ready" {
                state = .degraded
                detail = snapshot.cameraStatus?.message ?? "Camera tracking needs attention"
            } else if snapshot.trackerConnections == 0 || snapshot.streamStatus != "live" {
                state = .degraded
                detail = "Opening the background face tracker"
            } else if snapshot.trackerConnections > 1 {
                state = .degraded
                detail = "Close duplicate camera trackers; one owner is required"
            } else {
                state = .ready
                let camera = snapshot.cameraStatus?.cameraLabel ?? "Camera ready"
                detail = "\(camera) · \(snapshot.rendererConnections) output renderer\(snapshot.rendererConnections == 1 ? "" : "s")"
            }
        } catch {
            health = nil
            state = .offline
            detail = "Start Quads VTuber Studio on this Mac, then reconnect"
        }
    }

    private func ensureCameraOwner(for snapshot: VTuberHealth) {
        guard snapshot.status == "ready", snapshot.trackerConnections == 0 else { return }
        guard Date().timeIntervalSince(lastCameraOwnerLaunch) >= 15 else { return }
        lastCameraOwnerLaunch = Date()
        let openConfiguration = NSWorkspace.OpenConfiguration()
        openConfiguration.activates = false
        openConfiguration.addsToRecentItems = false

        if let applicationURL = configuration.installedStudioApplicationURL() {
            openConfiguration.arguments = ["--studio-only"]
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: openConfiguration,
                completionHandler: nil
            )
            return
        }

        guard let chromeURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") else {
            return
        }
        NSWorkspace.shared.open(
            [configuration.studioURL],
            withApplicationAt: chromeURL,
            configuration: openConfiguration
        )
    }
}
