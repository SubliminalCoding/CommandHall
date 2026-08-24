import Combine
import Foundation

enum SignalDeckConnectionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case unavailable

    var label: String {
        switch self {
        case .idle: "Not connected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reconnecting: "Reconnecting"
        case .unavailable: "Unavailable"
        }
    }
}

enum SignalDeckStreamState: String, Equatable {
    case unknown
    case offline
    case live

    var label: String {
        switch self {
        case .unknown: "Live state unknown"
        case .offline: "Stream offline"
        case .live: "Stream live"
        }
    }
}

enum SignalDeckRoutingTruth: String, Equatable {
    case unavailable
    case configuredOnly
    case appliedUnverified
    case engineVerified

    var label: String {
        switch self {
        case .unavailable: "Unavailable"
        case .configuredOnly: "Configured only"
        case .appliedUnverified: "Applied, not verified"
        case .engineVerified: "Engine verified"
        }
    }
}

struct SignalDeckAuthoritativeStatus: Equatable {
    let connected: Bool
    let authoritative: Bool
    let instanceID: String?
    let revision: UInt64?
    let sourceIDs: [String]
    let busIDs: [String]
    let configuredProfileID: String?
    let truth: SignalDeckRoutingTruth
    let mutationMode: String?
    let streamState: SignalDeckStreamState
}

enum SignalDeckSemanticAction: Equatable {
    case listenPrivately(sourceID: String)
    case includeInStream(sourceID: String)
    case excludeFromStream(sourceID: String)
    case muteSource(sourceID: String)
    case setBusMuted(busID: String, muted: Bool)
    case applyProfile(profileID: String)
    case panicMute

    var resourceID: String? {
        switch self {
        case .listenPrivately(let sourceID),
             .includeInStream(let sourceID),
             .excludeFromStream(let sourceID),
             .muteSource(let sourceID): sourceID
        case .setBusMuted(let busID, _): busID
        case .applyProfile(let profileID): profileID
        case .panicMute: nil
        }
    }
}

enum SignalDeckChangeDirection: String, Equatable {
    case privacyReduction
    case exposureIncrease
    case mixed
    case neutral

    var label: String {
        switch self {
        case .privacyReduction: "Reduces exposure"
        case .exposureIncrease: "Adds exposure"
        case .mixed: "Mixed routing change"
        case .neutral: "No broadcast exposure change"
        }
    }
}

enum SignalDeckPlanPolicy: String, Equatable {
    case automatic
    case requiresApproval
}

struct SignalDeckChangePreview: Equatable, Identifiable {
    let resource: String
    let before: String
    let after: String

    var id: String { resource }
}

enum SignalDeckPlannedMutation: Equatable {
    case route(sourceID: String, targetBusIDs: [String], gain: Double, muted: Bool)
    case bus(busID: String, gain: Double, muted: Bool)
    case profile(profileID: String, fingerprint: String)
    case panic(fingerprint: String)
}

struct SignalDeckChangePlan: Equatable, Identifiable {
    let id: String
    let action: SignalDeckSemanticAction
    let expectedRevision: UInt64
    let createdAtMs: UInt64
    let expiresAtMs: UInt64
    let requester: String
    let reason: String?
    let summary: String
    let preview: [SignalDeckChangePreview]
    let direction: SignalDeckChangeDirection
    let policy: SignalDeckPlanPolicy
    let mutation: SignalDeckPlannedMutation

    var requiresConfirmation: Bool { policy == .requiresApproval }
}

enum SignalDeckRequestResult: Equatable {
    case configured(SignalDeckMutationReceipt)
    case approvalRequired(SignalDeckChangePlan)
}

enum SignalDeckPlanError: LocalizedError, Equatable {
    case controlUnavailable
    case snapshotNotAuthoritative
    case writeAccessUnavailable
    case unknownSource(String)
    case unknownBus(String)
    case unknownProfile(String)
    case invalidProfile(String)
    case noChange
    case planNotFound
    case invalidPlanID
    case staleRevision(expected: UInt64, current: UInt64?)
    case expired
    case busy

    var errorDescription: String? {
        switch self {
        case .controlUnavailable:
            "SignalDeck control is unavailable."
        case .snapshotNotAuthoritative:
            "A fresh authoritative SignalDeck snapshot is required."
        case .writeAccessUnavailable:
            "SignalDeck write control is unavailable."
        case .unknownSource(let id):
            "SignalDeck does not advertise the source \(id)."
        case .unknownBus(let id):
            "SignalDeck does not advertise the bus \(id)."
        case .unknownProfile(let id):
            "SignalDeck does not advertise the profile \(id)."
        case .invalidProfile(let id):
            "The advertised \(id) profile contains an invalid routing reference."
        case .noChange:
            "The requested audio state is already configured."
        case .planNotFound:
            "That audio plan is no longer pending. Create a fresh plan."
        case .invalidPlanID:
            "The audio plan identifier is not bound to its router revision."
        case .staleRevision(let expected, let current):
            "Audio plan revision \(expected) is stale; SignalDeck is now at revision \(current.map(String.init) ?? "unknown")."
        case .expired:
            "That audio plan expired. Review a fresh plan before applying it."
        case .busy:
            "Another SignalDeck change is still being processed."
        }
    }
}

enum SignalDeckAuditKind: String, Equatable {
    case planned
    case approvalRequired
    case approved
    case automatic
    case rejected
    case expired
    case stale
    case configured
    case failed
}

struct SignalDeckAuditEntry: Equatable, Identifiable {
    let id: UUID
    let occurredAtMs: UInt64
    let planID: String?
    let requester: String
    let kind: SignalDeckAuditKind
    let summary: String
    let detail: String
    let operationID: String?
}

