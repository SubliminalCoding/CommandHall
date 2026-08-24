import AppKit
import Foundation

enum BarehandsConnectionState: Equatable {
    case stopped
    case checking
    case starting
    case ready
    case missing
    case failed(String)

    var label: String {
        switch self {
        case .stopped: "Offline"
        case .checking: "Checking Barehands"
        case .starting: "Starting Barehands"
        case .ready: "Barehands service ready"
        case .missing: "Barehands is not installed"
        case .failed: "Barehands needs attention"
        }
    }
}

struct BarehandsHoverTarget: Equatable {
    let id: Int
    let type: String
    let title: String
}

enum BarehandsInteractionPhase: String, Equatable {
    case waitingForHand = "waiting_for_hand"
    case aiming
    case ready
    case pinching
    case activated
    case rejected
}

enum BarehandsInteractionReason: String, Equatable {
    case noHand = "no_hand"
    case noTarget = "no_target"
    case moveSlower = "move_slower"
    case holdOKSign = "hold_ok_sign"
    case releaseQuickly = "release_quickly"
    case movedTooFar = "moved_too_far"
    case heldTooLong = "held_too_long"
    case trackingLost = "tracking_lost"
    case targetChanged = "target_changed"
    case gestureUnstable = "gesture_unstable"
    case actionComplete = "action_complete"
    case useOneHand = "use_one_hand"
}

struct BarehandsInteractionSnapshot: Equatable {
    let phase: BarehandsInteractionPhase
    let reason: BarehandsInteractionReason?
    let target: BarehandsHoverTarget?
}

enum BarehandsJarvisCommunication {
    static let holdDurationNanoseconds: UInt64 = 650_000_000

    static func isRingHold(_ interaction: BarehandsInteractionSnapshot?) -> Bool {
        guard interaction?.phase == .pinching,
              let target = interaction?.target else { return false }
        // The Barehands wire contract exposes the pinned assistant ring as its
        // only widget target. Do not key this to the displayed assistant name:
        // Barehands intentionally lets that name be customized.
        return target.type == "widget"
    }
}

struct BarehandsAssistantVisualState: Equatable {
    let state: String
    let mood: String

    static func resolve(_ state: JarvisVoiceState) -> Self {
        switch state {
        case .idle: Self(state: "idle", mood: "green")
        case .listening: Self(state: "listening", mood: "green")
        case .transcribing: Self(state: "thinking", mood: "green")
        case .thinking: Self(state: "thinking", mood: "green")
        case .speaking: Self(state: "speaking", mood: "green")
        case .recovering: Self(state: "idle", mood: "amber")
        case .error: Self(state: "idle", mood: "amber")
        }
    }
}

struct BarehandsAssistantStateWriter {
    let stateDirectoryURL: URL

    func write(_ visual: BarehandsAssistantVisualState, audioLevel: Double, now: Date = Date()) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
        try Data(visual.state.utf8).write(
            to: stateDirectoryURL.appendingPathComponent("state"),
            options: .atomic
        )

        let mood: [String: Any] = [
            "mood": visual.mood,
            "ts": now.timeIntervalSince1970,
        ]
        try JSONSerialization.data(withJSONObject: mood, options: [.sortedKeys]).write(
            to: stateDirectoryURL.appendingPathComponent("mood.json"),
            options: .atomic
        )

        if visual.state == "speaking" {
            let level = min(max(audioLevel, 0), 1)
            let wave: [String: Any] = [
                "samples": Array(repeating: level, count: 64),
                "ts": now.timeIntervalSince1970,
            ]
            try JSONSerialization.data(withJSONObject: wave, options: [.sortedKeys]).write(
                to: stateDirectoryURL.appendingPathComponent("wave.json"),
                options: .atomic
            )
        }
    }
}

enum BarehandsCoachStep: String, Equatable {
    case showOneHand = "show_one_hand"
    case targetRing = "target_ring"
    case makeOKSign = "make_ok_sign"
    case release
    case chooseOrb = "choose_orb"
    case complete

