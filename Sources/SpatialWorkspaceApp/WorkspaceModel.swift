import CoreGraphics
import Foundation

enum NodeKind: String, Codable, CaseIterable {
    case agent
    case browser
    case terminal
    case note
    case music
    case mission
    case preview
    case liveChat

    var label: String {
        switch self {
        case .agent: "Agent"
        case .browser: "Browser"
        case .terminal: "Terminal"
        case .note: "Note"
        case .music: "Music"
        case .mission: "Mission"
        case .preview: "Preview"
        case .liveChat: "Live Chat"
        }
    }

    var symbol: String {
        switch self {
        case .agent: "sparkles"
        case .browser: "globe"
        case .terminal: "terminal"
        case .note: "note.text"
        case .music: "waveform"
        case .mission: "flag.checkered"
        case .preview: "play.rectangle"
        case .liveChat: "bubble.left.and.bubble.right"
        }
    }
}

enum NodeStatus: String, Codable {
    case idle
    case working
    case complete
    case needsAttention
}

enum SessionRuntimeState: String, Codable, CaseIterable {
    case idle
    case launching
    case attached
    case working
    case needsYou
    case exited
    case interrupted
    case unavailable

    var label: String {
        switch self {
        case .idle: "Idle"
        case .launching: "Launching"
        case .attached: "Attached"
        case .working: "Working"
        case .needsYou: "Needs you"
        case .exited: "Exited"
        case .interrupted: "Interrupted"
        case .unavailable: "Unavailable"
        }
    }
}

enum SessionProvider: String, Codable, CaseIterable, Identifiable {
    case claude
    case codex
    case jarvis
    case shell
    case browser
    case note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .jarvis: "Jarvis"
        case .shell: "Terminal"
        case .browser: "Browser"
        case .note: "Note"
        }
    }

    var symbol: String {
        switch self {
        case .claude, .codex: "sparkles"
        case .jarvis: "waveform.circle.fill"
        case .shell: "terminal"
        case .browser: "globe"
        case .note: "note.text"
        }
    }

    var nodeKind: NodeKind {
        switch self {
        case .claude, .codex, .jarvis: .agent
        case .shell: .terminal
        case .browser: .browser
        case .note: .note
        }
    }
}

struct AgentModelOption: Identifiable, Equatable {
    let id: String
    let label: String
    let detail: String
}

enum AgentModelCatalog {
    static let providerDefaultID = ""
    static let customID = "__custom__"

    static func options(for provider: SessionProvider) -> [AgentModelOption] {
        switch provider {
        case .claude:
            [
                AgentModelOption(id: providerDefaultID, label: "Provider default", detail: "Use the model selected by Claude Code."),
                AgentModelOption(id: "fable", label: "Fable", detail: "Claude Code's latest-model alias."),
                AgentModelOption(id: "opus", label: "Opus", detail: "Best suited to demanding implementation and review work."),
                AgentModelOption(id: "sonnet", label: "Sonnet", detail: "Balanced capability and response speed."),
            ]
        case .codex:
            [
                AgentModelOption(id: providerDefaultID, label: "Provider default", detail: "Use the model selected in Codex configuration."),
                AgentModelOption(id: "gpt-5.6-sol", label: "GPT-5.6-Sol", detail: "Frontier model for the hardest coding work."),
                AgentModelOption(id: "gpt-5.6-terra", label: "GPT-5.6-Terra", detail: "Balanced model for everyday agent work."),
                AgentModelOption(id: "gpt-5.6-luna", label: "GPT-5.6-Luna", detail: "Fast, efficient model for routine work."),
                AgentModelOption(id: "gpt-5.5", label: "GPT-5.5", detail: "Strong model for complex coding and research."),
                AgentModelOption(id: "gpt-5.4", label: "GPT-5.4", detail: "Reliable model for everyday coding."),
                AgentModelOption(id: "gpt-5.4-mini", label: "GPT-5.4-Mini", detail: "Small, fast model for simpler tasks."),
                AgentModelOption(id: "gpt-5.3-codex-spark", label: "GPT-5.3-Codex-Spark", detail: "Ultra-fast model for short coding loops."),
            ]
        default:
            []
        }
    }