enum SignalDeckApplicationPolicy {
    static func canApply(
        profileID: String,
        knownProfileIDs: Set<String>,
        configuredProfileID: String?,
        connected: Bool,
        authoritative: Bool,
        mutationsAvailable: Bool,
        hasWriteAccess: Bool,
        busy: Bool
    ) -> Bool {
        knownProfileIDs.contains(profileID)
            && configuredProfileID != profileID
            && connected
            && authoritative
            && mutationsAvailable
            && hasWriteAccess
            && !busy
    }

    static func policy(
        for direction: SignalDeckChangeDirection,
        streamState: SignalDeckStreamState
    ) -> SignalDeckPlanPolicy {
        let increasesExposure = direction == .exposureIncrease || direction == .mixed
        return increasesExposure && streamState != .offline ? .requiresApproval : .automatic
    }
}

enum SignalDeckSemanticPlanner {
    static let defaultLifetime: TimeInterval = 90

    static func makePlan(
        action: SignalDeckSemanticAction,
        snapshot: SignalDeckSnapshot,
        profiles: SignalDeckProfilesSnapshot,
        streamState: SignalDeckStreamState,
        requester: String,
        reason: String? = nil,
        now: Date = Date(),
        lifetime: TimeInterval = defaultLifetime,
        nonce: UUID = UUID()
    ) throws -> SignalDeckChangePlan {
        guard snapshot.instanceId == profiles.instanceId,
              snapshot.revision == profiles.revision,
              snapshot.configurationAvailable != false,
              profiles.configurationAvailable != false else {
            throw SignalDeckPlanError.snapshotNotAuthoritative
        }
        guard lifetime > 0, lifetime <= 300 else { throw SignalDeckPlanError.expired }

        guard Set(snapshot.sources.map(\.id)).count == snapshot.sources.count,
              Set(snapshot.buses.map(\.id)).count == snapshot.buses.count,
              Set(profiles.profiles.map(\.id)).count == profiles.profiles.count else {
            throw SignalDeckPlanError.snapshotNotAuthoritative
        }
        let sourceByID = Dictionary(uniqueKeysWithValues: snapshot.sources.map { ($0.id, $0) })
        let busByID = Dictionary(uniqueKeysWithValues: snapshot.buses.map { ($0.id, $0) })
        let profileByID = Dictionary(uniqueKeysWithValues: profiles.profiles.map { ($0.id, $0) })
        let planned: PlannedChange

        switch action {
        case .listenPrivately(let sourceID):
            let source = try knownSource(sourceID, in: sourceByID)
            _ = try knownBus("monitor-mix", in: busByID)
            let targets = ["monitor-mix"]
            guard source.targetBusIds != targets || source.muted else { throw SignalDeckPlanError.noChange }
            let reduced = source.targetBusIds.contains { isExposureBus($0, buses: busByID) }
            planned = PlannedChange(
                summary: "Keep \(source.displayName) private",
                preview: [routePreview(source, targets: targets, muted: false, buses: busByID)],
                direction: reduced ? .privacyReduction : .neutral,
                mutation: .route(sourceID: sourceID, targetBusIDs: targets, gain: source.gain, muted: false)
            )

        case .includeInStream(let sourceID):
            let source = try knownSource(sourceID, in: sourceByID)
            _ = try knownBus("monitor-mix", in: busByID)
            _ = try knownBus("stream-mix", in: busByID)
            var targets = source.targetBusIds.filter { $0 != "monitor-mix" && $0 != "stream-mix" }
            targets.append(contentsOf: ["monitor-mix", "stream-mix"])
            guard source.targetBusIds != targets || source.muted else { throw SignalDeckPlanError.noChange }
            planned = PlannedChange(
                summary: "Include \(source.displayName) in Stream Mix",
                preview: [routePreview(source, targets: targets, muted: false, buses: busByID)],
                direction: .exposureIncrease,
                mutation: .route(sourceID: sourceID, targetBusIDs: targets, gain: source.gain, muted: false)
            )

        case .excludeFromStream(let sourceID):
            let source = try knownSource(sourceID, in: sourceByID)
            let targets = source.targetBusIds.filter { $0 != "stream-mix" }
            guard targets != source.targetBusIds else { throw SignalDeckPlanError.noChange }
            planned = PlannedChange(
                summary: "Remove \(source.displayName) from Stream Mix",
                preview: [routePreview(source, targets: targets, muted: source.muted, buses: busByID)],
                direction: .privacyReduction,
                mutation: .route(sourceID: sourceID, targetBusIDs: targets, gain: source.gain, muted: source.muted)
            )

        case .muteSource(let sourceID):
            let source = try knownSource(sourceID, in: sourceByID)
            guard !source.muted else { throw SignalDeckPlanError.noChange }
            let reduced = source.targetBusIds.contains { isExposureBus($0, buses: busByID) }
            planned = PlannedChange(
                summary: "Mute \(source.displayName)",
                preview: [routePreview(source, targets: source.targetBusIds, muted: true, buses: busByID)],
                direction: reduced ? .privacyReduction : .neutral,
                mutation: .route(
                    sourceID: sourceID,
                    targetBusIDs: source.targetBusIds,
                    gain: source.gain,
                    muted: true
                )
            )

        case .setBusMuted(let busID, let muted):
            let bus = try knownBus(busID, in: busByID)
            guard bus.muted != muted else { throw SignalDeckPlanError.noChange }
            let direction: SignalDeckChangeDirection
            if muted, isExposureRole(bus.role) {
                direction = .privacyReduction
            } else if !muted, isExposureRole(bus.role) {
                direction = .exposureIncrease
            } else {
                direction = .neutral
            }
            planned = PlannedChange(
                summary: "\(muted ? "Mute" : "Unmute") \(bus.displayName)",
                preview: [SignalDeckChangePreview(
                    resource: bus.displayName,
                    before: bus.muted ? "Muted" : "Open at gain \(formatGain(bus.gain))",
                    after: muted ? "Muted" : "Open at gain \(formatGain(bus.gain))"
                )],
                direction: direction,
                mutation: .bus(busID: busID, gain: bus.gain, muted: muted)
            )

        case .applyProfile(let profileID):
            guard let profile = profileByID[profileID] else {
                throw SignalDeckPlanError.unknownProfile(profileID)
            }
            if snapshot.configuredProfile?.id == profileID,
               snapshot.configuredProfile?.matchesCatalog != false {
                throw SignalDeckPlanError.noChange
            }
            try validate(profile: profile, sources: sourceByID, buses: busByID)
            let direction = profileDirection(profile, snapshot: snapshot, buses: busByID)
            planned = PlannedChange(
                summary: "Configure \(profile.displayName)",
                preview: [SignalDeckChangePreview(
                    resource: "Routing profile",
                    before: snapshot.configuredProfile?.id ?? "Custom routing",
                    after: profile.displayName
                )],
                direction: direction,
                mutation: .profile(profileID: profileID, fingerprint: profile.fingerprint)
            )

        case .panicMute:
            guard let profile = profileByID["panic-muted"] else {
                throw SignalDeckPlanError.unknownProfile("panic-muted")
            }
            try validate(profile: profile, sources: sourceByID, buses: busByID)
            planned = PlannedChange(
                summary: "Configure every SignalDeck route and bus muted",
                preview: [SignalDeckChangePreview(
                    resource: "All logical audio",
                    before: snapshot.configuredProfile?.id ?? "Custom routing",
                    after: "Panic-muted configuration"
                )],
                direction: .privacyReduction,
                mutation: .panic(fingerprint: profile.fingerprint)
            )
        }

        let createdAtMs = milliseconds(now)
        let expiresAtMs = milliseconds(now.addingTimeInterval(lifetime))
        let planID = "signaldeck-plan-v1.r\(snapshot.revision).\(nonce.uuidString.lowercased())"
        return SignalDeckChangePlan(
            id: planID,
            action: action,
            expectedRevision: snapshot.revision,
            createdAtMs: createdAtMs,
            expiresAtMs: expiresAtMs,
            requester: bounded(requester, maximum: 96, fallback: "unknown-agent"),
            reason: reason.map { bounded($0, maximum: 240, fallback: "Requested audio change") },
            summary: bounded(planned.summary, maximum: 180, fallback: "SignalDeck change"),
            preview: Array(planned.preview.prefix(16)),
            direction: planned.direction,
            policy: SignalDeckApplicationPolicy.policy(for: planned.direction, streamState: streamState),
            mutation: planned.mutation
        )
    }

