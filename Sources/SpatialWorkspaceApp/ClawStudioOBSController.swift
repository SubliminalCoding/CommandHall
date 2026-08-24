import AppKit
import Foundation

enum ClawStudioOBSConnectionState: Equatable {
    case stopped
    case checking
    case connected
    case offline
    case failed

    var label: String {
        switch self {
        case .stopped: "Offline"
        case .checking: "Checking ClawStudio"
        case .connected: "OBS connected"
        case .offline: "OBS offline"
        case .failed: "ClawStudio unavailable"
        }
    }
}

struct ClawStudioOBSConfiguration: Equatable {
    var localPort = 5_274
    var projectURL = ProcessInfo.processInfo.environment["COMMANDHALL_CLAWSTUDIO_PATH"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/ClawStudio", isDirectory: true)

    var baseURL: URL {
        URL(string: "http://127.0.0.1:\(localPort)/")!
    }

    func apiURL(_ path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!.absoluteURL
    }
}

struct ClawStudioOBSVersion: Decodable, Equatable {
    var obsVersion: String
    var obsWebSocketVersion: String
    var rpcVersion: Int
}

struct ClawStudioOBSRecording: Decodable, Equatable {
    var active: Bool
    var paused: Bool
    var durationMs: Double
    var timecode: String
    var productionId: String?
    var recoveryToken: String?
    var stale: Bool?
}

struct ClawStudioOBSStatus: Decodable, Equatable {
    var state: String
    var configured: Bool
    var version: ClawStudioOBSVersion?
    var recording: ClawStudioOBSRecording?
    var message: String?
    var warning: String?
}

struct ClawStudioOBSScene: Decodable, Equatable, Identifiable {
    var name: String
    var uuid: String
    var identityKind: String?
    var index: Int?

    var id: String { uuid }
}

struct ClawStudioOBSStream: Decodable, Equatable {
    var active: Bool
    var reconnecting: Bool
    var durationMs: Double
    var timecode: String
    var productionId: String?
}

enum ClawStudioOBSCameraCorner: String, Codable, CaseIterable, Identifiable {
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
    var symbol: String {
        switch self {
        case .topLeft: "arrow.up.left"
        case .topRight: "arrow.up.right"
        case .bottomLeft: "arrow.down.left"
        case .bottomRight: "arrow.down.right"
        }
    }
}

enum ClawStudioOBSCameraSize: String, Codable, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum ClawStudioOBSCameraMode: String, Codable, CaseIterable, Identifiable {
    case human
    case vtuber

    var id: String { rawValue }
    var label: String { self == .human ? "Human" : "VTuber" }
    var detail: String {
        self == .human ? "Brio camera" : "Full character"
    }
    var symbol: String {
        self == .human ? "person.crop.rectangle" : "theatermasks.fill"
    }
}

struct ClawStudioOBSSpatialLayout: Decodable, Equatable {
    var supported: Bool
    var configured: Bool
    var sceneName: String
    var cameraCorner: ClawStudioOBSCameraCorner
    var cameraSize: ClawStudioOBSCameraSize
    var cameraMode: ClawStudioOBSCameraMode
    var cameraVisible: Bool
    var cameraSourceName: String
    var vtuberSourceName: String
    var workspaceSourceName: String
    var message: String?
}

struct ClawStudioProduction: Decodable, Equatable, Identifiable {
    var productionId: String
    var artifactCount: Int
    var updatedAt: Double

    var id: String { productionId }
    var shortLabel: String {
        "Production …\(productionId.suffix(8))"
    }
}

private struct OBSStatusEnvelope: Decodable { var ok: Bool; var status: ClawStudioOBSStatus }
private struct OBSScenesEnvelope: Decodable {
    var ok: Bool
    var scenes: [ClawStudioOBSScene]
    var currentProgramScene: ClawStudioOBSScene?
}
private struct OBSStreamEnvelope: Decodable { var ok: Bool; var stream: ClawStudioOBSStream }
private struct OBSSpatialLayoutEnvelope: Decodable { var ok: Bool; var layout: ClawStudioOBSSpatialLayout }
private struct ProductionsEnvelope: Decodable { var ok: Bool; var productions: [ClawStudioProduction] }
private struct OBSProgramSceneEnvelope: Decodable { var ok: Bool; var currentProgramScene: ClawStudioOBSScene }
private struct OBSRecordingEnvelope: Decodable { var ok: Bool; var recording: ClawStudioOBSRecording }
private struct OBSRecordingStopEnvelope: Decodable {
    struct Take: Decodable { var id: String; var outputPath: String }
    var ok: Bool
    var recording: ClawStudioOBSRecording
    var take: Take
}

enum OBSControlPolicy {
    static func canSwitchScene(connected: Bool, productionID: String?, busy: Bool) -> Bool {
        connected && productionID?.isEmpty == false && !busy
    }

