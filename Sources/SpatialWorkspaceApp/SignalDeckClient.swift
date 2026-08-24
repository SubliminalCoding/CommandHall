import Darwin
import Foundation

struct SignalDeckDiscoveryDocument: Decodable, Equatable {
    let schemaVersion: String
    let apiVersion: String
    let address: String
    let tokenFile: String?
    let readTokenFile: String?
    let writeTokenFile: String?
}

struct SignalDeckCapabilities: Decodable, Equatable {
    let schemaVersion: String
    let apiVersion: String
    let readOnly: Bool
    let snapshot: Bool
    let profiles: Bool
    let mutations: Bool
    let events: Bool
    let meters: Bool
    let logicalRouting: Bool
    let audioGraphApplication: Bool
    let virtualDeviceOperations: Bool
    let panicMuteApplied: Bool?
    let mutationMode: String?
    let idempotencyReceiptRetention: Int?
}

struct SignalDeckEngineSnapshot: Decodable, Equatable {
    let state: String
    let pipelineRunning: Bool
}

struct SignalDeckIntegrationSnapshot: Decodable, Equatable {
    let mode: String
    let profileManagementAvailable: Bool
    let mutationsAvailable: Bool
    let eventsAvailable: Bool
    let meterTelemetryAvailable: Bool
    let audioGraphApplied: Bool
    let virtualDeviceOperationsAvailable: Bool
    let panicMuteApplied: Bool?
    let mutationMode: String?
}

struct SignalDeckProfileState: Decodable, Equatable {
    let id: String
    let fingerprint: String
    let revision: UInt64
    let matchesCatalog: Bool?
}

struct SignalDeckActiveProfile: Decodable, Equatable {
    let id: String
    let fingerprint: String
    let revision: UInt64
    let appliedToEngine: Bool
}

struct SignalDeckBus: Decodable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let role: String
    let available: Bool
    let muted: Bool
    let gain: Double
    let peakDbfs: Double?
    let clipping: Bool
    let availabilityReason: String
}

struct SignalDeckSource: Decodable, Equatable, Identifiable {
    let id: String
    let role: String
    let displayName: String
    let available: Bool
    let muted: Bool
    let gain: Double
    let processingBusIds: [String]?
    let targetBusIds: [String]
    let availabilityReason: String
}

struct SignalDeckCheck: Decodable, Equatable, Identifiable {
    let id: String
    let status: String
    let message: String
}

struct SignalDeckSnapshot: Decodable, Equatable {
    let schemaVersion: String
    let apiVersion: String
    let instanceId: String
    let observedAtMs: UInt64
    let version: String
    let engine: SignalDeckEngineSnapshot
    let integration: SignalDeckIntegrationSnapshot
    let revision: UInt64
    let configurationAvailable: Bool?
    let configuredProfile: SignalDeckProfileState?
    let activeProfile: SignalDeckActiveProfile?
    let buses: [SignalDeckBus]
    let sources: [SignalDeckSource]
    let checks: [SignalDeckCheck]
    let audioGraphApplied: Bool
    let panicMuteApplied: Bool?
}

struct SignalDeckRouteConfiguration: Decodable, Equatable {
    let targetBusIds: [String]
    let gain: Double
    let muted: Bool
}

struct SignalDeckBusControl: Decodable, Equatable {
    let gain: Double
    let muted: Bool
}

struct SignalDeckProfile: Decodable, Equatable, Identifiable {
    let id: String
    let displayName: String
    let description: String
    let fingerprint: String
    let routes: [String: SignalDeckRouteConfiguration]
    let buses: [String: SignalDeckBusControl]
}

struct SignalDeckProfilesSnapshot: Decodable, Equatable {
    let schemaVersion: String
    let apiVersion: String
    let instanceId: String
    let observedAtMs: UInt64
    let revision: UInt64
    let configurationAvailable: Bool?
    let configuredProfile: SignalDeckProfileState?
    let activeProfile: SignalDeckActiveProfile?
    let profiles: [SignalDeckProfile]
}

struct SignalDeckMutationReceipt: Decodable, Equatable {
    let operationId: String
    let operation: String
    let resourceId: String?
    let idempotencyKey: String
    let requestHash: String
    let beforeRevision: UInt64
    let afterRevision: UInt64
    let profileId: String?
    let profileFingerprint: String?
    let profileFingerprintSchema: String?
    let consumer: String
    let requesterScope: String?
    let contextId: String
    let createdAtMs: UInt64
    let status: String
    let appliedToEngine: Bool
}

