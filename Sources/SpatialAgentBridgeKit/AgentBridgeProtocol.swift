import Foundation

public enum AgentBridgeLimits {
    public static let protocolVersion = 1
    public static let maximumRequestBytes = 65_536
    public static let maximumResponseBytes = 262_144
    public static let maximumIdentifierLength = 128
    public static let maximumReasonLength = 500
    public static let maximumSummaryLength = 1_000
    public static let maximumSources = 64
    public static let maximumChanges = 32
}

public enum AgentBridgeOperation: String, Codable, CaseIterable, Sendable {
    case status
    case plan
    case apply
    case panic
}

public struct AgentBridgeAuthentication: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let token: String
    public let nodeID: UUID
    public let provider: String

    public init(sessionID: UUID, token: String, nodeID: UUID, provider: String) {
        self.sessionID = sessionID
        self.token = token
        self.nodeID = nodeID
        self.provider = provider
    }
}

public enum AgentAudioIntent: String, Codable, CaseIterable, Sendable {
    case listenPrivately = "listen-privately"
    case includeInStream = "include-in-stream"
    case excludeFromStream = "exclude-from-stream"
    case muteSource = "mute-source"
    case applyProfile = "apply-profile"
    case setBus = "set-bus"
}

public struct AgentAudioPlanRequest: Codable, Equatable, Sendable {
    public let intent: AgentAudioIntent
    public let sourceID: String?
    public let profileID: String?
    public let busID: String?
    public let enabled: Bool?
    public let reason: String?

    public init(
        intent: AgentAudioIntent,
        sourceID: String? = nil,
        profileID: String? = nil,
        busID: String? = nil,
        enabled: Bool? = nil,
        reason: String? = nil
    ) {
        self.intent = intent
        self.sourceID = sourceID
        self.profileID = profileID
        self.busID = busID
        self.enabled = enabled
        self.reason = reason
    }
}

public struct AgentAudioApplyRequest: Codable, Equatable, Sendable {
    public let planID: String
    public let expectedRevision: Int
    public let idempotencyKey: String

    public init(planID: String, expectedRevision: Int, idempotencyKey: String) {
        self.planID = planID
        self.expectedRevision = expectedRevision
        self.idempotencyKey = idempotencyKey
    }
}

public struct AgentAudioPanicRequest: Codable, Equatable, Sendable {
    public let idempotencyKey: String
    public let reason: String?

    public init(idempotencyKey: String, reason: String? = nil) {
        self.idempotencyKey = idempotencyKey
        self.reason = reason
    }
}

public enum AgentAudioCommand: Equatable, Sendable {
    case status
    case plan(AgentAudioPlanRequest)
    case apply(AgentAudioApplyRequest)
    case panic(AgentAudioPanicRequest)

    public var operation: AgentBridgeOperation {
        switch self {
        case .status: .status
        case .plan: .plan
        case .apply: .apply
        case .panic: .panic
        }
    }
}

extension AgentAudioCommand: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case arguments
    }

    private struct EmptyArguments: Codable {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let operation = try container.decode(AgentBridgeOperation.self, forKey: .name)
        switch operation {
        case .status:
            _ = try container.decode(EmptyArguments.self, forKey: .arguments)
            self = .status
        case .plan:
            self = .plan(try container.decode(AgentAudioPlanRequest.self, forKey: .arguments))
        case .apply:
            self = .apply(try container.decode(AgentAudioApplyRequest.self, forKey: .arguments))
        case .panic:
            self = .panic(try container.decode(AgentAudioPanicRequest.self, forKey: .arguments))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(operation, forKey: .name)
        switch self {
        case .status:
            try container.encode(EmptyArguments(), forKey: .arguments)
        case .plan(let request):
            try container.encode(request, forKey: .arguments)
        case .apply(let request):
            try container.encode(request, forKey: .arguments)
        case .panic(let request):
            try container.encode(request, forKey: .arguments)
        }
    }
}

public struct AgentBridgeRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: UUID
    public let auth: AgentBridgeAuthentication
    public let command: AgentAudioCommand

    public init(
        version: Int = AgentBridgeLimits.protocolVersion,
        requestID: UUID = UUID(),
        auth: AgentBridgeAuthentication,
        command: AgentAudioCommand
    ) {
        self.version = version
        self.requestID = requestID
        self.auth = auth
        self.command = command
    }
}