    var progress: Int {
        switch self {
        case .showOneHand: 0
        case .targetRing: 1
        case .makeOKSign: 2
        case .release: 3
        case .chooseOrb: 4
        case .complete: 5
        }
    }
}

struct BarehandsCoachSnapshot: Equatable {
    let step: BarehandsCoachStep
    let completed: Bool
}

struct BarehandsBoardSnapshot: Equatable {
    let undoClearAvailable: Bool
    let undoExpiresAtMilliseconds: Int64?

    func canUndoClear(at now: Date = Date()) -> Bool {
        guard undoClearAvailable,
              let undoExpiresAtMilliseconds else { return false }
        return Date(timeIntervalSince1970: TimeInterval(undoExpiresAtMilliseconds) / 1_000) > now
    }

    func undoSecondsRemaining(at now: Date = Date()) -> Int? {
        guard canUndoClear(at: now), let undoExpiresAtMilliseconds else { return nil }
        let expiration = Date(timeIntervalSince1970: TimeInterval(undoExpiresAtMilliseconds) / 1_000)
        return max(1, Int(ceil(expiration.timeIntervalSince(now))))
    }
}

enum BarehandsCommandResultStatus: String, Equatable {
    case applied
    case rejected
}

struct BarehandsCommandResult: Equatable {
    let commandID: String
    let action: BarehandsBoardCommand
    let status: BarehandsCommandResultStatus
    let reason: String?
}

enum BarehandsCommandAcknowledgement: Equatable {
    case applied
    case rejected(String?)
    case timedOut
    case cancelled
}

struct BarehandsTrackingSnapshot: Equatable {
    let handCount: Int
    let pinchedHandCount: Int
    let itemCount: Int
    let clearableItemCount: Int
    let hoveredTargets: [BarehandsHoverTarget]
    let updatedAtMilliseconds: Int64?
    let interaction: BarehandsInteractionSnapshot?
    let coach: BarehandsCoachSnapshot?
    let board: BarehandsBoardSnapshot?
    let trackerID: String?
    let commandResult: BarehandsCommandResult?

    var isPinching: Bool { pinchedHandCount > 0 }
    var primaryHoverTarget: BarehandsHoverTarget? { hoveredTargets.first }

    init(
        handCount: Int,
        pinchedHandCount: Int,
        itemCount: Int,
        clearableItemCount: Int? = nil,
        hoveredTargets: [BarehandsHoverTarget] = [],
        updatedAtMilliseconds: Int64? = nil,
        interaction: BarehandsInteractionSnapshot? = nil,
        coach: BarehandsCoachSnapshot? = nil,
        board: BarehandsBoardSnapshot? = nil,
        trackerID: String? = nil,
        commandResult: BarehandsCommandResult? = nil
    ) {
        self.handCount = handCount
        self.pinchedHandCount = pinchedHandCount
        self.itemCount = itemCount
        self.clearableItemCount = clearableItemCount ?? itemCount
        self.hoveredTargets = hoveredTargets
        self.updatedAtMilliseconds = updatedAtMilliseconds
        self.interaction = interaction
        self.coach = coach
        self.board = board
        self.trackerID = trackerID
        self.commandResult = commandResult
    }

    var hasClearableContent: Bool { clearableItemCount > 0 }

    var requiresReloadConfirmation: Bool {
        hasClearableContent || board?.undoClearAvailable == true
    }

    func isAuthoritative(for expectedTrackerID: String) -> Bool {
        trackerID == expectedTrackerID
    }

    func isFresh(at now: Date = Date(), maximumAge: TimeInterval = 2) -> Bool {
        guard let updatedAtMilliseconds else { return false }
        let updatedAt = Date(timeIntervalSince1970: TimeInterval(updatedAtMilliseconds) / 1_000)
        let age = now.timeIntervalSince(updatedAt)
        return age >= -1 && age <= maximumAge
    }

    func remainsAuthoritativeAfterFailedPoll(
        at now: Date = Date(),
        legacyDeadline: Date?
    ) -> Bool {
        if updatedAtMilliseconds != nil {
            return isFresh(at: now)
        }
        guard let legacyDeadline else { return false }
        return now <= legacyDeadline
    }