    static func validate(_ plan: SignalDeckChangePlan, revision: UInt64, now: Date = Date()) throws {
        guard revisionBoundRevision(plan.id) == plan.expectedRevision else {
            throw SignalDeckPlanError.invalidPlanID
        }
        guard plan.expectedRevision == revision else {
            throw SignalDeckPlanError.staleRevision(expected: plan.expectedRevision, current: revision)
        }
        guard milliseconds(now) < plan.expiresAtMs else {
            throw SignalDeckPlanError.expired
        }
    }

    static func revisionBoundRevision(_ planID: String) -> UInt64? {
        let pieces = planID.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0] == "signaldeck-plan-v1",
              pieces[1].first == "r",
              let revision = UInt64(pieces[1].dropFirst()),
              revision > 0,
              UUID(uuidString: String(pieces[2])) != nil else { return nil }
        return revision
    }

    private struct PlannedChange {
        let summary: String
        let preview: [SignalDeckChangePreview]
        let direction: SignalDeckChangeDirection
        let mutation: SignalDeckPlannedMutation
    }

    private static func knownSource(
        _ id: String,
        in sources: [String: SignalDeckSource]
    ) throws -> SignalDeckSource {
        guard let source = sources[id] else { throw SignalDeckPlanError.unknownSource(id) }
        return source
    }

    private static func knownBus(
        _ id: String,
        in buses: [String: SignalDeckBus]
    ) throws -> SignalDeckBus {
        guard let bus = buses[id] else { throw SignalDeckPlanError.unknownBus(id) }
        return bus
    }

    private static func validate(
        profile: SignalDeckProfile,
        sources: [String: SignalDeckSource],
        buses: [String: SignalDeckBus]
    ) throws {
        guard isSHA256(profile.fingerprint) else { throw SignalDeckPlanError.invalidProfile(profile.id) }
        for (sourceID, route) in profile.routes {
            guard sources[sourceID] != nil else { throw SignalDeckPlanError.unknownSource(sourceID) }
            guard route.gain.isFinite, (0 ... 2).contains(route.gain),
                  Set(route.targetBusIds).count == route.targetBusIds.count else {
                throw SignalDeckPlanError.invalidProfile(profile.id)
            }
            for busID in route.targetBusIds where buses[busID] == nil {
                throw SignalDeckPlanError.unknownBus(busID)
            }
        }
        for (busID, control) in profile.buses {
            guard buses[busID] != nil else { throw SignalDeckPlanError.unknownBus(busID) }
            guard control.gain.isFinite, (0 ... 2).contains(control.gain) else {
                throw SignalDeckPlanError.invalidProfile(profile.id)
            }
        }
    }

    private static func profileDirection(
        _ profile: SignalDeckProfile,
        snapshot: SignalDeckSnapshot,
        buses: [String: SignalDeckBus]
    ) -> SignalDeckChangeDirection {
        guard Set(snapshot.sources.map(\.id)).count == snapshot.sources.count else { return .mixed }
        let sources = Dictionary(uniqueKeysWithValues: snapshot.sources.map { ($0.id, $0) })
        var addsExposure = false
        var reducesExposure = false

        for (sourceID, next) in profile.routes {
            guard let current = sources[sourceID] else { continue }
            let oldExposure = Set(current.targetBusIds.filter { isExposureBus($0, buses: buses) })
            let newExposure = Set(next.targetBusIds.filter { isExposureBus($0, buses: buses) })
            if !newExposure.subtracting(oldExposure).isEmpty { addsExposure = true }
            if !oldExposure.subtracting(newExposure).isEmpty { reducesExposure = true }
            if !newExposure.isEmpty {
                if current.muted && !next.muted { addsExposure = true }
                if !current.muted && next.muted { reducesExposure = true }
                if !next.muted && next.gain > current.gain { addsExposure = true }
                if !current.muted && next.gain < current.gain { reducesExposure = true }
            }
        }
        for (busID, next) in profile.buses {
            guard let current = buses[busID], isExposureRole(current.role) else { continue }
            if current.muted && !next.muted { addsExposure = true }
            if !current.muted && next.muted { reducesExposure = true }
            if !next.muted && next.gain > current.gain { addsExposure = true }
            if !current.muted && next.gain < current.gain { reducesExposure = true }
        }
        switch (addsExposure, reducesExposure) {
        case (true, true): return .mixed
        case (true, false): return .exposureIncrease
        case (false, true): return .privacyReduction
        case (false, false): return .neutral
        }
    }

    private static func routePreview(
        _ source: SignalDeckSource,
        targets: [String],
        muted: Bool,
        buses: [String: SignalDeckBus]
    ) -> SignalDeckChangePreview {
        SignalDeckChangePreview(
            resource: source.displayName,
            before: routeDescription(targets: source.targetBusIds, muted: source.muted, buses: buses),
            after: routeDescription(targets: targets, muted: muted, buses: buses)
        )
    }

    private static func routeDescription(
        targets: [String],
        muted: Bool,
        buses: [String: SignalDeckBus]
    ) -> String {
        if muted { return "Muted" }
        if targets.isEmpty { return "No destinations" }
        return targets.map { buses[$0]?.displayName ?? $0 }.joined(separator: " + ")
    }

    private static func isExposureBus(_ id: String, buses: [String: SignalDeckBus]) -> Bool {
        buses[id].map { isExposureRole($0.role) } ?? (id == "stream-mix")
    }

    private static func isExposureRole(_ role: String) -> Bool {
        role == "stream" || role == "chat" || role == "record"
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

    private static func bounded(_ value: String, maximum: Int, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(maximum))
    }

    private static func formatGain(_ gain: Double) -> String {
        String(format: "%.2f", gain)
    }

    fileprivate static func milliseconds(_ date: Date) -> UInt64 {
        UInt64(max(0, date.timeIntervalSince1970 * 1_000))
    }
}

