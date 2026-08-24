import SwiftUI

struct WorkspaceNodeView: View {
    let node: WorkspaceNode
    let latestRun: WorkspaceRun?
    var recentRuns: [WorkspaceRun] = []
    let mission: WorkspaceMission?
    let terminalSession: TerminalSession?
    let workspaceTheme: WorkspaceTheme
    let isSelected: Bool
    let isReceivingPrompt: Bool
    let scale: Double
    let allowsManipulation: Bool
    let onSelect: () -> Void
    let onBeginManipulation: () -> Void
    let onMovePreview: (CGSize) -> Void
    let onMove: (CGPoint) -> Void
    let onResizePreview: (CGSize) -> Void
    let onResize: (CGSize) -> Void
    let onContentChange: (String) -> Void
    let onURLChange: (String) -> Void
    let onRefresh: () -> Void
    let onSendTask: (String) -> Bool
    let onOpenArtifact: (WorkspaceArtifact, UUID) -> Void
    let onReviewRun: (UUID) -> Void
    let onDraftChange: (String) -> Void
    let onAgentDisplayModeChange: (AgentDisplayMode) -> Void
    let onRename: (String) -> Void
    let onFocus: () -> Void
    let onCancel: () -> Void
    let onFinish: () -> Void
    var onReorder: () -> Void = {}
    let onShowGuardian: () -> Void
    let onStartMission: (UUID) -> Void
    let onCancelMission: (UUID) -> Void
    let onReviewMission: (UUID) -> Void
    let onVerifyMission: (UUID) -> Void
    let onOpenMissionWorker: (UUID) -> Void
    let missionWorkerName: (UUID) -> String
    let onMinimize: () -> Void
    let onClose: () -> Void
    let browserUsesFullDisplay: Bool
    let onBrowserPresentationChange: (Bool) -> Void
    let onRequestBrowserFullDisplay: () -> Void

