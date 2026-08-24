import Foundation

struct StageLocalPublishedSession: Equatable {
    var id: String
    var title: String
    var provider: String
    var runtimeState: String
    var sessionId: String?
    var lastActivityAt: Date
    var eventCount: Int
    var minimized: Bool
    var activitySummary: String? = nil

    static func standaloneID(for tty: String) -> String {
        let stem = tty.lowercased()
            .replacingOccurrences(of: "[^a-z0-9-]", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "terminal-app-\(stem.isEmpty ? "session" : stem)"
    }
}

struct StageLocalSessionSnapshot: Codable, Equatable {
    static let source = "mac-mini"
    static let maximumSessions = 64

    var source: String
    var workspace: String
    var observedAt: String
    var selectedSessionId: String?
    var sessions: [Session]

    struct Session: Codable, Equatable {
        var id: String
        var title: String
        var provider: String
        var runtimeState: String
        var sessionId: String?
        var lastActivityAt: String
        var eventCount: Int
        var minimized: Bool
        var activitySummary: String?
    }

    init(
        workspace: WorkspaceDocument,
        selectedSession: StageLocalPublishedSession? = nil,
        now: Date = Date()
    ) {
        let formatter = ISO8601DateFormatter()
        source = Self.source
        self.workspace = Self.bounded(workspace.name, maximum: 100, fallback: "Workspace")
        observedAt = formatter.string(from: now)
        var mapped = workspace.nodes
            .filter { $0.kind == .agent || $0.kind == .terminal }
            .map { node in
                Session(
                    id: node.id.uuidString.lowercased(),
                    title: Self.bounded(node.title, maximum: 100, fallback: node.kind.label),
                    provider: node.resolvedProvider?.rawValue ?? SessionProvider.shell.rawValue,
                    runtimeState: node.resolvedRuntimeState.rawValue,
                    sessionId: node.sessionID.map { Self.bounded($0, maximum: 160, fallback: "") }.flatMap { $0.isEmpty ? nil : $0 },
                    lastActivityAt: formatter.string(from: node.runtimeUpdatedAt ?? now),
                    eventCount: Self.eventCount(for: node),
                    minimized: node.isMinimizedResolved,
                    activitySummary: StageTerminalActivity.summary(
                        for: node.activityLog ?? "",
                        runtimeState: node.resolvedRuntimeState.rawValue
                    )
                )
            }
        if let selectedSession {
            let selected = Session(
                id: selectedSession.id,
                title: Self.bounded(selectedSession.title, maximum: 100, fallback: "Terminal"),
                provider: selectedSession.provider,
                runtimeState: selectedSession.runtimeState,
                sessionId: selectedSession.sessionId,
                lastActivityAt: formatter.string(from: selectedSession.lastActivityAt),
                eventCount: min(100_000, max(0, selectedSession.eventCount)),
                minimized: selectedSession.minimized,
                activitySummary: selectedSession.activitySummary.map {
                    Self.bounded($0, maximum: 160, fallback: "The selected terminal is open and quiet")
                }
            )
            if let index = mapped.firstIndex(where: { $0.id == selected.id }) {
                mapped[index] = selected
            } else {
                mapped.append(selected)
            }
            selectedSessionId = selected.id
        } else {
            selectedSessionId = nil
        }
        sessions = Array(mapped.prefix(Self.maximumSessions))
        if let selectedSessionId, !sessions.contains(where: { $0.id == selectedSessionId }) {
            self.selectedSessionId = nil
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    private static func bounded(_ value: String, maximum: Int, fallback: String) -> String {
        let clean = value
            .replacingOccurrences(of: "[\\u{0000}-\\u{001F}\\u{007F}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return fallback }
        return String(clean.prefix(maximum))
    }

    private static func eventCount(for node: WorkspaceNode) -> Int {
        eventCount(in: node.activityLog)
    }

    static func eventCount(in log: String?) -> Int {
        guard let log, !log.isEmpty else { return 0 }
        var count = 1
        var previousWasCarriageReturn = false
        for byte in log.utf8 {
            if byte == 0x0A, !previousWasCarriageReturn {
                count += 1
                if count == 100_000 { return count }
            }
            previousWasCarriageReturn = byte == 0x0D
        }
        return count
    }
}
