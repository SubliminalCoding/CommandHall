import Foundation
import XCTest
@testable import SpatialWorkspaceApp

final class SignalDeckIntegrationTests: XCTestCase {
    func testDiscoveryV2LoadsDistinctOwnerOnlyReadAndWriteTokens() throws {
        let fixture = try DiscoveryFixture(schemaVersion: "signaldeck-control-discovery/v2")
        defer { fixture.remove() }

        let credentials = try SignalDeckControlClient(discoveryURL: fixture.discoveryURL).resolveCredentials()

        XCTAssertEqual(credentials.baseURL.absoluteString, "http://127.0.0.1:5287/")
        XCTAssertEqual(credentials.readToken, fixture.readToken)
        XCTAssertEqual(credentials.writeToken, fixture.writeToken)
        XCTAssertNotEqual(credentials.readToken, credentials.writeToken)
    }

    func testLegacyDiscoveryRemainsReadOnlyUntilSignalDeckPublishesV2() throws {
        let fixture = try DiscoveryFixture(schemaVersion: "signaldeck-control-discovery/v1")
        defer { fixture.remove() }

        let credentials = try SignalDeckControlClient(discoveryURL: fixture.discoveryURL).resolveCredentials()

        XCTAssertEqual(credentials.readToken, fixture.readToken)
        XCTAssertNil(credentials.writeToken)
    }

