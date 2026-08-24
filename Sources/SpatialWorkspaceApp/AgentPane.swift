import SwiftUI

struct AgentPane: View {
    let node: WorkspaceNode
    let run: WorkspaceRun?
    let priorRuns: [WorkspaceRun]
    let onSend: (String) -> Bool
    let onOpenArtifact: (WorkspaceArtifact, UUID) -> Void
    let onReviewRun: (UUID) -> Void
    let onDraftChange: (String) -> Void
    let onDisplayModeChange: (AgentDisplayMode) -> Void

    @State private var taskText = ""
    @FocusState private var taskFocused: Bool
    @State private var draftSyncTask: Task<Void, Never>?

    init(
        node: WorkspaceNode,
        run: WorkspaceRun?,
        priorRuns: [WorkspaceRun] = [],
        onSend: @escaping (String) -> Bool,
        onOpenArtifact: @escaping (WorkspaceArtifact, UUID) -> Void,
        onReviewRun: @escaping (UUID) -> Void,
        onDraftChange: @escaping (String) -> Void,
        onDisplayModeChange: @escaping (AgentDisplayMode) -> Void
    ) {
        self.node = node
        self.run = run
        self.priorRuns = priorRuns
        self.onSend = onSend
        self.onOpenArtifact = onOpenArtifact
        self.onReviewRun = onReviewRun
        self.onDraftChange = onDraftChange
        self.onDisplayModeChange = onDisplayModeChange
        _taskText = State(initialValue: node.draft ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            if node.isCodingAgent {
                displayModeBar
                Divider().opacity(0.3)
            }

            if node.isCodingAgent, node.resolvedAgentDisplayMode == .terminal {
                terminalOutput
            } else {
                briefOutput
            }

            Divider().opacity(0.35)
            TaskComposer(
                text: Binding(
                    get: { taskText },
                    set: { scheduleDraftSync($0) }
                ),
                prompt: promptLabel,
                targetLabel: node.title,
                statusMessage: composerStatusMessage,
                intentPreview: nil,
                disabled: false,
                focus: $taskFocused,
                onSubmit: onSend
            )
        }
        .background(Color.black.opacity(0.18))
        .onChange(of: node.draft) { _, draft in
            // External draft updates (delegation, restore) only; while the field is
            // focused the local text is authoritative or the echo displaces the cursor.
            if !taskFocused, taskText != (draft ?? "") { taskText = draft ?? "" }
        }
        .onChange(of: taskFocused) { _, focused in
            if !focused { flushDraftSync() }
        }
    }

    private func scheduleDraftSync(_ text: String) {
        taskText = text
        draftSyncTask?.cancel()
        draftSyncTask = Task { @MainActor [text] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            onDraftChange(text)
        }
    }

    private func flushDraftSync() {
        draftSyncTask?.cancel()
        draftSyncTask = nil
        onDraftChange(taskText)
    }