struct SignalDeckMutationResponse: Decodable, Equatable {
    let schemaVersion: String
    let apiVersion: String
    let instanceId: String
    let receipt: SignalDeckMutationReceipt
}

struct SignalDeckControlEvent: Decodable, Equatable {
    let schemaVersion: String
    let sequence: UInt64?
    let routerRevision: UInt64?
    let observedAtMs: UInt64?
    let type: String
    let instanceId: String?
    let reason: String?
    let receipt: SignalDeckMutationReceipt?
    let operationId: String?
    let operation: String?
    let resourceId: String?
}

struct SignalDeckCredentials {
    let baseURL: URL
    let readToken: String
    let writeToken: String?
}

enum SignalDeckClientError: LocalizedError {
    case discoveryUnavailable
    case insecureFile(String)
    case invalidDiscovery(String)
    case invalidToken(String)
    case writeAccessUnavailable
    case invalidRequest(String)
    case invalidResponse
    case responseTooLarge
    case unsupportedContract(String)
    case http(status: Int, code: String?, message: String?, currentRevision: UInt64?)

    var errorDescription: String? {
        switch self {
        case .discoveryUnavailable:
            "SignalDeck has not published its local control discovery yet. Open SignalDeck once, then reconnect."
        case .insecureFile(let role):
            "The SignalDeck \(role) file did not pass the owner-only security check."
        case .invalidDiscovery(let reason):
            "SignalDeck discovery is invalid: \(reason)"
        case .invalidToken(let role):
            "The SignalDeck \(role) token is invalid."
        case .writeAccessUnavailable:
            "Restart the updated SignalDeck app to publish its write-control token."
        case .invalidRequest(let reason):
            "SignalDeck control request is invalid: \(reason)"
        case .invalidResponse:
            "SignalDeck returned an invalid local response."
        case .responseTooLarge:
            "SignalDeck returned more control data than the client accepts."
        case .unsupportedContract(let contract):
            "SignalDeck returned an unsupported control contract (\(contract))."
        case .http(let status, _, let message, _):
            message ?? "SignalDeck returned HTTP \(status)."
        }
    }

    var isUnauthorized: Bool {
        if case .http(status: 401, code: _, message: _, currentRevision: _) = self { return true }
        return false
    }

    var isRevisionConflict: Bool {
        if case .http(status: 409, code: "stale-router-revision", message: _, currentRevision: _) = self {
            return true
        }
        return false
    }
}

private struct SignalDeckErrorResponse: Decodable {
    let schemaVersion: String?
    let code: String?
    let message: String?
    let currentRouterRevision: UInt64?
}

private struct SignalDeckProfileApplicationRequest: Encodable {
    let schemaVersion = "signaldeck-profile-application/v1"
    let profileId: String
    let expectedRouterRevision: UInt64
    let consumer = "spatial-workspace"
    let contextId: String
    let idempotencyKey: String
}

private struct SignalDeckRouteMutationRequest: Encodable {
    let schemaVersion = "signaldeck-route-mutation/v1"
    let targetBusIds: [String]
    let gain: Double
    let muted: Bool
    let expectedRouterRevision: UInt64
    let consumer = "spatial-workspace"
    let contextId: String
    let idempotencyKey: String
}

private struct SignalDeckBusMutationRequest: Encodable {
    let schemaVersion = "signaldeck-bus-mutation/v1"
    let gain: Double
    let muted: Bool
    let expectedRouterRevision: UInt64
    let consumer = "spatial-workspace"
    let contextId: String
    let idempotencyKey: String
}

private struct SignalDeckPanicMuteRequest: Encodable {
    let schemaVersion = "signaldeck-panic-mute/v1"
    let expectedRouterRevision: UInt64
    let consumer = "spatial-workspace"
    let contextId: String
    let idempotencyKey: String
}

struct SignalDeckSSEParser {
    private(set) var eventName: String?
    private var dataLines: [String] = []

