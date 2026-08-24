import AppKit
import SwiftUI

struct SessionLauncherView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var isPresented: Bool
    let initialProvider: SessionProvider

    @State private var provider: SessionProvider
    @State private var name = ""
    @State private var purpose = ""
    @State private var workingFolderPath: String?
    @State private var authorityProfile = AgentCapabilitySettings.defaultProfile
    @State private var modelSelection = AgentModelCatalog.providerDefaultID
    @State private var customModelID = ""
    @State private var showsAdvancedOptions = false
    @FocusState private var nameFocused: Bool

    init(store: WorkspaceStore, isPresented: Binding<Bool>, initialProvider: SessionProvider) {
        self.store = store
        _isPresented = isPresented
        self.initialProvider = initialProvider
        _provider = State(initialValue: initialProvider)
        _workingFolderPath = State(initialValue: nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: provider.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(provider.workspaceAccent ?? WorkspaceVisualStyle.accent)
                    .frame(width: 24, height: 24)
                Text("New session")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(WorkspacePressButtonStyle())
                .accessibilityLabel("Close new session")
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)

            Divider().opacity(0.36)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    formRow("Type") {
                        Picker("Session type", selection: $provider) {
                            ForEach(SessionProvider.allCases) { option in
                                Label(option.label, systemImage: option.symbol).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Session type")
                    }

                    formRow("Name") {
                        TextField("Session name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .medium))
                            .focused($nameFocused)
                            .onSubmit(create)
                            .padding(.horizontal, 11)
                            .frame(height: 38)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.10)))
                            .accessibilityLabel("Session name")
                    }

                    if provider == .claude || provider == .codex {
                        formRow("Model") { modelPicker }
                    }

                    if provider == .claude || provider == .codex {
                        formRow("Authority") {
                            Picker("Session authority", selection: $authorityProfile) {
                                ForEach(SessionAuthorityProfile.allCases) { profile in
                                    Text(profile.label).tag(profile)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Session authority")
                        }
                    }

                    launcherNotice

                    DisclosureGroup(isExpanded: $showsAdvancedOptions) {
                        VStack(alignment: .leading, spacing: 14) {
                            formRow("Purpose") {
                                TextField(purposePrompt, text: $purpose)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 11)
                                    .frame(height: 38)
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.10)))
                                    .accessibilityLabel("Session purpose, optional")
                            }

                            if providerUsesWorkingFolder {
                                formRow("Folder") { workingFolderPicker }
                            }
                        }
                        .padding(.top, 14)
                    } label: {
                        HStack {
                            Text("More options")
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Text(providerUsesWorkingFolder ? "Purpose and working folder" : "Purpose")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.secondary)
                }
                .padding(22)
            }
            .frame(maxHeight: 440)

            Divider().opacity(0.36)

            HStack {
                Spacer()
                Button("Create", action: create)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.66, green: 0.72, blue: 0.48))
                    .disabled(!canCreate)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .frame(width: 480)
        .background(Color(red: 0.035, green: 0.045, blue: 0.07))
        .onAppear {
            provider = initialProvider
            name = store.suggestedSessionName(for: initialProvider)
            workingFolderPath = nil
            authorityProfile = AgentCapabilitySettings.defaultProfile
            showsAdvancedOptions = false
            resetModelSelection()
            nameFocused = true
        }
        .onChange(of: provider) { _, newProvider in
            name = store.suggestedSessionName(for: newProvider)
            resetModelSelection()
        }
    }

    private var purposePrompt: String {
        switch provider {
        case .claude, .codex: "frontend, tests, architecture review…"
        case .jarvis: "strategy, decisions, project memory…"
        case .shell: "dev server, build, logs…"
        case .browser: "app preview, documentation…"
        case .note: "brief, findings, decisions…"
        }
    }

    private var providerUsesWorkingFolder: Bool {
        provider == .claude || provider == .codex || provider == .shell
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && modelSelectionIsValid
    }

    private var selectedAgentModelID: String? {
        if modelSelection == AgentModelCatalog.customID {
            return AgentModelCatalog.normalizedModelID(customModelID)
        }
        return AgentModelCatalog.normalizedModelID(modelSelection)
    }

    private var modelSelectionIsValid: Bool {
        guard provider == .claude || provider == .codex else { return true }
        if modelSelection == AgentModelCatalog.providerDefaultID { return true }
        return selectedAgentModelID != nil
    }

    private var selectedModelDetail: String {
        if modelSelection == AgentModelCatalog.customID {
            return modelSelectionIsValid
                ? "Uses the exact CLI model ID entered above."
                : "Enter a model ID using letters, numbers, dots, dashes, slashes, or colons."
        }
        return AgentModelCatalog.options(for: provider)
            .first(where: { $0.id == modelSelection })?.detail
            ?? "Use the provider's configured model."
    }

    private var modelPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Picker("Model", selection: $modelSelection) {
                ForEach(AgentModelCatalog.options(for: provider)) { option in
                    Text(option.label).tag(option.id)
                }
                Divider()
                Text("Custom model…").tag(AgentModelCatalog.customID)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Model for this \(provider.label) session")

            if modelSelection == AgentModelCatalog.customID {
                TextField("Exact CLI model ID", text: $customModelID)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(modelSelectionIsValid ? .white.opacity(0.10) : Color.orange.opacity(0.72))
                    )
            }

            if modelSelection == AgentModelCatalog.customID {
                Text(selectedModelDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(modelSelectionIsValid ? Color.secondary : Color.orange)
            }
        }
    }

    @ViewBuilder
    private var launcherNotice: some View {
        if provider == .claude || provider == .codex, authorityProfile == .unrestricted {
            Label(
                "Unrestricted bypasses provider approvals and sandboxes.",
                systemImage: "exclamationmark.shield.fill"
            )
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.orange.opacity(0.94))
            .padding(.leading, 94)
            .accessibilityLabel("Warning: Unrestricted bypasses provider approvals and sandboxes.")
        } else if provider == .jarvis {
            Label("HQ personality, memory, and voice.", systemImage: "waveform.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.leading, 94)
        } else if provider == .shell {
            Label("A local terminal without an agent.", systemImage: "terminal")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.leading, 94)
        }
    }

    private var workingFolderPicker: some View {
        HStack(spacing: 9) {
            Image(systemName: workingFolderPath == nil ? "minus.circle" : "folder.fill")
                .foregroundStyle(.secondary)
            Text(workingFolderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No folder")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            Button(workingFolderPath == nil ? "Choose…" : "Change…", action: chooseWorkingFolder)
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WorkspaceVisualStyle.accent)
            if workingFolderPath != nil {
                Button { workingFolderPath = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear working folder")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.08)))
        .accessibilityElement(children: .contain)
    }

    private func formRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 80, height: 38, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func chooseWorkingFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a working folder"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if let workingFolderPath {
            panel.directoryURL = URL(fileURLWithPath: workingFolderPath, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workingFolderPath = url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func resetModelSelection() {
        modelSelection = AgentModelCatalog.providerDefaultID
        customModelID = ""
    }

    private func create() {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, modelSelectionIsValid else { return }
        _ = store.createSession(
            provider: provider,
            name: cleanName,
            purpose: purpose,
            workingFolderMode: workingFolderPath == nil ? .unattached : .custom,
            workingFolderPath: workingFolderPath,
            authorityProfile: authorityProfile,
            agentModelID: selectedAgentModelID
        )
        isPresented = false
    }
}
