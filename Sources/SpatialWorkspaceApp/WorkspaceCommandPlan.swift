import Foundation

enum WorkspaceCommandOperation: Equatable {
    case switchWorkspace(id: UUID, name: String)
    case closeNodes(ids: [UUID], names: [String])
    case openMusic(existingNodeID: UUID?)
    case openSessions(provider: SessionProvider, count: Int)
    case openJarvis
    case openBrowser(url: String, existingNodeID: UUID?)
    case refreshBrowsers
    case sendTask(nodeID: UUID, nodeName: String, task: String)
    case sendTaskToNewestProvider(provider: SessionProvider, task: String)

    var isDestructive: Bool {
        if case .closeNodes = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .switchWorkspace(_, let name):
            return "Switch to \(name)"
        case .closeNodes(_, let names):
            if names.count == 1 { return "Close \(names[0])" }
            return "Close \(names.count) items"
        case .openMusic(let existingNodeID):
            return existingNodeID == nil ? "Add music player" : "Restore music player"
        case .openSessions(let provider, let count):
            let noun = provider == .shell ? "terminal" : provider.label
            return count == 1 ? "Open \(noun)" : "Open \(count) \(noun) sessions"
        case .openJarvis:
            return "Open Jarvis"
        case .openBrowser(let url, let existingNodeID):
            let verb = existingNodeID == nil ? "Open" : "Navigate"
            return "\(verb) browser · \(Self.shortURL(url))"
        case .refreshBrowsers:
            return "Refresh previews"
        case .sendTask(_, let nodeName, _):
            return "Send task to \(nodeName)"
        case .sendTaskToNewestProvider(let provider, _):
            return "Send task to \(provider.label)"
        }
    }

    private static func shortURL(_ value: String) -> String {
        guard value.count > 34 else { return value }
        return String(value.prefix(31)) + "…"
    }
}

struct WorkspaceCommandPlan: Equatable {
    let rawInput: String
    let sourceWorkspaceID: UUID
    let sourceWorkspaceName: String
    let operations: [WorkspaceCommandOperation]
    let failureMessage: String?

    var isExecutable: Bool { !operations.isEmpty && failureMessage == nil }
    var requiresConfirmation: Bool { operations.contains(where: \.isDestructive) }

    var title: String {
        if let failureMessage { return failureMessage }
        if operations.count == 1 { return operations[0].label }
        return "\(operations.count) planned actions"
    }

    var detail: String {
        guard isExecutable else { return "Keep editing, or select an agent for an ordinary task." }
        return operations.map(\.label).joined(separator: "  →  ")
    }

    var symbol: String {
        if failureMessage != nil { return "questionmark.circle" }
        if requiresConfirmation { return "exclamationmark.shield" }
        if operations.contains(where: {
            switch $0 {
            case .sendTask, .sendTaskToNewestProvider: true
            default: false
            }
        }) { return "paperplane" }
        return operations.count > 1 ? "list.bullet.rectangle" : "arrow.turn.down.right"
    }
}
