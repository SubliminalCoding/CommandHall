import Foundation

enum SessionAuthorityProfile: String, Codable, CaseIterable, Identifiable, Comparable {
    case readOnly
    case workspaceEdits
    case localCommands
    case unrestricted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .readOnly: "Read only"
        case .workspaceEdits: "Workspace edits"
        case .localCommands: "Run local commands"
        case .unrestricted: "Unrestricted"
        }
    }

    var symbol: String {
        switch self {
        case .readOnly: "eye"
        case .workspaceEdits: "pencil.and.outline"
        case .localCommands: "terminal"
        case .unrestricted: "bolt.shield.fill"
        }
    }

    var detail: String {
        switch self {
        case .readOnly: "Inspect the project without changing files or running mutating commands."
        case .workspaceEdits: "Read and edit files inside the attached workspace; shell execution remains restricted."
        case .localCommands: "Edit the workspace and run locally reviewed commands inside provider safeguards."
        case .unrestricted: "Bypass provider approvals and sandboxes for trusted network, SSH, or boundary-expanding work."
        }
    }

    private var rank: Int {
        switch self {
        case .readOnly: 0
        case .workspaceEdits: 1
        case .localCommands: 2
        case .unrestricted: 3
        }
    }

    static func < (lhs: SessionAuthorityProfile, rhs: SessionAuthorityProfile) -> Bool {
        lhs.rank < rhs.rank
    }
}

enum AgentCapabilitySettings {
    static let defaultProfileKey = "agentCapabilities.defaultSessionProfile"
    static let legacyProfileKey = "agentCapabilities.profile"
    static let sparkHandoffKey = "agentCapabilities.sparkHandoff"
    static let sparkHostKey = "agentCapabilities.sparkHost"

    static var sparkHost: String {
        get {
            let saved = UserDefaults.standard.string(forKey: sparkHostKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? "spark" : saved
        }
        set {
            UserDefaults.standard.set(
                newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                forKey: sparkHostKey
            )
        }
    }

    static var defaultProfile: SessionAuthorityProfile {
        get {
            if let rawValue = UserDefaults.standard.string(forKey: defaultProfileKey),
               let saved = SessionAuthorityProfile(rawValue: rawValue) {
                return saved
            }
            if UserDefaults.standard.string(forKey: legacyProfileKey) == "full" { return .unrestricted }
            if UserDefaults.standard.string(forKey: legacyProfileKey) == "standard" { return .workspaceEdits }
            return .unrestricted
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: defaultProfileKey) }
    }

    static var usesSparkHandoff: Bool {
        get {
            guard UserDefaults.standard.object(forKey: sparkHandoffKey) != nil else { return false }
            return UserDefaults.standard.bool(forKey: sparkHandoffKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: sparkHandoffKey) }
    }

    static func commandArguments(for harness: AgentHarness, profile: SessionAuthorityProfile) -> [String] {
        switch (harness, profile) {
        case (.codex, .readOnly): ["--sandbox", "read-only", "-c", "approval_policy=\"never\""]
        case (.codex, .workspaceEdits): ["--sandbox", "workspace-write", "-c", "approval_policy=\"never\""]
        case (.codex, .localCommands): ["--approve-for-me"]
        case (.codex, .unrestricted): ["--dangerously-bypass-approvals-and-sandbox"]
        case (.claude, .readOnly): ["--permission-mode", "plan"]
        case (.claude, .workspaceEdits): ["--permission-mode", "acceptEdits"]
        case (.claude, .localCommands): ["--permission-mode", "auto"]
        case (.claude, .unrestricted): ["--dangerously-skip-permissions"]
#if DEBUG
        case (.diagnostic, _), (.diagnosticSleep, _), (.diagnosticEnvironment, _), (.diagnosticDelayedOutput, _): []
#endif
        }
    }