    static func normalizedModelID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:/"))
        guard trimmed.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return trimmed
    }

    static func label(for modelID: String?, provider: SessionProvider) -> String? {
        guard let modelID = normalizedModelID(modelID) else { return nil }
        return options(for: provider).first(where: { $0.id == modelID })?.label ?? modelID
    }

    static func sessionSubtitle(provider: SessionProvider, modelID: String?) -> String {
        guard let label = label(for: modelID, provider: provider) else { return provider.label }
        return "\(provider.label) · \(label)"
    }
}

enum AgentDisplayMode: String, Codable, CaseIterable, Identifiable {
    case brief
    case terminal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brief: "Brief"
        case .terminal: "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .brief: "text.bubble"
        case .terminal: "terminal"
        }
    }
}

enum SessionWorkingFolderMode: String, Codable, Equatable {
    case workspace
    case unattached
    case custom
}

enum WorkspaceChatRole: String, Codable, Equatable {
    case user
    case assistant
}

struct WorkspaceChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: WorkspaceChatRole
    var content: String
    var createdAt = Date()
}

enum RunReviewState: String, Codable {
    case accepted
    case working
    case readyToReview
    case verified
    case needsEvidence
    case failed
    case cancelled

    var isTerminal: Bool {
        switch self {
        case .accepted, .working: false
        case .readyToReview, .verified, .needsEvidence, .failed, .cancelled: true
        }
    }
}

enum ArtifactKind: String, Codable {
    case html
    case markdown
    case image
    case pdf
    case text
    case url
    case file

    var label: String {
        switch self {
        case .html: "Web page"
        case .markdown: "Markdown"
        case .image: "Image"
        case .pdf: "PDF"
        case .text: "Text"
        case .url: "Live URL"
        case .file: "File"
        }
    }

    var symbol: String {
        switch self {
        case .html, .url: "globe"
        case .markdown, .text: "doc.text"
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .file: "doc"
        }
    }

    var supportsEmbeddedPreview: Bool {
        switch self {
        case .html, .markdown, .image, .pdf, .text, .url: true
        case .file: false
        }
    }
}

struct RunEvidence: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var detail: String
    var passed: Bool
}

struct WorkspaceArtifact: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ArtifactKind
    var title: String
    var location: String
    var verified: Bool
    var modifiedAt: Date?

    var previewURL: String? {
        if kind == .url { return location }
        guard kind.supportsEmbeddedPreview else { return nil }
        return URL(fileURLWithPath: location).absoluteString
    }
}

struct WorkspaceRun: Identifiable, Codable, Equatable {
    var id = UUID()
    var sessionNodeID: UUID
    var request: String
    var state: RunReviewState
    var startedAt = Date()
    var completedAt: Date?
    var summary: String?
    var workingDirectory: String
    var evidence: [RunEvidence] = []
    var artifacts: [WorkspaceArtifact] = []
    var missionTaskID: UUID?
    var parentRunID: UUID?
    var memoryEntryIDs: [UUID]? = nil
    var memoryEntries: [WorkspaceMemoryEntry]? = nil
    var authorityProfile: SessionAuthorityProfile? = nil
    var approvalID: UUID? = nil

    var includedMemoryEntryIDs: [UUID] { memoryEntryIDs ?? [] }
    var includedMemorySnapshots: [WorkspaceMemoryEntry] { memoryEntries ?? [] }
}

enum WorkspaceApprovalState: String, Codable {
    case pending
    case approved
    case rejected
    case cancelled
}

struct WorkspaceApprovalRequest: Identifiable, Codable, Equatable {
    var id = UUID()
    var nodeID: UUID
    var nodeName: String
    var task: String
    var currentProfile: SessionAuthorityProfile
    var requestedProfile: SessionAuthorityProfile
    var reason: String
    var state: WorkspaceApprovalState = .pending
    var createdAt = Date()
    var resolvedAt: Date?
    var runID: UUID?
}

