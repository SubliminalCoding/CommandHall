import SwiftUI

struct MissionPane: View {
    let mission: WorkspaceMission
    let nodeTitle: (UUID) -> String
    let onStart: () -> Void
    let onCancel: () -> Void
    let onReview: () -> Void
    let onVerify: () -> Void
    let onOpenWorker: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(mission.state.label, systemImage: stateSymbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(stateColor)
                        Text(mission.objective)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(4)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 12)
                    progressRing
                }
                ProgressView(value: progress)
                    .tint(stateColor)
            }
            .padding(14)
            .background(.white.opacity(0.035))

            ScrollView {
                VStack(spacing: 7) {
                    ForEach(mission.tasks) { task in
                        Button { onOpenWorker(task.assigneeNodeID) } label: {
                            HStack(spacing: 9) {
                                Image(systemName: task.role == .reviewer ? "checkmark.seal" : "person.crop.circle")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(task.role == .reviewer ? Color.cyan.opacity(0.85) : .white.opacity(0.72))
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 5) {
                                        Text(nodeTitle(task.assigneeNodeID))
                                            .font(.system(size: 11, weight: .semibold))
                                        if task.role == .reviewer {
                                            Text("REVIEWER")
                                                .font(.system(size: 7, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .frame(height: 14)
                                                .background(Color.cyan.opacity(0.12), in: Capsule())
                                        }
                                    }
                                    Text(task.title)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if let detail = task.detail {
                                        Text(detail)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Label(taskStateLabel(task.state), systemImage: taskStateSymbol(task.state))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(taskStateColor(task.state))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.07)))
                        }
                        .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 8))
                        .accessibilityLabel("Open \(nodeTitle(task.assigneeNodeID)), \(taskStateLabel(task.state))")
                    }
                }
                .padding(12)
            }

            Divider().opacity(0.35)
            HStack(spacing: 8) {
                switch mission.state {
                case .drafted, .needsAttention:
                    Button("Launch mission", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.36, green: 0.58, blue: 0.49))
                case .working:
                    Button("Cancel mission", role: .destructive, action: onCancel)
                        .buttonStyle(.bordered)
                case .readyForReview:
                    Button("Open Review Room", action: onReview)
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.42, green: 0.59, blue: 0.46))
                    Button("Accept mission", action: onVerify)
                        .buttonStyle(.bordered)
                case .verified:
                    Label("Mission accepted", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                case .failed, .cancelled:
                    Button("Review available work", action: onReview)
                        .buttonStyle(.bordered)
                }
                Spacer()
            }
            .padding(10)
        }
        .background(Color.black.opacity(0.18))
    }

    private var progress: Double {
        guard !mission.tasks.isEmpty else { return 0 }
        return Double(mission.tasks.filter(\.state.isTerminal).count) / Double(mission.tasks.count)
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.09), lineWidth: 4)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(stateColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .frame(width: 46, height: 46)
        .accessibilityLabel("Mission progress, \(Int((progress * 100).rounded())) percent")
    }

    private var stateSymbol: String {
        switch mission.state {
        case .drafted: "paperplane"
        case .working: "arrow.trianglehead.2.clockwise.rotate.90"
        case .needsAttention: "person.crop.circle.badge.exclamationmark"
        case .readyForReview: "doc.badge.ellipsis"
        case .verified: "checkmark.seal.fill"
        case .failed, .cancelled: "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch mission.state {
        case .drafted: .white.opacity(0.7)
        case .working: Color(red: 0.94, green: 0.78, blue: 0.35)
        case .needsAttention: Color.orange
        case .readyForReview: Color(red: 0.78, green: 0.90, blue: 0.67)
        case .verified: Color.green
        case .failed, .cancelled: Color.red
        }
    }

    private func taskStateLabel(_ state: MissionTaskState) -> String {
        switch state {
        case .planned: "Planned"
        case .working: "Working"
        case .blocked: "Blocked"
        case .readyForReview: "Ready"
        case .verified: "Verified"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }

    private func taskStateSymbol(_ state: MissionTaskState) -> String {
        switch state {
        case .planned: "circle"
        case .working: "hourglass"
        case .blocked: "exclamationmark.circle.fill"
        case .readyForReview: "doc.badge.ellipsis"
        case .verified: "checkmark.circle.fill"
        case .failed, .cancelled: "xmark.circle.fill"
        }
    }

    private func taskStateColor(_ state: MissionTaskState) -> Color {
        switch state {
        case .planned: .secondary
        case .working: .yellow
        case .blocked: .orange
        case .readyForReview: Color(red: 0.78, green: 0.90, blue: 0.67)
        case .verified: .green
        case .failed, .cancelled: .red
        }
    }
}