@MainActor
final class SignalDeckController: ObservableObject {
    @Published private(set) var connectionState: SignalDeckConnectionState = .idle
    @Published private(set) var detail = "SignalDeck owns audio routing independently"
    @Published private(set) var isAuthoritative = false
    @Published private(set) var capabilities: SignalDeckCapabilities?
    @Published private(set) var snapshot: SignalDeckSnapshot?
    @Published private(set) var profiles: SignalDeckProfilesSnapshot?
    @Published private(set) var applyingProfileID: String?
    @Published private(set) var pendingProfileID: String?
    @Published private(set) var executingPlanID: String?
    @Published private(set) var pendingApprovals: [SignalDeckChangePlan] = []
    @Published private(set) var auditTrail: [SignalDeckAuditEntry] = []
    @Published private(set) var receiptHistory: [SignalDeckMutationReceipt] = []
    @Published private(set) var actionMessage: String?
    @Published private(set) var actionError: String?
    @Published private(set) var lastReceipt: SignalDeckMutationReceipt?
    @Published private(set) var streamState: SignalDeckStreamState = .unknown

    private let client: SignalDeckControlClient
    private var credentials: SignalDeckCredentials?
    private var monitorTask: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var preparedPlans: [String: SignalDeckChangePlan] = [:]
    private var lastEventSequence: UInt64?

    init(client: SignalDeckControlClient = SignalDeckControlClient()) {
        self.client = client
    }

    var connected: Bool { connectionState == .connected }

    var hasWriteAccess: Bool { credentials?.writeToken != nil }

    var configuredProfileID: String? {
        guard snapshot?.configuredProfile?.matchesCatalog != false else { return nil }
        return snapshot?.configuredProfile?.id
    }

    var hasCatalogDrift: Bool { snapshot?.configuredProfile?.matchesCatalog == false }

    var audioGraphApplied: Bool {
        snapshot?.audioGraphApplied == true && snapshot?.integration.audioGraphApplied == true
    }

    var configurationAvailable: Bool {
        snapshot?.configurationAvailable != false && profiles?.configurationAvailable != false
    }

    private var mutationsAvailable: Bool {
        capabilities?.mutations == true && snapshot?.integration.mutationsAvailable == true
    }

    var routingTruth: SignalDeckRoutingTruth {
        guard let snapshot, configurationAvailable else { return .unavailable }
        guard snapshot.audioGraphApplied, snapshot.integration.audioGraphApplied else {
            return .configuredOnly
        }
        let engineCheckPassed = snapshot.checks.contains { $0.id == "audio-graph" && $0.status == "pass" }
        if snapshot.engine.pipelineRunning && engineCheckPassed {
            return .engineVerified
        }
        return .appliedUnverified
    }

