import CryptoKit
import Foundation
import Security

public struct AgentBridgeCredential: Equatable, Sendable {
    public let sessionID: UUID
    public let token: String
    public let nodeID: UUID
    public let provider: String
    public let issuedAtEpochMilliseconds: Int64
    public let expiresAtEpochMilliseconds: Int64
    public let scopes: Set<AgentBridgeOperation>

    public init(
        sessionID: UUID,
        token: String,
        nodeID: UUID,
        provider: String,
        issuedAtEpochMilliseconds: Int64,
        expiresAtEpochMilliseconds: Int64,
        scopes: Set<AgentBridgeOperation>
    ) {
        self.sessionID = sessionID
        self.token = token
        self.nodeID = nodeID
        self.provider = provider
        self.issuedAtEpochMilliseconds = issuedAtEpochMilliseconds
        self.expiresAtEpochMilliseconds = expiresAtEpochMilliseconds
        self.scopes = scopes
    }

    public var authentication: AgentBridgeAuthentication {
        AgentBridgeAuthentication(sessionID: sessionID, token: token, nodeID: nodeID, provider: provider)
    }
}

public enum AgentBridgeEnvironment {
    public static let socketPath = "SPATIAL_AGENT_BRIDGE_SOCKET"
    public static let sessionID = "SPATIAL_AGENT_SESSION_ID"
    public static let sessionToken = "SPATIAL_AGENT_SESSION_TOKEN"
    public static let nodeID = "SPATIAL_AGENT_NODE_ID"
    public static let provider = "SPATIAL_AGENT_PROVIDER"
    public static let expiresAt = "SPATIAL_AGENT_SESSION_EXPIRES_AT_MS"
    public static let cliPath = "SPATIAL_AGENT_CLI"
}

public final class AgentBridgeSessionRegistry: @unchecked Sendable {
    public static let defaultLifetime: TimeInterval = 30 * 60
    public static let maximumLifetime: TimeInterval = 60 * 60
    public static let defaultAbsoluteLifetime: TimeInterval = 12 * 60 * 60
    public static let maximumAbsoluteLifetime: TimeInterval = 12 * 60 * 60
    public static let allAudioScopes = Set(AgentBridgeOperation.allCases)

    private struct Record {
        var identity: AgentBridgeSessionIdentity
        let tokenDigest: Data
        let idleLifetime: TimeInterval
        let absoluteExpiresAtEpochMilliseconds: Int64
        var requestTimes: [TimeInterval]
    }

    private let lock = NSLock()
    private var records: [UUID: Record] = [:]
    private let maximumSessions: Int
    private let requestsPerMinute: Int

    public init(maximumSessions: Int = 256, requestsPerMinute: Int = 120) {
        self.maximumSessions = max(1, min(maximumSessions, 1_024))
        self.requestsPerMinute = max(10, min(requestsPerMinute, 1_000))
    }