    static func canStartRecording(
        connected: Bool,
        productionID: String?,
        scene: ClawStudioOBSScene?,
        recording: ClawStudioOBSRecording?,
        busy: Bool
    ) -> Bool {
        canSwitchScene(connected: connected, productionID: productionID, busy: busy)
            && scene != nil
            && recording?.active == false
    }

    static func canStopRecording(
        connected: Bool,
        productionID: String?,
        recording: ClawStudioOBSRecording?,
        busy: Bool
    ) -> Bool {
        connected
            && !busy
            && recording?.active == true
            && recording?.productionId != nil
            && recording?.productionId == productionID
    }
}

enum OBSSnapshotAuthority {
    static func isAuthoritative(
        state: ClawStudioOBSConnectionState,
        lastSuccessfulRefreshAt: Date?
    ) -> Bool {
        lastSuccessfulRefreshAt != nil
            && state != .checking
            && state != .failed
            && state != .stopped
    }
}

@MainActor
final class ClawStudioOBSController: ObservableObject {
    @Published private(set) var state: ClawStudioOBSConnectionState = .stopped
    @Published private(set) var detail = "ClawStudio owns OBS control on this Mac"
    @Published private(set) var status: ClawStudioOBSStatus?
    @Published private(set) var scenes: [ClawStudioOBSScene] = []
    @Published private(set) var currentProgramScene: ClawStudioOBSScene?
    @Published private(set) var stream: ClawStudioOBSStream?
    @Published private(set) var spatialLayout: ClawStudioOBSSpatialLayout?
    @Published private(set) var productions: [ClawStudioProduction] = []
    @Published var selectedProductionID: String?
    @Published private(set) var busyAction: String?
    @Published private(set) var actionError: String?
    @Published private(set) var lastTake: String?
    @Published private(set) var lastSuccessfulRefreshAt: Date?

    let configuration: ClawStudioOBSConfiguration
    private var monitorTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshTaskID: UUID?

    init(configuration: ClawStudioOBSConfiguration = ClawStudioOBSConfiguration()) {
        self.configuration = configuration
    }

    var connected: Bool { state == .connected }
    var recording: ClawStudioOBSRecording? { status?.recording }
    var busy: Bool { busyAction != nil }
    var snapshotIsAuthoritative: Bool {
        OBSSnapshotAuthority.isAuthoritative(
            state: state,
            lastSuccessfulRefreshAt: lastSuccessfulRefreshAt
        )
    }

    var canSwitchScene: Bool {
        OBSControlPolicy.canSwitchScene(
            connected: connected,
            productionID: selectedProductionID,
            busy: busy
        )
    }

    var canStartRecording: Bool {
        OBSControlPolicy.canStartRecording(
            connected: connected,
            productionID: selectedProductionID,
            scene: currentProgramScene,
            recording: recording,
            busy: busy
        )
    }

    var canStopRecording: Bool {
        OBSControlPolicy.canStopRecording(
            connected: connected,
            productionID: selectedProductionID,
            recording: recording,
            busy: busy
        )
    }

    var canAdjustSpatialLayout: Bool {
        connected
            && selectedProductionID?.isEmpty == false
            && spatialLayout?.supported == true
            && spatialLayout?.configured == true
            && !busy
    }