    static func sessionInstructions(profile: SessionAuthorityProfile) -> String {
        var lines: [String] = []
        switch profile {
        case .readOnly:
            lines.append("- Session authority: Read only. Inspect and report; do not change files or execute mutating commands.")
        case .workspaceEdits:
            lines.append("- Session authority: Workspace edits. Changes must remain inside the attached workspace. Report any shell or boundary access that provider safeguards deny.")
        case .localCommands:
            lines.append("- Session authority: Run local commands. Work inside the attached workspace and use locally reviewed commands; report requests for network, SSH, or access outside the workspace.")
        case .unrestricted:
            lines.append("- Session authority: Unrestricted for this approved run. Provider sandbox and approval prompts are disabled. Use the smallest necessary scope and preserve unrelated work.")
        }
        let host = sparkHost
        if usesSparkHandoff, profile == .unrestricted {
            lines.append("- Linux handoff: SSH host `\(host)` is configured. When verification needs Linux tools or services unavailable on macOS, use `ssh \(host)`. Inspect the remote repository and its working tree before changing it. For local-only edits, transfer an isolated copy to a remote temporary directory rather than overwriting unrelated remote work.")
        } else if usesSparkHandoff {
            lines.append("- Linux handoff: SSH host `\(host)` exists, but this run is not approved for remote access. Report that boundary if the task requires it.")
        }
        lines.append("- macOS privacy boundary: Automation, Accessibility, Full Disk Access, microphone, and protected-folder access remain controlled by macOS. If TCC blocks an operation, try a non-UI command or SSH route first; otherwise report the exact Privacy & Security permission and target application required.")
        lines.append("- Spatial audio controls: this session receives a scoped, short-lived Spatial Workspace identity. Use `$SPATIAL_AGENT_CLI audio status` to inspect audio, `audio plan` before a change, `audio apply` only with the returned plan and revision, and `audio panic` for immediate mute. Never print, copy, or persist the session environment. MCP-capable clients may run `$SPATIAL_AGENT_CLI mcp`; both interfaces enforce the same four semantic operations.")
        lines.append("- Completion standard: do not call work complete while required tests, builds, previews, or evidence remain unattempted. Distinguish a verified result from a remaining external permission boundary.")
        return lines.joined(separator: "\n")
    }

    static func processEnvironment(for harness: AgentHarness) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let preferredPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "\(home)/.bun/bin",
            "\(home)/.local/share/pnpm",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let inherited = environment["PATH"]?.split(separator: ":").map(String.init) ?? []
        environment["PATH"] = Array(NSOrderedSet(array: preferredPaths + inherited))
            .compactMap { $0 as? String }
            .joined(separator: ":")
        environment["TERM"] = environment["TERM"] ?? "xterm-256color"
        if harness == .claude {
            // Preserve Claude subscription/keychain auth instead of accidentally
            // switching the session to an inherited pay-as-you-go API key.
            environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        }
        return environment
    }
}

struct SessionAuthorityAssessment: Equatable {
    var requiredProfile: SessionAuthorityProfile
    var reason: String

    static func assess(_ task: String) -> SessionAuthorityAssessment {
        let text = task.lowercased()
        let boundaryTerms = [
            "ssh ", "spark", "deploy", "publish", "release", "download", "network",
            "outside the workspace", "outside workspace", "full disk", "force push",
            "delete files", "remove files", "drop database",
        ]
        if boundaryTerms.contains(where: text.contains) {
            return SessionAuthorityAssessment(
                requiredProfile: .unrestricted,
                reason: "The request appears to use network, remote, destructive, or outside-workspace access."
            )
        }
        let commandTerms = [
            "run ", "build", "test", "lint", "compile", "install", "command", "script",
            "git ", "npm ", "swift ", "cargo ", "bun ",
        ]
        if commandTerms.contains(where: text.contains) {
            return SessionAuthorityAssessment(
                requiredProfile: .localCommands,
                reason: "The request appears to require local command execution."
            )
        }
        let editTerms = [
            "edit", "change", "fix", "write", "create", "implement", "update", "refactor",
            "make ", "add ", "polish", "improve",
        ]
        if editTerms.contains(where: text.contains) {
            return SessionAuthorityAssessment(
                requiredProfile: .workspaceEdits,
                reason: "The request appears to change files in the attached workspace."
            )
        }
        return SessionAuthorityAssessment(
            requiredProfile: .readOnly,
            reason: "The request appears to need inspection only."
        )
    }
}