public enum AgentAudioMutationMode: String, Codable, Sendable {
    case configurationOnly = "configuration-only"
    case live
}

public enum AgentAudioStreamState: String, Codable, Sendable {
    case offline
    case preview
    case live
    case unknown
}

public struct AgentAudioSourceStatus: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let monitorEnabled: Bool
    public let streamEnabled: Bool
    public let verified: Bool

    public init(id: String, label: String, monitorEnabled: Bool, streamEnabled: Bool, verified: Bool) {
        self.id = id
        self.label = label
        self.monitorEnabled = monitorEnabled
        self.streamEnabled = streamEnabled
        self.verified = verified
    }
}

public struct AgentAudioStatus: Codable, Equatable, Sendable {
    public let capturedAtEpochMilliseconds: Int64
    public let revision: Int
    public let mutationMode: AgentAudioMutationMode
    public let configuredProfileID: String?
    public let activeProfileID: String?
    public let streamState: AgentAudioStreamState
    public let sources: [AgentAudioSourceStatus]
    public let warnings: [String]

    public init(
        capturedAtEpochMilliseconds: Int64,
        revision: Int,
        mutationMode: AgentAudioMutationMode,
        configuredProfileID: String? = nil,
        activeProfileID: String? = nil,
        streamState: AgentAudioStreamState = .unknown,
        sources: [AgentAudioSourceStatus] = [],
        warnings: [String] = []
    ) {
        self.capturedAtEpochMilliseconds = capturedAtEpochMilliseconds
        self.revision = revision
        self.mutationMode = mutationMode
        self.configuredProfileID = configuredProfileID
        self.activeProfileID = activeProfileID
        self.streamState = streamState
        self.sources = sources
        self.warnings = warnings
    }
}

public struct AgentAudioChange: Codable, Equatable, Sendable {
    public let targetKind: String
    public let targetID: String
    public let field: String
    public let fromValue: String?
    public let toValue: String

    public init(targetKind: String, targetID: String, field: String, fromValue: String? = nil, toValue: String) {
        self.targetKind = targetKind
        self.targetID = targetID
        self.field = field
        self.fromValue = fromValue
        self.toValue = toValue
    }
}

public struct AgentAudioPlan: Codable, Equatable, Sendable {
    public let id: String
    public let intent: AgentAudioIntent
    public let summary: String
    public let expectedRevision: Int
    public let expiresAtEpochMilliseconds: Int64
    public let requiresConfirmation: Bool
    public let changes: [AgentAudioChange]

    public init(
        id: String,
        intent: AgentAudioIntent,
        summary: String,
        expectedRevision: Int,
        expiresAtEpochMilliseconds: Int64,
        requiresConfirmation: Bool,
        changes: [AgentAudioChange]
    ) {
        self.id = id
        self.intent = intent
        self.summary = summary
        self.expectedRevision = expectedRevision
        self.expiresAtEpochMilliseconds = expiresAtEpochMilliseconds
        self.requiresConfirmation = requiresConfirmation
        self.changes = changes
    }
}

public enum AgentAudioReceiptOperation: String, Codable, Sendable {
    case apply
    case panic
}

public struct AgentAudioMutationReceipt: Codable, Equatable, Sendable {
    public let receiptID: String
    public let operation: AgentAudioReceiptOperation
    public let planID: String?
    public let configuredRevision: Int
    public let activeRevision: Int?
    public let appliedToEngine: Bool
    public let verified: Bool
    public let summary: String
    public let completedAtEpochMilliseconds: Int64

    public init(
        receiptID: String,
        operation: AgentAudioReceiptOperation,
        planID: String? = nil,
        configuredRevision: Int,
        activeRevision: Int? = nil,
        appliedToEngine: Bool,
        verified: Bool,
        summary: String,
        completedAtEpochMilliseconds: Int64
    ) {
        self.receiptID = receiptID
        self.operation = operation
        self.planID = planID
        self.configuredRevision = configuredRevision
        self.activeRevision = activeRevision
        self.appliedToEngine = appliedToEngine
        self.verified = verified
        self.summary = summary
        self.completedAtEpochMilliseconds = completedAtEpochMilliseconds
    }
}