    static func decode(_ data: Data) -> BarehandsTrackingSnapshot? {
        guard !data.isEmpty,
              data.count <= 262_144,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cursors = payload["cursors"] as? [[String: Any]],
              cursors.count <= 2,
              let items = payload["items"] as? [[String: Any]],
              items.count <= 512 else {
            return nil
        }
        let trackerID: String?
        if payload.keys.contains("trackerId") {
            guard let decoded = BarehandsWireContract.identifier(payload["trackerId"]) else { return nil }
            trackerID = decoded
        } else {
            trackerID = nil
        }
        let commandResult: BarehandsCommandResult?
        if payload.keys.contains("commandResult") {
            guard trackerID != nil,
                  let decoded = decodeCommandResult(payload["commandResult"]) else { return nil }
            commandResult = decoded
        } else {
            commandResult = nil
        }
        let pinchedHandCount = cursors.reduce(into: 0) { count, cursor in
            if let value = cursor["p"] as? NSNumber, value.boolValue {
                count += 1
            }
        }
        let hoveredTargets = cursors.compactMap { cursor -> BarehandsHoverTarget? in
            guard let hover = cursor["hover"] as? [String: Any],
                  let id = hover["id"] as? NSNumber,
                  let type = hover["type"] as? String,
                  let title = hover["title"] as? String else { return nil }
            return BarehandsHoverTarget(
                id: id.intValue,
                type: String(type.prefix(40)),
                title: String(title.prefix(80))
            )
        }
        let interaction: BarehandsInteractionSnapshot?
        if payload.keys.contains("interaction") {
            guard let decoded = decodeInteraction(payload["interaction"]) else { return nil }
            interaction = decoded
        } else {
            interaction = nil
        }
        let coach: BarehandsCoachSnapshot?
        if payload.keys.contains("coach") {
            guard let decoded = decodeCoach(payload["coach"]) else { return nil }
            coach = decoded
        } else {
            coach = nil
        }
        let board: BarehandsBoardSnapshot?
        if payload.keys.contains("board") {
            guard let decoded = decodeBoard(payload["board"]) else { return nil }
            board = decoded
        } else {
            board = nil
        }
        return BarehandsTrackingSnapshot(
            handCount: cursors.count,
            pinchedHandCount: pinchedHandCount,
            itemCount: items.count,
            clearableItemCount: items.reduce(into: 0) { count, item in
                // The wire contract identifies the pinned Jarvis ring by its
                // existing widget/ring pair. Unknown item shapes stay
                // clearable so malformed or future furniture never weakens a
                // destructive-action guardrail.
                let isPinnedJarvis = item["type"] as? String == "widget"
                    && item["w"] as? String == "ring"
                if !isPinnedJarvis { count += 1 }
            },
            hoveredTargets: hoveredTargets,
            updatedAtMilliseconds: (payload["updatedAtMs"] as? NSNumber)?.int64Value,
            interaction: interaction,
            coach: coach,
            board: board,
            trackerID: trackerID,
            commandResult: commandResult
        )
    }

    func commandAcknowledgement(
        trackerID expectedTrackerID: String,
        commandID expectedCommandID: String,
        command expectedCommand: BarehandsBoardCommand
    ) -> BarehandsCommandAcknowledgement? {
        guard trackerID == expectedTrackerID,
              let commandResult,
              commandResult.commandID == expectedCommandID,
              commandResult.action == expectedCommand else { return nil }
        switch commandResult.status {
        case .applied:
            return .applied
        case .rejected:
            return .rejected(commandResult.reason)
        }
    }