    mutating func consume(_ line: String) throws -> SignalDeckControlEvent? {
        guard line.utf8.count <= 16 * 1_024 else { throw SignalDeckClientError.responseTooLarge }
        if line.isEmpty {
            defer {
                eventName = nil
                dataLines.removeAll(keepingCapacity: true)
            }
            guard !dataLines.isEmpty else { return nil }
            let data = Data(dataLines.joined(separator: "\n").utf8)
            let event = try JSONDecoder().decode(SignalDeckControlEvent.self, from: data)
            guard event.schemaVersion == "signaldeck-control-event/v1" else {
                throw SignalDeckClientError.unsupportedContract(event.schemaVersion)
            }
            return event
        }
        if line.hasPrefix(":") { return nil }
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            guard dataLines.count < 16 else { throw SignalDeckClientError.responseTooLarge }
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

struct SignalDeckControlClient {
    static let defaultDiscoveryURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("com.clawstudio.signaldeck.dev", isDirectory: true)
        .appendingPathComponent("control.json", isDirectory: false)

    let discoveryURL: URL
    let session: URLSession

    init(discoveryURL: URL = Self.defaultDiscoveryURL, session: URLSession? = nil) {
        self.discoveryURL = discoveryURL
        self.session = session ?? Self.makeSession()
    }

    func resolveCredentials() throws -> SignalDeckCredentials {
        let discoveryData: Data
        do {
            discoveryData = try SecureOwnerFile.read(discoveryURL, role: "discovery", maximumBytes: 16 * 1_024)
        } catch let error as SignalDeckClientError {
            throw error
        } catch {
            throw SignalDeckClientError.discoveryUnavailable
        }

        let discovery: SignalDeckDiscoveryDocument
        do {
            discovery = try JSONDecoder().decode(SignalDeckDiscoveryDocument.self, from: discoveryData)
        } catch {
            throw SignalDeckClientError.invalidDiscovery("the JSON document could not be decoded")
        }
        guard discovery.apiVersion == "v1" else {
            throw SignalDeckClientError.unsupportedContract(discovery.apiVersion)
        }
        guard discovery.schemaVersion == "signaldeck-control-discovery/v1"
                || discovery.schemaVersion == "signaldeck-control-discovery/v2" else {
            throw SignalDeckClientError.unsupportedContract(discovery.schemaVersion)
        }
        guard let baseURL = Self.loopbackURL(for: discovery.address) else {
            throw SignalDeckClientError.invalidDiscovery("the control address is not an IPv4 loopback endpoint")
        }

        let readPath = discovery.readTokenFile ?? discovery.tokenFile
        guard let readPath else {
            throw SignalDeckClientError.invalidDiscovery("the read-token file is missing")
        }
        let readURL = try validatedTokenURL(readPath)
        let readToken = try Self.readToken(at: readURL, role: "read-control")

        let writeToken: String?
        if discovery.schemaVersion == "signaldeck-control-discovery/v2" {
            guard let writePath = discovery.writeTokenFile else {
                throw SignalDeckClientError.invalidDiscovery("the write-token file is missing")
            }
            writeToken = try Self.readToken(at: validatedTokenURL(writePath), role: "write-control")
            guard writeToken != readToken else {
                throw SignalDeckClientError.invalidDiscovery("read and write tokens must be distinct")
            }
        } else {
            writeToken = nil
        }
        return SignalDeckCredentials(baseURL: baseURL, readToken: readToken, writeToken: writeToken)
    }

    func fetchCapabilities(credentials: SignalDeckCredentials) async throws -> SignalDeckCapabilities {
        let value: SignalDeckCapabilities = try await get("v1/capabilities", credentials: credentials)
        guard value.schemaVersion == "signaldeck-control-capabilities/v1", value.apiVersion == "v1" else {
            throw SignalDeckClientError.unsupportedContract(value.schemaVersion)
        }
        return value
    }

    func fetchSnapshot(credentials: SignalDeckCredentials) async throws -> SignalDeckSnapshot {
        let value: SignalDeckSnapshot = try await get("v1/snapshot", credentials: credentials)
        guard value.schemaVersion == "signaldeck-control-snapshot/v1", value.apiVersion == "v1" else {
            throw SignalDeckClientError.unsupportedContract(value.schemaVersion)
        }
        guard value.revision > 0,
              !value.instanceId.isEmpty,
              value.buses.count <= 32,
              value.sources.count <= 32,
              value.checks.count <= 32 else {
            throw SignalDeckClientError.invalidResponse
        }
        try Self.validateSnapshotShape(value)
        return value
    }

    func fetchProfiles(credentials: SignalDeckCredentials) async throws -> SignalDeckProfilesSnapshot {
        let value: SignalDeckProfilesSnapshot = try await get("v1/profiles", credentials: credentials)
        guard value.schemaVersion == "signaldeck-control-profiles/v1", value.apiVersion == "v1" else {
            throw SignalDeckClientError.unsupportedContract(value.schemaVersion)
        }
        guard value.revision > 0, !value.instanceId.isEmpty, value.profiles.count <= 32 else {
            throw SignalDeckClientError.invalidResponse
        }
        try Self.validateProfilesShape(value)
        return value
    }

    func applyProfile(
        _ profileID: String,
        expectedRevision: UInt64,
        idempotencyKey: String,
        contextID: String,
        credentials: SignalDeckCredentials,
        expectedInstanceID: String? = nil,
        expectedProfileFingerprint: String? = nil
    ) async throws -> SignalDeckMutationResponse {
        guard let writeToken = credentials.writeToken else {
            throw SignalDeckClientError.writeAccessUnavailable
        }
        try Self.validateResourceID(profileID, role: "profile")
        try Self.validateMutationMetadata(
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID
        )
        let body = SignalDeckProfileApplicationRequest(
            profileId: profileID,
            expectedRouterRevision: expectedRevision,
            contextId: contextID,
            idempotencyKey: idempotencyKey
        )
        var request = request(
            "v1/profile-applications",
            baseURL: credentials.baseURL,
            token: writeToken,
            method: "POST"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let value: SignalDeckMutationResponse = try await send(request, expectedStatus: 202)
        return try Self.validateProfileApplicationResponse(
            value,
            profileID: profileID,
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID,
            expectedInstanceID: expectedInstanceID,
            expectedProfileFingerprint: expectedProfileFingerprint
        )
    }

    static func validateProfileApplicationResponse(
        _ value: SignalDeckMutationResponse,
        profileID: String,
        expectedRevision: UInt64,
        idempotencyKey: String,
        contextID: String,
        expectedInstanceID: String? = nil,
        expectedProfileFingerprint: String? = nil
    ) throws -> SignalDeckMutationResponse {
        try validateMutationResponse(
            value,
            operation: "profile.apply",
            resourceID: profileID,
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID,
            expectedInstanceID: expectedInstanceID,
            expectedProfileID: profileID,
            expectedProfileFingerprint: expectedProfileFingerprint
        )
    }

    func putRoute(
        sourceID: String,
        targetBusIDs: [String],
        gain: Double,
        muted: Bool,
        expectedRevision: UInt64,
        idempotencyKey: String,
        contextID: String,
        credentials: SignalDeckCredentials,
        expectedInstanceID: String? = nil
    ) async throws -> SignalDeckMutationResponse {
        guard let writeToken = credentials.writeToken else {
            throw SignalDeckClientError.writeAccessUnavailable
        }
        try Self.validateResourceID(sourceID, role: "source")
        try Self.validateTargetBusIDs(targetBusIDs)
        try Self.validateGain(gain)
        try Self.validateMutationMetadata(
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID
        )
        let body = SignalDeckRouteMutationRequest(
            targetBusIds: targetBusIDs,
            gain: gain,
            muted: muted,
            expectedRouterRevision: expectedRevision,
            contextId: contextID,
            idempotencyKey: idempotencyKey
        )
        var mutationRequest = request(
            "v1/routes/\(sourceID)",
            baseURL: credentials.baseURL,
            token: writeToken,
            method: "PUT"
        )
        mutationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mutationRequest.httpBody = try JSONEncoder().encode(body)
        let value: SignalDeckMutationResponse = try await send(mutationRequest, expectedStatus: 202)
        return try Self.validateMutationResponse(
            value,
            operation: "route.put",
            resourceID: sourceID,
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID,
            expectedInstanceID: expectedInstanceID
        )
    }

    func putBus(
        busID: String,
        gain: Double,
        muted: Bool,
        expectedRevision: UInt64,
        idempotencyKey: String,
        contextID: String,
        credentials: SignalDeckCredentials,
        expectedInstanceID: String? = nil
    ) async throws -> SignalDeckMutationResponse {
        guard let writeToken = credentials.writeToken else {
            throw SignalDeckClientError.writeAccessUnavailable
        }
        try Self.validateResourceID(busID, role: "bus")
        try Self.validateGain(gain)
        try Self.validateMutationMetadata(
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID
        )
        let body = SignalDeckBusMutationRequest(
            gain: gain,
            muted: muted,
            expectedRouterRevision: expectedRevision,
            contextId: contextID,
            idempotencyKey: idempotencyKey
        )
        var mutationRequest = request(
            "v1/buses/\(busID)",
            baseURL: credentials.baseURL,
            token: writeToken,
            method: "PUT"
        )
        mutationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mutationRequest.httpBody = try JSONEncoder().encode(body)
        let value: SignalDeckMutationResponse = try await send(mutationRequest, expectedStatus: 202)
        return try Self.validateMutationResponse(
            value,
            operation: "bus.put",
            resourceID: busID,
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID,
            expectedInstanceID: expectedInstanceID
        )
    }

    func panicMute(
        expectedRevision: UInt64,
        idempotencyKey: String,
        contextID: String,
        credentials: SignalDeckCredentials,
        expectedInstanceID: String? = nil,
        expectedProfileFingerprint: String? = nil
    ) async throws -> SignalDeckMutationResponse {
        guard let writeToken = credentials.writeToken else {
            throw SignalDeckClientError.writeAccessUnavailable
        }
        try Self.validateMutationMetadata(
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID
        )
        let body = SignalDeckPanicMuteRequest(
            expectedRouterRevision: expectedRevision,
            contextId: contextID,
            idempotencyKey: idempotencyKey
        )
        var mutationRequest = request(
            "v1/panic-mute",
            baseURL: credentials.baseURL,
            token: writeToken,
            method: "POST"
        )
        mutationRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        mutationRequest.httpBody = try JSONEncoder().encode(body)
        let value: SignalDeckMutationResponse = try await send(mutationRequest, expectedStatus: 202)
        return try Self.validateMutationResponse(
            value,
            operation: "panic.mute",
            resourceID: nil,
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID,
            expectedInstanceID: expectedInstanceID,
            expectedProfileID: "panic-muted",
            expectedProfileFingerprint: expectedProfileFingerprint
        )
    }

    static func validateMutationResponse(
        _ value: SignalDeckMutationResponse,
        operation: String,
        resourceID: String?,
        expectedRevision: UInt64,
        idempotencyKey: String,
        contextID: String,
        expectedInstanceID: String? = nil,
        expectedProfileID: String? = nil,
        expectedProfileFingerprint: String? = nil
    ) throws -> SignalDeckMutationResponse {
        try validateMutationMetadata(
            expectedRevision: expectedRevision,
            idempotencyKey: idempotencyKey,
            contextID: contextID
        )
        switch operation {
        case "profile.apply":
            guard let resourceID, expectedProfileID == resourceID else {
                throw SignalDeckClientError.invalidResponse
            }
            try validateResourceID(resourceID, role: "profile")
        case "route.put":
            guard let resourceID, expectedProfileID == nil else {
                throw SignalDeckClientError.invalidResponse
            }
            try validateResourceID(resourceID, role: "source")
        case "bus.put":
            guard let resourceID, expectedProfileID == nil else {
                throw SignalDeckClientError.invalidResponse
            }
            try validateResourceID(resourceID, role: "bus")
        case "panic.mute":
            guard resourceID == nil, expectedProfileID == "panic-muted" else {
                throw SignalDeckClientError.invalidResponse
            }
        default:
            throw SignalDeckClientError.invalidResponse
        }
        if let expectedInstanceID, expectedInstanceID.isEmpty {
            throw SignalDeckClientError.invalidResponse
        }
        if let expectedProfileFingerprint, !isSHA256(expectedProfileFingerprint) {
            throw SignalDeckClientError.invalidResponse
        }
        let receipt = value.receipt
        let applicationTruthIsConsistent = (receipt.status == "configured" && !receipt.appliedToEngine)
            || (receipt.status == "applied" && receipt.appliedToEngine)
        guard value.schemaVersion == "signaldeck-control-mutation/v1",
              value.apiVersion == "v1",
              !value.instanceId.isEmpty,
              expectedInstanceID.map({ $0 == value.instanceId }) ?? true,
              expectedRevision < UInt64.max,
              receipt.operation == operation,
              receipt.resourceId == resourceID,
              receipt.idempotencyKey == idempotencyKey,
              receipt.beforeRevision == expectedRevision,
              receipt.afterRevision == expectedRevision + 1,
              receipt.consumer == "spatial-workspace",
              receipt.requesterScope == "owner-write",
              receipt.contextId == contextID,
              receipt.createdAtMs > 0,
              applicationTruthIsConsistent,
              isBoundedOperationID(receipt.operationId),
              isSHA256(receipt.requestHash) else {
            throw SignalDeckClientError.invalidResponse
        }

        if let expectedProfileID {
            guard receipt.profileId == expectedProfileID,
                  let fingerprint = receipt.profileFingerprint,
                  isSHA256(fingerprint),
                  receipt.profileFingerprintSchema == "signaldeck-profile-definition/v2",
                  expectedProfileFingerprint.map({ $0 == fingerprint }) ?? true else {
                throw SignalDeckClientError.invalidResponse
            }
        } else {
            guard receipt.profileId == nil,
                  receipt.profileFingerprint == nil,
                  receipt.profileFingerprintSchema == nil else {
                throw SignalDeckClientError.invalidResponse
            }
        }
        return value
    }

    private static func validateResourceID(_ value: String, role: String) throws {
        guard (1 ... 64).contains(value.utf8.count),
              value.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57)
                      || (byte >= 65 && byte <= 90)
                      || (byte >= 97 && byte <= 122)
                      || byte == 45
                      || byte == 95
              }) else {
            throw SignalDeckClientError.invalidRequest("the \(role) identifier is not allowlisted")
        }
    }

