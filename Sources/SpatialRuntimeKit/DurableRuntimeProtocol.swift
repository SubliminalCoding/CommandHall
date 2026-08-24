import Foundation

public enum DurableRuntimeState: String, Codable, Sendable {
    case preparing
    case starting
    case running
    case completed
    case failed
    case cancelled
    case interrupted

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled, .interrupted: true
        case .preparing, .starting, .running: false
        }
    }
}

public struct DurableRuntimeManifest: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var runID: UUID
    public var nodeID: UUID
    public var harness: String
    public var executablePath: String
    public var arguments: [String]
    public var workingDirectory: String
    public var environment: [String: String]
    public var goal: String
    public var createdAt: Date

    public init(
        runID: UUID,
        nodeID: UUID,
        harness: String,
        executablePath: String,
        arguments: [String],
        workingDirectory: String,
        environment: [String: String],
        goal: String,
        createdAt: Date = Date()
    ) {
        schemaVersion = Self.schemaVersion
        self.runID = runID
        self.nodeID = nodeID
        self.harness = harness
        self.executablePath = executablePath
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.goal = goal
        self.createdAt = createdAt
    }

    public func validate(allowDiagnostic: Bool = false) throws {
        guard schemaVersion == Self.schemaVersion else { throw DurableRuntimeProtocolError.unsupportedSchema }
        let executable = URL(fileURLWithPath: executablePath).lastPathComponent
        let allowed = (harness == "claude" && executable == "claude")
            || (harness == "codex" && executable == "codex")
            || (allowDiagnostic && harness.hasPrefix("diagnostic"))
        guard allowed else { throw DurableRuntimeProtocolError.executableNotAllowed }
        guard workingDirectory.hasPrefix("/") else {
            throw DurableRuntimeProtocolError.invalidWorkingDirectory
        }
    }
}

public struct DurableRuntimeStatus: Codable, Equatable, Sendable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var runID: UUID
    public var nodeID: UUID
    public var harness: String
    public var state: DurableRuntimeState
    public var workerPID: Int32
    public var childPID: Int32?
    public var exitCode: Int32?
    public var detail: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        runID: UUID,
        nodeID: UUID,
        harness: String,
        state: DurableRuntimeState,
        workerPID: Int32,
        childPID: Int32? = nil,
        exitCode: Int32? = nil,
        detail: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        schemaVersion = Self.schemaVersion
        self.runID = runID
        self.nodeID = nodeID
        self.harness = harness
        self.state = state
        self.workerPID = workerPID
        self.childPID = childPID
        self.exitCode = exitCode
        self.detail = detail.map { String($0.prefix(2_000)) }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct DurableRuntimeRunDirectory: Equatable, Sendable {
    public let root: URL
    public let runID: UUID

    public init(root: URL, runID: UUID) {
        self.root = root
        self.runID = runID
    }

    public var directory: URL { root.appendingPathComponent(runID.uuidString.lowercased(), isDirectory: true) }
    public var manifest: URL { directory.appendingPathComponent("launch.json") }
    public var output: URL { directory.appendingPathComponent("output.log") }
    public var status: URL { directory.appendingPathComponent("status.json") }
    public var cancellationRequest: URL { directory.appendingPathComponent("cancel") }
}

public enum DurableRuntimeProtocolError: Error, Equatable {
    case unsupportedSchema
    case executableNotAllowed
    case invalidWorkingDirectory
    case identityMismatch
}

public enum DurableRuntimeCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