    public func issue(
        nodeID: UUID,
        provider: String,
        scopes: Set<AgentBridgeOperation> = AgentBridgeSessionRegistry.allAudioScopes,
        lifetime: TimeInterval = AgentBridgeSessionRegistry.defaultLifetime,
        absoluteLifetime: TimeInterval = AgentBridgeSessionRegistry.defaultAbsoluteLifetime,
        now: Date = Date()
    ) throws -> AgentBridgeCredential {
        guard Self.isValidProvider(provider) else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Provider must be a lowercase provider slug", field: "provider")
        }
        guard !scopes.isEmpty, scopes.isSubset(of: Self.allAudioScopes) else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "At least one recognized scope is required", field: "scopes")
        }
        guard lifetime >= 1, lifetime <= Self.maximumLifetime else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Session lifetime must be between one second and one hour", field: "lifetime")
        }
        guard absoluteLifetime >= lifetime, absoluteLifetime <= Self.maximumAbsoluteLifetime else {
            throw AgentBridgeErrorPayload(
                code: .invalidRequest,
                message: "Absolute session lifetime must cover the idle window and cannot exceed twelve hours",
                field: "absoluteLifetime"
            )
        }

        let token = try Self.secureToken()
        let sessionID = UUID()
        let issuedAt = Self.epochMilliseconds(now)
        let expiresAt = Self.epochMilliseconds(now.addingTimeInterval(lifetime))
        let absoluteExpiresAt = Self.epochMilliseconds(now.addingTimeInterval(absoluteLifetime))
        let identity = AgentBridgeSessionIdentity(
            sessionID: sessionID,
            nodeID: nodeID,
            provider: provider,
            issuedAtEpochMilliseconds: issuedAt,
            expiresAtEpochMilliseconds: expiresAt,
            scopes: scopes
        )

        lock.lock()
        defer { lock.unlock() }
        pruneLocked(now: now)
        guard records.count < maximumSessions else {
            throw AgentBridgeErrorPayload(code: .rateLimited, message: "The agent session limit has been reached", retryable: true)
        }
        records[sessionID] = Record(
            identity: identity,
            tokenDigest: Self.digest(token),
            idleLifetime: lifetime,
            absoluteExpiresAtEpochMilliseconds: absoluteExpiresAt,
            requestTimes: []
        )
        return AgentBridgeCredential(
            sessionID: sessionID,
            token: token,
            nodeID: nodeID,
            provider: provider,
            issuedAtEpochMilliseconds: issuedAt,
            expiresAtEpochMilliseconds: expiresAt,
            scopes: scopes
        )
    }

    public func authorize(
        _ authentication: AgentBridgeAuthentication,
        operation: AgentBridgeOperation,
        now: Date = Date()
    ) throws -> AgentBridgeSessionIdentity {
        lock.lock()
        defer { lock.unlock() }
        guard var record = records[authentication.sessionID] else {
            throw AgentBridgeErrorPayload(code: .invalidSession, message: "Agent session is unknown or has been revoked")
        }
        guard Self.constantTimeEqual(record.tokenDigest, Self.digest(authentication.token)) else {
            throw AgentBridgeErrorPayload(code: .invalidSession, message: "Agent session authentication failed")
        }
        guard record.identity.nodeID == authentication.nodeID,
              record.identity.provider == authentication.provider else {
            throw AgentBridgeErrorPayload(code: .identityMismatch, message: "Agent session identity does not match its assigned node and provider")
        }
        let nowMilliseconds = Self.epochMilliseconds(now)
        guard nowMilliseconds < record.identity.expiresAtEpochMilliseconds,
              nowMilliseconds < record.absoluteExpiresAtEpochMilliseconds else {
            records.removeValue(forKey: authentication.sessionID)
            throw AgentBridgeErrorPayload(code: .sessionExpired, message: "Agent session has expired")
        }
        guard record.identity.scopes.contains(operation) else {
            throw AgentBridgeErrorPayload(code: .forbidden, message: "Agent session is not allowed to perform this operation")
        }

        let cutoff = now.timeIntervalSince1970 - 60
        record.requestTimes.removeAll(where: { $0 < cutoff })
        guard record.requestTimes.count < requestsPerMinute else {
            records[authentication.sessionID] = record
            throw AgentBridgeErrorPayload(code: .rateLimited, message: "Agent session request rate exceeded", retryable: true)
        }
        record.requestTimes.append(now.timeIntervalSince1970)
        let renewedIdleDeadline = Self.epochMilliseconds(now.addingTimeInterval(record.idleLifetime))
        let nextExpiresAt = min(renewedIdleDeadline, record.absoluteExpiresAtEpochMilliseconds)
        record.identity = AgentBridgeSessionIdentity(
            sessionID: record.identity.sessionID,
            nodeID: record.identity.nodeID,
            provider: record.identity.provider,
            issuedAtEpochMilliseconds: record.identity.issuedAtEpochMilliseconds,
            expiresAtEpochMilliseconds: nextExpiresAt,
            scopes: record.identity.scopes
        )
        records[authentication.sessionID] = record
        return record.identity
    }

    public func revoke(sessionID: UUID) {
        lock.lock()
        records.removeValue(forKey: sessionID)
        lock.unlock()
    }

    public func revoke(nodeID: UUID) {
        lock.lock()
        records = records.filter { $0.value.identity.nodeID != nodeID }
        lock.unlock()
    }

    public func revokeAll() {
        lock.lock()
        records.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    public func activeSessionCount(now: Date = Date()) -> Int {
        lock.lock()
        defer { lock.unlock() }
        pruneLocked(now: now)
        return records.count
    }

    private func pruneLocked(now: Date) {
        let nowMilliseconds = Self.epochMilliseconds(now)
        records = records.filter {
            $0.value.identity.expiresAtEpochMilliseconds > nowMilliseconds
                && $0.value.absoluteExpiresAtEpochMilliseconds > nowMilliseconds
        }
    }

    private static func secureToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AgentBridgeErrorPayload(code: .internalError, message: "Could not create an agent session")
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func digest(_ token: String) -> Data {
        Data(SHA256.hash(data: Data(token.utf8)))
    }

    private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices {
            difference |= lhs[index] ^ rhs[index]
        }
        return difference == 0
    }

    private static func epochMilliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded(.down))
    }

    private static func isValidProvider(_ provider: String) -> Bool {
        !provider.isEmpty && provider.count <= 32 && provider.unicodeScalars.allSatisfy { scalar in
            CharacterSet.lowercaseLetters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || "._-".unicodeScalars.contains(scalar)
        }
    }
}
