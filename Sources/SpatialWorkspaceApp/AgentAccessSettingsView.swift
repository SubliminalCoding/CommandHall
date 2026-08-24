import AppKit
import SwiftUI

enum AgentFilesystemAccess {
    static let additionalRootKey = "agentFilesystemAccess.additionalRoot"

    static var additionalRoot: String {
        get {
            let saved = UserDefaults.standard.string(forKey: additionalRootKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : saved
        }
        set {
            UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: additionalRootKey)
        }
    }

    static func commandArguments(for harness: AgentHarness, root: String) -> [String] {
        let clean = root.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }
        switch harness {
        case .claude, .codex:
            return ["--add-dir", clean]
#if DEBUG
        case .diagnostic, .diagnosticSleep, .diagnosticEnvironment, .diagnosticDelayedOutput:
            return []
#endif
        }
    }
}

struct AgentAccessSettingsView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var isPresented: Bool
    @State private var additionalRoot = AgentFilesystemAccess.additionalRoot
    @State private var profile = AgentCapabilitySettings.defaultProfile
    @State private var usesSparkHandoff = AgentCapabilitySettings.usesSparkHandoff
    @State private var sparkHost = AgentCapabilitySettings.sparkHost
    @State private var statusMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Agent Capabilities")
                        .font(.title2.weight(.semibold))
                    Text("Set a default for new agents and explicit authority for every open coding session.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("DEFAULT FOR NEW SESSIONS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label("Default authority", systemImage: profile.symbol)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Picker("Default authority", selection: $profile) {
                        ForEach(SessionAuthorityProfile.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Text(profile.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                if profile == .unrestricted {
                    Label(
                        "Unrestricted disables provider approvals and sandboxing. macOS privacy controls still apply.",
                        systemImage: "exclamationmark.shield.fill"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange.opacity(0.94))
                }
            }
            .padding(14)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 9) {
                Text("OPEN CODING SESSIONS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                if store.activeWorkspace.nodes.filter(\.isCodingAgent).isEmpty {
                    Text("No Claude Code or Codex sessions are open in this workspace.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                ForEach(store.activeWorkspace.nodes.filter(\.isCodingAgent)) { node in
                    HStack {
                        Label(node.title, systemImage: node.resolvedProvider?.symbol ?? "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 150, alignment: .leading)
                        Picker("Authority for \(node.title)", selection: Binding(
                            get: { node.resolvedAuthorityProfile },
                            set: { store.setAuthorityProfile($0, for: node.id) }
                        )) {
                            ForEach(SessionAuthorityProfile.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        Spacer()
                        Text(node.status == .working ? "Next run" : "Active")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text("Additional accessible folder").font(.headline)
                HStack {
                    TextField(FileManager.default.homeDirectoryForCurrentUser.path, text: $additionalRoot)
                        .textFieldStyle(.roundedBorder)
                    Button("Choose…", action: chooseFolder)
                }
                Text("Passed with --add-dir only to unrestricted runs. Lower profiles stay bounded to their attached workspace; macOS privacy controls still apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Toggle(isOn: $usesSparkHandoff) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Linux handoff through Spark").font(.system(size: 12, weight: .semibold))
                    Text("Agents may use a configured SSH host for Linux-only builds, tests, and services after inspecting remote state.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(12)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            if usesSparkHandoff {
                HStack {
                    Text("SSH host").font(.system(size: 11, weight: .semibold))
                    TextField("spark", text: $sparkHost)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("MACOS PRIVACY")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                Text("Provider access cannot override macOS TCC. Grant this signed app only the system permissions you want it to use.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Accessibility") { openPrivacyPane("Privacy_Accessibility") }
                    Button("Automation") { openPrivacyPane("Privacy_Automation") }
                    Button("Full Disk Access") { openPrivacyPane("Privacy_AllFiles") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage).font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Save Capabilities", action: save)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 760)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: additionalRoot, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url { additionalRoot = url.path }
    }

    private func save() {
        let clean = additionalRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: clean, isDirectory: &isDirectory), isDirectory.boolValue else {
            statusMessage = "Choose an existing folder."
            return
        }
        AgentFilesystemAccess.additionalRoot = clean
        AgentCapabilitySettings.defaultProfile = profile
        AgentCapabilitySettings.usesSparkHandoff = usesSparkHandoff
        AgentCapabilitySettings.sparkHost = sparkHost
        additionalRoot = clean
        statusMessage = "Saved. New sessions default to \(profile.label) with access to \(clean)."
    }

    private func openPrivacyPane(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