    @State private var dragOrigin: CGPoint?
    @State private var resizeOrigin: CGSize?
    @State private var isRenaming = false
    @State private var nameDraft = ""
    @State private var isBrowserFullscreen = false
    @State private var isPointerInside = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !isBrowserFullscreen { titleBar }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.ultraThinMaterial)
        .background(nodeSurface)
        .clipShape(RoundedRectangle(cornerRadius: nodeCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: nodeCornerRadius, style: .continuous)
                .strokeBorder(
                    nodeBorder,
                    lineWidth: isSelected || isReceivingPrompt ? 1.6 : 1
                )
        }
        .overlay(alignment: .bottomTrailing) {
            if allowsManipulation, !isBrowserFullscreen, isSelected || isPointerInside { resizeHandle }
        }
        .shadow(color: nodeShadowColor, radius: isSelected ? 18 : 12, y: 8)
        .onHover { isPointerInside = $0 }
        .onChange(of: isBrowserFullscreen) { _, active in
            onBrowserPresentationChange(active)
        }
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(node.title), \(node.subtitle)")
    }

    private var titleBar: some View {
        HStack(spacing: 7) {
            Button(action: onShowGuardian) {
                Image(systemName: statusSymbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(statusColor)
                    .frame(width: 28, height: 28)
                    .background(statusColor.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(statusColor.opacity(0.20)))
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .accessibilityLabel("Open session health for \(node.title)")
            .accessibilityValue(node.resolvedRuntimeState.label)
            .help("Session health · \(node.resolvedRuntimeState.label)")
            if isRenaming {
                TextField("Session name", text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .focused($nameFocused)
                    .onSubmit(commitRename)
                    .onExitCommand { isRenaming = false }
                    .frame(minWidth: 90, maxWidth: 180)
            } else {
                Text(node.title)
                    .font(.system(size: 12, weight: .semibold))
                    .onTapGesture(count: 2, perform: beginRename)
                    .help("Double-click to rename")
            }
            Text(node.subtitle)
                .foregroundStyle(.tertiary)
                .font(.system(size: 10))
                .lineLimit(1)
            Spacer()
            if isReceivingPrompt {
                Label("Incoming", systemImage: "paperplane.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Incoming task for \(node.title)")
                    .help("Incoming task")
            }
            if node.kind == .agent, node.status == .working {
                WorkspaceIconButton(
                    symbol: "stop.fill",
                    label: "Cancel current task in \(node.title)",
                    size: 30,
                    action: onCancel
                )
            }
            if showsQuickActions {
                WorkspaceIconButton(
                    symbol: "arrow.up.left.and.arrow.down.right",
                    label: "Focus \(node.title)",
                    size: 28,
                    action: onFocus
                )
            }
            Menu {
                Button("Focus session", systemImage: "arrow.up.left.and.arrow.down.right", action: onFocus)
                if node.kind == .agent, node.status == .working {
                    Button("Cancel current task", systemImage: "stop.fill", role: .destructive, action: onCancel)
                }
                Divider()
                Button("Rename…", action: beginRename)
                Button("Minimize", action: onMinimize)
                Divider()
                Button("Close session", role: .destructive, action: onClose)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.025), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.045)))
            }
            .menuStyle(.borderlessButton)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Session options for \(node.title)")
            .help("Session options")
        }
        .padding(.leading, 7)
        .padding(.trailing, 5)
        .frame(height: 34)
        .background(titleBarSurface)
        .contentShape(Rectangle())
        .gesture(moveGesture, isEnabled: allowsManipulation)
        .help(sessionDetails)
    }

    private var showsQuickActions: Bool {
        isSelected || isPointerInside || node.status == .needsAttention
    }

    private var sessionDetails: String {
        [node.subtitle, node.purpose, node.terminalSummary]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " · ")
    }

    private var nodeCornerRadius: CGFloat {
        node.kind == .terminal ? 16 : 12
    }

    private var nodeSurface: some ShapeStyle {
        AnyShapeStyle(Color(red: 0.018, green: 0.032, blue: 0.055).opacity(0.76))
    }

    private var nodeBorder: LinearGradient {
        if isSelected || isReceivingPrompt {
            return LinearGradient(
                colors: [(providerAccent ?? WorkspaceVisualStyle.cyan).opacity(0.72), .white.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        if node.status == .needsAttention {
            return LinearGradient(
                colors: [statusColor.opacity(0.68), .white.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [.white.opacity(0.26), .white.opacity(0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var titleBarSurface: some ShapeStyle {
        AnyShapeStyle(Color.black.opacity(0.20))
    }

    private var nodeShadowColor: Color {
        isSelected ? (providerAccent ?? WorkspaceVisualStyle.cyan).opacity(0.16) : .black.opacity(0.38)
    }

    private var providerAccent: Color? {
        node.resolvedProvider?.workspaceAccent
    }

    @ViewBuilder
    private var content: some View {
        switch node.kind {
        case .browser:
            BrowserPane(
                node: node,
                isContainedFullscreen: $isBrowserFullscreen,
                usesFullDisplay: browserUsesFullDisplay,
                onNavigate: onURLChange,
                onRefresh: onRefresh,
                onRequestFullDisplay: onRequestBrowserFullDisplay
            )
        case .preview:
            PreviewPane(
                node: node,
                onNavigate: onURLChange,
                onRefresh: onRefresh
            )
        case .music:
            MusicPane(theme: workspaceTheme, urlString: node.url, onChoose: onURLChange)
        case .liveChat:
            LiveChatPane(node: node, onNavigate: onURLChange, onRefresh: onRefresh)
        case .note:
            TextEditor(text: Binding(get: { node.content }, set: onContentChange))
                .scrollContentBackground(.hidden)
                .font(.system(size: 19, design: .rounded))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        case .agent:
            AgentPane(
                node: node,
                run: latestRun,
                priorRuns: recentRuns,
                onSend: onSendTask,
                onOpenArtifact: onOpenArtifact,
                onReviewRun: onReviewRun,
                onDraftChange: onDraftChange,
                onDisplayModeChange: onAgentDisplayModeChange
            )
        case .terminal:
            if let terminalSession {
                TerminalPane(
                    session: terminalSession,
                    workingFolderLabel: node.workingFolderMode == .unattached ? "No folder" : nil
                )
            } else {
                Text("Terminal unavailable")
                    .foregroundStyle(.secondary)
            }
        case .mission:
            if let mission {
                MissionPane(
                    mission: mission,
                    nodeTitle: missionWorkerName,
                    onStart: { onStartMission(mission.id) },
                    onCancel: { onCancelMission(mission.id) },
                    onReview: { onReviewMission(mission.id) },
                    onVerify: { onVerifyMission(mission.id) },
                    onOpenWorker: onOpenMissionWorker
                )
            } else {
                ContentUnavailableView("Mission unavailable", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.down.right.and.arrow.up.left")
            .font(.system(size: node.kind == .browser ? 11 : 9, weight: .bold))
            .foregroundStyle(node.kind == .browser ? WorkspaceVisualStyle.browser.opacity(0.92) : .white.opacity(0.42))
            .frame(width: node.kind == .browser ? 38 : 28, height: node.kind == .browser ? 38 : 28)
            .background(
                node.kind == .browser ? WorkspaceVisualStyle.browser.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                if node.kind == .browser {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(WorkspaceVisualStyle.browser.opacity(0.24))
                }
            }
            .contentShape(Rectangle())
            .help(node.kind == .browser ? "Drag to resize this browser" : "Drag to resize")
            .gesture(
                DragGesture(minimumDistance: 3, coordinateSpace: .global)
                    .onChanged { value in
                        if resizeOrigin == nil { resizeOrigin = node.size.cgSize; onBeginManipulation() }
                        guard let origin = resizeOrigin else { return }
                        let translation = WorkspaceDrag.worldTranslation(value.translation, scale: scale)
                        let minimum = node.kind == .note
                            ? CGSize(width: 220, height: 150)
                            : CGSize(width: 320, height: 220)
                        onResizePreview(
                            WorkspaceMotion.constrainedSize(
                                CGSize(width: origin.width + translation.width, height: origin.height + translation.height),
                                minimum: minimum
                            )
                        )
                    }
                    .onEnded { value in
                        guard let origin = resizeOrigin else { return }
                        let translation = WorkspaceDrag.worldTranslation(value.translation, scale: scale)
                        let minimum = node.kind == .note
                            ? CGSize(width: 220, height: 150)
                            : CGSize(width: 320, height: 220)
                        let finalSize = WorkspaceMotion.constrainedSize(
                            CGSize(width: origin.width + translation.width, height: origin.height + translation.height),
                            minimum: minimum
                        )
                        resizeOrigin = nil
                        onResize(finalSize)
                        onFinish()
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
            )
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if dragOrigin == nil { dragOrigin = node.position.cgPoint; onBeginManipulation() }
                let translation = WorkspaceDrag.worldTranslation(value.translation, scale: scale)
                onMovePreview(translation)
            }
            .onEnded { value in
                guard let origin = dragOrigin else { return }
                let translation = WorkspaceDrag.worldTranslation(value.translation, scale: scale)
                dragOrigin = nil
                onMove(CGPoint(x: origin.x + translation.width, y: origin.y + translation.height))
                onReorder()
                onFinish()
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
    }

    private func beginRename() {
        nameDraft = node.title
        isRenaming = true
        nameFocused = true
    }

    private func commitRename() {
        let cleanName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        onRename(cleanName)
        isRenaming = false
    }

    private var statusColor: Color {
        switch node.status {
        case .idle: .white.opacity(0.35)
        case .working: Color(red: 0.92, green: 0.78, blue: 0.36)
        case .complete: Color(red: 0.48, green: 0.86, blue: 0.56)
        case .needsAttention: Color(red: 0.97, green: 0.42, blue: 0.39)
        }
    }

    private var statusSymbol: String {
        switch node.status {
        case .idle: "pause.fill"
        case .working: "bolt.fill"
        case .complete: "checkmark"
        case .needsAttention: "exclamationmark"
        }
    }
}