    private static func validateSnapshotShape(_ snapshot: SignalDeckSnapshot) throws {
        let busIDs = snapshot.buses.map(\.id)
        let sourceIDs = snapshot.sources.map(\.id)
        let checkIDs = snapshot.checks.map(\.id)
        guard Set(busIDs).count == busIDs.count,
              Set(sourceIDs).count == sourceIDs.count,
              Set(checkIDs).count == checkIDs.count,
              snapshot.audioGraphApplied == snapshot.integration.audioGraphApplied,
              snapshot.panicMuteApplied == nil
                || snapshot.integration.panicMuteApplied == nil
                || snapshot.panicMuteApplied == snapshot.integration.panicMuteApplied else {
            throw SignalDeckClientError.invalidResponse
        }
        let knownBusIDs = Set(busIDs)
        for bus in snapshot.buses {
            try validateResourceID(bus.id, role: "bus")
            guard ["monitor", "stream", "chat", "record", "mic-clean", "source"].contains(bus.role),
                  bus.gain.isFinite, (0 ... 2).contains(bus.gain),
                  bus.displayName.utf8.count <= 160,
                  bus.availabilityReason.utf8.count <= 640,
                  bus.peakDbfs.map(\.isFinite) ?? true else {
                throw SignalDeckClientError.invalidResponse
            }
        }
        for source in snapshot.sources {
            try validateResourceID(source.id, role: "source")
            guard ["microphone", "discord", "browser", "music", "jarvis", "system"].contains(source.role),
                  source.gain.isFinite, (0 ... 2).contains(source.gain),
                  source.displayName.utf8.count <= 160,
                  source.availabilityReason.utf8.count <= 640,
                  Set(source.targetBusIds).count == source.targetBusIds.count,
                  source.targetBusIds.allSatisfy(knownBusIDs.contains),
                  Set(source.processingBusIds ?? []).count == (source.processingBusIds ?? []).count,
                  (source.processingBusIds ?? []).allSatisfy(knownBusIDs.contains) else {
                throw SignalDeckClientError.invalidResponse
            }
        }
        for check in snapshot.checks {
            try validateResourceID(check.id, role: "check")
            guard ["pass", "warn", "fail"].contains(check.status),
                  check.message.utf8.count <= 640 else {
                throw SignalDeckClientError.invalidResponse
            }
        }
        if let configured = snapshot.configuredProfile {
            try validateResourceID(configured.id, role: "configured profile")
            guard isSHA256(configured.fingerprint), configured.revision <= snapshot.revision else {
                throw SignalDeckClientError.invalidResponse
            }
        }
        if let active = snapshot.activeProfile {
            try validateResourceID(active.id, role: "active profile")
            guard isSHA256(active.fingerprint), active.revision <= snapshot.revision,
                  active.appliedToEngine, snapshot.audioGraphApplied else {
                throw SignalDeckClientError.invalidResponse
            }
        }
    }