    private static func decodeInteraction(_ value: Any?) -> BarehandsInteractionSnapshot? {
        guard let payload = value as? [String: Any],
              let rawPhase = payload["phase"] as? String,
              let phase = BarehandsInteractionPhase(rawValue: rawPhase) else { return nil }

        let reason: BarehandsInteractionReason?
        if let rawReason = payload["reason"] {
            guard let rawReason = rawReason as? String,
                  let decoded = BarehandsInteractionReason(rawValue: rawReason) else { return nil }
            reason = decoded
        } else {
            reason = nil
        }

        let target: BarehandsHoverTarget?
        if let rawTarget = payload["target"], !(rawTarget is NSNull) {
            guard let decoded = decodeTarget(rawTarget) else { return nil }
            target = decoded
        } else {
            target = nil
        }
        return BarehandsInteractionSnapshot(phase: phase, reason: reason, target: target)
    }

    private static func decodeCoach(_ value: Any?) -> BarehandsCoachSnapshot? {
        guard let payload = value as? [String: Any],
              let rawStep = payload["step"] as? String,
              let step = BarehandsCoachStep(rawValue: rawStep),
              let completed = strictBoolean(payload["completed"]) else { return nil }
        return BarehandsCoachSnapshot(step: step, completed: completed)
    }

    private static func decodeBoard(_ value: Any?) -> BarehandsBoardSnapshot? {
        guard let payload = value as? [String: Any],
              let undoClearAvailable = strictBoolean(payload["undoClearAvailable"]) else { return nil }
        let expiresAt = (payload["undoExpiresAtMs"] as? NSNumber)?.int64Value
        if undoClearAvailable, expiresAt == nil { return nil }
        return BarehandsBoardSnapshot(
            undoClearAvailable: undoClearAvailable,
            undoExpiresAtMilliseconds: expiresAt
        )
    }

    private static func decodeCommandResult(_ value: Any?) -> BarehandsCommandResult? {
        guard let payload = value as? [String: Any],
              let commandID = BarehandsWireContract.identifier(payload["commandId"]),
              let rawAction = payload["action"] as? String,
              let action = BarehandsBoardCommand(rawValue: rawAction),
              let rawStatus = payload["status"] as? String,
              let status = BarehandsCommandResultStatus(rawValue: rawStatus) else { return nil }

        let reason: String?
        if payload.keys.contains("reason") {
            guard let decoded = BarehandsWireContract.reason(payload["reason"]) else { return nil }
            reason = decoded
        } else {
            reason = nil
        }
        return BarehandsCommandResult(
            commandID: commandID,
            action: action,
            status: status,
            reason: reason
        )
    }

    private static func decodeTarget(_ value: Any) -> BarehandsHoverTarget? {
        guard let payload = value as? [String: Any],
              let id = payload["id"] as? NSNumber,
              let type = payload["type"] as? String,
              let title = payload["title"] as? String,
              !type.isEmpty,
              !title.isEmpty else { return nil }
        return BarehandsHoverTarget(
            id: id.intValue,
            type: String(type.prefix(40)),
            title: String(title.prefix(80))
        )
    }

    private static func strictBoolean(_ value: Any?) -> Bool? {
        guard let value = value as? NSNumber,
              String(cString: value.objCType) == "c" else { return nil }
        return value.boolValue
    }
}

enum BarehandsWireContract {
    private static let identifierCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
    )

    static func identifier(_ value: Any?) -> String? {
        guard let value = value as? String,
              (1 ... 64).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({
                  $0.isASCII && identifierCharacters.contains($0)
              }) else { return nil }
        return value
    }

    static func reason(_ value: Any?) -> String? {
        guard let value = value as? String,
              (1 ... 160).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
}

enum BarehandsBoardCommand: String, CaseIterable, Equatable {
    case findRing = "find_ring"
    case fitBoard = "fit_board"
    case clearBoard = "clear_board"
    case undoClear = "undo_clear"
    case restartCoach = "restart_coach"

    var progressLabel: String {
        switch self {
        case .findRing: "Finding Jarvis"
        case .fitBoard: "Fitting board"
        case .clearBoard: "Clearing board"
        case .undoClear: "Restoring board"
        case .restartCoach: "Restarting practice"
        }
    }

    var successMessage: String {
        switch self {
        case .findRing: "Jarvis returned to his home position"
        case .fitBoard: "Board fitted without closing anything"
        case .clearBoard: "Board cleared"
        case .undoClear: "Cleared board restored"
        case .restartCoach: "Gesture practice restarted"
        }
    }
}

