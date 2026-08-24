import SwiftUI

struct ApprovalInboxView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Approvals")
                        .font(.system(size: 20, weight: .bold))
                    Text("Requests that expand a session’s authority in \(store.activeWorkspace.name)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            if store.pendingAuthorityApprovals.isEmpty {
                ContentUnavailableView {
                    Label("Nothing needs you", systemImage: "checkmark.shield")
                } description: {
                    Text("Authority requests appear when a session needs a wider boundary.")
                }
            } else {
                List(store.pendingAuthorityApprovals) { approval in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top) {
                            Image(systemName: approval.requestedProfile.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(approval.requestedProfile == .unrestricted ? Color.orange : WorkspaceVisualStyle.accent)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(approval.nodeName) requests \(approval.requestedProfile.label)")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Currently \(approval.currentProfile.label) · \(approval.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(approval.task)
                            .font(.system(size: 12, weight: .medium))
                            .textSelection(.enabled)
                        Text(approval.reason)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if approval.requestedProfile == .unrestricted {
                            Label("This run will bypass provider approvals and sandboxing. macOS privacy controls still apply.", systemImage: "exclamationmark.shield.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.orange)
                        }
                        HStack {
                            Button("Reject") {
                                store.rejectAuthorityRequest(approval.id)
                            }
                            Spacer()
                            Button("Allow for session & run") {
                                if store.approveAuthorityRequest(approval.id) {
                                    store.setAuthorityProfile(approval.requestedProfile, for: approval.nodeID)
                                }
                            }
                            .buttonStyle(.bordered)
                            Button("Approve once") {
                                _ = store.approveAuthorityRequest(approval.id)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.vertical, 10)
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(WorkspaceVisualStyle.panelTint.opacity(0.97))
    }
}