    var authoritativeStatus: SignalDeckAuthoritativeStatus {
        SignalDeckAuthoritativeStatus(
            connected: connected,
            authoritative: isAuthoritative,
            instanceID: snapshot?.instanceId,
            revision: snapshot?.revision,
            sourceIDs: snapshot?.sources.map(\.id) ?? [],
            busIDs: snapshot?.buses.map(\.id) ?? [],
            configuredProfileID: configuredProfileID,
            truth: routingTruth,
            mutationMode: capabilities?.mutationMode ?? snapshot?.integration.mutationMode,
            streamState: streamState
        )
    }

    var statusColorName: String {
        if connected && isAuthoritative { return audioGraphApplied ? "green" : "orange" }
        if connectionState == .connecting || connectionState == .reconnecting { return "yellow" }
        return "red"
    }

    func updateStreamState(_ state: SignalDeckStreamState) {
        streamState = state
    }

    func start() {
        guard monitorTask == nil else { return }
        generation &+= 1
        let activeGeneration = generation
        connectionState = .connecting
        detail = "Finding the owner-only SignalDeck control service"
        isAuthoritative = false
        monitorTask = Task { [weak self] in
            await self?.monitor(generation: activeGeneration)
        }
    }

    func reconnect() {
        monitorTask?.cancel()
        monitorTask = nil
        credentials = nil
        generation &+= 1
        let activeGeneration = generation
        connectionState = .reconnecting
        detail = "Refreshing SignalDeck discovery and its full routing snapshot"
        isAuthoritative = false
        monitorTask = Task { [weak self] in
            await self?.monitor(generation: activeGeneration)
        }
    }

    func canApplyProfile(_ profileID: String) -> Bool {
        SignalDeckApplicationPolicy.canApply(
            profileID: profileID,
            knownProfileIDs: Set(profiles?.profiles.map(\.id) ?? []),
            configuredProfileID: configuredProfileID,
            connected: connected,
            authoritative: isAuthoritative,
            mutationsAvailable: mutationsAvailable && configurationAvailable,
            hasWriteAccess: hasWriteAccess,
            busy: executingPlanID != nil
        ) && !pendingApprovals.contains { plan in
            if case .applyProfile(let pendingID) = plan.action { return pendingID == profileID }
            return false
        }
    }

    func canPlan(_ action: SignalDeckSemanticAction, now: Date = Date()) -> Bool {
        guard connected, isAuthoritative, configurationAvailable,
              mutationsAvailable, hasWriteAccess,
              executingPlanID == nil, let snapshot, let profiles else { return false }
        return (try? SignalDeckSemanticPlanner.makePlan(
            action: action,
            snapshot: snapshot,
            profiles: profiles,
            streamState: streamState,
            requester: "operator-ui",
            now: now
        )) != nil
    }

    @discardableResult
    func createPlan(
        action: SignalDeckSemanticAction,
        requestedBy: String,
        reason: String? = nil,
        streamState requestedStreamState: SignalDeckStreamState? = nil,
        now: Date = Date(),
        lifetime: TimeInterval = SignalDeckSemanticPlanner.defaultLifetime
    ) throws -> SignalDeckChangePlan {
        guard connected else { throw SignalDeckPlanError.controlUnavailable }
        guard isAuthoritative, let snapshot, let profiles else {
            throw SignalDeckPlanError.snapshotNotAuthoritative
        }
        guard configurationAvailable, mutationsAvailable else {
            throw SignalDeckPlanError.controlUnavailable
        }
        guard hasWriteAccess else { throw SignalDeckPlanError.writeAccessUnavailable }
        guard executingPlanID == nil else { throw SignalDeckPlanError.busy }

        prunePlans(now: now)
        let effectiveStreamState = conservativeStreamState(requestedStreamState)
        let plan = try SignalDeckSemanticPlanner.makePlan(
            action: action,
            snapshot: snapshot,
            profiles: profiles,
            streamState: effectiveStreamState,
            requester: requestedBy,
            reason: reason,
            now: now,
            lifetime: lifetime
        )
        if plan.requiresConfirmation, pendingApprovals.count >= 16 {
            throw SignalDeckPlanError.busy
        }
        preparedPlans[plan.id] = plan
        appendAudit(
            kind: .planned,
            plan: plan,
            detail: "Bound to router revision \(plan.expectedRevision)."
        )
        if plan.requiresConfirmation {
            pendingApprovals.removeAll { $0.id == plan.id }
            pendingApprovals.append(plan)
            pendingProfileID = pendingApprovals.compactMap { pending in
                if case .applyProfile(let profileID) = pending.action { return profileID }
                return nil
            }.first
            appendAudit(
                kind: .approvalRequired,
                plan: plan,
                detail: "Exposure can increase while the stream is \(effectiveStreamState.rawValue)."
            )
        }
        trimPreparedPlans()
        return plan
    }

    @discardableResult
    func requestSemanticChange(
        _ action: SignalDeckSemanticAction,
        requestedBy: String = "operator-ui",
        reason: String? = nil,
        streamState requestedStreamState: SignalDeckStreamState? = nil,
        now: Date = Date()
    ) async throws -> SignalDeckRequestResult {
        let plan = try createPlan(
            action: action,
            requestedBy: requestedBy,
            reason: reason,
            streamState: requestedStreamState,
            now: now
        )
        if plan.requiresConfirmation {
            actionMessage = "Review the pending audio exposure before applying it."
            actionError = nil
            return .approvalRequired(plan)
        }
        appendAudit(kind: .automatic, plan: plan, detail: "Policy allowed this bounded change automatically.")
        let receipt = try await apply(
            planID: plan.id,
            expectedRevision: plan.expectedRevision,
            idempotencyKey: makeIdempotencyKey(for: plan),
            now: now
        )
        return .configured(receipt)
    }