enum BarehandsCommandAcknowledger {
    @MainActor
    static func wait(
        trackerID: String,
        commandID: String,
        command: BarehandsBoardCommand,
        timeout: TimeInterval = 4,
        pollIntervalNanoseconds: UInt64 = 50_000_000,
        snapshot: @escaping @MainActor () -> BarehandsTrackingSnapshot?
    ) async -> BarehandsCommandAcknowledgement {
        let deadline = Date().addingTimeInterval(max(0, timeout))
        repeat {
            if Task.isCancelled { return .cancelled }
            if let acknowledgement = snapshot()?.commandAcknowledgement(
                trackerID: trackerID,
                commandID: commandID,
                command: command
            ) {
                return acknowledgement
            }
            guard Date() < deadline else { return .timedOut }
            do {
                try await Task.sleep(nanoseconds: max(1_000_000, pollIntervalNanoseconds))
            } catch {
                return .cancelled
            }
        } while true
    }
}

enum BarehandsBoardCommandAvailability {
    static func isActionable(
        connectionState: BarehandsConnectionState,
        snapshot: BarehandsTrackingSnapshot?,
        snapshotIsStale: Bool,
        trackerID: String
    ) -> Bool {
        connectionState == .ready
            && !snapshotIsStale
            && snapshot?.isAuthoritative(for: trackerID) == true
    }
}

enum BarehandsReloadProtection {
    static func requiresConfirmation(
        snapshot: BarehandsTrackingSnapshot?,
        snapshotIsStale: Bool,
        trackerID: String
    ) -> Bool {
        guard !snapshotIsStale,
              let snapshot,
              snapshot.isAuthoritative(for: trackerID) else { return true }
        return snapshot.requiresReloadConfirmation
    }
}

struct BarehandsServiceConfiguration: Equatable {
    var repositoryURL = ProcessInfo.processInfo.environment["COMMANDHALL_BAREHANDS_PATH"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Projects/barehands-redwood", isDirectory: true)
    var port = 8_794
    var preferredCamera = "Brio 101"

    var serverURL: URL {
        repositoryURL.appendingPathComponent("server.py")
    }

    var assistantStateDirectoryURL: URL {
        repositoryURL.appendingPathComponent("state", isDirectory: true)
    }

    var stageURL: URL { stageURL(hostedBySpatial: true, trackerID: nil) }

    var standaloneStageURL: URL {
        stageURL(hostedBySpatial: false, trackerID: nil)
    }

    func hostedStageURL(trackerID: String) -> URL? {
        guard BarehandsWireContract.identifier(trackerID) != nil else { return nil }
        return stageURL(hostedBySpatial: true, trackerID: trackerID)
    }

    private func stageURL(hostedBySpatial: Bool, trackerID: String?) -> URL {
        var components = URLComponents(string: "http://127.0.0.1:\(port)/stage.html")!
        components.queryItems = [
            URLQueryItem(name: "mode", value: "mirror"),
            URLQueryItem(name: "cam", value: preferredCamera),
            URLQueryItem(name: "res", value: "1920x1080"),
        ]
        if hostedBySpatial {
            components.queryItems?.append(URLQueryItem(name: "host", value: "spatial"))
        }
        if let trackerID {
            components.queryItems?.append(URLQueryItem(name: "trackerId", value: trackerID))
        }
        return components.url!
    }

    var healthURL: URL {
        URL(string: "http://127.0.0.1:\(port)/config")!
    }

    var sceneStateURL: URL {
        URL(string: "http://127.0.0.1:\(port)/state")!
    }

    func sceneStateURL(trackerID: String) -> URL? {
        guard BarehandsWireContract.identifier(trackerID) != nil else { return nil }
        var components = URLComponents(url: sceneStateURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "trackerId", value: trackerID)]
        return components.url
    }

    var commandURL: URL {
        URL(string: "http://127.0.0.1:\(port)/cmd")!
    }

