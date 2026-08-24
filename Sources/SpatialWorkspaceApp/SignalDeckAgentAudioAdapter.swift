import Foundation
import SpatialAgentBridgeKit

@MainActor
protocol SignalDeckAgentAudioControlling: AnyObject {
    var authoritativeStatus: SignalDeckAuthoritativeStatus { get }
    var snapshot: SignalDeckSnapshot? { get }
    var routingTruth: SignalDeckRoutingTruth { get }

    func createPlan(
        action: SignalDeckSemanticAction,
        requestedBy: String,
        reason: String?,
        streamState requestedStreamState: SignalDeckStreamState?,
        now: Date,
        lifetime: TimeInterval
    ) throws -> SignalDeckChangePlan

    func apply(
        planID: String,
        expectedRevision: UInt64,
        idempotencyKey: String,
        now: Date
    ) async throws -> SignalDeckMutationReceipt

    func requestPanicMute(
        idempotencyKey: String,
        requestedBy: String,
        reason: String?,
        now: Date
    ) async throws -> SignalDeckMutationReceipt
}

extension SignalDeckController: SignalDeckAgentAudioControlling {}

final class SignalDeckAgentAudioAdapter: AgentAudioControlHandling, @unchecked Sendable {
    private struct OwnedPlan {
        let plan: SignalDeckChangePlan
        let sessionID: UUID
        let nodeID: UUID
        let provider: String

        func belongs(to identity: AgentBridgeSessionIdentity) -> Bool {
            sessionID == identity.sessionID && nodeID == identity.nodeID && provider == identity.provider
        }
    }

    private let controller: any SignalDeckAgentAudioControlling
    private var agentPlans: [String: OwnedPlan] = [:]

    @MainActor
    init(controller: any SignalDeckAgentAudioControlling) {
        self.controller = controller
    }

    func handle(_ command: AgentAudioCommand, for identity: AgentBridgeSessionIdentity) async throws -> AgentAudioResult {
        try await handleOnMainActor(command, identity: identity)
    }

    @MainActor
    private func handleOnMainActor(
        _ command: AgentAudioCommand,
        identity: AgentBridgeSessionIdentity
    ) async throws -> AgentAudioResult {
        do {
            switch command {
            case .status:
                return .status(try status())
            case .plan(let request):
                let action = try semanticAction(for: request)
                let plan = try controller.createPlan(
                    action: action,
                    requestedBy: requester(identity),
                    reason: request.reason,
                    streamState: nil,
                    now: Date(),
                    lifetime: SignalDeckSemanticPlanner.defaultLifetime
                )
                remember(plan, for: identity)
                return .plan(try bridgePlan(plan, intent: request.intent, request: request))
            case .apply(let request):
                guard let ownedPlan = agentPlans[request.planID] else {
                    throw AgentBridgeHandlerError(
                        code: .conflict,
                        message: "Create a fresh audio plan in this agent session before applying it",
                        field: "planId"
                    )
                }
                guard ownedPlan.belongs(to: identity) else {
                    throw AgentBridgeHandlerError(
                        code: .forbidden,
                        message: "Audio plans can only be applied by the agent session that created them",
                        field: "planId"
                    )
                }
                guard !ownedPlan.plan.requiresConfirmation else {
                    throw AgentBridgeHandlerError(
                        code: .forbidden,
                        message: "This audio proposal requires operator approval in Signal Deck",
                        field: "planId"
                    )
                }
                let increasesExposure = ownedPlan.plan.direction == .exposureIncrease
                    || ownedPlan.plan.direction == .mixed
                guard !increasesExposure || controller.authoritativeStatus.streamState == .offline else {
                    throw AgentBridgeHandlerError(
                        code: .forbidden,
                        message: "The live state changed; create a fresh audio proposal for operator approval",
                        field: "planId"
                    )
                }
                guard let revision = UInt64(exactly: request.expectedRevision) else {
                    throw AgentBridgeHandlerError(
                        code: .invalidRequest,
                        message: "Audio plan revision is outside the supported range",
                        field: "expectedRevision"
                    )
                }
                let receipt = try await controller.apply(
                    planID: request.planID,
                    expectedRevision: revision,
                    idempotencyKey: request.idempotencyKey,
                    now: Date()
                )
                agentPlans.removeValue(forKey: request.planID)
                return .applied(try bridgeReceipt(receipt, operation: .apply, planID: request.planID))
            case .panic(let request):
                let receipt = try await controller.requestPanicMute(
                    idempotencyKey: request.idempotencyKey,
                    requestedBy: requester(identity),
                    reason: request.reason,
                    now: Date()
                )
                return .panic(try bridgeReceipt(receipt, operation: .panic, planID: nil))
            }
        } catch let error as AgentBridgeHandlerError {
            throw error
        } catch let error as SignalDeckPlanError {
            throw bridgeError(for: error)
        } catch let error as SignalDeckClientError {
            let message = bounded(error.localizedDescription, maximum: 500, fallback: "SignalDeck rejected the request")
            if error.isRevisionConflict {
                throw AgentBridgeHandlerError(code: .conflict, message: message, retryable: true)
            }
            throw AgentBridgeHandlerError(code: .notReady, message: message, retryable: true)
        } catch {
            throw AgentBridgeHandlerError(
                code: .internalError,
                message: "SignalDeck could not complete the requested semantic audio operation",
                retryable: true
            )
        }
    }

