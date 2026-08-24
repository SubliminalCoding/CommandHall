import Foundation
import SpatialAgentBridgeKit
import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class AgentBridgePolicyTests: XCTestCase {
    private final class AudioController: SignalDeckAgentAudioControlling {
        var streamState: SignalDeckStreamState
        let snapshot: SignalDeckSnapshot?
        let profiles: SignalDeckProfilesSnapshot
        var applyCalls = 0
        var preparedPlanIDs: Set<String> = []

        init(streamState: SignalDeckStreamState) {
            self.streamState = streamState
            let fixture = Self.fixture(revision: 5)
            snapshot = fixture.snapshot
            profiles = fixture.profiles
        }

        var authoritativeStatus: SignalDeckAuthoritativeStatus {
            SignalDeckAuthoritativeStatus(
                connected: true,
                authoritative: true,
                instanceID: snapshot?.instanceId,
                revision: snapshot?.revision,
                sourceIDs: snapshot?.sources.map(\.id) ?? [],
                busIDs: snapshot?.buses.map(\.id) ?? [],
                configuredProfileID: nil,
                truth: .configuredOnly,
                mutationMode: "configuration-only",
                streamState: streamState
            )
        }

        var routingTruth: SignalDeckRoutingTruth { .configuredOnly }

        func createPlan(
            action: SignalDeckSemanticAction,
            requestedBy: String,
            reason: String?,
            streamState requestedStreamState: SignalDeckStreamState?,
            now: Date,
            lifetime: TimeInterval
        ) throws -> SignalDeckChangePlan {
            let plan = try SignalDeckSemanticPlanner.makePlan(
                action: action,
                snapshot: try XCTUnwrap(snapshot),
                profiles: profiles,
                streamState: requestedStreamState ?? streamState,
                requester: requestedBy,
                reason: reason,
                now: now,
                lifetime: lifetime
            )
            preparedPlanIDs.insert(plan.id)
            return plan
        }

        func apply(
            planID: String,
            expectedRevision: UInt64,
            idempotencyKey: String,
            now: Date
        ) async throws -> SignalDeckMutationReceipt {
            applyCalls += 1
            preparedPlanIDs.remove(planID)
            return SignalDeckMutationReceipt(
                operationId: "audioop_agent_bridge_apply",
                operation: "route.put",
                resourceId: "browser",
                idempotencyKey: idempotencyKey,
                requestHash: String(repeating: "a", count: 64),
                beforeRevision: expectedRevision,
                afterRevision: expectedRevision + 1,
                profileId: nil,
                profileFingerprint: nil,
                profileFingerprintSchema: nil,
                consumer: "spatial-workspace",
                requesterScope: "owner-write",
                contextId: "spatial-workspace:agent-test",
                createdAtMs: UInt64(now.timeIntervalSince1970 * 1_000),
                status: "configured",
                appliedToEngine: false
            )
        }

        func requestPanicMute(
            idempotencyKey: String,
            requestedBy: String,
            reason: String?,
            now: Date
        ) async throws -> SignalDeckMutationReceipt {
            try await apply(planID: "panic", expectedRevision: snapshot?.revision ?? 0, idempotencyKey: idempotencyKey, now: now)
        }

        private static func fixture(
            revision: UInt64
        ) -> (snapshot: SignalDeckSnapshot, profiles: SignalDeckProfilesSnapshot) {
            let buses = [
                SignalDeckBus(
                    id: "monitor-mix",
                    displayName: "Monitor Mix",
                    role: "monitor",
                    available: false,
                    muted: false,
                    gain: 1,
                    peakDbfs: nil,
                    clipping: false,
                    availabilityReason: "Test fixture"
                ),
                SignalDeckBus(
                    id: "stream-mix",
                    displayName: "Stream Mix",
                    role: "stream",
                    available: false,
                    muted: false,
                    gain: 1,
                    peakDbfs: nil,
                    clipping: false,
                    availabilityReason: "Test fixture"
                ),
            ]
            let sources = [
                SignalDeckSource(
                    id: "browser",
                    role: "browser",
                    displayName: "Browser",
                    available: false,
                    muted: false,
                    gain: 1,
                    processingBusIds: [],
                    targetBusIds: ["monitor-mix", "stream-mix"],
                    availabilityReason: "Test fixture"
                ),
                SignalDeckSource(
                    id: "discord",
                    role: "discord",
                    displayName: "Discord",
                    available: false,
                    muted: false,
                    gain: 1,
                    processingBusIds: [],
                    targetBusIds: ["monitor-mix"],
                    availabilityReason: "Test fixture"
                ),
            ]
            let snapshot = SignalDeckSnapshot(
                schemaVersion: "signaldeck-control-snapshot/v1",
                apiVersion: "v1",
                instanceId: "instance-agent-policy",
                observedAtMs: 1,
                version: "1.0.0",
                engine: SignalDeckEngineSnapshot(state: "idle", pipelineRunning: false),
                integration: SignalDeckIntegrationSnapshot(
                    mode: "durable-logical-routing",
                    profileManagementAvailable: true,
                    mutationsAvailable: true,
                    eventsAvailable: true,
                    meterTelemetryAvailable: false,
                    audioGraphApplied: false,
                    virtualDeviceOperationsAvailable: false,
                    panicMuteApplied: false,
                    mutationMode: "configuration-only"
                ),
                revision: revision,
                configurationAvailable: true,
                configuredProfile: nil,
                activeProfile: nil,
                buses: buses,
                sources: sources,
                checks: [],
                audioGraphApplied: false,
                panicMuteApplied: false
            )
            let profiles = SignalDeckProfilesSnapshot(
                schemaVersion: "signaldeck-control-profiles/v1",
                apiVersion: "v1",
                instanceId: snapshot.instanceId,
                observedAtMs: 1,
                revision: revision,
                configurationAvailable: true,
                configuredProfile: nil,
                activeProfile: nil,
                profiles: []
            )
            return (snapshot, profiles)
        }
    }

    func testLiveAndUnknownExposureRemainOperatorApprovalProposals() async throws {
        for streamState in [SignalDeckStreamState.live, .unknown] {
            let controller = AudioController(streamState: streamState)
            let adapter = SignalDeckAgentAudioAdapter(controller: controller)
            let identity = makeIdentity()

            let planned = try await adapter.handle(
                .plan(AgentAudioPlanRequest(intent: .includeInStream, sourceID: "discord")),
                for: identity
            )
            guard case .plan(let plan) = planned else { return XCTFail("Expected a plan") }
            XCTAssertTrue(plan.requiresConfirmation)
            XCTAssertTrue(controller.preparedPlanIDs.contains(plan.id))

            do {
                _ = try await adapter.handle(
                    .apply(AgentAudioApplyRequest(
                        planID: plan.id,
                        expectedRevision: plan.expectedRevision,
                        idempotencyKey: "agent-apply-\(streamState.rawValue)"
                    )),
                    for: identity
                )
                XCTFail("Agent apply must not satisfy operator approval")
            } catch let error as AgentBridgeHandlerError {
                XCTAssertEqual(error.payload.code, .forbidden)
                XCTAssertTrue(error.payload.message.contains("operator approval"))
            }

            XCTAssertEqual(controller.applyCalls, 0)
            XCTAssertTrue(controller.preparedPlanIDs.contains(plan.id), "The proposal must remain queued for the operator")
        }
    }

    func testPrivacyReducingAgentPlanStillApplies() async throws {
        let controller = AudioController(streamState: .live)
        let adapter = SignalDeckAgentAudioAdapter(controller: controller)
        let identity = makeIdentity()

        let planned = try await adapter.handle(
            .plan(AgentAudioPlanRequest(intent: .excludeFromStream, sourceID: "browser")),
            for: identity
        )
        guard case .plan(let plan) = planned else { return XCTFail("Expected a plan") }
        XCTAssertFalse(plan.requiresConfirmation)

        let result = try await adapter.handle(
            .apply(AgentAudioApplyRequest(
                planID: plan.id,
                expectedRevision: plan.expectedRevision,
                idempotencyKey: "agent-private-apply"
            )),
            for: identity
        )

        guard case .applied(let receipt) = result else { return XCTFail("Expected an apply receipt") }
        XCTAssertEqual(receipt.planID, plan.id)
        XCTAssertEqual(controller.applyCalls, 1)
        XCTAssertFalse(controller.preparedPlanIDs.contains(plan.id))
    }

    func testPlanApplicationIsBoundToCreatingSessionNodeAndProvider() async throws {
        let controller = AudioController(streamState: .live)
        let adapter = SignalDeckAgentAudioAdapter(controller: controller)
        let creator = makeIdentity()
        let otherSession = makeIdentity()

        let planned = try await adapter.handle(
            .plan(AgentAudioPlanRequest(intent: .excludeFromStream, sourceID: "browser")),
            for: creator
        )
        guard case .plan(let plan) = planned else { return XCTFail("Expected a plan") }

        do {
            _ = try await adapter.handle(
                .apply(AgentAudioApplyRequest(
                    planID: plan.id,
                    expectedRevision: plan.expectedRevision,
                    idempotencyKey: "cross-session-apply"
                )),
                for: otherSession
            )
            XCTFail("A different bridge identity must not apply the plan")
        } catch let error as AgentBridgeHandlerError {
            XCTAssertEqual(error.payload.code, .forbidden)
        }
        XCTAssertEqual(controller.applyCalls, 0)
        XCTAssertTrue(controller.preparedPlanIDs.contains(plan.id))
    }

    func testOfflineExposurePlanCannotCrossAChangeToLiveState() async throws {
        let controller = AudioController(streamState: .offline)
        let adapter = SignalDeckAgentAudioAdapter(controller: controller)
        let identity = makeIdentity()

        let planned = try await adapter.handle(
            .plan(AgentAudioPlanRequest(intent: .includeInStream, sourceID: "discord")),
            for: identity
        )
        guard case .plan(let plan) = planned else { return XCTFail("Expected a plan") }
        XCTAssertFalse(plan.requiresConfirmation)

        controller.streamState = .live
        do {
            _ = try await adapter.handle(
                .apply(AgentAudioApplyRequest(
                    planID: plan.id,
                    expectedRevision: plan.expectedRevision,
                    idempotencyKey: "offline-to-live-apply"
                )),
                for: identity
            )
            XCTFail("An offline exposure plan must not survive a transition to live")
        } catch let error as AgentBridgeHandlerError {
            XCTAssertEqual(error.payload.code, .forbidden)
            XCTAssertTrue(error.payload.message.contains("live state changed"))
        }
        XCTAssertEqual(controller.applyCalls, 0)
    }

    private func makeIdentity() -> AgentBridgeSessionIdentity {
        AgentBridgeSessionIdentity(
            sessionID: UUID(),
            nodeID: UUID(),
            provider: "codex",
            issuedAtEpochMilliseconds: 1,
            expiresAtEpochMilliseconds: Int64.max,
            scopes: AgentBridgeSessionRegistry.allAudioScopes
        )
    }
}