    private static func validateProfilesShape(_ snapshot: SignalDeckProfilesSnapshot) throws {
        let profileIDs = snapshot.profiles.map(\.id)
        guard Set(profileIDs).count == profileIDs.count else {
            throw SignalDeckClientError.invalidResponse
        }
        for profile in snapshot.profiles {
            try validateResourceID(profile.id, role: "profile")
            guard isSHA256(profile.fingerprint),
                  profile.displayName.utf8.count <= 160,
                  profile.description.utf8.count <= 640,
                  profile.routes.count <= 32,
                  profile.buses.count <= 32 else {
                throw SignalDeckClientError.invalidResponse
            }
            for (sourceID, route) in profile.routes {
                try validateResourceID(sourceID, role: "profile source")
                try validateTargetBusIDs(route.targetBusIds)
                try validateGain(route.gain)
            }
            for (busID, control) in profile.buses {
                try validateResourceID(busID, role: "profile bus")
                try validateGain(control.gain)
            }
        }
        if let configured = snapshot.configuredProfile {
            try validateResourceID(configured.id, role: "configured profile")
            guard isSHA256(configured.fingerprint), configured.revision <= snapshot.revision else {
                throw SignalDeckClientError.invalidResponse
            }
        }
        if let active = snapshot.activeProfile {
            try validateResourceID(active.id, role: "active profile")
            guard isSHA256(active.fingerprint), active.revision <= snapshot.revision,
                  active.appliedToEngine else {
                throw SignalDeckClientError.invalidResponse
            }
        }
    }

