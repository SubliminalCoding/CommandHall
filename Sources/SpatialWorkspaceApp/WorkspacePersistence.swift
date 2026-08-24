import Foundation

enum WorkspaceLoadSource: Equatable {
    case primary
    case migrated(Int)
    case backup
    case seeded
}

struct WorkspaceLoadResult {
    var state: PersistedWorkspaceState
    var source: WorkspaceLoadSource
}

enum WorkspacePersistence {
    static let currentSchemaVersion = 7

    static func load(from url: URL, seed: () -> PersistedWorkspaceState) -> WorkspaceLoadResult {
        if let data = try? Data(contentsOf: url), let decoded = decodeValid(data) {
            if decoded.schemaVersion == currentSchemaVersion {
                return WorkspaceLoadResult(state: decoded, source: .primary)
            }
            var migrated = decoded
            let previousVersion = migrated.schemaVersion
            migrated.schemaVersion = currentSchemaVersion
            return WorkspaceLoadResult(state: migrated, source: .migrated(previousVersion))
        }

        archiveCorruptPrimary(at: url)
        let backupURL = backupURL(for: url)
        if let data = try? Data(contentsOf: backupURL), var backup = decodeValid(data) {
            backup.schemaVersion = currentSchemaVersion
            return WorkspaceLoadResult(state: backup, source: .backup)
        }
        return WorkspaceLoadResult(state: seed(), source: .seeded)
    }

    static func save(_ state: PersistedWorkspaceState, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        if let existing = try? Data(contentsOf: url), decodeValid(existing) != nil {
            try existing.write(to: backupURL(for: url), options: .atomic)
        }

        var current = state
        current.schemaVersion = currentSchemaVersion
        let data = try JSONEncoder.workspace.encode(current)
        try data.write(to: url, options: .atomic)
    }

    static func backupURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent("workspaces.previous.json")
    }

    private static func decodeValid(_ data: Data) -> PersistedWorkspaceState? {
        guard var state = try? JSONDecoder().decode(PersistedWorkspaceState.self, from: data),
              (1 ... currentSchemaVersion).contains(state.schemaVersion),
              !state.workspaces.isEmpty,
              state.workspaces.contains(where: { $0.id == state.activeWorkspaceID }),
              Set(state.workspaces.map(\.id)).count == state.workspaces.count,
              state.workspaces.allSatisfy({ Set($0.nodes.map(\.id)).count == $0.nodes.count }) else {
            return nil
        }
        let allNodeIDs = state.workspaces.flatMap { $0.nodes.map(\.id) }
        let allRunIDs = state.workspaces.flatMap { $0.runHistory.map(\.id) }
        let allMissionIDs = state.workspaces.flatMap { $0.missionHistory.map(\.id) }
        let allTaskIDs = state.workspaces.flatMap { $0.missionHistory.flatMap { $0.tasks.map(\.id) } }
        let allMemoryIDs = state.workspaces.flatMap { $0.memoryEntries.map(\.id) }
        let allEventIDs = state.workspaces.flatMap { $0.eventHistory.map(\.id) }
        let allApprovalIDs = state.workspaces.flatMap { $0.approvalHistory.map(\.id) }
        guard Set(allNodeIDs).count == allNodeIDs.count,
              Set(allRunIDs).count == allRunIDs.count,
              Set(allMissionIDs).count == allMissionIDs.count,
              Set(allTaskIDs).count == allTaskIDs.count,
              Set(allMemoryIDs).count == allMemoryIDs.count,
              Set(allEventIDs).count == allEventIDs.count,
              Set(allApprovalIDs).count == allApprovalIDs.count,
              state.workspaces.allSatisfy(workspaceReferencesAreValid) else {
            return nil
        }
        state.workspaces.indices.forEach { workspaceIndex in
            state.workspaces[workspaceIndex].camera.clampScale()
        }
        return state
    }

    private static func workspaceReferencesAreValid(_ workspace: WorkspaceDocument) -> Bool {
        let nodeIDs = Set(workspace.nodes.map(\.id))
        let missionIDs = Set(workspace.missionHistory.map(\.id))
        let runIDs = Set(workspace.runHistory.map(\.id))
        let memoryIDs = Set(workspace.memoryEntries.map(\.id))
        let approvalIDs = Set(workspace.approvalHistory.map(\.id))
        guard workspace.nodes.allSatisfy({ node in
            node.kind != .mission || (node.missionID.map(missionIDs.contains) ?? false)
        }) else { return false }
        guard workspace.memoryEntries.allSatisfy({ entry in
            entry.sourceRunID.map(runIDs.contains) ?? true
        }), workspace.runHistory.allSatisfy({ run in
            (!run.includedMemorySnapshots.isEmpty || run.includedMemoryEntryIDs.allSatisfy(memoryIDs.contains))
                && (run.approvalID.map(approvalIDs.contains) ?? true)
        }), workspace.approvalHistory.allSatisfy({ approval in
            (approval.state != .pending || nodeIDs.contains(approval.nodeID))
                && (approval.runID.map(runIDs.contains) ?? true)
        }) else { return false }
        for mission in workspace.missionHistory {
            guard nodeIDs.contains(mission.nodeID),
                  workspace.nodes.contains(where: { $0.id == mission.nodeID && $0.kind == .mission && $0.missionID == mission.id }) else {
                return false
            }
            let taskIDs = Set(mission.tasks.map(\.id))
            guard mission.tasks.allSatisfy({ task in
                task.dependencyIDs.allSatisfy(taskIDs.contains)
                    && !task.dependencyIDs.contains(task.id)
            }) else { return false }
        }
        return true
    }

    private static func archiveCorruptPrimary(at url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let timestamp = Int(Date().timeIntervalSince1970)
        let archive = url.deletingLastPathComponent().appendingPathComponent("workspaces.corrupt-\(timestamp).json")
        try? data.write(to: archive, options: .atomic)
    }
}

private extension JSONEncoder {
    static var workspace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