    func boardCommandRequest(
        _ command: BarehandsBoardCommand,
        trackerID: String,
        commandID: String
    ) -> URLRequest? {
        guard commandURL.scheme == "http",
              commandURL.host == "127.0.0.1",
              commandURL.port == port,
              commandURL.path == "/cmd",
              commandURL.user == nil,
              commandURL.password == nil,
              commandURL.query == nil,
              commandURL.fragment == nil,
              BarehandsWireContract.identifier(trackerID) != nil,
              BarehandsWireContract.identifier(commandID) != nil else { return nil }
        var request = URLRequest(url: commandURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "a": command.rawValue,
            "trackerId": trackerID,
            "commandId": commandID,
        ]
        if command == .clearBoard { payload["confirmed"] = true }
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        guard request.httpBody != nil else { return nil }
        return request
    }
}

@MainActor
final class BarehandsServiceController: ObservableObject {
    @Published private(set) var state: BarehandsConnectionState = .stopped
    @Published private(set) var detail = "The Redwood Barehands edition runs privately on this Mac"
    @Published private(set) var webRevision = 0
    @Published private(set) var trackingSnapshot: BarehandsTrackingSnapshot?
    @Published private(set) var trackingSnapshotIsStale = false
    @Published private(set) var activeBoardCommand: BarehandsBoardCommand?
    @Published private(set) var boardActionMessage: String?
    @Published private(set) var boardActionFailed = false
    @Published private(set) var assistantBridgeError: String?

    let configuration: BarehandsServiceConfiguration
    let trackerID: String

    private var process: Process?
    private var monitorTask: Task<Void, Never>?
    private var boardActionTask: Task<Void, Never>?
    private var ownsProcess = false
    private var legacyTrackingDeadline: Date?
    private var lastAssistantVisualState: BarehandsAssistantVisualState?
    private var lastAssistantWaveWriteAt = Date.distantPast

    init(
        configuration: BarehandsServiceConfiguration = BarehandsServiceConfiguration(),
        trackerID: String = UUID().uuidString
    ) {
        self.configuration = configuration
        self.trackerID = BarehandsWireContract.identifier(trackerID) != nil
            ? trackerID
            : UUID().uuidString
    }

    var hostedStageURL: URL {
        // Controller construction guarantees this identifier satisfies the
        // wire contract, so the fallback is unreachable in normal operation.
        configuration.hostedStageURL(trackerID: trackerID) ?? configuration.stageURL
    }

    func start() {
        guard monitorTask == nil else { return }
        state = .checking
        detail = "Checking the local Barehands service"
        trackingSnapshot = nil
        trackingSnapshotIsStale = false
        legacyTrackingDeadline = nil
        boardActionMessage = nil
        boardActionFailed = false
        monitorTask = Task { [weak self] in
            guard let self else { return }
            await self.prepareService()
            guard self.state == .ready else {
                self.monitorTask = nil
                return
            }
            var trackingPoll = 0
            while !Task.isCancelled {
                await self.refreshTrackingSnapshot()
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { break }
                trackingPoll += 1
                if trackingPoll.isMultiple(of: 30), !(await self.endpointIsHealthy()) {
                    self.state = .failed("The local Barehands service stopped answering")
                    self.detail = "Choose Try again to restart the camera workspace"
                    self.trackingSnapshot = nil
                    break
                }
            }
            self.monitorTask = nil
        }
    }

    func stop() {
        monitorTask?.cancel()
        monitorTask = nil
        boardActionTask?.cancel()
        boardActionTask = nil
        if ownsProcess, process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        ownsProcess = false
        state = .stopped
        trackingSnapshot = nil
        trackingSnapshotIsStale = false
        legacyTrackingDeadline = nil
        activeBoardCommand = nil
        boardActionMessage = nil
        boardActionFailed = false
        detail = "Barehands releases the camera when you leave this view"
    }

    func reconnect() {
        stop()
        webRevision += 1
        start()
    }

    func reloadPage() {
        webRevision += 1
    }