    @discardableResult
    func apply(
        planID: String,
        expectedRevision: UInt64,
        idempotencyKey: String,
        now: Date = Date()
    ) async throws -> SignalDeckMutationReceipt {
        guard let plan = preparedPlans[planID] else { throw SignalDeckPlanError.planNotFound }
        do {
            guard let revision = snapshot?.revision else {
                throw SignalDeckPlanError.snapshotNotAuthoritative
            }
            try SignalDeckSemanticPlanner.validate(plan, revision: revision, now: now)
        } catch let planError as SignalDeckPlanError {
            if planError == .expired {
                appendAudit(kind: .expired, plan: plan, detail: "Plan lifetime elapsed without mutation.")
                removePlan(plan.id)
            } else if case .staleRevision = planError {
                appendAudit(kind: .stale, plan: plan, detail: "Router changed before the plan could be applied.")
                removePlan(plan.id)
            }
            throw planError
        }
        prunePlans(now: now)
        guard plan.expectedRevision == expectedRevision else {
            throw SignalDeckPlanError.staleRevision(expected: expectedRevision, current: snapshot?.revision)
        }
        guard let revision = snapshot?.revision else { throw SignalDeckPlanError.snapshotNotAuthoritative }
        try SignalDeckSemanticPlanner.validate(plan, revision: revision, now: now)
        guard connected, isAuthoritative else { throw SignalDeckPlanError.snapshotNotAuthoritative }
        guard configurationAvailable, mutationsAvailable else {
            throw SignalDeckPlanError.controlUnavailable
        }
        guard let credentials else { throw SignalDeckPlanError.writeAccessUnavailable }
        guard executingPlanID == nil else { throw SignalDeckPlanError.busy }

        if plan.requiresConfirmation {
            appendAudit(kind: .approved, plan: plan, detail: "The pending exposure change was explicitly applied.")
        }
        executingPlanID = plan.id
        if case .profile(let profileID, _) = plan.mutation { applyingProfileID = profileID }
        actionError = nil
        actionMessage = "Configuring \(plan.summary)…"
        defer {
            executingPlanID = nil
            applyingProfileID = nil
        }

        do {
            let response = try await execute(
                plan,
                idempotencyKey: idempotencyKey,
                credentials: credentials
            )
            guard response.instanceId == snapshot?.instanceId else {
                throw SignalDeckClientError.invalidResponse
            }
            lastReceipt = response.receipt
            appendReceipt(response.receipt)

            do {
                try await installFullSnapshot(credentials: credentials, generation: generation)
                guard let refreshed = snapshot,
                      configuredMutation(plan, receipt: response.receipt, matches: refreshed) else {
                    throw SignalDeckClientError.invalidResponse
                }
            } catch {
                isAuthoritative = false
                actionMessage = "SignalDeck accepted the configuration receipt, but current state has not been re-verified."
                appendAudit(
                    kind: .configured,
                    plan: plan,
                    detail: "Receipt accepted; authoritative refresh is pending.",
                    operationID: response.receipt.operationId
                )
                removePlan(plan.id)
                reconnect()
                return response.receipt
            }

            let truthMessage: String
            switch routingTruth {
            case .engineVerified:
                truthMessage = "Configured at revision \(response.receipt.afterRevision); SignalDeck verifies engine application, not program content."
            case .appliedUnverified:
                truthMessage = "Configured at revision \(response.receipt.afterRevision); engine application is not verified."
            case .configuredOnly, .unavailable:
                truthMessage = "Configured at revision \(response.receipt.afterRevision). Live audio was not rerouted by this development backend."
            }
            actionMessage = truthMessage
            appendAudit(
                kind: .configured,
                plan: plan,
                detail: truthMessage,
                operationID: response.receipt.operationId
            )
            removePlan(plan.id)
            return response.receipt
        } catch let error as SignalDeckClientError where error.isRevisionConflict {
            appendAudit(kind: .stale, plan: plan, detail: "SignalDeck rejected the stale router revision.")
            removePlan(plan.id)
            isAuthoritative = false
            actionError = "The routing configuration changed elsewhere. Review the refreshed state before trying again."
            try? await installFullSnapshot(credentials: credentials, generation: generation)
            throw error
        } catch {
            appendAudit(kind: .failed, plan: plan, detail: safeMessage(for: error))
            actionError = safeMessage(for: error)
            actionMessage = "The result was not assumed. Reconnect before retrying the same plan and idempotency key."
            isAuthoritative = false
            reconnect()
            throw error
        }
    }

    func approvePlan(_ planID: String) async {
        guard let plan = preparedPlans[planID] else {
            actionError = SignalDeckPlanError.planNotFound.localizedDescription
            return
        }
        do {
            _ = try await apply(
                planID: plan.id,
                expectedRevision: plan.expectedRevision,
                idempotencyKey: makeIdempotencyKey(for: plan)
            )
        } catch {
            actionError = safeMessage(for: error)
        }
    }

    func rejectPlan(_ planID: String) {
        guard let plan = preparedPlans[planID] else { return }
        appendAudit(kind: .rejected, plan: plan, detail: "The proposed change was dismissed without mutation.")
        removePlan(planID)
        actionMessage = "Audio proposal dismissed."
        actionError = nil
    }

    @discardableResult
    func requestPanicMute(
        idempotencyKey: String,
        requestedBy: String,
        reason: String? = nil,
        now: Date = Date()
    ) async throws -> SignalDeckMutationReceipt {
        let plan = try createPlan(
            action: .panicMute,
            requestedBy: requestedBy,
            reason: reason,
            streamState: .live,
            now: now
        )
        appendAudit(kind: .automatic, plan: plan, detail: "Privacy-reducing panic configuration does not wait for approval.")
        return try await apply(
            planID: plan.id,
            expectedRevision: plan.expectedRevision,
            idempotencyKey: idempotencyKey,
            now: now
        )
    }