    func testDiscoveryRejectsGroupReadableTokenFile() throws {
        let fixture = try DiscoveryFixture(schemaVersion: "signaldeck-control-discovery/v2")
        defer { fixture.remove() }
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o644))],
            ofItemAtPath: fixture.readTokenURL.path
        )

        XCTAssertThrowsError(
            try SignalDeckControlClient(discoveryURL: fixture.discoveryURL).resolveCredentials()
        ) { error in
            guard case SignalDeckClientError.insecureFile(let role) = error else {
                return XCTFail("Expected an owner-only file failure, got \(error)")
            }
            XCTAssertTrue(role.contains("read-control"))
            XCTAssertFalse(error.localizedDescription.contains(fixture.directory.path))
        }
    }

    func testDiscoveryRejectsTokenSymlinkAndSharedReadWriteSecret() throws {
        let fixture = try DiscoveryFixture(schemaVersion: "signaldeck-control-discovery/v2")
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.readTokenURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.readTokenURL,
            withDestinationURL: fixture.writeTokenURL
        )
        XCTAssertThrowsError(
            try SignalDeckControlClient(discoveryURL: fixture.discoveryURL).resolveCredentials()
        ) { error in
            guard case SignalDeckClientError.insecureFile = error else {
                return XCTFail("Expected a symlink rejection, got \(error)")
            }
        }

        try FileManager.default.removeItem(at: fixture.readTokenURL)
        try DiscoveryFixture.writeSecure(Data(fixture.writeToken.utf8), to: fixture.readTokenURL)
        XCTAssertThrowsError(
            try SignalDeckControlClient(discoveryURL: fixture.discoveryURL).resolveCredentials()
        ) { error in
            guard case SignalDeckClientError.invalidDiscovery = error else {
                return XCTFail("Expected distinct read/write tokens, got \(error)")
            }
        }
    }

    func testDiscoveryRejectsNonLoopbackAddressAndTokenOutsideItsDirectory() throws {
        let fixture = try DiscoveryFixture(schemaVersion: "signaldeck-control-discovery/v2")
        defer { fixture.remove() }
        try fixture.writeDiscovery(address: "localhost:5287")
        XCTAssertThrowsError(
            try SignalDeckControlClient(discoveryURL: fixture.discoveryURL).resolveCredentials()
        ) { error in
            guard case SignalDeckClientError.invalidDiscovery = error else {
                return XCTFail("Expected invalid loopback discovery, got \(error)")
            }
        }

        try fixture.writeDiscovery(
            address: "127.0.0.1:5287",
            readTokenPath: FileManager.default.temporaryDirectory.appendingPathComponent("untrusted-token").path
        )
        XCTAssertThrowsError(
            try SignalDeckControlClient(discoveryURL: fixture.discoveryURL).resolveCredentials()
        ) { error in
            guard case SignalDeckClientError.invalidDiscovery = error else {
                return XCTFail("Expected an adjacent-token policy failure, got \(error)")
            }
        }
    }

    func testSnapshotDecodesConfigurationOnlyTruthAndProcessingBuses() throws {
        let payload = Data(#"""
        {
          "schemaVersion":"signaldeck-control-snapshot/v1",
          "apiVersion":"v1",
          "instanceId":"instance-1",
          "observedAtMs":1786910000000,
          "version":"1.0.0",
          "engine":{"state":"idle","pipelineRunning":false},
          "integration":{"mode":"durable-logical-routing","profileManagementAvailable":true,"mutationsAvailable":true,"eventsAvailable":true,"meterTelemetryAvailable":false,"audioGraphApplied":false,"virtualDeviceOperationsAvailable":false,"panicMuteApplied":false,"mutationMode":"configuration-only"},
          "revision":7,
          "configurationAvailable":true,
          "configuredProfile":{"id":"streaming","fingerprint":"abc","revision":7,"matchesCatalog":false},
          "activeProfile":null,
          "buses":[{"id":"stream-mix","displayName":"Stream Mix","role":"stream","available":false,"muted":false,"gain":1.0,"peakDbfs":null,"clipping":false,"availabilityReason":"Not materialized"}],
          "sources":[{"id":"browser","role":"browser","displayName":"Browser","available":false,"muted":false,"gain":1.0,"processingBusIds":["browser"],"targetBusIds":["monitor-mix","stream-mix"],"availabilityReason":"Not bound","futureField":"ignored"}],
          "checks":[{"id":"audio-graph","status":"fail","message":"Not applied"}],
          "audioGraphApplied":false,
          "panicMuteApplied":false
        }
        """#.utf8)

        let snapshot = try JSONDecoder().decode(SignalDeckSnapshot.self, from: payload)

        XCTAssertEqual(snapshot.revision, 7)
        XCTAssertEqual(snapshot.configuredProfile?.id, "streaming")
        XCTAssertEqual(snapshot.configuredProfile?.matchesCatalog, false)
        XCTAssertNil(snapshot.activeProfile)
        XCTAssertFalse(snapshot.audioGraphApplied)
        XCTAssertEqual(snapshot.configurationAvailable, true)
        XCTAssertEqual(snapshot.integration.panicMuteApplied, false)
        XCTAssertEqual(snapshot.integration.mutationMode, "configuration-only")
        XCTAssertEqual(snapshot.panicMuteApplied, false)
        XCTAssertEqual(snapshot.sources.first?.processingBusIds, ["browser"])
        XCTAssertEqual(snapshot.sources.first?.targetBusIds, ["monitor-mix", "stream-mix"])
    }

    func testProfilesAndConfiguredReceiptDecodeWithoutClaimingEngineApplication() throws {
        let profilesPayload = Data(#"""
        {
          "schemaVersion":"signaldeck-control-profiles/v1","apiVersion":"v1","instanceId":"instance-1","observedAtMs":1,"revision":7,
          "configurationAvailable":true,"configuredProfile":{"id":"private-work","fingerprint":"fp","revision":7,"matchesCatalog":true},"activeProfile":null,
          "profiles":[{"id":"streaming","displayName":"Streaming","description":"OBS mix","fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","routes":{"discord":{"targetBusIds":["monitor-mix"],"gain":1.0,"muted":false}},"buses":{"stream-mix":{"gain":1.0,"muted":false}}}]
        }
        """#.utf8)
        let mutationPayload = Data(#"""
        {
          "schemaVersion":"signaldeck-control-mutation/v1","apiVersion":"v1","instanceId":"instance-1",
          "receipt":{"operationId":"audioop_1234567890","operation":"profile.apply","resourceId":"streaming","idempotencyKey":"spatial-workspace.profile.12345678","requestHash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","beforeRevision":7,"afterRevision":8,"profileId":"streaming","profileFingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","profileFingerprintSchema":"signaldeck-profile-definition/v2","consumer":"spatial-workspace","requesterScope":"owner-write","contextId":"spatial-workspace-ui","createdAtMs":1,"status":"configured","appliedToEngine":false}
        }
        """#.utf8)

        let profiles = try JSONDecoder().decode(SignalDeckProfilesSnapshot.self, from: profilesPayload)
        let mutation = try JSONDecoder().decode(SignalDeckMutationResponse.self, from: mutationPayload)

        XCTAssertEqual(profiles.profiles.first?.routes["discord"]?.targetBusIds, ["monitor-mix"])
        XCTAssertNil(profiles.activeProfile)
        XCTAssertEqual(mutation.receipt.status, "configured")
        XCTAssertFalse(mutation.receipt.appliedToEngine)
        XCTAssertNoThrow(try SignalDeckControlClient.validateProfileApplicationResponse(
            mutation,
            profileID: "streaming",
            expectedRevision: 7,
            idempotencyKey: "spatial-workspace.profile.12345678",
            contextID: "spatial-workspace-ui"
        ))
        XCTAssertThrowsError(try SignalDeckControlClient.validateProfileApplicationResponse(
            mutation,
            profileID: "streaming",
            expectedRevision: 7,
            idempotencyKey: "different-request",
            contextID: "spatial-workspace-ui"
        ))
    }

    func testSanitizedRouterEventWithoutReceiptStillRequestsRefresh() throws {
        var parser = SignalDeckSSEParser()
        XCTAssertNil(try parser.consume("event: router.changed"))
        XCTAssertNil(try parser.consume(#"data: {"schemaVersion":"signaldeck-control-event/v1","instanceId":"instance-1","sequence":4,"routerRevision":8,"observedAtMs":1,"type":"router.changed"}"#))
        let event = try XCTUnwrap(parser.consume(""))

        XCTAssertEqual(event.type, "router.changed")
        XCTAssertEqual(event.instanceId, "instance-1")
        XCTAssertEqual(event.routerRevision, 8)
        XCTAssertNil(event.receipt)
    }

    func testProfileApplicationPolicyRequiresAuthoritativeWritableSnapshot() {
        let known: Set<String> = ["private-work", "streaming"]
        XCTAssertTrue(SignalDeckApplicationPolicy.canApply(
            profileID: "streaming",
            knownProfileIDs: known,
            configuredProfileID: "private-work",
            connected: true,
            authoritative: true,
            mutationsAvailable: true,
            hasWriteAccess: true,
            busy: false
        ))
        XCTAssertFalse(SignalDeckApplicationPolicy.canApply(
            profileID: "streaming",
            knownProfileIDs: known,
            configuredProfileID: "private-work",
            connected: true,
            authoritative: false,
            mutationsAvailable: true,
            hasWriteAccess: true,
            busy: false
        ))
        XCTAssertFalse(SignalDeckApplicationPolicy.canApply(
            profileID: "streaming",
            knownProfileIDs: known,
            configuredProfileID: "private-work",
            connected: true,
            authoritative: true,
            mutationsAvailable: true,
            hasWriteAccess: false,
            busy: false
        ))
        XCTAssertFalse(SignalDeckApplicationPolicy.canApply(
            profileID: "private-work",
            knownProfileIDs: known,
            configuredProfileID: "private-work",
            connected: true,
            authoritative: true,
            mutationsAvailable: true,
            hasWriteAccess: true,
            busy: false
        ))
    }

    func testSemanticPlansRejectUnknownResourcesAndBindRevision() throws {
        let fixture = semanticFixture(revision: 7)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertThrowsError(try SignalDeckSemanticPlanner.makePlan(
            action: .listenPrivately(sourceID: "unknown-source"),
            snapshot: fixture.snapshot,
            profiles: fixture.profiles,
            streamState: .live,
            requester: "codex:nova",
            now: now
        )) { error in
            XCTAssertEqual(error as? SignalDeckPlanError, .unknownSource("unknown-source"))
        }
        XCTAssertThrowsError(try SignalDeckSemanticPlanner.makePlan(
            action: .setBusMuted(busID: "unknown-bus", muted: true),
            snapshot: fixture.snapshot,
            profiles: fixture.profiles,
            streamState: .live,
            requester: "claude:maya",
            now: now
        )) { error in
            XCTAssertEqual(error as? SignalDeckPlanError, .unknownBus("unknown-bus"))
        }

        let plan = try SignalDeckSemanticPlanner.makePlan(
            action: .excludeFromStream(sourceID: "browser"),
            snapshot: fixture.snapshot,
            profiles: fixture.profiles,
            streamState: .live,
            requester: "codex:nova",
            now: now,
            nonce: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!
        )
        XCTAssertEqual(plan.expectedRevision, 7)
        XCTAssertEqual(SignalDeckSemanticPlanner.revisionBoundRevision(plan.id), 7)
        XCTAssertNoThrow(try SignalDeckSemanticPlanner.validate(plan, revision: 7, now: now))
        XCTAssertThrowsError(try SignalDeckSemanticPlanner.validate(plan, revision: 8, now: now)) { error in
            XCTAssertEqual(error as? SignalDeckPlanError, .staleRevision(expected: 7, current: 8))
        }
    }

    func testSemanticPlanExpiryFailsClosed() throws {
        let fixture = semanticFixture(revision: 11)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = try SignalDeckSemanticPlanner.makePlan(
            action: .muteSource(sourceID: "browser"),
            snapshot: fixture.snapshot,
            profiles: fixture.profiles,
            streamState: .live,
            requester: "gemini:reviewer",
            now: now,
            lifetime: 1
        )

        XCTAssertThrowsError(try SignalDeckSemanticPlanner.validate(
            plan,
            revision: 11,
            now: now.addingTimeInterval(1)
        )) { error in
            XCTAssertEqual(error as? SignalDeckPlanError, .expired)
        }
    }

    func testExposureWhileLiveNeedsApprovalButPrivacyReductionIsAutomatic() throws {
        let fixture = semanticFixture(revision: 5)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let privatePlan = try SignalDeckSemanticPlanner.makePlan(
            action: .excludeFromStream(sourceID: "browser"),
            snapshot: fixture.snapshot,
            profiles: fixture.profiles,
            streamState: .live,
            requester: "codex:nova",
            now: now
        )
        XCTAssertEqual(privatePlan.direction, .privacyReduction)
        XCTAssertEqual(privatePlan.policy, .automatic)

        let liveExposure = try SignalDeckSemanticPlanner.makePlan(
            action: .includeInStream(sourceID: "discord"),
            snapshot: fixture.snapshot,
            profiles: fixture.profiles,
            streamState: .live,
            requester: "claude:maya",
            now: now
        )
        XCTAssertEqual(liveExposure.direction, .exposureIncrease)
        XCTAssertEqual(liveExposure.policy, .requiresApproval)

        let unknownExposure = try SignalDeckSemanticPlanner.makePlan(
            action: .includeInStream(sourceID: "discord"),
            snapshot: fixture.snapshot,
            profiles: fixture.profiles,
            streamState: .unknown,
            requester: "claude:maya",
            now: now
        )
        XCTAssertEqual(unknownExposure.policy, .requiresApproval)

        let offlineExposure = try SignalDeckSemanticPlanner.makePlan(
            action: .includeInStream(sourceID: "discord"),
            snapshot: fixture.snapshot,
            profiles: fixture.profiles,
            streamState: .offline,
            requester: "claude:maya",
            now: now
        )
        XCTAssertEqual(offlineExposure.policy, .automatic)
    }

    func testMutationReceiptsBindEveryExpectedField() throws {
        let hash = String(repeating: "a", count: 64)
        let route = mutationResponse(
            operation: "route.put",
            resourceID: "browser",
            profileID: nil,
            profileFingerprint: nil,
            requestHash: hash
        )
        XCTAssertNoThrow(try SignalDeckControlClient.validateMutationResponse(
            route,
            operation: "route.put",
            resourceID: "browser",
            expectedRevision: 7,
            idempotencyKey: "agent.route.12345678",
            contextID: "spatial-workspace:codex-nova",
            expectedInstanceID: "instance-1"
        ))
        XCTAssertThrowsError(try SignalDeckControlClient.validateMutationResponse(
            route,
            operation: "route.put",
            resourceID: "discord",
            expectedRevision: 7,
            idempotencyKey: "agent.route.12345678",
            contextID: "spatial-workspace:codex-nova",
            expectedInstanceID: "instance-1"
        ))

        let panicFingerprint = String(repeating: "b", count: 64)
        let panic = mutationResponse(
            operation: "panic.mute",
            resourceID: nil,
            profileID: "panic-muted",
            profileFingerprint: panicFingerprint,
            requestHash: hash
        )
        XCTAssertNoThrow(try SignalDeckControlClient.validateMutationResponse(
            panic,
            operation: "panic.mute",
            resourceID: nil,
            expectedRevision: 7,
            idempotencyKey: "agent.route.12345678",
            contextID: "spatial-workspace:codex-nova",
            expectedInstanceID: "instance-1",
            expectedProfileID: "panic-muted",
            expectedProfileFingerprint: panicFingerprint
        ))
    }

    func testReceiptStatusMustMatchEngineApplicationTruth() {
        let configuredClaimingApplication = mutationResponse(
            operation: "bus.put",
            resourceID: "stream-mix",
            profileID: nil,
            profileFingerprint: nil,
            requestHash: String(repeating: "c", count: 64),
            appliedToEngine: true
        )

        XCTAssertThrowsError(try SignalDeckControlClient.validateMutationResponse(
            configuredClaimingApplication,
            operation: "bus.put",
            resourceID: "stream-mix",
            expectedRevision: 7,
            idempotencyKey: "agent.route.12345678",
            contextID: "spatial-workspace:codex-nova",
            expectedInstanceID: "instance-1"
        ))

        let applied = mutationResponse(
            operation: "bus.put",
            resourceID: "stream-mix",
            profileID: nil,
            profileFingerprint: nil,
            requestHash: String(repeating: "c", count: 64),
            status: "applied",
            appliedToEngine: true
        )
        XCTAssertNoThrow(try SignalDeckControlClient.validateMutationResponse(
            applied,
            operation: "bus.put",
            resourceID: "stream-mix",
            expectedRevision: 7,
            idempotencyKey: "agent.route.12345678",
            contextID: "spatial-workspace:codex-nova",
            expectedInstanceID: "instance-1"
        ))

        let appliedWithoutEvidence = mutationResponse(
            operation: "bus.put",
            resourceID: "stream-mix",
            profileID: nil,
            profileFingerprint: nil,
            requestHash: String(repeating: "c", count: 64),
            status: "applied",
            appliedToEngine: false
        )
        XCTAssertThrowsError(try SignalDeckControlClient.validateMutationResponse(
            appliedWithoutEvidence,
            operation: "bus.put",
            resourceID: "stream-mix",
            expectedRevision: 7,
            idempotencyKey: "agent.route.12345678",
            contextID: "spatial-workspace:codex-nova",
            expectedInstanceID: "instance-1"
        ))
    }

    func testRealSignalDeckReadOnlyInteropWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_SIGNALDECK_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_SIGNALDECK_E2E=1 while SignalDeck is running.")
        }

        let client = SignalDeckControlClient()
        let credentials = try client.resolveCredentials()
        let capabilities = try await client.fetchCapabilities(credentials: credentials)
        let snapshot = try await client.fetchSnapshot(credentials: credentials)
        let profiles = try await client.fetchProfiles(credentials: credentials)

        XCTAssertNotNil(credentials.writeToken)
        XCTAssertTrue(capabilities.snapshot)
        XCTAssertTrue(capabilities.profiles)
        XCTAssertEqual(snapshot.instanceId, profiles.instanceId)
        XCTAssertEqual(snapshot.revision, profiles.revision)
        XCTAssertEqual(snapshot.configurationAvailable, profiles.configurationAvailable)
        XCTAssertFalse(snapshot.audioGraphApplied)
        XCTAssertTrue(snapshot.buses.allSatisfy { !$0.available })
        XCTAssertEqual(Set(profiles.profiles.map(\.id)), [
            "private-work", "streaming", "stage-on-air", "stage-muted", "recording", "panic-muted",
        ])
    }
}

private func semanticFixture(
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
            availabilityReason: "Not materialized"
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
            availabilityReason: "Not materialized"
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
            availabilityReason: "Not bound"
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
            availabilityReason: "Not bound"
        ),
    ]
    let privateProfile = SignalDeckProfile(
        id: "private-work",
        displayName: "Private Work",
        description: "Nothing is sent to Stream Mix",
        fingerprint: String(repeating: "1", count: 64),
        routes: [
            "browser": SignalDeckRouteConfiguration(targetBusIds: ["monitor-mix"], gain: 1, muted: false),
            "discord": SignalDeckRouteConfiguration(targetBusIds: ["monitor-mix"], gain: 1, muted: false),
        ],
        buses: [
            "monitor-mix": SignalDeckBusControl(gain: 1, muted: false),
            "stream-mix": SignalDeckBusControl(gain: 1, muted: true),
        ]
    )
    let streamingProfile = SignalDeckProfile(
        id: "streaming",
        displayName: "Streaming",
        description: "Browser is included while Discord remains private",
        fingerprint: String(repeating: "2", count: 64),
        routes: [
            "browser": SignalDeckRouteConfiguration(
                targetBusIds: ["monitor-mix", "stream-mix"],
                gain: 1,
                muted: false
            ),
            "discord": SignalDeckRouteConfiguration(targetBusIds: ["monitor-mix"], gain: 1, muted: false),
        ],
        buses: [
            "monitor-mix": SignalDeckBusControl(gain: 1, muted: false),
            "stream-mix": SignalDeckBusControl(gain: 1, muted: false),
        ]
    )
    let panicProfile = SignalDeckProfile(
        id: "panic-muted",
        displayName: "Panic Muted",
        description: "Every logical route and bus is muted",
        fingerprint: String(repeating: "3", count: 64),
        routes: [
            "browser": SignalDeckRouteConfiguration(targetBusIds: [], gain: 1, muted: true),
            "discord": SignalDeckRouteConfiguration(targetBusIds: [], gain: 1, muted: true),
        ],
        buses: [
            "monitor-mix": SignalDeckBusControl(gain: 1, muted: true),
            "stream-mix": SignalDeckBusControl(gain: 1, muted: true),
        ]
    )
    let snapshot = SignalDeckSnapshot(
        schemaVersion: "signaldeck-control-snapshot/v1",
        apiVersion: "v1",
        instanceId: "instance-1",
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
        checks: [SignalDeckCheck(id: "audio-graph", status: "fail", message: "Not applied")],
        audioGraphApplied: false,
        panicMuteApplied: false
    )
    let profiles = SignalDeckProfilesSnapshot(
        schemaVersion: "signaldeck-control-profiles/v1",
        apiVersion: "v1",
        instanceId: "instance-1",
        observedAtMs: 1,
        revision: revision,
        configurationAvailable: true,
        configuredProfile: nil,
        activeProfile: nil,
        profiles: [privateProfile, streamingProfile, panicProfile]
    )
    return (snapshot, profiles)
}

private func mutationResponse(
    operation: String,
    resourceID: String?,
    profileID: String?,
    profileFingerprint: String?,
    requestHash: String,
    status: String = "configured",
    appliedToEngine: Bool = false
) -> SignalDeckMutationResponse {
    SignalDeckMutationResponse(
        schemaVersion: "signaldeck-control-mutation/v1",
        apiVersion: "v1",
        instanceId: "instance-1",
        receipt: SignalDeckMutationReceipt(
            operationId: "audioop_1234567890",
            operation: operation,
            resourceId: resourceID,
            idempotencyKey: "agent.route.12345678",
            requestHash: requestHash,
            beforeRevision: 7,
            afterRevision: 8,
            profileId: profileID,
            profileFingerprint: profileFingerprint,
            profileFingerprintSchema: profileID == nil ? nil : "signaldeck-profile-definition/v2",
            consumer: "spatial-workspace",
            requesterScope: "owner-write",
            contextId: "spatial-workspace:codex-nova",
            createdAtMs: 1,
            status: status,
            appliedToEngine: appliedToEngine
        )
    )
}

private final class DiscoveryFixture {
    let directory: URL
    let discoveryURL: URL
    let readTokenURL: URL
    let writeTokenURL: URL
    let readToken: String
    let writeToken: String
    let schemaVersion: String

    init(schemaVersion: String) throws {
        self.schemaVersion = schemaVersion
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("signaldeck-spatial-\(UUID().uuidString)", isDirectory: true)
        discoveryURL = directory.appendingPathComponent("control.json")
        readTokenURL = directory.appendingPathComponent("control-read-token")
        writeTokenURL = directory.appendingPathComponent("control-write-token")
        readToken = Self.token(byte: 0x11)
        writeToken = Self.token(byte: 0x22)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.writeSecure(Data(readToken.utf8), to: readTokenURL)
        try Self.writeSecure(Data(writeToken.utf8), to: writeTokenURL)
        try writeDiscovery()
    }

    func writeDiscovery(address: String = "127.0.0.1:5287", readTokenPath: String? = nil) throws {
        var document: [String: Any] = [
            "schemaVersion": schemaVersion,
            "apiVersion": "v1",
            "address": address,
            "tokenFile": readTokenPath ?? readTokenURL.path,
        ]
        if schemaVersion == "signaldeck-control-discovery/v2" {
            document["readTokenFile"] = readTokenPath ?? readTokenURL.path
            document["writeTokenFile"] = writeTokenURL.path
        }
        try Self.writeSecure(try JSONSerialization.data(withJSONObject: document), to: discoveryURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func token(byte: UInt8) -> String {
        Data(repeating: byte, count: 32)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    fileprivate static func writeSecure(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
    }
}