struct MissionLauncherView: View {
    @ObservedObject var store: WorkspaceStore
    @Binding var isPresented: Bool

    @State private var title = ""
    @State private var objective = ""
    @State private var workerIDs: Set<UUID> = []
    @State private var reviewerID: UUID?
    @FocusState private var objectiveFocused: Bool

    private var agents: [WorkspaceNode] {
        store.activeWorkspace.nodes.filter(\.isCodingAgent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New mission")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("Assign workers now. The reviewer starts after their work is ready.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.05), in: Circle())
                }
                    .buttonStyle(WorkspacePressButtonStyle())
                    .accessibilityLabel("Close new mission")
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("MISSION NAME").missionFieldLabel()
                TextField("Landing page launch", text: $title)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 11)
                    .frame(height: 38)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.10)))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("OBJECTIVE").missionFieldLabel()
                TextEditor(text: $objective)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13))
                    .focused($objectiveFocused)
                    .padding(8)
                    .frame(height: 105)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.10)))
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("WORKERS").missionFieldLabel()
                    VStack(spacing: 4) {
                        ForEach(agents) { agent in
                            Toggle(isOn: Binding(
                                get: { workerIDs.contains(agent.id) },
                                set: { selected in
                                    if selected {
                                        workerIDs.insert(agent.id)
                                    } else {
                                        workerIDs.remove(agent.id)
                                    }
                                }
                            )) {
                                HStack {
                                    Text(agent.title).font(.system(size: 11, weight: .medium))
                                    Spacer()
                                    Text(agent.resolvedProvider?.label ?? "Agent").font(.system(size: 9)).foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .padding(.horizontal, 9)
                            .frame(height: 30)
                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 7) {
                    Text("REVIEW GATE").missionFieldLabel()
                    Menu {
                        Button("No reviewer") { reviewerID = nil }
                        Divider()
                        ForEach(agents.filter { !workerIDs.contains($0.id) }) { agent in
                            Button(agent.title) { reviewerID = agent.id }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "checkmark.seal")
                            Text(reviewerID.flatMap { id in agents.first(where: { $0.id == id })?.title } ?? "No reviewer")
                            Spacer()
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .menuStyle(.borderlessButton)
                }
                .frame(width: 190)
            }

            if agents.isEmpty {
                Label("Add at least one Claude Code or Codex session before creating a mission.", systemImage: "person.crop.circle.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }

            HStack {
                Text("The mission stays drafted until you launch it from its node.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Create mission", action: create)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.36, green: 0.58, blue: 0.49))
                    .disabled(objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || workerIDs.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 620)
        .background(
            LinearGradient(
                colors: [WorkspaceVisualStyle.panelTint, Color(red: 0.025, green: 0.035, blue: 0.075)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            workerIDs = Set(agents.prefix(2).map(\.id))
            reviewerID = agents.dropFirst(2).first?.id
            objectiveFocused = true
        }
        .onChange(of: workerIDs) { _, selectedWorkers in
            if let reviewerID, selectedWorkers.contains(reviewerID) {
                self.reviewerID = nil
            }
        }
    }

    private func create() {
        guard store.createMission(title: title, objective: objective, workerIDs: Array(workerIDs), reviewerID: reviewerID) != nil else { return }
        isPresented = false
    }
}

private extension Text {
    func missionFieldLabel() -> some View {
        font(.system(size: 9, weight: .bold))
            .foregroundStyle(.secondary)
            .tracking(0.7)
    }
}
