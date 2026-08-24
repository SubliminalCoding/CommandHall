import Foundation

enum StageGroup: Int, CaseIterable {
    case needsYou
    case working
    case agentsAndMissions
    case tools

    var label: String {
        switch self {
        case .needsYou: "NEEDS YOU"
        case .working: "WORKING"
        case .agentsAndMissions: "AGENTS & MISSIONS"
        case .tools: "TOOLS"
        }
    }
}

enum StageProjection {
    static func group(
        for node: WorkspaceNode,
        runtimeState: SessionRuntimeState,
        missions: [WorkspaceMission]
    ) -> StageGroup {
        let attentionIsRolledUp = node.kind == .agent && missions.contains { mission in
            mission.state != .verified && mission.state != .cancelled && mission.state != .failed
                && mission.tasks.contains(where: { $0.assigneeNodeID == node.id })
        }
        if !attentionIsRolledUp,
           node.status == .needsAttention || runtimeState == .needsYou || runtimeState == .interrupted || runtimeState == .unavailable {
            return .needsYou
        }
        if node.status == .working || runtimeState == .working || runtimeState == .launching {
            return .working
        }
        if node.kind == .agent || node.kind == .mission {
            return .agentsAndMissions
        }
        return .tools
    }

    static func ordered(
        nodes: [WorkspaceNode],
        missions: [WorkspaceMission],
        runtimeState: (WorkspaceNode) -> SessionRuntimeState
    ) -> [WorkspaceNode] {
        nodes.enumerated()
            .sorted { left, right in
                let leftGroup = group(for: left.element, runtimeState: runtimeState(left.element), missions: missions)
                let rightGroup = group(for: right.element, runtimeState: runtimeState(right.element), missions: missions)
                return leftGroup == rightGroup ? left.offset < right.offset : leftGroup.rawValue < rightGroup.rawValue
            }
            .map(\.element)
    }
}