    private static func validateTargetBusIDs(_ values: [String]) throws {
        guard values.count <= 32, Set(values).count == values.count else {
            throw SignalDeckClientError.invalidRequest("destination buses must be unique and bounded")
        }
        for value in values {
            try validateResourceID(value, role: "destination bus")
        }
    }

    private static func validateGain(_ gain: Double) throws {
        guard gain.isFinite, (0 ... 2).contains(gain) else {
            throw SignalDeckClientError.invalidRequest("gain must be between 0 and 2")
        }
    }

    private static func validateMutationMetadata(
        expectedRevision: UInt64,
        idempotencyKey: String,
        contextID: String
    ) throws {
        guard expectedRevision > 0, expectedRevision < UInt64.max else {
            throw SignalDeckClientError.invalidRequest("the router revision is invalid")
        }
        guard isBoundedKey(idempotencyKey, minimum: 8, maximum: 128) else {
            throw SignalDeckClientError.invalidRequest("the idempotency key is invalid")
        }
        guard isBoundedKey(contextID, minimum: 1, maximum: 96) else {
            throw SignalDeckClientError.invalidRequest("the context identifier is invalid")
        }
    }

    private static func isBoundedKey(_ value: String, minimum: Int, maximum: Int) -> Bool {
        (minimum ... maximum).contains(value.utf8.count)
            && value.utf8.allSatisfy { byte in
                (byte >= 48 && byte <= 57)
                    || (byte >= 65 && byte <= 90)
                    || (byte >= 97 && byte <= 122)
                    || byte == 45
                    || byte == 95
                    || byte == 46
                    || byte == 58
            }
    }