    func reflectJarvis(state: JarvisVoiceState, audioLevel: Double, now: Date = Date()) {
        let visual = BarehandsAssistantVisualState.resolve(state)
        let stateChanged = visual != lastAssistantVisualState
        let waveIsDue = visual.state == "speaking" && now.timeIntervalSince(lastAssistantWaveWriteAt) >= 0.08
        guard stateChanged || waveIsDue else { return }

        do {
            try BarehandsAssistantStateWriter(
                stateDirectoryURL: configuration.assistantStateDirectoryURL
            ).write(visual, audioLevel: audioLevel, now: now)
            lastAssistantVisualState = visual
            if visual.state == "speaking" { lastAssistantWaveWriteAt = now }
            assistantBridgeError = nil
        } catch {
            assistantBridgeError = "Jarvis ring feedback is unavailable"
        }
    }

    var canSendBoardCommands: Bool {
        BarehandsBoardCommandAvailability.isActionable(
            connectionState: state,
            snapshot: trackingSnapshot,
            snapshotIsStale: trackingSnapshotIsStale,
            trackerID: trackerID
        )
    }

    var canClearBoard: Bool {
        canSendBoardCommands && trackingSnapshot?.hasClearableContent == true
    }

    var canUndoClear: Bool {
        canSendBoardCommands && trackingSnapshot?.board?.canUndoClear() == true
    }

    var trackingSnapshotNeedsServiceRestart: Bool {
        guard !trackingSnapshotIsStale, let trackingSnapshot else { return false }
        return !trackingSnapshot.isAuthoritative(for: trackerID)
    }

    var undoClearSecondsRemaining: Int? {
        trackingSnapshot?.board?.undoSecondsRemaining()
    }

    var reloadRequiresConfirmation: Bool {
        BarehandsReloadProtection.requiresConfirmation(
            snapshot: trackingSnapshot,
            snapshotIsStale: trackingSnapshotIsStale,
            trackerID: trackerID
        )
    }

    var reloadConfirmationMessage: String {
        guard !trackingSnapshotIsStale,
              let trackingSnapshot,
              trackingSnapshot.isAuthoritative(for: trackerID) else {
            return "The board state cannot be verified. Reload only if tracking does not recover; open content may close."
        }
        if trackingSnapshot.board?.undoClearAvailable == true,
           trackingSnapshot.hasClearableContent {
            return "Reloading may close open Barehands content and discards the current Undo window."
        }
        if trackingSnapshot.board?.undoClearAvailable == true {
            return "Reloading restarts the camera page and discards the current Undo window."
        }
        return "Reloading restarts the camera page and may close open Barehands content. Jarvis remains available."
    }