    @MainActor
    private func status() throws -> AgentAudioStatus {
        let truth = controller.authoritativeStatus
        guard let revisionValue = truth.revision, let revision = Int(exactly: revisionValue), revision <= Int(Int32.max) else {
            if truth.revision == nil {
                throw AgentBridgeHandlerError(code: .notReady, message: "SignalDeck has no authoritative router revision", retryable: true)
            }
            throw AgentBridgeHandlerError(code: .internalError, message: "SignalDeck router revision exceeds the agent bridge range")
        }
        let verified = truth.authoritative && truth.truth == .engineVerified
        let sources = (controller.snapshot?.sources ?? []).prefix(AgentBridgeLimits.maximumSources).map { source in
            AgentAudioSourceStatus(
                id: source.id,
                label: bounded(source.displayName, maximum: 128, fallback: source.id),
                monitorEnabled: !source.muted && source.targetBusIds.contains("monitor-mix"),
                streamEnabled: !source.muted && source.targetBusIds.contains("stream-mix"),
                verified: verified && source.available
            )
        }
        var warnings: [String] = []
        if !truth.connected { warnings.append("SignalDeck is not connected.") }
        if !truth.authoritative { warnings.append("The routing snapshot is not authoritative.") }
        switch truth.truth {
        case .configuredOnly:
            warnings.append("Routes are configured only; this backend does not claim live audio application.")
        case .appliedUnverified:
            warnings.append("SignalDeck reports engine application, but current routing has not been verified.")
        case .unavailable:
            warnings.append("SignalDeck routing truth is unavailable.")
        case .engineVerified:
            break
        }
        if let unavailable = controller.snapshot?.sources.filter({ !$0.available }).map(\.displayName), !unavailable.isEmpty {
            warnings.append("Unavailable sources: \(unavailable.prefix(8).joined(separator: ", ")).")
        }
        return AgentAudioStatus(
            capturedAtEpochMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000),
            revision: revision,
            mutationMode: truth.mutationMode == "live" ? .live : .configurationOnly,
            configuredProfileID: truth.configuredProfileID,
            activeProfileID: controller.snapshot?.activeProfile?.appliedToEngine == true
                ? controller.snapshot?.activeProfile?.id
                : nil,
            streamState: bridgeStreamState(truth.streamState),
            sources: Array(sources),
            warnings: Array(warnings.prefix(16))
        )
    }

    private func semanticAction(for request: AgentAudioPlanRequest) throws -> SignalDeckSemanticAction {
        switch request.intent {
        case .listenPrivately:
            return .listenPrivately(sourceID: try required(request.sourceID, field: "sourceId"))
        case .includeInStream:
            return .includeInStream(sourceID: try required(request.sourceID, field: "sourceId"))
        case .excludeFromStream:
            return .excludeFromStream(sourceID: try required(request.sourceID, field: "sourceId"))
        case .muteSource:
            return .muteSource(sourceID: try required(request.sourceID, field: "sourceId"))
        case .applyProfile:
            return .applyProfile(profileID: try required(request.profileID, field: "profileId"))
        case .setBus:
            guard let enabled = request.enabled else {
                throw AgentBridgeHandlerError(code: .invalidRequest, message: "set-bus requires enabled", field: "enabled")
            }
            return .setBusMuted(busID: try required(request.busID, field: "busId"), muted: !enabled)
        }
    }

    private func bridgePlan(
        _ plan: SignalDeckChangePlan,
        intent: AgentAudioIntent,
        request: AgentAudioPlanRequest
    ) throws -> AgentAudioPlan {
        guard let expectedRevision = Int(exactly: plan.expectedRevision), expectedRevision <= Int(Int32.max),
              let expiresAt = Int64(exactly: plan.expiresAtMs) else {
            throw AgentBridgeHandlerError(code: .internalError, message: "SignalDeck plan values exceed the agent bridge range")
        }
        let targetKind: String
        let targetID: String
        switch intent {
        case .applyProfile:
            targetKind = "profile"
            targetID = try required(request.profileID, field: "profileId")
        case .setBus:
            targetKind = "bus"
            targetID = try required(request.busID, field: "busId")
        default:
            targetKind = "source"
            targetID = try required(request.sourceID, field: "sourceId")
        }
        let changes = plan.preview.prefix(AgentBridgeLimits.maximumChanges).map { preview in
            AgentAudioChange(
                targetKind: targetKind,
                targetID: targetID,
                field: "routing",
                fromValue: bounded(preview.before, maximum: 256, fallback: "unknown"),
                toValue: bounded(preview.after, maximum: 256, fallback: "requested")
            )
        }
        return AgentAudioPlan(
            id: plan.id,
            intent: intent,
            summary: bounded(plan.summary, maximum: AgentBridgeLimits.maximumSummaryLength, fallback: "SignalDeck audio change"),
            expectedRevision: expectedRevision,
            expiresAtEpochMilliseconds: expiresAt,
            requiresConfirmation: plan.requiresConfirmation,
            changes: Array(changes)
        )
    }

    @MainActor
    private func bridgeReceipt(
        _ receipt: SignalDeckMutationReceipt,
        operation: AgentAudioReceiptOperation,
        planID: String?
    ) throws -> AgentAudioMutationReceipt {
        guard let configuredRevision = Int(exactly: receipt.afterRevision), configuredRevision <= Int(Int32.max),
              let completedAt = Int64(exactly: receipt.createdAtMs) else {
            throw AgentBridgeHandlerError(code: .internalError, message: "SignalDeck receipt values exceed the agent bridge range")
        }
        let verified = receipt.appliedToEngine
            && controller.routingTruth == .engineVerified
            && controller.snapshot?.revision == receipt.afterRevision
        let activeRevision = controller.snapshot?.activeProfile.flatMap { activeProfile -> Int? in
            guard activeProfile.appliedToEngine,
                  activeProfile.revision == receipt.afterRevision else { return nil }
            return Int(exactly: activeProfile.revision)
        }
        let summary = "SignalDeck receipt \(receipt.status) at revision \(receipt.afterRevision); engine application \(receipt.appliedToEngine ? "reported" : "not reported"); verification \(verified ? "passed" : "not established")."
        return AgentAudioMutationReceipt(
            receiptID: receipt.operationId,
            operation: operation,
            planID: planID,
            configuredRevision: configuredRevision,
            activeRevision: activeRevision,
            appliedToEngine: receipt.appliedToEngine,
            verified: verified,
            summary: summary,
            completedAtEpochMilliseconds: completedAt
        )
    }

    private func bridgeError(for error: SignalDeckPlanError) -> AgentBridgeHandlerError {
        let message = bounded(error.localizedDescription, maximum: 500, fallback: "SignalDeck rejected the audio plan")
        switch error {
        case .controlUnavailable, .snapshotNotAuthoritative, .writeAccessUnavailable:
            return AgentBridgeHandlerError(code: .notReady, message: message, retryable: true)
        case .unknownSource, .unknownBus, .unknownProfile, .invalidProfile:
            return AgentBridgeHandlerError(code: .invalidRequest, message: message)
        case .noChange, .planNotFound, .invalidPlanID, .staleRevision, .expired:
            return AgentBridgeHandlerError(code: .conflict, message: message)
        case .busy:
            return AgentBridgeHandlerError(code: .conflict, message: message, retryable: true)
        }
    }

    private func requester(_ identity: AgentBridgeSessionIdentity) -> String {
        "provider:\(identity.provider):session:\(identity.sessionID.uuidString.lowercased().prefix(12))"
    }

    private func remember(_ plan: SignalDeckChangePlan, for identity: AgentBridgeSessionIdentity) {
        let now = UInt64(max(0, Date().timeIntervalSince1970 * 1_000))
        agentPlans = agentPlans.filter { $0.value.plan.expiresAtMs > now }
        agentPlans[plan.id] = OwnedPlan(
            plan: plan,
            sessionID: identity.sessionID,
            nodeID: identity.nodeID,
            provider: identity.provider
        )
        if agentPlans.count > 48 {
            for stale in agentPlans.values.sorted(by: { $0.plan.createdAtMs < $1.plan.createdAtMs }).prefix(agentPlans.count - 48) {
                agentPlans.removeValue(forKey: stale.plan.id)
            }
        }
    }

    private func required(_ value: String?, field: String) throws -> String {
        guard let value, !value.isEmpty else {
            throw AgentBridgeHandlerError(code: .invalidRequest, message: "Audio request is missing \(field)", field: field)
        }
        return value
    }

    private func bridgeStreamState(_ value: SignalDeckStreamState) -> AgentAudioStreamState {
        switch value {
        case .unknown: .unknown
        case .offline: .offline
        case .live: .live
        }
    }

    private func bounded(_ value: String, maximum: Int, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(maximum))
    }
}

@MainActor
enum SignalDeckAgentBridgeConnection {
    static func install(controller: SignalDeckController) {
        SpatialAgentBridgeRuntime.shared.installAudioHandler(
            SignalDeckAgentAudioAdapter(controller: controller)
        )
    }
}
