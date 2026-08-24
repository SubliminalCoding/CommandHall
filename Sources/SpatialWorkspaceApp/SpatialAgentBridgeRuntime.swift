import Foundation
import SpatialAgentBridgeKit

protocol SpatialAgentBridgeSessionProviding: AnyObject {
    func issueSession(
        nodeID: UUID,
        provider: String,
        scopes: Set<AgentBridgeOperation>
    ) throws -> AgentBridgeCredential
    func revoke(_ credential: AgentBridgeCredential?)
    func environment(for credential: AgentBridgeCredential) -> [String: String]
}

final class SpatialAgentBridgeRuntime: SpatialAgentBridgeSessionProviding {
    static let shared = SpatialAgentBridgeRuntime()

    let socketURL: URL

    private let registry: AgentBridgeSessionRegistry
    private let router: AgentAudioControlRouter
    private let broker: AgentBridgeBroker

    init(socketURL: URL = SpatialAgentBridgeRuntime.defaultSocketURL) {
        self.socketURL = socketURL
        registry = AgentBridgeSessionRegistry()
        router = AgentAudioControlRouter()
        broker = AgentBridgeBroker(socketURL: socketURL, registry: registry, router: router)
    }

    func installAudioHandler(_ handler: (any AgentAudioControlHandling)?) {
        router.install(handler)
    }

    func issueSession(
        nodeID: UUID,
        provider: String,
        scopes: Set<AgentBridgeOperation> = AgentBridgeSessionRegistry.allAudioScopes
    ) throws -> AgentBridgeCredential {
        try broker.start()
        return try registry.issue(nodeID: nodeID, provider: provider, scopes: scopes)
    }

    func revoke(_ credential: AgentBridgeCredential?) {
        guard let credential else { return }
        registry.revoke(sessionID: credential.sessionID)
    }

    func revoke(nodeID: UUID) {
        registry.revoke(nodeID: nodeID)
    }

    func environment(for credential: AgentBridgeCredential) -> [String: String] {
        var values = [
            AgentBridgeEnvironment.socketPath: socketURL.path,
            AgentBridgeEnvironment.sessionID: credential.sessionID.uuidString.lowercased(),
            AgentBridgeEnvironment.sessionToken: credential.token,
            AgentBridgeEnvironment.nodeID: credential.nodeID.uuidString.lowercased(),
            AgentBridgeEnvironment.provider: credential.provider,
            AgentBridgeEnvironment.expiresAt: String(credential.expiresAtEpochMilliseconds),
        ]
        if let cliURL = Self.agentCLIURL {
            values[AgentBridgeEnvironment.cliPath] = cliURL.path
        }
        return values
    }

    static func sanitizedChildEnvironment(
        _ inherited: [String: String],
        bridgeEnvironment: [String: String]
    ) -> [String: String] {
        var environment = inherited.filter { !$0.key.hasPrefix("SPATIAL_AGENT_") }
        environment.merge(bridgeEnvironment, uniquingKeysWith: { _, bridgeValue in bridgeValue })
        return environment
    }

    static var defaultSocketURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support
            .appendingPathComponent("SpatialWorkspace", isDirectory: true)
            .appendingPathComponent("agent-bridge", isDirectory: true)
            .appendingPathComponent("bridge.sock", isDirectory: false)
    }

    static var agentCLIURL: URL? {
        if let override = ProcessInfo.processInfo.environment["SPATIAL_AGENT_CLI_PATH"] {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        if let executable = Bundle.main.executableURL {
            let sibling = executable.deletingLastPathComponent().appendingPathComponent("spatial-agent")
            if FileManager.default.isExecutableFile(atPath: sibling.path) { return sibling }
        }
        let pathDirectories = ProcessInfo.processInfo.environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        return pathDirectories
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent("spatial-agent") }
            .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) })
    }
}
