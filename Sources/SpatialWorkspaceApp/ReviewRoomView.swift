import SwiftUI

struct ReviewRoomView: View {
    @ObservedObject var store: WorkspaceStore
    let runID: UUID

    @State private var selectedArtifactID: UUID?
    @State private var previewRevision = 0
    @State private var reviewDetail = ""

    private var run: WorkspaceRun? { store.runRecord(withID: runID) }
    private var sourceNode: WorkspaceNode? {
        guard let run else { return nil }
        return store.activeWorkspace.nodes.first(where: { $0.id == run.sessionNodeID })
    }
    private var selectedArtifact: WorkspaceArtifact? {
        guard let run else { return nil }
        return run.artifacts.first(where: { $0.id == selectedArtifactID }) ?? run.artifacts.first
    }
    private var reviewerCandidates: [WorkspaceNode] {
        guard let sourceNode else { return [] }
        return store.activeWorkspace.nodes.filter { $0.isCodingAgent && $0.id != sourceNode.id }
    }

    var body: some View {
        Group {
            if let run {
                VStack(spacing: 0) {
                    header(run)
                    Divider().opacity(0.32)
                    HStack(spacing: 0) {
                        requestPanel(run)
                            .frame(width: 270)
                        Divider().opacity(0.32)
                        previewPanel(run)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider().opacity(0.32)
                        evidencePanel(run)
                            .frame(width: 340)
                    }
                }
                .background(.ultraThinMaterial)
                .background(Color(red: 0.015, green: 0.032, blue: 0.065).opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom)))
                .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
                .padding(.horizontal, 34)
                .padding(.top, 54)
                .padding(.bottom, 34)
                .onAppear {
                    selectedArtifactID = run.artifacts.first?.id
                    updateReviewDetail(run)
                }
                .onChange(of: selectedArtifactID) { _, _ in updateReviewDetail(run) }
            } else {
                ContentUnavailableView("Review unavailable", systemImage: "doc.badge.ellipsis")
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.985)))
    }

    private func header(_ run: WorkspaceRun) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(reviewColor(run).opacity(0.14))
                Image(systemName: "rectangle.3.group.bubble.left.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(reviewColor(run))
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review Room")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("\(sourceNode?.title ?? "Agent") · \(run.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if run.state == .readyToReview || run.state == .needsEvidence {
                Button("Accept work") { store.verifyRun(run.id) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.36, green: 0.58, blue: 0.49))
            }
            Button("Ask for revision") { store.prepareRevision(for: run.id) }
                .buttonStyle(.bordered)
                .disabled(sourceNode == nil)
            if reviewerCandidates.isEmpty {
                Button("Send to reviewer") {}
                    .buttonStyle(.bordered)
                    .disabled(true)
            } else {
                Menu("Send to reviewer") {
                    ForEach(reviewerCandidates) { reviewer in
                        Button(reviewer.title) {
                            if store.sendRunForReview(run.id, to: reviewer.id) {
                                store.endReview()
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Button { store.endReview() } label: {
                Image(systemName: "xmark")
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.05), in: Circle())
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .accessibilityLabel("Close Review Room")
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }

    private func requestPanel(_ run: WorkspaceRun) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                panelTitle("ORIGINAL REQUEST")
                Text(run.request)
                    .font(.system(size: 12, weight: .medium))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let summary = run.summary {
                    Divider().opacity(0.28)
                    panelTitle("AGENT SUMMARY")
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                let includedMemory = store.includedMemory(for: run)
                if !includedMemory.isEmpty {
                    Divider().opacity(0.28)
                    panelTitle("WORKSPACE MEMORY INCLUDED")
                    ForEach(includedMemory) { entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(entry.title, systemImage: entry.kind.symbol)
                                .font(.system(size: 10, weight: .semibold))
                            Text(entry.detail)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(4)
                            Text("Source: \(entry.sourceLabel)")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Divider().opacity(0.28)
                panelTitle("RUN")
                fact("State", run.state.rawValue)
                fact("Authority", (run.authorityProfile ?? sourceNode?.resolvedAuthorityProfile ?? AgentCapabilitySettings.defaultProfile).label)
                if run.approvalID != nil { fact("Approval", "Approved once from the workspace inbox") }
                fact("Started", run.startedAt.formatted(date: .omitted, time: .standard))
                if let completed = run.completedAt { fact("Finished", completed.formatted(date: .omitted, time: .standard)) }
                fact("Folder", run.workingDirectory)
            }
            .padding(14)
        }
        .background(Color.black.opacity(0.14))
    }

    @ViewBuilder
    private func previewPanel(_ run: WorkspaceRun) -> some View {
        if let artifact = selectedArtifact {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: artifact.kind.symbol)
                    Text(artifact.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Text(artifact.kind.label).font(.system(size: 9)).foregroundStyle(.secondary)
                    Button { previewRevision += 1 } label: { Image(systemName: "arrow.clockwise").frame(width: 24, height: 24) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Refresh review preview")
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color.black.opacity(0.17))
                if let url = ReviewResolver.previewURL(for: artifact, rootPath: run.workingDirectory) {
                    WebPreview(urlString: url, revision: previewRevision)
                } else {
                    detailText
                }
            }
        } else {
            ContentUnavailableView(
                "No previewable artifact",
                systemImage: "magnifyingglass",
                description: Text("The evidence panel still shows what the process reported.")
            )
        }
    }

    private func evidencePanel(_ run: WorkspaceRun) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                panelTitle("CHECKS & EVIDENCE")
                ForEach(run.evidence) { evidence in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: evidence.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .foregroundStyle(evidence.passed ? Color.green : Color.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(evidence.label).font(.system(size: 10, weight: .semibold))
                            Text(evidence.detail).font(.system(size: 9)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }

                Divider().opacity(0.28)
                panelTitle("ARTIFACTS & CHANGES")
                if run.artifacts.isEmpty {
                    Label("No verifiable artifact was captured", systemImage: "questionmark.diamond")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                ForEach(run.artifacts) { artifact in
                    Button { selectedArtifactID = artifact.id } label: {
                        HStack(spacing: 8) {
                            Image(systemName: artifact.kind.symbol).frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(artifact.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                Text(artifact.location).font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer()
                            if selectedArtifactID == artifact.id || (selectedArtifactID == nil && run.artifacts.first?.id == artifact.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.78, green: 0.90, blue: 0.67))
                            }
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 42)
                        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                if selectedArtifact != nil {
                    Divider().opacity(0.28)
                    panelTitle("DIFF OR FILE DETAIL")
                    Text(reviewDetail)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .textSelection(.enabled)
                        .lineLimit(28)
                }
            }
            .padding(13)
        }
        .background(Color.black.opacity(0.14))
    }

    private var detailText: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(reviewDetail)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .textSelection(.enabled)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color.black.opacity(0.25))
    }

    private func updateReviewDetail(_ run: WorkspaceRun) {
        guard let artifact = run.artifacts.first(where: { $0.id == selectedArtifactID }) ?? run.artifacts.first else {
            reviewDetail = "No artifact detail is available."
            return
        }
        reviewDetail = ReviewResolver.detail(for: artifact, rootPath: run.workingDirectory)
    }

    private func panelTitle(_ value: String) -> some View {
        Text(value).font(.system(size: 8, weight: .bold)).tracking(0.7).foregroundStyle(.secondary)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
            Text(value).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }

    private func reviewColor(_ run: WorkspaceRun) -> Color {
        switch run.state {
        case .verified: .green
        case .readyToReview: Color(red: 0.78, green: 0.90, blue: 0.67)
        case .needsEvidence: .orange
        case .failed, .cancelled: .red
        case .accepted, .working: .yellow
        }
    }
}