    func applyProfile(_ profileID: String) async {
        await requestFromUI(.applyProfile(profileID: profileID))
    }

    func requestFromUI(_ action: SignalDeckSemanticAction) async {
        do {
            _ = try await requestSemanticChange(
                action,
                requestedBy: "operator-ui"
            )
        } catch {
            actionError = safeMessage(for: error)
        }
    }

    func requestLifecycleProfile(
        _ profileID: String,
        requestedBy: String,
        reason: String
    ) async {
        do {
            _ = try await requestSemanticChange(
                .applyProfile(profileID: profileID),
                requestedBy: requestedBy,
                reason: reason
            )
        } catch {
            actionError = safeMessage(for: error)
        }
    }

    private func execute(
        _ plan: SignalDeckChangePlan,
        idempotencyKey: String,
        credentials: SignalDeckCredentials
    ) async throws -> SignalDeckMutationResponse {
        let contextID = contextID(for: plan.requester)
        let instanceID = snapshot?.instanceId
        switch plan.mutation {
        case .route(let sourceID, let targetBusIDs, let gain, let muted):
            return try await client.putRoute(
                sourceID: sourceID,
                targetBusIDs: targetBusIDs,
                gain: gain,
                muted: muted,
                expectedRevision: plan.expectedRevision,
                idempotencyKey: idempotencyKey,
                contextID: contextID,
                credentials: credentials,
                expectedInstanceID: instanceID
            )
        case .bus(let busID, let gain, let muted):
            return try await client.putBus(
                busID: busID,
                gain: gain,
                muted: muted,
                expectedRevision: plan.expectedRevision,
                idempotencyKey: idempotencyKey,
                contextID: contextID,
                credentials: credentials,
                expectedInstanceID: instanceID
            )
        case .profile(let profileID, let fingerprint):
            return try await client.applyProfile(
                profileID,
                expectedRevision: plan.expectedRevision,
                idempotencyKey: idempotencyKey,
                contextID: contextID,
                credentials: credentials,
                expectedInstanceID: instanceID,
                expectedProfileFingerprint: fingerprint
            )
        case .panic(let fingerprint):
            return try await client.panicMute(
                expectedRevision: plan.expectedRevision,
                idempotencyKey: idempotencyKey,
                contextID: contextID,
                credentials: credentials,
                expectedInstanceID: instanceID,
                expectedProfileFingerprint: fingerprint
            )
        }
    }

    private func monitor(generation activeGeneration: UInt64) async {
        var attempt = 0
        while !Task.isCancelled, activeGeneration == generation {
            do {
                connectionState = attempt == 0 ? .connecting : .reconnecting
                isAuthoritative = false
                let resolved = try client.resolveCredentials()
                credentials = resolved

                let (bytes, _) = try await client.eventBytes(credentials: resolved)
                try await installFullSnapshot(credentials: resolved, generation: activeGeneration)
                try Task.checkCancellation()
                guard activeGeneration == generation else { return }

                attempt = 0
                lastEventSequence = nil
                var parser = SignalDeckSSEParser()
                for try await line in bytes.lines {
                    try Task.checkCancellation()
                    guard activeGeneration == generation else { return }
                    if let event = try parser.consume(line) {
                        try await handle(event, credentials: resolved, generation: activeGeneration)
                    }
                }
                throw URLError(.networkConnectionLost)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, activeGeneration == generation else { return }
                isAuthoritative = false
                credentials = nil
                connectionState = attempt == 0 ? .unavailable : .reconnecting
                detail = safeMessage(for: error)
                attempt += 1
                let seconds = min(8, 1 << min(attempt - 1, 3))
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            }
        }
    }

    private func installFullSnapshot(
        credentials: SignalDeckCredentials,
        generation activeGeneration: UInt64
    ) async throws {
        let nextCapabilities = try await client.fetchCapabilities(credentials: credentials)
        let nextSnapshot = try await client.fetchSnapshot(credentials: credentials)
        let nextProfiles = try await client.fetchProfiles(credentials: credentials)
        try Task.checkCancellation()
        guard activeGeneration == generation else { throw CancellationError() }
        guard nextSnapshot.instanceId == nextProfiles.instanceId,
              nextSnapshot.revision == nextProfiles.revision else {
            throw SignalDeckClientError.invalidResponse
        }

        capabilities = nextCapabilities
        snapshot = nextSnapshot
        profiles = nextProfiles
        isAuthoritative = true
        connectionState = .connected
        if nextSnapshot.configurationAvailable == false || nextProfiles.configurationAvailable == false {
            detail = "SignalDeck preserved an invalid routing file for recovery; changes are disabled"
        } else if nextSnapshot.configuredProfile?.matchesCatalog == false {
            detail = "The saved routing graph predates the current catalog; review a new profile"
        } else if nextSnapshot.audioGraphApplied, nextSnapshot.integration.audioGraphApplied {
            detail = "SignalDeck reports engine routing at revision \(nextSnapshot.revision)"
        } else {
            detail = "Logical routing is durable at revision \(nextSnapshot.revision); live audio is not rerouted"
        }
        prunePlans(now: Date(), currentRevision: nextSnapshot.revision)
    }