enum MissionTaskRole: String, Codable {
    case worker
    case reviewer
}

enum MissionTaskState: String, Codable {
    case planned
    case working
    case blocked
    case readyForReview
    case verified
    case failed
    case cancelled

    var isSuccessful: Bool { self == .readyForReview || self == .verified }
    var isTerminal: Bool { isSuccessful || self == .failed || self == .cancelled }
}

struct MissionTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var role: MissionTaskRole
    var assigneeNodeID: UUID
    var state: MissionTaskState = .planned
    var dependencyIDs: [UUID] = []
    var runID: UUID?
    var detail: String?
}

enum MissionState: String, Codable {
    case drafted
    case working
    case needsAttention
    case readyForReview
    case verified
    case failed
    case cancelled

    var label: String {
        switch self {
        case .drafted: "Ready to launch"
        case .working: "In progress"
        case .needsAttention: "Needs you"
        case .readyForReview: "Ready to review"
        case .verified: "Verified"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

struct WorkspaceMission: Identifiable, Codable, Equatable {
    var id = UUID()
    var nodeID: UUID
    var title: String
    var objective: String
    var state: MissionState = .drafted
    var createdAt = Date()
    var startedAt: Date?
    var completedAt: Date?
    var tasks: [MissionTask]
}

struct PromptDispatch: Identifiable, Equatable {
    var id = UUID()
    var targetNodeID: UUID
    var summary: String
}

struct PointValue: Codable, Equatable {
    var x: Double
    var y: Double

    init(_ point: CGPoint) {
        x = point.x
        y = point.y
    }

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

struct SizeValue: Codable, Equatable {
    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    var cgSize: CGSize { CGSize(width: width, height: height) }
}

struct CameraTransform: Codable, Equatable {
    static let scaleRange = 0.25 ... 1.8

    var offset = PointValue(x: 0, y: 0)
    var scale = 1.0

    mutating func clampScale() {
        scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
    }

    func worldTranslation(forScreenTranslation translation: CGSize) -> CGSize {
        CGSize(width: translation.width / scale, height: translation.height / scale)
    }

    mutating func zoom(to requestedScale: Double, around screenPoint: CGPoint) {
        let oldScale = scale
        let newScale = min(max(requestedScale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        guard oldScale > 0, newScale != oldScale else { return }
        let worldX = (screenPoint.x - offset.x) / oldScale
        let worldY = (screenPoint.y - offset.y) / oldScale
        scale = newScale
        offset = PointValue(
            x: screenPoint.x - worldX * newScale,
            y: screenPoint.y - worldY * newScale
        )
    }
}

struct WorkspaceNode: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: NodeKind
    var title: String
    var subtitle: String
    var position: PointValue
    var size: SizeValue
    var zIndex: Int
    var status: NodeStatus
    var content: String
    var url: String?
    var sessionID: String?
    var revision: Int
    var provider: SessionProvider?
    var purpose: String?
    var agentModelID: String?
    /// Auto-generated 1-2 word label describing what a terminal is currently working on. Best-effort, refreshed as output grows.
    var terminalSummary: String?
    var linkedRunID: UUID?
    var draft: String?
    var queuedPrompt: String?
    var isMinimized: Bool?
    var runtimeState: SessionRuntimeState?
    var runtimeDetail: String?
    var runtimeUpdatedAt: Date?
    var missionID: UUID?
    var chatHistory: [WorkspaceChatMessage]?
    var agentDisplayMode: AgentDisplayMode?
    var activityLog: String?
    var workingFolderMode: SessionWorkingFolderMode?
    var workingFolderPath: String?
    var authorityProfile: SessionAuthorityProfile?

    init(
        id: UUID = UUID(),
        kind: NodeKind,
        title: String,
        subtitle: String,
        position: CGPoint,
        size: CGSize,
        zIndex: Int,
        status: NodeStatus = .idle,
        content: String = "",
        url: String? = nil,
        sessionID: String? = nil,
        revision: Int = 0,
        provider: SessionProvider? = nil,
        purpose: String? = nil,
        terminalSummary: String? = nil,
        linkedRunID: UUID? = nil,
        draft: String? = nil,
        isMinimized: Bool = false,
        runtimeState: SessionRuntimeState = .idle,
        runtimeDetail: String? = nil,
        runtimeUpdatedAt: Date? = nil,
        missionID: UUID? = nil,
        chatHistory: [WorkspaceChatMessage]? = nil,
        agentDisplayMode: AgentDisplayMode? = nil,
        activityLog: String? = nil,
        workingFolderMode: SessionWorkingFolderMode? = nil,
        workingFolderPath: String? = nil,
        authorityProfile: SessionAuthorityProfile? = nil,
        agentModelID: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.position = PointValue(position)
        self.size = SizeValue(width: size.width, height: size.height)
        self.zIndex = zIndex
        self.status = status
        self.content = content
        self.url = url
        self.sessionID = sessionID
        self.revision = revision
        self.provider = provider
        self.purpose = purpose
        self.agentModelID = agentModelID
        self.terminalSummary = terminalSummary
        self.linkedRunID = linkedRunID
        self.draft = draft
        self.isMinimized = isMinimized
        self.runtimeState = runtimeState
        self.runtimeDetail = runtimeDetail
        self.runtimeUpdatedAt = runtimeUpdatedAt
        self.missionID = missionID
        self.chatHistory = chatHistory
        self.agentDisplayMode = agentDisplayMode
        self.activityLog = activityLog
        self.workingFolderMode = workingFolderMode
        self.workingFolderPath = workingFolderPath
        self.authorityProfile = authorityProfile
    }

    var isMinimizedResolved: Bool { isMinimized ?? false }
    var resolvedRuntimeState: SessionRuntimeState { runtimeState ?? (status == .working ? .working : .idle) }

    var resolvedProvider: SessionProvider? {
        if let provider { return provider }
        let label = subtitle.lowercased()
        if label.contains("claude") { return .claude }
        if label.contains("codex") { return .codex }
        if label.contains("jarvis") { return .jarvis }
        if kind == .terminal { return .shell }
        if kind == .browser { return .browser }
        if kind == .note { return .note }
        return nil
    }

    var isCodingAgent: Bool {
        kind == .agent && (resolvedProvider == .claude || resolvedProvider == .codex)
    }

    var resolvedAgentDisplayMode: AgentDisplayMode { agentDisplayMode ?? .brief }
    var resolvedAuthorityProfile: SessionAuthorityProfile { authorityProfile ?? AgentCapabilitySettings.defaultProfile }
    var resolvedAgentModelID: String? { AgentModelCatalog.normalizedModelID(agentModelID) }
}

struct WorkspaceDocument: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var theme: String
    var rootPath: String?
    var camera: CameraTransform
    var nodes: [WorkspaceNode]
    var runs: [WorkspaceRun]?
    var layoutMode: WorkspaceLayoutMode?
    var missions: [WorkspaceMission]?
    var memory: [WorkspaceMemoryEntry]? = nil
    var activityEvents: [WorkspaceActivityEvent]? = nil
    var approvalRequests: [WorkspaceApprovalRequest]? = nil

    var runHistory: [WorkspaceRun] { runs ?? [] }
    var resolvedLayoutMode: WorkspaceLayoutMode { layoutMode ?? .balanced }
    var missionHistory: [WorkspaceMission] { missions ?? [] }
    var memoryEntries: [WorkspaceMemoryEntry] { memory ?? [] }
    var eventHistory: [WorkspaceActivityEvent] { activityEvents ?? [] }
    var approvalHistory: [WorkspaceApprovalRequest] { approvalRequests ?? [] }
}

struct PersistedWorkspaceState: Codable, Equatable {
    var schemaVersion = WorkspacePersistence.currentSchemaVersion
    var activeWorkspaceID: UUID
    var workspaces: [WorkspaceDocument]
}