    func start() {
        guard monitorTask == nil else { return }
        state = .checking
        detail = "Checking ClawStudio and OBS WebSocket"
        monitorTask = Task { [weak self] in
            var spatialSourceRebound = false
            while let self, !Task.isCancelled {
                await self.refresh()
                if !spatialSourceRebound,
                   let layout = self.spatialLayout,
                   self.selectedProductionID != nil {
                    await self.setSpatialLayout(
                        corner: layout.cameraCorner,
                        size: layout.cameraSize,
                        mode: layout.cameraMode,
                        cameraVisible: layout.cameraVisible
                    )
                    spatialSourceRebound = self.actionError == nil
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshTaskID = nil
        state = .stopped
        detail = "OBS monitoring is paused"
    }

    func reconnect() {
        if monitorTask == nil { start() }
        Task { await refresh() }
    }

    func dismissActionError() {
        actionError = nil
    }

    func refresh() async {
        if let refreshTask {
            let taskID = refreshTaskID
            await refreshTask.value
            clearRefreshTask(ifMatching: taskID)
            return
        }
        let taskID = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRefresh()
        }
        refreshTask = task
        refreshTaskID = taskID
        await task.value
        clearRefreshTask(ifMatching: taskID)
    }

    private func performRefresh() async {
        let recoveringFromConnectivityFailure = state == .failed
        do {
            async let nextStatus: OBSStatusEnvelope = get("api/obs/status")
            async let nextScenes: OBSScenesEnvelope = get("api/obs/scenes")
            async let nextStream: OBSStreamEnvelope = get("api/obs/stream/status")
            async let nextProductions: ProductionsEnvelope = get("api/productions")
            async let nextSpatialLayout: OBSSpatialLayoutEnvelope? = try? get("api/obs/spatial-workspace/layout")
            let snapshot = try await (nextStatus, nextScenes, nextStream, nextProductions, nextSpatialLayout)
            guard !Task.isCancelled else { return }
            status = snapshot.0.status
            scenes = snapshot.1.scenes.sorted { ($0.index ?? .max) < ($1.index ?? .max) }
            currentProgramScene = snapshot.1.currentProgramScene
            stream = snapshot.2.stream
            productions = snapshot.3.productions
            spatialLayout = snapshot.4?.layout
            lastSuccessfulRefreshAt = Date()
            if recoveringFromConnectivityFailure, !busy {
                actionError = nil
            }
            if selectedProductionID == nil || !productions.contains(where: { $0.productionId == selectedProductionID }) {
                selectedProductionID = productions.first?.productionId
            }
            switch snapshot.0.status.state {
            case "connected":
                state = .connected
                detail = "ClawStudio is connected to OBS \(snapshot.0.status.version?.obsVersion ?? "")"
            case "connecting", "offline", "unsupported":
                state = .offline
                detail = snapshot.0.status.message ?? "Open OBS and enable its local WebSocket server"
            default:
                state = .failed
                detail = snapshot.0.status.message ?? "OBS returned an unavailable state"
            }
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed
            detail = "Start the local ClawStudio cockpit, then reconnect"
            if !busy { actionError = error.localizedDescription }
        }
    }

    func switchToScene(_ scene: ClawStudioOBSScene) async {
        guard canSwitchScene, let productionID = selectedProductionID else { return }
        await perform("Taking \(scene.name)") {
            let _: OBSProgramSceneEnvelope = try await post(
                "api/obs/program-scene",
                body: ["productionId": productionID, "obsSceneName": scene.name]
            )
        }
    }

    func startRecording() async {
        guard canStartRecording,
              let productionID = selectedProductionID,
              let scene = currentProgramScene else { return }
        await perform("Starting recording") {
            let _: OBSRecordingEnvelope = try await post(
                "api/obs/recording/start",
                body: [
                    "productionId": productionID,
                    "obsSceneName": scene.name,
                    "obsSceneUuid": scene.uuid,
                ]
            )
        }
    }

    func stopRecording() async {
        guard canStopRecording, let productionID = selectedProductionID else { return }
        await perform("Stopping recording") {
            let result: OBSRecordingStopEnvelope = try await post(
                "api/obs/recording/stop",
                body: ["productionId": productionID]
            )
            lastTake = result.take.outputPath
        }
    }

    func setSpatialLayout(
        corner: ClawStudioOBSCameraCorner,
        size: ClawStudioOBSCameraSize,
        mode: ClawStudioOBSCameraMode,
        cameraVisible: Bool
    ) async {
        guard canAdjustSpatialLayout, let productionID = selectedProductionID else { return }
        await perform("Updating face camera") {
            let result: OBSSpatialLayoutEnvelope = try await post(
                "api/obs/spatial-workspace/layout",
                body: [
                    "productionId": productionID,
                    "cameraCorner": corner.rawValue,
                    "cameraSize": size.rawValue,
                    "cameraMode": mode.rawValue,
                    "cameraVisible": cameraVisible,
                ]
            )
            spatialLayout = result.layout
        }
    }


    func openOBS() {
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.obsproject.obs-studio") {
            NSWorkspace.shared.open(appURL)
        }
    }

    func openClawStudio() {
        NSWorkspace.shared.open(configuration.baseURL)
    }

    private func perform(_ label: String, operation: () async throws -> Void) async {
        guard busyAction == nil else { return }
        busyAction = label
        actionError = nil
        do {
            try await operation()
            await refreshAfterMutation()
        } catch {
            actionError = "\(label) failed. \(error.localizedDescription)"
        }
        busyAction = nil
    }

    private func refreshAfterMutation() async {
        if let refreshTask {
            let taskID = refreshTaskID
            await refreshTask.value
            clearRefreshTask(ifMatching: taskID)
        }
        await refresh()
    }

    private func clearRefreshTask(ifMatching taskID: UUID?) {
        guard refreshTaskID == taskID else { return }
        refreshTask = nil
        refreshTaskID = nil
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: configuration.apiURL(path))
        request.timeoutInterval = 3
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await send(request)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        var request = URLRequest(url: configuration.apiURL(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 6
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw NSError(
                domain: "ClawStudioOBS",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: Self.errorMessage(data) ?? "ClawStudio OBS request failed (\(http.statusCode))."]
            )
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func errorMessage(_ data: Data) -> String? {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = body["error"] as? String { return message }
        if let error = body["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return nil
    }
}