    func performBoardCommand(_ command: BarehandsBoardCommand) {
        guard canSendBoardCommands, activeBoardCommand == nil,
              command != .undoClear || canUndoClear,
              command != .clearBoard || canClearBoard else { return }
        let commandID = UUID().uuidString
        guard let request = configuration.boardCommandRequest(
            command,
            trackerID: trackerID,
            commandID: commandID
        ) else { return }
        activeBoardCommand = command
        boardActionMessage = nil
        boardActionFailed = false
        boardActionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeBoardCommand = nil
                self.boardActionTask = nil
            }
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 204 else {
                    self.boardActionMessage = "Barehands rejected the \(command.progressLabel.lowercased()) request"
                    self.boardActionFailed = true
                    return
                }
                let acknowledgement = await BarehandsCommandAcknowledger.wait(
                    trackerID: self.trackerID,
                    commandID: commandID,
                    command: command
                ) { [weak self] in
                    guard let self, !self.trackingSnapshotIsStale else { return nil }
                    return self.trackingSnapshot
                }
                guard !Task.isCancelled else { return }
                switch acknowledgement {
                case .applied:
                    self.boardActionMessage = command.successMessage
                    self.boardActionFailed = false
                case let .rejected(reason):
                    let explanation = reason.map { ": \($0.replacingOccurrences(of: "_", with: " "))" } ?? ""
                    self.boardActionMessage = "Barehands rejected the \(command.progressLabel.lowercased()) request\(explanation)"
                    self.boardActionFailed = true
                case .timedOut:
                    self.boardActionMessage = "Request accepted, but Barehands did not confirm the result. Check the board before trying again."
                    self.boardActionFailed = true
                case .cancelled:
                    return
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.boardActionMessage = "Could not reach Barehands to \(command.progressLabel.lowercased())"
                self.boardActionFailed = true
            }
        }
    }

    func openInBrowser() {
        NSWorkspace.shared.open(configuration.standaloneStageURL)
    }

    func openSourceRepository() {
        guard let url = URL(string: "https://github.com/jaredrhod/barehands") else { return }
        NSWorkspace.shared.open(url)
    }

    private func prepareService() async {
        guard FileManager.default.fileExists(atPath: configuration.serverURL.path) else {
            state = .missing
            detail = "Barehands was not found at \(configuration.repositoryURL.path)"
            return
        }

        if await endpointIsHealthy() {
            becomeReady()
            return
        }

        state = .starting
        detail = "Starting the private loopback service"
        let candidate = Process()
        candidate.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        candidate.arguments = [configuration.serverURL.path]
        candidate.currentDirectoryURL = configuration.repositoryURL
        candidate.standardInput = FileHandle.nullDevice
        candidate.standardOutput = FileHandle.nullDevice
        candidate.standardError = FileHandle.nullDevice

        do {
            try candidate.run()
            process = candidate
            ownsProcess = true
        } catch {
            state = .failed("Barehands could not start")
            detail = error.localizedDescription
            return
        }

        for _ in 0 ..< 20 {
            guard !Task.isCancelled else { return }
            if await endpointIsHealthy() {
                becomeReady()
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        state = .failed("Barehands started but did not answer")
        detail = "Port \(configuration.port) is unavailable or the service exited"
    }

    private func becomeReady() {
        state = .ready
        detail = "The local board is available; camera and tracking status appear in the view"
        legacyTrackingDeadline = Date().addingTimeInterval(2)
        webRevision += 1
    }

    private func refreshTrackingSnapshot() async {
        guard let sceneStateURL = configuration.sceneStateURL(trackerID: trackerID) else { return }
        var request = URLRequest(url: sceneStateURL)
        request.timeoutInterval = 1
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let now = Date()
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let snapshot = BarehandsTrackingSnapshot.decode(data) else {
                expireTrackingSnapshotAfterFailedPoll(at: now)
                return
            }
            if snapshot.updatedAtMilliseconds != nil {
                legacyTrackingDeadline = nil
                if snapshot.isFresh(at: now) {
                    trackingSnapshot = snapshot
                    trackingSnapshotIsStale = false
                } else {
                    trackingSnapshot = nil
                    trackingSnapshotIsStale = true
                }
            } else if let legacyTrackingDeadline, now <= legacyTrackingDeadline {
                trackingSnapshot = snapshot
                trackingSnapshotIsStale = false
            } else {
                trackingSnapshot = nil
                trackingSnapshotIsStale = true
            }
        } catch {
            // The service health loop owns connection failures. A missed scene
            // heartbeat should not tear down an otherwise healthy board.
            expireTrackingSnapshotAfterFailedPoll()
        }
    }

    private func expireTrackingSnapshotAfterFailedPoll(at now: Date = Date()) {
        let shouldExpire: Bool
        if let trackingSnapshot {
            shouldExpire = !trackingSnapshot.remainsAuthoritativeAfterFailedPoll(
                at: now,
                legacyDeadline: legacyTrackingDeadline
            )
        } else if let legacyTrackingDeadline {
            shouldExpire = now > legacyTrackingDeadline
        } else {
            shouldExpire = trackingSnapshotIsStale
        }
        guard shouldExpire else { return }
        trackingSnapshot = nil
        trackingSnapshotIsStale = true
        legacyTrackingDeadline = nil
    }

    private func endpointIsHealthy() async -> Bool {
        var request = URLRequest(url: configuration.healthURL)
        request.timeoutInterval = 1.5
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