    private static func isBoundedOperationID(_ value: String) -> Bool {
        (16 ... 128).contains(value.utf8.count)
            && value.hasPrefix("audioop_")
            && value.utf8.allSatisfy { byte in
                (byte >= 48 && byte <= 57)
                    || (byte >= 65 && byte <= 90)
                    || (byte >= 97 && byte <= 122)
                    || byte == 45
                    || byte == 95
            }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { byte in
            (byte >= 48 && byte <= 57)
                || (byte >= 65 && byte <= 70)
                || (byte >= 97 && byte <= 102)
        }
    }

    func eventBytes(
        credentials: SignalDeckCredentials
    ) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var request = request(
            "v1/events",
            baseURL: credentials.baseURL,
            token: credentials.readToken,
            method: "GET"
        )
        request.timeoutInterval = 60 * 60
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw SignalDeckClientError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            var body = Data()
            for try await byte in bytes {
                guard body.count < 16 * 1_024 else { throw SignalDeckClientError.responseTooLarge }
                body.append(byte)
            }
            throw Self.httpError(status: http.statusCode, data: body)
        }
        return (bytes, http)
    }

    private func validatedTokenURL(_ path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw SignalDeckClientError.invalidDiscovery("token paths must be absolute")
        }
        let candidate = URL(fileURLWithPath: path, isDirectory: false).standardizedFileURL
        let discoveryParent = discoveryURL.standardizedFileURL.deletingLastPathComponent()
        guard candidate.deletingLastPathComponent() == discoveryParent else {
            throw SignalDeckClientError.invalidDiscovery("token files must be beside discovery")
        }
        return candidate
    }

    private static func readToken(at url: URL, role: String) throws -> String {
        let data = try SecureOwnerFile.read(url, role: "\(role) token", maximumBytes: 256)
        guard let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              token.utf8.count == 43,
              token.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57)
                      || (byte >= 65 && byte <= 90)
                      || (byte >= 97 && byte <= 122)
                      || byte == 45
                      || byte == 95
              }),
              decodeURLSafeToken(token)?.count == 32 else {
            throw SignalDeckClientError.invalidToken(role)
        }
        return token
    }

    private static func decodeURLSafeToken(_ token: String) -> Data? {
        var base64 = token.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64 += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: base64)
    }

    private static func loopbackURL(for address: String) -> URL? {
        let pieces = address.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              pieces[0] == "127.0.0.1",
              let port = Int(pieces[1]),
              (1 ... 65_535).contains(port),
              String(port) == pieces[1] else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/")
    }

    private func get<T: Decodable>(
        _ path: String,
        credentials: SignalDeckCredentials
    ) async throws -> T {
        try await send(request(
            path,
            baseURL: credentials.baseURL,
            token: credentials.readToken,
            method: "GET"
        ))
    }

    private func request(_ path: String, baseURL: URL, token: String, method: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = method == "GET" ? 4 : 8
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<T: Decodable>(
        _ request: URLRequest,
        expectedStatus: Int? = nil
    ) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SignalDeckClientError.invalidResponse }
        if let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init),
           length > 512 * 1_024 {
            throw SignalDeckClientError.responseTooLarge
        }
        guard data.count <= 512 * 1_024 else { throw SignalDeckClientError.responseTooLarge }
        let statusAccepted = expectedStatus.map { http.statusCode == $0 }
            ?? (200 ..< 300).contains(http.statusCode)
        guard statusAccepted else {
            throw Self.httpError(status: http.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SignalDeckClientError.invalidResponse
        }
    }

    private static func httpError(status: Int, data: Data) -> SignalDeckClientError {
        let body = try? JSONDecoder().decode(SignalDeckErrorResponse.self, from: data)
        let safeMessage = body?.message.map { String($0.prefix(320)) }
        return .http(
            status: status,
            code: body?.code,
            message: safeMessage,
            currentRevision: body?.currentRouterRevision
        )
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.connectionProxyDictionary = [:]
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(
            configuration: configuration,
            delegate: SignalDeckNoRedirectDelegate(),
            delegateQueue: nil
        )
    }
}

