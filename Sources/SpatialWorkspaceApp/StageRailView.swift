import SwiftUI

struct StageRailView: View {
    @ObservedObject var store: WorkspaceStore
    let onClose: () -> Void
    let onGuardian: (UUID) -> Void

    private var orderedNodes: [WorkspaceNode] {
        StageProjection.ordered(
            nodes: store.activeWorkspace.nodes,
            missions: store.activeWorkspace.missionHistory,
            runtimeState: store.sessionRuntimeState
        )
    }

    private var needsYouCount: Int {
        orderedNodes.filter { group(for: $0) == .needsYou }.count
    }

    private var workingCount: Int {
        orderedNodes.filter { group(for: $0) == .working }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color(red: 0.78, green: 0.90, blue: 0.67).opacity(0.13))
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.78, green: 0.90, blue: 0.67))
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sessions")
                        .font(.system(size: 13, weight: .semibold))
                    Text(stageSummary)
                        .font(.system(size: 9))
                        .foregroundStyle(needsYouCount == 0 ? .secondary : Color.orange)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 30, height: 30)
                        .background(.white.opacity(0.04), in: Circle())
                }
                .buttonStyle(WorkspacePressButtonStyle())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Close session rail")
            }
            .padding(.horizontal, 10)
            .frame(height: 46)

            Divider().opacity(0.3)

            AutonomousMissionPanel(store: store)
                .padding(.horizontal, 8)
                .padding(.top, 8)

            if orderedNodes.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "rectangle.stack", description: Text("Add an agent or terminal to begin."))
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4, pinnedViews: []) {
                        ForEach(Array(orderedNodes.enumerated()), id: \.element.id) { index, node in
                            if index == 0 || group(for: orderedNodes[index - 1]) != group(for: node) {
                                groupHeader(for: node)
                            }
                            StageRailRow(
                                node: node,
                                runtimeState: store.sessionRuntimeState(for: node),
                                latestRun: store.latestRun(for: node.id),
                                mission: store.mission(for: node),
                                isFocused: store.focusedNodeID == node.id,
                                onChoose: { store.showOnStage(node.id) },
                                onGuardian: { onGuardian(node.id) }
                            )
                        }
                    }
                    .padding(8)
                }
                .animation(.easeInOut(duration: 0.22), value: orderedNodes.map(\.id))
            }
        }
        .frame(maxWidth: .infinity)
        .workspaceGlassPanel(cornerRadius: 16, tintOpacity: 0.80, shadowRadius: 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session rail")
    }

    private var stageSummary: String {
        if needsYouCount > 0 { return "\(needsYouCount) need\(needsYouCount == 1 ? "s" : "") you" }
        if workingCount > 0 { return "\(workingCount) working" }
        return "Fleet is under control"
    }

    private func group(for node: WorkspaceNode) -> StageGroup {
        StageProjection.group(
            for: node,
            runtimeState: store.sessionRuntimeState(for: node),
            missions: store.activeWorkspace.missionHistory
        )
    }

    private func groupHeader(for node: WorkspaceNode) -> some View {
        let group = group(for: node)
        return HStack {
            Text(group.label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.7)
                .foregroundStyle(group == .needsYou ? Color.orange : .secondary)
            Spacer()
        }
        .padding(.top, 7)
        .padding(.horizontal, 4)
    }
}

private struct StageRailRow: View {
    let node: WorkspaceNode
    let runtimeState: SessionRuntimeState
    let latestRun: WorkspaceRun?
    let mission: WorkspaceMission?
    let isFocused: Bool
    let onChoose: () -> Void
    let onGuardian: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Button(action: onChoose) {
                HStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: node.kind.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(providerAccent ?? Color.white.opacity(0.82))
                            .frame(width: 26, height: 26)
                            .background((providerAccent ?? Color.white).opacity(providerAccent == nil ? 0.065 : 0.10), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7)
                                    .stroke((providerAccent ?? Color.white).opacity(providerAccent == nil ? 0.06 : 0.30))
                            )
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(Color.black.opacity(0.65), lineWidth: 1.5))
                            .offset(x: 2, y: 2)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(node.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            if node.isMinimizedResolved {
                                Image(systemName: "minus.rectangle")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Text(goalLine)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 5)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(statusLabel)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(statusColor)
                        if let startedAt = latestRun?.startedAt, node.status == .working {
                            Text(elapsed(since: startedAt, now: context.date))
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .frame(height: 48)
                .background(isFocused ? Color.white.opacity(0.11) : .white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(isFocused ? Color(red: 0.78, green: 0.90, blue: 0.67).opacity(0.54) : .white.opacity(0.055)))
            }
            .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 9))
            .contextMenu {
                Button("Open session health", action: onGuardian)
                if node.isMinimizedResolved { Button("Restore and focus", action: onChoose) }
            }
            .accessibilityLabel("\(node.title), \(node.resolvedProvider?.label ?? node.subtitle), \(goalLine), \(statusLabel)")
            .accessibilityHint("Opens this session on the Stage.")
            .help("Focus \(node.title)")
        }
    }

    private var goalLine: String {
        if let mission { return mission.objective }
        if let run = latestRun { return run.request }
        if let purpose = node.purpose, !purpose.isEmpty { return purpose }
        return node.subtitle
    }

    private var statusLabel: String {
        if node.kind == .mission, let mission { return mission.state.label }
        return runtimeState.label
    }

    private var statusColor: Color {
        if node.status == .needsAttention || runtimeState == .needsYou || runtimeState == .interrupted || runtimeState == .unavailable { return .orange }
        if node.status == .working || runtimeState == .working || runtimeState == .launching { return .yellow }
        if node.status == .complete { return .green }
        return .white.opacity(0.36)
    }

    private var providerAccent: Color? {
        node.resolvedProvider?.workspaceAccent
    }

    private func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        return "\(seconds / 3_600)h \((seconds % 3_600) / 60)m"
    }
}
