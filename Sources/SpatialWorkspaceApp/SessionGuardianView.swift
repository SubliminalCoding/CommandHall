import SwiftUI

struct SessionGuardianView: View {
    @ObservedObject var store: WorkspaceStore
    let nodeID: UUID
    @Binding var isPresented: Bool

    private var node: WorkspaceNode? {
        store.activeWorkspace.nodes.first(where: { $0.id == nodeID })
    }

    var body: some View {
        Group {
            if let node {
                guardian(node)
            } else {
                ContentUnavailableView("Session unavailable", systemImage: "exclamationmark.triangle")
                    .frame(width: 500, height: 300)
            }
        }
        .background(WorkspaceVisualStyle.panelTint)
    }

    private func guardian(_ node: WorkspaceNode) -> some View {
        let diagnostic = store.sessionDiagnostic(for: node.id)
        let runtime = store.sessionRuntimeState(for: node)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "heart.text.square")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(statusColor(runtime))
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Session Guardian")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("\(node.title) · \(node.subtitle)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.05), in: Circle())
                }
                    .buttonStyle(WorkspacePressButtonStyle())
                    .accessibilityLabel("Close Session Guardian")
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor(runtime))
                        .frame(width: 7, height: 7)
                    Text(runtime.label)
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    if !diagnostic.isReady {
                        Label("Action needed", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Text(node.runtimeDetail ?? runtimeDetail(runtime))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if !diagnostic.isReady {
                    Text(diagnostic.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
            }
            .padding(13)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack(spacing: 8) {
                if node.kind == .agent, node.status == .working {
                    Button("Cancel current task", role: .destructive) { store.cancelAgent(node.id) }
                        .buttonStyle(.bordered)
                } else if node.kind == .agent, store.latestRun(for: node.id) != nil {
                    Button(node.sessionID == nil ? "Retry last task" : "Resume conversation") {
                        if store.retryLastTask(for: node.id) {
                            isPresented = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.36, green: 0.58, blue: 0.49))
                }
                if node.kind == .terminal {
                    Button("Restart terminal") {
                        store.restartTerminal(node.id)
                        isPresented = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                if (node.kind == .agent || node.kind == .terminal),
                   node.status == .needsAttention || runtime == .interrupted || runtime == .unavailable {
                    Button("Dismiss issue") { store.dismissSessionIssue(node.id) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if !diagnostic.isReady {
                    Button("Choose working folder…", action: store.chooseActiveWorkspaceFolder)
                        .buttonStyle(.bordered)
                }
            }

            DisclosureGroup("Session details") {
                VStack(alignment: .leading, spacing: 7) {
                    diagnosticRow("Readiness", detail: diagnostic.isReady ? "Ready" : diagnostic.title, symbol: diagnostic.isReady ? "checkmark.circle" : "exclamationmark.triangle")
                    diagnosticRow("Working folder", detail: store.sessionWorkingFolderLabel(for: node.id), symbol: "folder")
                    diagnosticRow("Executable", detail: diagnostic.executablePath ?? "Not required or unavailable", symbol: "terminal")
                    if node.isCodingAgent {
                        diagnosticRow("Authority", detail: node.resolvedAuthorityProfile.label, symbol: node.resolvedAuthorityProfile.symbol)
                        diagnosticRow(
                            "Linux handoff",
                            detail: AgentCapabilitySettings.usesSparkHandoff ? "ssh \(AgentCapabilitySettings.sparkHost)" : "Disabled",
                            symbol: "server.rack"
                        )
                    }
                    diagnosticRow("Conversation", detail: node.sessionID ?? "A new provider session will be created", symbol: "bubble.left.and.bubble.right")
                    diagnosticRow("Ownership", detail: "\(ownershipLabel(node)) · \(ownershipDetail(node))", symbol: "person.crop.circle.badge.checkmark")
                    diagnosticRow("Last check", detail: diagnostic.checkedAt.formatted(date: .omitted, time: .standard), symbol: "clock")

                    if let run = store.latestRun(for: node.id) {
                        Divider().opacity(0.5)
                        HStack {
                            Text(run.request)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(2)
                            Spacer()
                            Text(run.state.rawValue.replacingOccurrences(of: "readyToReview", with: "ready to review"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        if let summary = run.summary {
                            Text(summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text("Authority used: \((run.authorityProfile ?? node.resolvedAuthorityProfile).label)\(run.approvalID == nil ? "" : " · approved once")")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .tint(.secondary)
            .padding(12)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .padding(22)
        .frame(width: 620)
    }

    private func diagnosticRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 16).foregroundStyle(.secondary)
            Text(title).font(.system(size: 10, weight: .medium))
            Spacer()
            Text(detail).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func runtimeDetail(_ state: SessionRuntimeState) -> String {
        switch state {
        case .idle: "Ready for work"
        case .launching: "Starting provider process"
        case .attached: "Interactive process is attached"
        case .working: "Task is executing"
        case .needsYou: "Input or review is required"
        case .exited: "The last process ended"
        case .interrupted: "The previous process did not finish normally"
        case .unavailable: "Provider or process is unavailable"
        }
    }

    private func ownershipDetail(_ node: WorkspaceNode) -> String {
        if node.resolvedProvider == .jarvis {
            return "Conversation runs through HQ over Tailscale"
        }
        return switch node.kind {
        case .agent: "Child process ends if the app exits"
        case .terminal: "PTY ends when the session closes"
        case .mission: "Saved coordination state; workers own their processes"
        case .browser, .preview, .liveChat: "Web view belongs to this app window"
        case .note, .music: "No child process is attached"
        }
    }

    private func ownershipLabel(_ node: WorkspaceNode) -> String {
        switch node.kind {
        case .agent, .terminal: "App owned"
        case .mission: "Saved state"
        case .browser, .preview, .liveChat, .note, .music: "No process"
        }
    }

    private func statusColor(_ state: SessionRuntimeState) -> Color {
        switch state {
        case .working, .launching: .yellow
        case .attached: .cyan
        case .needsYou, .interrupted, .unavailable: .orange
        case .exited: .green
        case .idle: .white.opacity(0.55)
        }
    }
}
