import SwiftUI

struct WorkspaceSwitcherView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Workspaces")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    isPresented = false
                    store.chooseFolderAndCreateWorkspace()
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(store.state.workspaces) { workspace in
                        workspaceCard(workspace)
                    }
                }
            }
            .frame(maxHeight: 380)
        }
        .padding(16)
        .frame(width: 510)
        .background(Color(red: 0.035, green: 0.055, blue: 0.09))
    }

    private func workspaceCard(_ workspace: WorkspaceDocument) -> some View {
        let isActive = workspace.id == store.activeWorkspace.id
        let agents = workspace.nodes.filter { $0.kind == .agent }
        let workingCount = agents.filter { $0.status == .working }.count
        let attentionCount = agents.filter { $0.status == .needsAttention }.count

        return HStack(spacing: 10) {
            Button {
                store.switchWorkspace(to: workspace.id)
                isPresented = false
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workspace.name)
                            .font(.system(size: 13, weight: .semibold))
                        Text(workspace.rootPath ?? "No project folder")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    if attentionCount > 0 {
                        Label("\(attentionCount) need you", systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    } else if workingCount > 0 {
                        Label("\(workingCount) working", systemImage: "circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color(red: 0.80, green: 0.86, blue: 0.63))
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 11))
            .accessibilityLabel(workspaceAccessibilityLabel(
                workspace: workspace,
                agentCount: agents.count,
                workingCount: workingCount,
                attentionCount: attentionCount,
                isActive: isActive
            ))
            .accessibilityAddTraits(isActive ? .isSelected : [])

            Menu {
                Button("Open") {
                    store.switchWorkspace(to: workspace.id)
                    isPresented = false
                }
                Button("Rename…") {
                    store.switchWorkspace(to: workspace.id)
                    isPresented = false
                    DispatchQueue.main.async { store.promptToRenameActiveWorkspace() }
                }
                Button("Change project folder…") {
                    store.switchWorkspace(to: workspace.id)
                    isPresented = false
                    DispatchQueue.main.async { store.chooseActiveWorkspaceFolder() }
                }
                Button("Duplicate") {
                    store.switchWorkspace(to: workspace.id)
                    store.duplicateActiveWorkspace()
                    isPresented = false
                }
                Divider()
                Button("Delete…", role: .destructive) {
                    store.switchWorkspace(to: workspace.id)
                    isPresented = false
                    DispatchQueue.main.async { store.confirmDeleteActiveWorkspace() }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Actions for \(workspace.name)")
        }
        .padding(10)
        .background(isActive ? .white.opacity(0.065) : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(isActive ? Color(red: 0.80, green: 0.86, blue: 0.63).opacity(0.32) : .white.opacity(0.06)))
    }

    private func workspaceAccessibilityLabel(
        workspace: WorkspaceDocument,
        agentCount: Int,
        workingCount: Int,
        attentionCount: Int,
        isActive: Bool
    ) -> String {
        var details = ["Open \(workspace.name)", "\(agentCount) agents"]
        if attentionCount > 0 { details.append("\(attentionCount) need attention") }
        if workingCount > 0 { details.append("\(workingCount) working") }
        if isActive { details.append("Current workspace") }
        return details.joined(separator: ", ")
    }
}