public enum AgentAudioResult: Equatable, Sendable {
    case status(AgentAudioStatus)
    case plan(AgentAudioPlan)
    case applied(AgentAudioMutationReceipt)
    case panic(AgentAudioMutationReceipt)
}

extension AgentAudioResult: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case status
        case plan
        case applied
        case panic
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .status: self = .status(try container.decode(AgentAudioStatus.self, forKey: .value))
        case .plan: self = .plan(try container.decode(AgentAudioPlan.self, forKey: .value))
        case .applied: self = .applied(try container.decode(AgentAudioMutationReceipt.self, forKey: .value))
        case .panic: self = .panic(try container.decode(AgentAudioMutationReceipt.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .status(let value):
            try container.encode(Kind.status, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .plan(let value):
            try container.encode(Kind.plan, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .applied(let value):
            try container.encode(Kind.applied, forKey: .kind)
            try container.encode(value, forKey: .value)
        case .panic(let value):
            try container.encode(Kind.panic, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

public enum AgentBridgeErrorCode: String, Codable, Sendable {
    case invalidJSON = "invalid_json"
    case invalidRequest = "invalid_request"
    case authenticationRequired = "authentication_required"
    case invalidSession = "invalid_session"
    case sessionExpired = "session_expired"
    case identityMismatch = "identity_mismatch"
    case forbidden
    case rateLimited = "rate_limited"
    case conflict
    case notReady = "not_ready"
    case handlerUnavailable = "handler_unavailable"
    case internalError = "internal_error"
}

public struct AgentBridgeErrorPayload: Codable, Equatable, Error, Sendable {
    public let code: AgentBridgeErrorCode
    public let message: String
    public let field: String?
    public let retryable: Bool

    public init(code: AgentBridgeErrorCode, message: String, field: String? = nil, retryable: Bool = false) {
        self.code = code
        self.message = message
        self.field = field
        self.retryable = retryable
    }
}

public struct AgentBridgeHandlerError: Error, Sendable {
    public let payload: AgentBridgeErrorPayload

    public init(code: AgentBridgeErrorCode, message: String, field: String? = nil, retryable: Bool = false) {
        payload = AgentBridgeErrorPayload(code: code, message: message, field: field, retryable: retryable)
    }
}

public struct AgentBridgeResponse: Codable, Equatable, Sendable {
    public let version: Int
    public let requestID: UUID?
    public let ok: Bool
    public let result: AgentAudioResult?
    public let error: AgentBridgeErrorPayload?

    public static func success(requestID: UUID, result: AgentAudioResult) -> Self {
        Self(version: AgentBridgeLimits.protocolVersion, requestID: requestID, ok: true, result: result, error: nil)
    }

    public static func failure(requestID: UUID?, error: AgentBridgeErrorPayload) -> Self {
        Self(version: AgentBridgeLimits.protocolVersion, requestID: requestID, ok: false, result: nil, error: error)
    }
}

public struct AgentBridgeSessionIdentity: Equatable, Sendable {
    public let sessionID: UUID
    public let nodeID: UUID
    public let provider: String
    public let issuedAtEpochMilliseconds: Int64
    public let expiresAtEpochMilliseconds: Int64
    public let scopes: Set<AgentBridgeOperation>

    public init(
        sessionID: UUID,
        nodeID: UUID,
        provider: String,
        issuedAtEpochMilliseconds: Int64,
        expiresAtEpochMilliseconds: Int64,
        scopes: Set<AgentBridgeOperation>
    ) {
        self.sessionID = sessionID
        self.nodeID = nodeID
        self.provider = provider
        self.issuedAtEpochMilliseconds = issuedAtEpochMilliseconds
        self.expiresAtEpochMilliseconds = expiresAtEpochMilliseconds
        self.scopes = scopes
    }
}

public protocol AgentAudioControlHandling: Sendable {
    func handle(_ command: AgentAudioCommand, for identity: AgentBridgeSessionIdentity) async throws -> AgentAudioResult
}

public enum AgentBridgeWireCodec {
    public static func encodeRequest(_ request: AgentBridgeRequest) throws -> Data {
        try request.validate()
        return try encoder.encode(request)
    }

    public static func decodeRequest(_ data: Data) throws -> AgentBridgeRequest {
        try AgentBridgeStrictSchema.validateRequestData(data)
        let request = try decoder.decode(AgentBridgeRequest.self, from: data)
        try request.validate()
        return request
    }

    public static func encodeResponse(_ response: AgentBridgeResponse) throws -> Data {
        try response.validate()
        let data = try encoder.encode(response)
        guard data.count <= AgentBridgeLimits.maximumResponseBytes else {
            throw AgentBridgeErrorPayload(code: .internalError, message: "Response exceeded the bridge limit")
        }
        return data
    }

    public static func decodeResponse(_ data: Data) throws -> AgentBridgeResponse {
        guard data.count <= AgentBridgeLimits.maximumResponseBytes else {
            throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Response exceeded the bridge limit")
        }
        let response = try decoder.decode(AgentBridgeResponse.self, from: data)
        try response.validate()
        return response
    }

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .custom { codingPath in
            let original = codingPath.last!.stringValue
            return AgentBridgeCodingKey(stringValue: original.replacingOccurrences(of: "ID", with: "Id"))!
        }
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { codingPath in
            let original = codingPath.last!.stringValue
            return AgentBridgeCodingKey(stringValue: original.replacingOccurrences(of: "Id", with: "ID"))!
        }
        return decoder
    }()
}

private struct AgentBridgeCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

private extension AgentBridgeRequest {
    func validate() throws {
        guard version == AgentBridgeLimits.protocolVersion else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Unsupported bridge protocol version", field: "version")
        }
        try AgentBridgeValidation.provider(auth.provider, field: "auth.provider")
        guard auth.token.count >= 32, auth.token.count <= 256 else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Session token has an invalid length", field: "auth.token")
        }
        switch command {
        case .status:
            break
        case .plan(let request):
            try request.validate()
        case .apply(let request):
            try AgentBridgeValidation.identifier(request.planID, field: "command.arguments.planId")
            try AgentBridgeValidation.revision(request.expectedRevision)
            try AgentBridgeValidation.identifier(request.idempotencyKey, field: "command.arguments.idempotencyKey")
        case .panic(let request):
            try AgentBridgeValidation.identifier(request.idempotencyKey, field: "command.arguments.idempotencyKey")
            try AgentBridgeValidation.optionalText(request.reason, maximum: AgentBridgeLimits.maximumReasonLength, field: "command.arguments.reason")
        }
    }
}

private extension AgentAudioPlanRequest {
    func validate() throws {
        try AgentBridgeValidation.optionalText(reason, maximum: AgentBridgeLimits.maximumReasonLength, field: "command.arguments.reason")
        switch intent {
        case .listenPrivately, .includeInStream, .excludeFromStream, .muteSource:
            try AgentBridgeValidation.identifier(sourceID, field: "command.arguments.sourceId")
            guard profileID == nil, busID == nil, enabled == nil else {
                throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Source actions only accept sourceId and reason", field: "command.arguments")
            }
        case .applyProfile:
            try AgentBridgeValidation.identifier(profileID, field: "command.arguments.profileId")
            guard sourceID == nil, busID == nil, enabled == nil else {
                throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Profile actions only accept profileId and reason", field: "command.arguments")
            }
        case .setBus:
            try AgentBridgeValidation.identifier(busID, field: "command.arguments.busId")
            guard enabled != nil, sourceID == nil, profileID == nil else {
                throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Bus actions require busId and enabled", field: "command.arguments")
            }
        }
    }
}

private extension AgentBridgeResponse {
    func validate() throws {
        guard version == AgentBridgeLimits.protocolVersion else {
            throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Unsupported bridge response version")
        }
        guard ok ? (result != nil && error == nil) : (result == nil && error != nil) else {
            throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Bridge response envelope is inconsistent")
        }
        try result?.validate()
        if let error {
            try AgentBridgeValidation.text(error.message, maximum: AgentBridgeLimits.maximumSummaryLength, field: "error.message")
            try AgentBridgeValidation.optionalText(error.field, maximum: 128, field: "error.field")
        }
    }
}

private extension AgentAudioResult {
    func validate() throws {
        switch self {
        case .status(let status):
            try AgentBridgeValidation.revision(status.revision)
            guard status.sources.count <= AgentBridgeLimits.maximumSources, status.warnings.count <= 16 else {
                throw AgentBridgeErrorPayload(code: .internalError, message: "Status result exceeded collection limits")
            }
            try AgentBridgeValidation.optionalIdentifier(status.configuredProfileID, field: "result.configuredProfileId")
            try AgentBridgeValidation.optionalIdentifier(status.activeProfileID, field: "result.activeProfileId")
            for source in status.sources {
                try AgentBridgeValidation.identifier(source.id, field: "result.sources.id")
                try AgentBridgeValidation.text(source.label, maximum: 128, field: "result.sources.label")
            }
            for warning in status.warnings {
                try AgentBridgeValidation.text(warning, maximum: AgentBridgeLimits.maximumSummaryLength, field: "result.warnings")
            }
        case .plan(let plan):
            try AgentBridgeValidation.identifier(plan.id, field: "result.plan.id")
            try AgentBridgeValidation.revision(plan.expectedRevision)
            try AgentBridgeValidation.text(plan.summary, maximum: AgentBridgeLimits.maximumSummaryLength, field: "result.plan.summary")
            guard plan.changes.count <= AgentBridgeLimits.maximumChanges else {
                throw AgentBridgeErrorPayload(code: .internalError, message: "Plan exceeded the change limit")
            }
            for change in plan.changes {
                try AgentBridgeValidation.identifier(change.targetKind, field: "result.plan.changes.targetKind")
                try AgentBridgeValidation.identifier(change.targetID, field: "result.plan.changes.targetId")
                try AgentBridgeValidation.identifier(change.field, field: "result.plan.changes.field")
                try AgentBridgeValidation.optionalText(change.fromValue, maximum: 256, field: "result.plan.changes.fromValue")
                try AgentBridgeValidation.text(change.toValue, maximum: 256, field: "result.plan.changes.toValue")
            }
        case .applied(let receipt):
            guard receipt.operation == .apply else {
                throw AgentBridgeErrorPayload(code: .internalError, message: "Apply result carried the wrong receipt operation")
            }
            try validate(receipt)
        case .panic(let receipt):
            guard receipt.operation == .panic else {
                throw AgentBridgeErrorPayload(code: .internalError, message: "Panic result carried the wrong receipt operation")
            }
            try validate(receipt)
        }
    }

    private func validate(_ receipt: AgentAudioMutationReceipt) throws {
            try AgentBridgeValidation.identifier(receipt.receiptID, field: "result.receipt.id")
            try AgentBridgeValidation.optionalIdentifier(receipt.planID, field: "result.receipt.planId")
            try AgentBridgeValidation.revision(receipt.configuredRevision)
            if let activeRevision = receipt.activeRevision { try AgentBridgeValidation.revision(activeRevision) }
            try AgentBridgeValidation.text(receipt.summary, maximum: AgentBridgeLimits.maximumSummaryLength, field: "result.receipt.summary")
            guard !receipt.verified || receipt.appliedToEngine,
                  receipt.appliedToEngine || receipt.activeRevision == nil else {
                throw AgentBridgeErrorPayload(code: .internalError, message: "Receipt engine and verification fields are inconsistent")
            }
    }
}

private enum AgentBridgeValidation {
    static func revision(_ value: Int) throws {
        guard value >= 0, value <= Int(Int32.max) else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Revision is outside the supported range", field: "command.arguments.expectedRevision")
        }
    }

    static func identifier(_ value: String?, field: String) throws {
        guard let value else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "A required identifier is missing", field: field)
        }
        try identifier(value, field: field)
    }

    static func identifier(_ value: String, field: String) throws {
        guard !value.isEmpty, value.count <= AgentBridgeLimits.maximumIdentifierLength,
              value.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.alphanumerics.contains(scalar) || "._:-".unicodeScalars.contains(scalar)
              }) else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Identifier contains unsupported characters or has an invalid length", field: field)
        }
    }

    static func optionalIdentifier(_ value: String?, field: String) throws {
        if let value { try identifier(value, field: field) }
    }

    static func provider(_ value: String, field: String) throws {
        guard !value.isEmpty, value.count <= 32,
              value.unicodeScalars.allSatisfy({ scalar in
                  CharacterSet.lowercaseLetters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) || "._-".unicodeScalars.contains(scalar)
              }) else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Provider must be a lowercase provider slug", field: field)
        }
    }

    static func text(_ value: String, maximum: Int, field: String) throws {
        guard !value.isEmpty, value.count <= maximum, !value.unicodeScalars.contains(where: { $0.value == 0 }) else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Text is empty, too long, or contains a null character", field: field)
        }
    }

    static func optionalText(_ value: String?, maximum: Int, field: String) throws {
        if let value { try text(value, maximum: maximum, field: field) }
    }
}