    private func handle(
        _ event: SignalDeckControlEvent,
        credentials: SignalDeckCredentials,
        generation activeGeneration: UInt64
    ) async throws {
        let runtimeChanged = event.type == "runtime.changed"
        guard event.type == "snapshot.required" || event.type == "router.changed" || runtimeChanged else { return }
        if let eventInstance = event.instanceId,
           let currentInstance = snapshot?.instanceId,
           eventInstance != currentInstance {
            throw SignalDeckClientError.invalidResponse
        }

        if let sequence = event.sequence {
            if let lastEventSequence, sequence > 0, sequence != lastEventSequence + 1 {
                isAuthoritative = false
            }
            self.lastEventSequence = sequence
        }

        let currentRevision = snapshot?.revision
        if let eventRevision = event.routerRevision,
           let currentRevision,
           eventRevision <= currentRevision,
           isAuthoritative,
           !runtimeChanged {
            return
        }

        isAuthoritative = false
        detail = "Refreshing the authoritative SignalDeck routing snapshot"
        try await installFullSnapshot(credentials: credentials, generation: activeGeneration)
    }

    private func configuredMutation(
        _ plan: SignalDeckChangePlan,
        receipt: SignalDeckMutationReceipt,
        matches snapshot: SignalDeckSnapshot
    ) -> Bool {
        guard snapshot.revision >= receipt.afterRevision else { return false }
        switch plan.mutation {
        case .route(let sourceID, let targets, let gain, let muted):
            guard let source = snapshot.sources.first(where: { $0.id == sourceID }) else { return false }
            return source.targetBusIds == targets && abs(source.gain - gain) <= 0.0001 && source.muted == muted
        case .bus(let busID, let gain, let muted):
            guard let bus = snapshot.buses.first(where: { $0.id == busID }) else { return false }
            return abs(bus.gain - gain) <= 0.0001 && bus.muted == muted
        case .profile(let profileID, let fingerprint):
            return snapshot.configuredProfile?.id == profileID
                && snapshot.configuredProfile?.fingerprint == fingerprint
                && snapshot.configuredProfile?.revision == receipt.afterRevision
        case .panic(let fingerprint):
            return snapshot.configuredProfile?.id == "panic-muted"
                && snapshot.configuredProfile?.fingerprint == fingerprint
                && snapshot.sources.allSatisfy(\.muted)
                && snapshot.buses.allSatisfy(\.muted)
        }
    }

    private func removePlan(_ id: String) {
        preparedPlans[id] = nil
        pendingApprovals.removeAll { $0.id == id }
        pendingProfileID = pendingApprovals.compactMap { plan in
            if case .applyProfile(let profileID) = plan.action { return profileID }
            return nil
        }.first
    }

    private func prunePlans(now: Date, currentRevision: UInt64? = nil) {
        let nowMs = SignalDeckSemanticPlanner.milliseconds(now)
        let revision = currentRevision ?? snapshot?.revision
        for plan in Array(preparedPlans.values) {
            if nowMs >= plan.expiresAtMs {
                appendAudit(kind: .expired, plan: plan, detail: "Plan lifetime elapsed without mutation.")
                removePlan(plan.id)
            } else if let revision, plan.expectedRevision != revision, plan.id != executingPlanID {
                appendAudit(kind: .stale, plan: plan, detail: "Router advanced to revision \(revision).")
                removePlan(plan.id)
            }
        }
    }

    private func trimPreparedPlans() {
        guard preparedPlans.count > 32 else { return }
        let removable = preparedPlans.values
            .filter { !pendingApprovals.contains($0) }
            .sorted { $0.createdAtMs < $1.createdAtMs }
        for plan in removable.prefix(preparedPlans.count - 32) {
            preparedPlans[plan.id] = nil
        }
    }

    private func appendReceipt(_ receipt: SignalDeckMutationReceipt) {
        receiptHistory.removeAll { $0.operationId == receipt.operationId }
        receiptHistory.insert(receipt, at: 0)
        if receiptHistory.count > 32 { receiptHistory.removeLast(receiptHistory.count - 32) }
    }

    private func appendAudit(
        kind: SignalDeckAuditKind,
        plan: SignalDeckChangePlan,
        detail: String,
        operationID: String? = nil
    ) {
        auditTrail.insert(SignalDeckAuditEntry(
            id: UUID(),
            occurredAtMs: SignalDeckSemanticPlanner.milliseconds(Date()),
            planID: plan.id,
            requester: plan.requester,
            kind: kind,
            summary: plan.summary,
            detail: String(detail.prefix(320)),
            operationID: operationID
        ), at: 0)
        if auditTrail.count > 100 { auditTrail.removeLast(auditTrail.count - 100) }
    }

    private func contextID(for requester: String) -> String {
        let safe = requester.lowercased().unicodeScalars.map { scalar -> Character in
            let value = scalar.value
            if (48 ... 57).contains(value) || (97 ... 122).contains(value) || value == 45 || value == 95 {
                return Character(String(scalar))
            }
            return "-"
        }
        let suffix = String(String(safe).prefix(72)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "spatial-workspace:\(suffix.isEmpty ? "agent" : suffix)"
    }

    private func makeIdempotencyKey(for plan: SignalDeckChangePlan) -> String {
        "spatial-workspace.plan.\(plan.expectedRevision).\(UUID().uuidString.lowercased())"
    }

    private func conservativeStreamState(_ requested: SignalDeckStreamState?) -> SignalDeckStreamState {
        guard let requested else { return streamState }
        if streamState == .live || requested == .live { return .live }
        if streamState == .unknown || requested == .unknown { return .unknown }
        return .offline
    }

    private func safeMessage(for error: Error) -> String {
        if let planError = error as? SignalDeckPlanError { return planError.localizedDescription }
        if let clientError = error as? SignalDeckClientError { return clientError.localizedDescription }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .networkConnectionLost, .timedOut:
                return "SignalDeck is not answering on its local control channel."
            default:
                return "The SignalDeck local connection was interrupted."
            }
        }
        return "The SignalDeck local connection could not be completed."
    }
}