    private var briefOutput: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !priorPrompts.isEmpty {
                        priorPromptsStrip
                    }
                    if let run {
                        requestHeader(run)
                    }
                    AgentBriefText(content: briefContent, accent: agentAccent)
                    if let run, run.state.isTerminal, node.resolvedProvider != .jarvis {
                        RunReceipt(
                            run: run,
                            onOpenArtifact: { onOpenArtifact($0, run.id) },
                            onReview: { onReviewRun(run.id) }
                        )
                    }
                    Color.clear.frame(height: 1).id("agent-output-end")
                }
                .padding(15)
            }
            .onChange(of: node.content) { _, _ in
                proxy.scrollTo("agent-output-end", anchor: .bottom)
            }
        }
    }

    private var terminalOutput: some View {
        ZStack {
            LinearGradient(
                colors: [.black.opacity(0.56), agentAccent.opacity(0.055), .black.opacity(0.46)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ScrollViewReader { proxy in
                ScrollView {
                    if !priorPrompts.isEmpty {
                        priorPromptsStrip
                            .padding(.horizontal, 15)
                            .padding(.top, 13)
                    }
                    Text(TerminalTypography.attributed(terminalTranscript, size: 11.5))
                        .lineSpacing(2.4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                    Color.clear.frame(height: 1).id("agent-terminal-end")
                }
                .scrollIndicators(.visible)
                .onChange(of: node.activityLog) { _, _ in
                    proxy.scrollTo("agent-terminal-end", anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo("agent-terminal-end", anchor: .bottom)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Read-only \(node.resolvedProvider?.label ?? "agent") execution terminal")
    }

    private var displayModeBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(node.status == .working ? agentAccent : .white.opacity(0.28))
                    .frame(width: 5, height: 5)
                    .shadow(color: node.status == .working ? agentAccent.opacity(0.75) : .clear, radius: 5)
                Text(node.status == .working ? "LIVE SESSION" : "SESSION VIEW")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.55)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 2) {
                ForEach(AgentDisplayMode.allCases) { mode in
                    Button {
                        onDisplayModeChange(mode)
                    } label: {
                        Label(mode.label, systemImage: mode.symbol)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 8)
                            .frame(height: 23)
                            .foregroundStyle(node.resolvedAgentDisplayMode == mode ? agentAccent : .secondary)
                            .background(
                                node.resolvedAgentDisplayMode == mode ? agentAccent.opacity(0.12) : .clear,
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                    .buttonStyle(WorkspacePressButtonStyle())
                    .accessibilityAddTraits(node.resolvedAgentDisplayMode == mode ? .isSelected : [])
                    .help(mode == .brief ? "Show the concise agent response and proof of work" : "Show commands, tool calls, edits, and output")
                }
            }
            .padding(2)
            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.07)))

            if node.resolvedAgentDisplayMode == .terminal {
                Text("READ ONLY")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(.black.opacity(0.14))
    }

    private var terminalTranscript: String {
        guard let activityLog = node.activityLog, !activityLog.isEmpty else {
            return "No execution activity yet.\n\nSend a task below; commands, tool calls, file edits, and output will appear here as the agent works."
        }
        return activityLog
    }

    private var agentAccent: Color {
        node.resolvedProvider?.workspaceAccent ?? WorkspaceVisualStyle.cyan
    }

    /// The agent tends to echo the prompt verbatim at the top of its reply, but
    /// the "Current Request" header already shows it — so drop the leading copy.
    private var briefContent: String {
        guard let request = run?.request else { return node.content }
        return AgentPane.strippingEchoedPrompt(from: node.content, prompt: request)
    }

    static func strippingEchoedPrompt(from content: String, prompt: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return content }
        let whitespace: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
        let leading = content.drop(while: whitespace)
        guard leading.hasPrefix(trimmedPrompt) else { return content }
        return String(leading.dropFirst(trimmedPrompt.count).drop(while: whitespace))
    }

    private var promptLabel: String {
        if node.resolvedProvider == .jarvis {
            return node.status == .working ? "Jarvis is thinking — type to queue…" : "Ask Jarvis…"
        }
        return node.status == .working
            ? "\(node.title) is working — type to queue the next task…"
            : "Give \(node.title) a task…"
    }

    private var composerStatusMessage: String? {
        guard node.status == .working else { return nil }
        if let queued = node.queuedPrompt, !queued.isEmpty {
            return "Queued: \(queued.prefix(60)) — sends when this run finishes"
        }
        return "Working on the current run"
    }

    /// The last few prompts sent before the current run, so context survives
    /// tab switches. Excludes the current run and caps at three.
    private var priorPrompts: [WorkspaceRun] {
        Array(priorRuns.filter { $0.id != run?.id }.suffix(3))
    }

    private var priorPromptsStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("EARLIER PROMPTS")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            ForEach(priorPrompts) { prior in
                Button { onReviewRun(prior.id) } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(prior.startedAt, style: .time)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 62, alignment: .leading)
                        Text(prior.request)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Earlier prompt: \(prior.request)")
                .help("Review this earlier run")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func requestHeader(_ run: WorkspaceRun) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("CURRENT REQUEST")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(run.startedAt, style: .time)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            Text(run.request)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(5)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct RunReceipt: View {
    let run: WorkspaceRun
    let onOpenArtifact: (WorkspaceArtifact) -> Void
    let onReview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: stateSymbol)
                    .foregroundStyle(stateColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateTitle)
                        .font(.system(size: 12, weight: .semibold))
                    if let summary = run.summary {
                        Text(summary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button("Review work", action: onReview)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(run.state == .failed || run.state == .cancelled)
            }

            ForEach(run.evidence) { evidence in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: evidence.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(evidence.passed ? Color.green.opacity(0.85) : Color.orange.opacity(0.9))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(evidence.label).font(.system(size: 10, weight: .semibold))
                        Text(evidence.detail).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }

            if !run.artifacts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(run.artifacts.prefix(4)) { artifact in
                        Button { onOpenArtifact(artifact) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: artifact.kind.symbol)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(artifact.title)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Text(artifact.kind.label)
                                        .font(.system(size: 9))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(artifact.kind.supportsEmbeddedPreview ? "Open preview" : "Open")
                                    .font(.system(size: 9, weight: .semibold))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 38)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Open \(artifact.title), \(artifact.kind.label)")
                    }
                }
            } else if run.state == .needsEvidence {
                Label("No verifiable artifact was found. Ask the agent for a file, URL, or test result.", systemImage: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(stateColor.opacity(0.26)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Run receipt, \(stateTitle)")
    }

    private var stateTitle: String {
        switch run.state {
        case .readyToReview: "Ready to review"
        case .verified: "Verified"
        case .needsEvidence: "Finished without proof"
        case .failed: "Run failed"
        case .cancelled: "Run cancelled"
        case .accepted: "Accepted"
        case .working: "Working"
        }
    }

    private var stateSymbol: String {
        switch run.state {
        case .readyToReview: "doc.badge.ellipsis"
        case .verified: "checkmark.seal.fill"
        case .needsEvidence: "questionmark.diamond.fill"
        case .failed, .cancelled: "exclamationmark.triangle.fill"
        case .accepted: "paperplane.fill"
        case .working: "hourglass"
        }
    }

    private var stateColor: Color {
        switch run.state {
        case .readyToReview: Color(red: 0.80, green: 0.86, blue: 0.63)
        case .verified: Color.green.opacity(0.85)
        case .needsEvidence: Color.orange.opacity(0.9)
        case .failed, .cancelled: Color.red.opacity(0.85)
        case .accepted, .working: Color.yellow.opacity(0.85)
        }
    }
}