private enum AgentBridgeStrictSchema {
    static func validateRequestData(_ data: Data) throws {
        guard !data.isEmpty, data.count <= AgentBridgeLimits.maximumRequestBytes else {
            throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Request is empty or exceeds the bridge limit")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw AgentBridgeErrorPayload(code: .invalidJSON, message: "Request is not valid JSON")
        }
        guard let root = object as? [String: Any] else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Request must be a JSON object")
        }
        try exactKeys(root, allowed: ["version", "requestId", "auth", "command"], field: "request")
        guard integer(root["version"]) == AgentBridgeLimits.protocolVersion else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Unsupported bridge protocol version", field: "version")
        }
        guard let requestID = root["requestId"] as? String, UUID(uuidString: requestID) != nil else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "requestId must be a UUID", field: "requestId")
        }
        guard let auth = root["auth"] as? [String: Any] else {
            throw AgentBridgeErrorPayload(code: .authenticationRequired, message: "Session authentication is required", field: "auth")
        }
        try exactKeys(auth, allowed: ["sessionId", "token", "nodeId", "provider"], field: "auth")
        guard let sessionID = auth["sessionId"] as? String, UUID(uuidString: sessionID) != nil,
              let nodeID = auth["nodeId"] as? String, UUID(uuidString: nodeID) != nil,
              auth["token"] is String, auth["provider"] is String else {
            throw AgentBridgeErrorPayload(code: .authenticationRequired, message: "Session authentication fields are malformed", field: "auth")
        }
        guard let command = root["command"] as? [String: Any] else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "command must be an object", field: "command")
        }
        try exactKeys(command, allowed: ["name", "arguments"], field: "command")
        guard let name = command["name"] as? String, let operation = AgentBridgeOperation(rawValue: name),
              let arguments = command["arguments"] as? [String: Any] else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Command name or arguments are invalid", field: "command")
        }
        switch operation {
        case .status:
            try exactKeys(arguments, allowed: [], field: "command.arguments")
        case .plan:
            try exactKeys(arguments, allowed: ["intent", "sourceId", "profileId", "busId", "enabled", "reason"], field: "command.arguments")
        case .apply:
            try exactKeys(arguments, allowed: ["planId", "expectedRevision", "idempotencyKey"], field: "command.arguments")
        case .panic:
            try exactKeys(arguments, allowed: ["idempotencyKey", "reason"], field: "command.arguments")
        }
    }

    private static func exactKeys(_ object: [String: Any], allowed: Set<String>, field: String) throws {
        let unknown = Set(object.keys).subtracting(allowed)
        guard unknown.isEmpty else {
            throw AgentBridgeErrorPayload(
                code: .invalidRequest,
                message: "Unknown field \(unknown.sorted().first!)",
                field: field
            )
        }
        let missing: Set<String>
        switch field {
        case "request": missing = allowed.subtracting(object.keys)
        case "auth", "command": missing = allowed.subtracting(object.keys)
        case "command.arguments": missing = []
        default: missing = []
        }
        guard missing.isEmpty else {
            throw AgentBridgeErrorPayload(code: .invalidRequest, message: "Missing field \(missing.sorted().first!)", field: field)
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.rounded() == double else { return nil }
        return number.intValue
    }
}