private final class SignalDeckNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private enum SecureOwnerFile {
    static func read(_ url: URL, role: String, maximumBytes: Int) throws -> Data {
        guard url.isFileURL else { throw SignalDeckClientError.insecureFile(role) }
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            if errno == ENOENT, role == "discovery" {
                throw SignalDeckClientError.discoveryUnavailable
            }
            throw SignalDeckClientError.insecureFile(role)
        }
        defer { Darwin.close(descriptor) }

        var information = stat()
        guard Darwin.fstat(descriptor, &information) == 0,
              information.st_mode & S_IFMT == S_IFREG,
              information.st_uid == geteuid(),
              information.st_mode & 0o077 == 0,
              information.st_size >= 0,
              information.st_size <= maximumBytes else {
            throw SignalDeckClientError.insecureFile(role)
        }

        var output = Data()
        output.reserveCapacity(min(Int(information.st_size), maximumBytes))
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = Darwin.read(descriptor, &buffer, min(buffer.count, maximumBytes + 1 - output.count))
            guard count >= 0 else { throw SignalDeckClientError.insecureFile(role) }
            if count == 0 { break }
            output.append(buffer, count: count)
            guard output.count <= maximumBytes else { throw SignalDeckClientError.insecureFile(role) }
        }
        return output
    }
}
