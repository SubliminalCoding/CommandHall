import SwiftUI

enum WorkspaceChromeLayout {
    static let minimizedDockFixedHeight: CGFloat = 116
    static let minimizedDockSessionSlotHeight: CGFloat = 46
    static let toolRailHeight: CGFloat = 267
    static let leftRailTopMargin: CGFloat = 58
    static let leftRailSectionSpacing: CGFloat = 20
    static let focusedNodeHorizontalMargin: CGFloat = 64
    static let focusedNodeTopMargin: CGFloat = 72
    static let focusedNodeBottomMargin: CGFloat = 72
    static let sessionRailEdgeMargin: CGFloat = 16
    static let focusedNodeRailSpacing: CGFloat = 20

    struct LeftRailPlacement: Equatable {
        var dockHeight: CGFloat
        var dockCenterY: CGFloat?
        var toolCenterY: CGFloat
    }

    static func minimizedDockHeight(
        nodeCount: Int,
        viewportHeight: CGFloat,
        maximumHeight: CGFloat? = nil
    ) -> CGFloat {
        // Fixed chrome is 32 pt header + two dividers + 30 pt footer + four
        // eight-point gaps + 20 pt outer padding. Each scroll slot is a 38 pt
        // card, eight-point spacing, and the first/last four-point insets.
        let contentHeight = CGFloat(nodeCount) * minimizedDockSessionSlotHeight
            + minimizedDockFixedHeight
        let minimumHeight = minimizedDockFixedHeight + minimizedDockSessionSlotHeight
        let availableHeight = maximumHeight ?? (viewportHeight - 210)
        return min(max(minimumHeight, contentHeight), max(minimumHeight, availableHeight))
    }

    static func leftRailPlacement(
        nodeCount: Int,
        viewportHeight: CGFloat,
        railHeight: CGFloat = toolRailHeight
    ) -> LeftRailPlacement {
        guard nodeCount > 0 else {
            return LeftRailPlacement(dockHeight: 0, dockCenterY: nil, toolCenterY: viewportHeight / 2)
        }

        let centeredSpaceAboveTools = viewportHeight / 2
            - railHeight / 2
            - leftRailSectionSpacing
            - leftRailTopMargin
        let dockHeight = minimizedDockHeight(
            nodeCount: nodeCount,
            viewportHeight: viewportHeight,
            maximumHeight: centeredSpaceAboveTools
        )
        let preferredDockTop = viewportHeight / 2
            - railHeight / 2
            - leftRailSectionSpacing
            - dockHeight
        let dockTop = max(leftRailTopMargin, preferredDockTop)
        return LeftRailPlacement(
            dockHeight: dockHeight,
            dockCenterY: dockTop + dockHeight / 2,
            toolCenterY: dockTop + dockHeight + leftRailSectionSpacing + railHeight / 2
        )
    }

    static func sessionRailWidth(viewportWidth: CGFloat) -> CGFloat {
        viewportWidth < 1_120 ? 238 : 268
    }

    static func focusedNodeFrame(
        viewportSize: CGSize,
        sessionRailVisible: Bool
    ) -> CGRect {
        let trailingMargin: CGFloat
        if sessionRailVisible {
            trailingMargin = sessionRailEdgeMargin
                + sessionRailWidth(viewportWidth: viewportSize.width)
                + focusedNodeRailSpacing
        } else {
            trailingMargin = focusedNodeHorizontalMargin
        }

        return CGRect(
            x: focusedNodeHorizontalMargin,
            y: focusedNodeTopMargin,
            width: max(1, viewportSize.width - focusedNodeHorizontalMargin - trailingMargin),
            height: max(1, viewportSize.height - focusedNodeTopMargin - focusedNodeBottomMargin)
        )
    }
}

/// Reports the tool rail's real rendered height so the left-rail placement can
/// space the minimized dock and tool rail apart correctly regardless of how many
/// icons the rail carries.
private struct ToolRailHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct WorkspaceRootView: View {
    struct Configuration {
        var startsExternalServices = true
        var animatesBackground = true
        var initialPage = AppPage.workspace
        var showsStageRail = false

        static let live = Configuration()

        static func visualTest(
            page: AppPage = .workspace,
            showsStageRail: Bool = false
        ) -> Configuration {
            Configuration(
                startsExternalServices: false,
                animatesBackground: false,
                initialPage: page,
                showsStageRail: showsStageRail
            )
        }
    }

    @ObservedObject var store: WorkspaceStore
    @ObservedObject var signalDeckController: SignalDeckController
    private let configuration: Configuration
    @StateObject private var speech = SpeechController()
    @StateObject private var stageService = StageServiceController()
    @StateObject private var vtuberService = VTuberServiceController()
    @StateObject private var obsController = ClawStudioOBSController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var commandFocused: Bool
    @Namespace private var workspaceMotionNamespace
    @State private var panOrigin: CGPoint?
    @State private var cameraBeforeMagnification: CameraTransform?
    @State private var transientCamera: CameraTransform?
    @State private var nodeDragPreview: WorkspaceNodeDragPreview?
    @State private var nodeResizePreview: WorkspaceNodeResizePreview?
    @State private var marqueeStart: CGPoint?
    @State private var marqueeRect: CGRect?
    @State private var showsSessionLauncher = false
    @State private var launcherProvider: SessionProvider = .claude
    @State private var showsWorkspaceSwitcher = false
    @State private var showsBackgroundPicker = false
    @State private var promptFlight: PromptFlight?
    @State private var promptFlightProgress = 0.0
    @State private var receivingNodeID: UUID?
    @State private var flightCleanupTask: Task<Void, Never>?
    @State private var viewportReflowTask: Task<Void, Never>?
    @State private var showsStageRail = false
    @State private var showsMissionLauncher = false
    @State private var showsGuardian = false
    @State private var showsVoiceSettings = false
    @State private var showsAgentAccessSettings = false
    @State private var showsWorkspaceLibrary = false
    @State private var showsApprovalInbox = false
    @State private var showsReleaseDiagnostics = false
    @State private var activePage = AppPage.workspace
    @State private var vtuberContainedFullscreen = false
    @State private var vtuberExitFullscreenRequest = 0
    @State private var guardianNodeID: UUID?
    @State private var featuredBrowserID: UUID?
    @State private var fullDisplayBrowserID: UUID?
    @State private var toolRailMeasuredHeight: CGFloat = WorkspaceChromeLayout.toolRailHeight

    init(
        store: WorkspaceStore,
        signalDeckController: SignalDeckController,
        configuration: Configuration = .live
    ) {
        self.store = store
        self.signalDeckController = signalDeckController
        self.configuration = configuration
        _showsStageRail = State(initialValue: configuration.showsStageRail)
        _activePage = State(initialValue: configuration.initialPage)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                workspacePage(in: proxy.size)
                    .opacity(activePage == .workspace ? 1 : 0)
                    .allowsHitTesting(activePage == .workspace)

                StagePage(controller: stageService, store: store, isActive: activePage == .stage)
                    .opacity(activePage == .stage ? 1 : 0)
                    .allowsHitTesting(activePage == .stage)
                    .accessibilityHidden(activePage != .stage)

                if activePage == .jarvis {
                    JarvisExperiencePanel(
                        store: store,
                        speech: speech,
                        isPresented: jarvisPagePresented
                    )
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(100_000)
                }

                if activePage == .vtuber {
                    VTuberControlsPage(
                        controller: vtuberService,
                        theme: WorkspaceTheme.resolve(store.activeWorkspace.theme),
                        isContainedFullscreen: $vtuberContainedFullscreen,
                        exitFullscreenRequest: vtuberExitFullscreenRequest
                    )
                    .transition(.opacity)
                    .zIndex(100_000)
                }

                if activePage == .obs {
                    OBSControlPage(controller: obsController, store: store)
                        .transition(.opacity)
                        .zIndex(100_000)
                }

                if activePage == .signalDeck {
                    SignalDeckPage(
                        controller: signalDeckController,
                        theme: WorkspaceTheme.resolve(store.activeWorkspace.theme)
                    )
                        .transition(.opacity)
                        .zIndex(100_000)
                }

                if fullDisplayBrowserID == nil {
                    AppPageNavigation(
                        selection: $activePage,
                        signalDeckState: signalDeckController.connectionState,
                        signalDeckIsAuthoritative: signalDeckController.isAuthoritative,
                        signalDeckAudioGraphApplied: signalDeckController.audioGraphApplied,
                        compact: proxy.size.width < 1_180
                    )
                        .fixedSize()
                        .position(x: proxy.size.width < 1_180 ? 122 : 250, y: 31)
                        .zIndex(120_000)
                }

                if fullDisplayBrowserID == nil, let stream = obsController.stream, stream.active {
                    LiveBroadcastBadge(
                        timecode: stream.timecode,
                        authoritative: obsController.snapshotIsAuthoritative
                    )
                        .fixedSize()
                        .position(
                            x: proxy.size.width - (obsController.snapshotIsAuthoritative ? 72 : 108),
                            y: 31
                        )
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .zIndex(125_000)
                }
            }
            .clipped()
            .background(Color(red: 0.01, green: 0.02, blue: 0.05))
            .onAppear {
                NSApp.keyWindow?.titlebarAppearsTransparent = true
                updateViewport(proxy.size, reflow: true)
                guard configuration.startsExternalServices else { return }
                stageService.start()
                obsController.start()
                synchronizeSignalDeckStreamState()
            }
            .onChange(of: activePage) { previousPage, page in
                if page == .stage {
                    stageService.start()
                    requestStageAudioProfile(
                        "stage-on-air",
                        reason: "The Stage page became the active broadcast surface."
                    )
                } else if previousPage == .stage {
                    requestStageAudioProfile(
                        "stage-muted",
                        reason: "The Stage page left the active broadcast surface."
                    )
                }
            }
            .onChange(of: obsController.state) { _, _ in synchronizeSignalDeckStreamState() }
            .onChange(of: obsController.stream) { _, _ in synchronizeSignalDeckStreamState() }
            .onChange(of: proxy.size) { _, size in updateViewport(size, reflow: true) }
            .onChange(of: store.promptDispatch) { _, dispatch in
                guard let dispatch else { return }
                animate(dispatch, in: proxy.size)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
                fullDisplayBrowserID = nil
            }
            .task {
                guard configuration.startsExternalServices else { return }
                while !Task.isCancelled {
                    stageService.publishLocalSessions(workspace: store.activeWorkspace)
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
            .onDeleteCommand {
                guard activePage == .workspace else { return }
                store.removeSelectedNodes()
            }
            .onExitCommand {
                if activePage == .vtuber, vtuberContainedFullscreen {
                    vtuberExitFullscreenRequest &+= 1
                } else if activePage != .workspace {
                    activePage = .workspace
                } else if store.reviewingRunID != nil {
                    store.endReview()
                } else if store.focusedNodeID != nil {
                    store.exitFocus()
                } else {
                    store.select(nil)
                }
            }
            .onMoveCommand { direction in
                guard activePage == .workspace else { return }
                switch direction {
                case .left: store.nudgeSelection(dx: -8, dy: 0)
                case .right: store.nudgeSelection(dx: 8, dy: 0)
                case .up: store.nudgeSelection(dx: 0, dy: -8)
                case .down: store.nudgeSelection(dx: 0, dy: 8)
                @unknown default: break
                }
            }
        }
        .keyboardShortcutFocus($commandFocused, key: "k")
        .appPageShortcuts($activePage)
        .sheet(isPresented: $showsSessionLauncher) {
            SessionLauncherView(store: store, isPresented: $showsSessionLauncher, initialProvider: launcherProvider)
        }
        .sheet(isPresented: $showsMissionLauncher) {
            MissionLauncherView(store: store, isPresented: $showsMissionLauncher)
        }
        .sheet(isPresented: $showsGuardian) {
            if let guardianNodeID {
                SessionGuardianView(store: store, nodeID: guardianNodeID, isPresented: $showsGuardian)
            }
        }
        .sheet(isPresented: $showsVoiceSettings) {
            VoiceTranscriptionSettingsView(isPresented: $showsVoiceSettings)
        }
        .sheet(isPresented: $showsAgentAccessSettings) {
            AgentAccessSettingsView(store: store, isPresented: $showsAgentAccessSettings)
        }
        .sheet(isPresented: $showsWorkspaceLibrary) {
            WorkspaceMemoryTimelineView(store: store, isPresented: $showsWorkspaceLibrary)
        }
        .sheet(isPresented: $showsApprovalInbox) {
            ApprovalInboxView(store: store, isPresented: $showsApprovalInbox)
        }
        .sheet(isPresented: $showsReleaseDiagnostics) {
            ReleaseDiagnosticsView(isPresented: $showsReleaseDiagnostics)
        }
        .onChange(of: store.state.activeWorkspaceID) { _, _ in
            flightCleanupTask?.cancel()
            promptFlight = nil
            receivingNodeID = nil
            featuredBrowserID = nil
            fullDisplayBrowserID = nil
            transientCamera = nil
            nodeDragPreview = nil
            nodeResizePreview = nil
        }
        .onChange(of: speech.autoStopRequested) { _, shouldStop in
            guard shouldStop, speech.isRecording, activePage != .jarvis else { return }
            Task { await finishVoiceCommand(execute: true) }
        }
        .onDisappear {
            flightCleanupTask?.cancel()
            viewportReflowTask?.cancel()
            speech.cancel()
            stageService.stop()
            vtuberService.stop()
            obsController.stop()
        }
    }

    private func synchronizeSignalDeckStreamState() {
        guard obsController.connected, let stream = obsController.stream else {
            signalDeckController.updateStreamState(.unknown)
            return
        }
        signalDeckController.updateStreamState(stream.active ? .live : .offline)
    }

    private func requestStageAudioProfile(_ profileID: String, reason: String) {
        Task { @MainActor in
            await signalDeckController.requestLifecycleProfile(
                profileID,
                requestedBy: "workspace-stage-lifecycle",
                reason: reason
            )
        }
    }

    @ViewBuilder
    private func workspacePage(in size: CGSize) -> some View {
        let effectiveCamera = transientCamera ?? store.activeWorkspace.camera
        let parallax = WorkspaceMotion.parallaxOffset(for: effectiveCamera.offset.cgPoint)
        ZStack(alignment: .topLeading) {
            background
                .offset(x: parallax.width, y: parallax.height)
            // The surface must occupy a single, unconditional slot. Placing it
            // inside a branch of an if/else gives that branch its own structural
            // identity, so entering focus or the Review Room tears the whole
            // surface down and rebuilds it -- restarting every persistent pane
            // beneath it (music playback, running terminals). Drive visibility
            // with modifiers instead, so identity and @StateObject survive both.
            surface(in: size)
                .opacity(surfaceIsHidden ? 0 : 1)
                .allowsHitTesting(!surfaceIsHidden)
                // Hiding the surface with opacity keeps its panes mounted (so
                // playback and terminals survive), but an opacity-0 text field
                // still sits in the key/first-responder chain. While a node is
                // focused it is drawn a second time in `focusedNode`, so two
                // identical agent composers exist at once; without this, Return
                // can route to the hidden copy — which just select-alls its text
                // instead of sending. Disabling drops the hidden copy out of the
                // responder chain so the visible composer submits reliably.
                .disabled(surfaceIsHidden)
            if store.reviewingRunID == nil {
                if store.focusedNodeID == nil,
                   !store.activeWorkspace.nodes.isEmpty,
                   store.visibleNodes.isEmpty {
                    ClearSurfaceView(onRestoreAll: store.restoreAllNodes)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
                focusedNode(in: size)
                if fullDisplayBrowserID == nil { chrome(in: size) }
                if let promptFlight {
                    PromptFlightView(flight: promptFlight, progress: promptFlightProgress)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .zIndex(50_000)
                }
            }
            if let reviewingRunID = store.reviewingRunID {
                ReviewRoomView(store: store, runID: reviewingRunID)
                    .zIndex(20_000)
            }
        }
    }

    /// The tiled surface stays mounted at all times; these are the states that
    /// hide it. Never express them as a branch that omits `surface`.
    private var surfaceIsHidden: Bool {
        store.focusedNodeID != nil || store.reviewingRunID != nil
    }

    private var jarvisPagePresented: Binding<Bool> {
        Binding(
            get: { activePage == .jarvis },
            set: { activePage = $0 ? .jarvis : .workspace }
        )
    }

    private var background: some View {
        WorkspaceBackdrop(
            theme: WorkspaceTheme.resolve(store.activeWorkspace.theme),
            animated: configuration.animatesBackground && activePage == .workspace
        )
    }

    private func surface(in viewportSize: CGSize) -> some View {
        let workspace = store.activeWorkspace
        let camera = transientCamera ?? workspace.camera
        let nodes = workspace.nodes
            .filter { !$0.isMinimizedResolved }
            .sorted(by: { $0.zIndex < $1.zIndex })
        let featuredIndex = featuredBrowserID.flatMap { id in nodes.firstIndex(where: { $0.id == id }) }
        let usesPresentationLayout = featuredIndex != nil
        let presentationFrames = featuredIndex.map { index in
            WorkspaceLayout.featuredVideoFrames(
                nodeCount: nodes.count,
                featuredIndex: index,
                viewportSize: viewportSize,
                fullDisplay: fullDisplayBrowserID != nil
            )
        }
        return ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .gesture(backgroundGesture(camera: camera), isEnabled: !usesPresentationLayout)
                .onTapGesture { store.select(nil) }
            ForEach(Array(nodes.enumerated()), id: \.element.id) { index, node in
                let presentationFrame = presentationFrames?[index]
                let storedFrame = presentationFrame ?? CGRect(
                    x: node.position.x,
                    y: node.position.y,
                    width: node.size.width,
                    height: node.size.height
                )
                let previewSize = nodeResizePreview?.nodeID == node.id
                    ? nodeResizePreview?.size ?? storedFrame.size
                    : storedFrame.size
                let frame = CGRect(origin: storedFrame.origin, size: previewSize)
                let dragOffset = nodeDragPreview?.nodeIDs.contains(node.id) == true
                    ? nodeDragPreview?.translation ?? .zero
                    : .zero
                let hiddenForFullDisplay = fullDisplayBrowserID != nil && node.id != fullDisplayBrowserID
                WorkspaceNodeView(
                    node: node,
                    latestRun: store.latestRun(for: node.id),
                recentRuns: store.recentRuns(for: node.id),
                    mission: store.mission(for: node),
                    terminalSession: node.kind == .terminal ? store.terminalSession(for: node.id) : nil,
                    workspaceTheme: WorkspaceTheme.resolve(workspace.theme),
                    isSelected: store.selectedNodeIDs.contains(node.id),
                    isReceivingPrompt: receivingNodeID == node.id,
                    scale: usesPresentationLayout ? 1 : camera.scale,
                    allowsManipulation: !usesPresentationLayout,
                    onSelect: { store.select(node.id, toggling: NSEvent.modifierFlags.contains(.shift)) },
                    onBeginManipulation: { store.beginDirectManipulation(node.id) },
                    onMovePreview: { translation in
                        let movingIDs = store.selectedNodeIDs.contains(node.id)
                            ? store.selectedNodeIDs
                            : Set([node.id])
                        nodeDragPreview = WorkspaceNodeDragPreview(
                            activeNodeID: node.id,
                            nodeIDs: movingIDs,
                            translation: translation
                        )
                    },
                    onMove: { position in
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            store.moveNode(node.id, to: position)
                            nodeDragPreview = nil
                        }
                    },
                    onResizePreview: { size in
                        nodeResizePreview = WorkspaceNodeResizePreview(nodeID: node.id, size: size)
                    },
                    onResize: { size in
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            store.resizeNode(node.id, to: size)
                            nodeResizePreview = nil
                        }
                    },
                    onContentChange: { store.updateNodeContent(node.id, content: $0) },
                    onURLChange: { store.updateNodeURL(node.id, url: $0) },
                    onRefresh: { store.refreshNode(node.id) },
                    onSendTask: { store.sendTask($0, to: node.id) },
                    onOpenArtifact: { store.openArtifact($0, from: $1) },
                    onReviewRun: store.beginReview,
                    onDraftChange: { store.updateNodeDraft(node.id, draft: $0) },
                    onAgentDisplayModeChange: { store.updateAgentDisplayMode(node.id, mode: $0) },
                    onRename: { store.renameNode(node.id, to: $0) },
                    onFocus: {
                        withAnimation(WorkspaceMotion.animation(WorkspaceMotion.layout, reduceMotion: reduceMotion)) {
                            showsStageRail = false
                            store.focusNode(node.id)
                        }
                    },
                    onCancel: { store.cancelAgent(node.id) },
                    onFinish: store.finishDirectManipulation,
                    onReorder: { store.reorderNodeAfterDrag(node.id) },
                    onShowGuardian: { showGuardian(node.id) },
                    onStartMission: store.startMission,
                    onCancelMission: store.cancelMission,
                    onReviewMission: store.reviewMission,
                    onVerifyMission: store.verifyMission,
                    onOpenMissionWorker: store.showOnStage,
                    missionWorkerName: workerName,
                    onMinimize: {
                        withAnimation(WorkspaceMotion.animation(WorkspaceMotion.layout, reduceMotion: reduceMotion)) {
                            store.minimizeNode(node.id)
                        }
                    },
                    onClose: { store.removeNode(node.id) },
                    browserUsesFullDisplay: fullDisplayBrowserID == node.id,
                    onBrowserPresentationChange: { active in
                        updateBrowserPresentation(nodeID: node.id, active: active)
                    },
                    onRequestBrowserFullDisplay: {
                        enterBrowserFullDisplay(nodeID: node.id)
                    }
                )
                .frame(width: frame.width, height: frame.height)
                .position(
                    x: frame.midX,
                    y: frame.midY
                )
                .offset(dragOffset)
                .opacity(hiddenForFullDisplay ? 0 : 1)
                .allowsHitTesting(!hiddenForFullDisplay)
                .zIndex(
                    nodeDragPreview?.nodeIDs.contains(node.id) == true
                        ? 9_500
                        : (node.id == featuredBrowserID ? 9_000 : Double(node.zIndex))
                )
                .workspaceGeometryMotion(
                    id: node.id,
                    in: workspaceMotionNamespace,
                    enabled: node.kind != .browser,
                    isSource: true
                )
                .transition(
                    node.kind == .browser
                        ? .opacity
                        : .scale(scale: 0.94).combined(with: .opacity)
                )
                .animation(
                    node.kind == .browser || reduceMotion
                        ? nil
                        : WorkspaceMotion.layout,
                    value: featuredBrowserID
                )
            }
            if let marqueeRect {
                Rectangle()
                    .fill(Color(red: 0.80, green: 0.86, blue: 0.63).opacity(0.08))
                    .overlay(Rectangle().stroke(Color(red: 0.80, green: 0.86, blue: 0.63).opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                    .frame(width: marqueeRect.width, height: marqueeRect.height)
                    .position(x: marqueeRect.midX, y: marqueeRect.midY)
                    .zIndex(10_000)
            }
        }
        .frame(
            width: usesPresentationLayout ? viewportSize.width : 1800,
            height: usesPresentationLayout ? viewportSize.height : 1100,
            alignment: .topLeading
        )
        .scaleEffect(usesPresentationLayout ? 1 : camera.scale, anchor: .topLeading)
        .offset(
            x: usesPresentationLayout ? 0 : camera.offset.x,
            y: usesPresentationLayout ? 0 : camera.offset.y
        )
        .gesture(magnificationGesture(camera: camera), including: usesPresentationLayout ? .none : .gesture)
        .animation(
            WorkspaceMotion.animation(WorkspaceMotion.layout, reduceMotion: reduceMotion),
            value: nodes.map(\.id)
        )
    }

    @ViewBuilder
    private func focusedNode(in viewportSize: CGSize) -> some View {
        if let id = store.focusedNodeID,
           let node = store.activeWorkspace.nodes.first(where: { $0.id == id }) {
            let frame = WorkspaceChromeLayout.focusedNodeFrame(
                viewportSize: viewportSize,
                sessionRailVisible: showsStageRail
            )
            WorkspaceNodeView(
                node: node,
                latestRun: store.latestRun(for: node.id),
                recentRuns: store.recentRuns(for: node.id),
                mission: store.mission(for: node),
                terminalSession: node.kind == .terminal ? store.terminalSession(for: node.id) : nil,
                workspaceTheme: WorkspaceTheme.resolve(store.activeWorkspace.theme),
                isSelected: true,
                isReceivingPrompt: receivingNodeID == node.id,
                scale: 1,
                allowsManipulation: false,
                onSelect: { store.select(node.id) },
                onBeginManipulation: {},
                onMovePreview: { _ in },
                onMove: { _ in },
                onResizePreview: { _ in },
                onResize: { _ in },
                onContentChange: { store.updateNodeContent(node.id, content: $0) },
                onURLChange: { store.updateNodeURL(node.id, url: $0) },
                onRefresh: { store.refreshNode(node.id) },
                onSendTask: { store.sendTask($0, to: node.id) },
                onOpenArtifact: { store.openArtifact($0, from: $1) },
                onReviewRun: store.beginReview,
                onDraftChange: { store.updateNodeDraft(node.id, draft: $0) },
                onAgentDisplayModeChange: { store.updateAgentDisplayMode(node.id, mode: $0) },
                onRename: { store.renameNode(node.id, to: $0) },
                onFocus: {
                    withAnimation(WorkspaceMotion.animation(WorkspaceMotion.layout, reduceMotion: reduceMotion)) {
                        store.exitFocus()
                    }
                },
                onCancel: { store.cancelAgent(node.id) },
                onFinish: store.finishDirectManipulation,
                onShowGuardian: { showGuardian(node.id) },
                onStartMission: store.startMission,
                onCancelMission: store.cancelMission,
                onReviewMission: store.reviewMission,
                onVerifyMission: store.verifyMission,
                onOpenMissionWorker: store.showOnStage,
                missionWorkerName: workerName,
                onMinimize: {
                    withAnimation(WorkspaceMotion.animation(WorkspaceMotion.layout, reduceMotion: reduceMotion)) {
                        store.minimizeNode(node.id)
                    }
                },
                onClose: { store.removeNode(node.id) },
                browserUsesFullDisplay: fullDisplayBrowserID == node.id,
                onBrowserPresentationChange: { active in
                    updateBrowserPresentation(nodeID: node.id, active: active)
                },
                onRequestBrowserFullDisplay: {
                    enterBrowserFullDisplay(nodeID: node.id)
                }
            )
            .frame(
                width: fullDisplayBrowserID == node.id ? viewportSize.width : frame.width,
                height: fullDisplayBrowserID == node.id ? viewportSize.height : frame.height
            )
            .position(
                x: fullDisplayBrowserID == node.id ? viewportSize.width / 2 : frame.midX,
                y: fullDisplayBrowserID == node.id ? viewportSize.height / 2 : frame.midY
            )
            // The workspace copy remains mounted while focus mode is active.
            // Matching its transformed canvas frame onto this explicit screen
            // frame shifts the focused card toward the source node. A local
            // scale/fade keeps the transition smooth without corrupting the
            // final centered geometry.
            .transition(node.kind == .browser ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private func updateBrowserPresentation(nodeID: UUID, active: Bool) {
        if active {
            featuredBrowserID = nodeID
            return
        }
        featuredBrowserID = nil
        if fullDisplayBrowserID == nodeID {
            fullDisplayBrowserID = nil
            if NSApp.keyWindow?.styleMask.contains(.fullScreen) == true {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
        }
    }

    private func enterBrowserFullDisplay(nodeID: UUID) {
        guard featuredBrowserID == nodeID else { return }
        fullDisplayBrowserID = nodeID
        if NSApp.keyWindow?.styleMask.contains(.fullScreen) != true {
            NSApp.keyWindow?.toggleFullScreen(nil)
        }
    }

    @ViewBuilder
    private func chrome(in size: CGSize) -> some View {
        let leftRail = WorkspaceChromeLayout.leftRailPlacement(
            nodeCount: store.minimizedNodes.count,
            viewportHeight: size.height,
            railHeight: toolRailMeasuredHeight
        )
        toolRail
            .fixedSize()
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ToolRailHeightKey.self, value: proxy.size.height)
                }
            )
            .onPreferenceChange(ToolRailHeightKey.self) { height in
                if height > 0 { toolRailMeasuredHeight = height }
            }
            .position(x: 34, y: leftRail.toolCenterY)
        workspaceControl
            .fixedSize()
            .position(x: size.width / 2, y: 31)
        commandBar(in: size)
            .position(x: size.width / 2, y: size.height - 53)
        if !store.minimizedNodes.isEmpty, let dockCenterY = leftRail.dockCenterY {
            MinimizedSessionDock(
                nodes: store.minimizedNodes,
                motionNamespace: workspaceMotionNamespace,
                reduceMotion: reduceMotion,
                onRestore: { id in
                    withAnimation(WorkspaceMotion.animation(WorkspaceMotion.layout, reduceMotion: reduceMotion)) {
                        store.restoreNode(id)
                    }
                },
                onRestoreAll: {
                    withAnimation(WorkspaceMotion.animation(WorkspaceMotion.layout, reduceMotion: reduceMotion)) {
                        store.restoreAllNodes()
                    }
                },
                onClose: { store.removeNode($0) }
            )
            .frame(width: 52, height: leftRail.dockHeight)
            .position(x: 34, y: dockCenterY)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(16_000)
        }
        if showsStageRail {
            let railWidth = WorkspaceChromeLayout.sessionRailWidth(viewportWidth: size.width)
            let railHeight = max(360, size.height - 150)
            StageRailView(
                store: store,
                onClose: {
                    showsStageRail = false
                },
                onGuardian: showGuardian
            )
            .frame(width: railWidth, height: railHeight)
            .position(x: size.width - railWidth / 2 - 16, y: 58 + railHeight / 2)
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(15_000)
        }
        zoomControl(in: size)
            .fixedSize()
            .position(x: 90, y: size.height - 31)
        HoverRevealMiniMap(
            workspace: store.activeWorkspace,
            selectedNodeIDs: store.selectedNodeIDs,
            viewportSize: size
        )
        .frame(width: 132, height: 96)
        .position(x: size.width - 66, y: size.height - 48)
    }

    private var workspaceControl: some View {
        HStack(spacing: 2) {
            Button { showsWorkspaceSwitcher.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 10, weight: .semibold))
                    Text(store.activeWorkspace.name).font(.system(size: 12, weight: .semibold))
                    if attentionCount > 0 {
                        Text("\(attentionCount)")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Color.orange, in: Circle())
                            .accessibilityLabel("\(attentionCount) sessions need attention")
                    }
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .workspaceHoverCallout(
                    "Switch workspace",
                    anchorSize: 34,
                    placement: .below
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showsWorkspaceSwitcher, arrowEdge: .top) {
                WorkspaceSwitcherView(store: store, isPresented: $showsWorkspaceSwitcher)
            }
            .accessibilityLabel("Open project switcher")
            if !store.pendingAuthorityApprovals.isEmpty {
                chromeButton(
                    "exclamationmark.bubble.fill",
                    label: "Open \(store.pendingAuthorityApprovals.count) pending approval\(store.pendingAuthorityApprovals.count == 1 ? "" : "s")",
                    isActive: true,
                    showsHoverLabel: true,
                    hoverCalloutPlacement: .below
                ) {
                    showsApprovalInbox = true
                }
            }
            Menu {
                Button("Balanced layout") { store.arrangeNodes(mode: .balanced) }
                Button("Fill available space") { store.arrangeNodes(mode: .fill) }
                Button(store.visibleNodes.isEmpty && !store.activeWorkspace.nodes.isEmpty ? "Restore all sessions" : "Minimize all sessions") {
                    if store.visibleNodes.isEmpty {
                        store.restoreAllNodes()
                    } else {
                        store.minimizeAllNodes()
                    }
                }
                Button(showsStageRail ? "Hide session rail" : "Show session rail") {
                    showsStageRail.toggle()
                }
                Divider()
                Button("Memory and timeline…") { showsWorkspaceLibrary = true }
                Button(store.pendingAuthorityApprovals.isEmpty ? "Approval inbox" : "Approval inbox (\(store.pendingAuthorityApprovals.count))") {
                    showsApprovalInbox = true
                }
                Button("Choose background…") { showsBackgroundPicker = true }
                Divider()
                Button("Choose working folder…", action: store.chooseActiveWorkspaceFolder)
                Button("Rename workspace…", action: store.promptToRenameActiveWorkspace)
                Button("Duplicate workspace", action: store.duplicateActiveWorkspace)
                Button(store.speaksCompletionNotices ? "Disable Jarvis announcements" : "Enable Jarvis announcements") {
                    store.speaksCompletionNotices.toggle()
                }
                Button("Test Jarvis voice", action: store.previewCompletionVoice)
                Button("Voice transcription…") { showsVoiceSettings = true }
                Button("Agent capabilities…") { showsAgentAccessSettings = true }
                Button("Release diagnostics…") { showsReleaseDiagnostics = true }
                Divider()
                Button("Delete workspace…", role: .destructive, action: store.confirmDeleteActiveWorkspace)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .workspaceHoverCallout(
                        "Workspace actions",
                        anchorSize: 32,
                        placement: .below
                    )
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Workspace actions")
            .popover(isPresented: $showsBackgroundPicker, arrowEdge: .top) {
                WorkspaceBackgroundPicker(
                    selectedTheme: WorkspaceTheme.resolve(store.activeWorkspace.theme),
                    onSelect: store.setTheme
                )
            }
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(WorkspaceVisualStyle.panelTint.opacity(0.52), in: Capsule())
        .overlay(Capsule().stroke(WorkspaceVisualStyle.panelBorder))
        .shadow(color: .black.opacity(0.32), radius: 14, y: 6)
    }

    private var toolRail: some View {
        VStack(spacing: 4) {
            Button {
                presentLauncher(.claude)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(.black.opacity(0.82))
                    .background(WorkspaceVisualStyle.accent, in: Circle())
                    .workspaceHoverCallout("New session", anchorSize: 34)
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .accessibilityLabel("New session")
            Menu {
                Button("New coordinated mission…") { showsMissionLauncher = true }
                Button("Add music player") {
                    store.addNode(kind: .music, title: "Focus", url: MusicStation.defaultURLString)
                }
                Button("Add live chat") { store.addNode(kind: .liveChat, title: "Live Chat") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 30, height: 30)
                    .workspaceHoverCallout("More workspace items", anchorSize: 30)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("More workspace items")
            if !store.selectedNodeIDs.isEmpty {
                Divider().frame(width: 18)
                chromeButton("arrow.up.left", label: "Clear selection", showsHoverLabel: true) {
                    store.select(nil)
                }
            }
        }
        .padding(5)
        .background(.ultraThinMaterial, in: Capsule())
        .background(WorkspaceVisualStyle.panelTint.opacity(0.52), in: Capsule())
        .overlay(Capsule().stroke(WorkspaceVisualStyle.panelBorder))
        .shadow(color: .black.opacity(0.3), radius: 14, y: 6)
    }

    private func commandBar(in size: CGSize) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                Task { await toggleVoiceInput() }
            } label: {
                Image(systemName: speech.isTranscribing ? "ellipsis" : (store.isListening ? "waveform" : "mic"))
                    .symbolEffect(.pulse, isActive: store.isListening)
                    .frame(width: 38, height: 38)
                    .foregroundStyle(store.isListening ? WorkspaceVisualStyle.accent : .white.opacity(0.76))
                    .background(store.isListening ? WorkspaceVisualStyle.accent.opacity(0.16) : .white.opacity(0.07), in: Circle())
                    .overlay(Circle().stroke(store.isListening ? WorkspaceVisualStyle.accent.opacity(0.48) : .white.opacity(0.08)))
            }
            .buttonStyle(WorkspacePressButtonStyle())
            .disabled(speech.isTranscribing)
            .accessibilityLabel(speech.isTranscribing ? "Transcribing voice command" : (store.isListening ? "Stop listening and run command" : "Start voice command"))
            .accessibilityHint("Microphone permission is remembered by macOS after it is granted.")
            Group {
                if let plan = store.stagedCommandPlan {
                    CommandPlanConfirmationView(
                        plan: plan,
                        onRun: { _ = store.confirmStagedCommand() },
                        onCancel: store.cancelStagedCommand
                    )
                } else {
                    TaskComposer(
                        text: $store.commandText,
                        prompt: "Tell the workspace what to do…",
                        targetLabel: commandTargetLabel,
                        statusMessage: store.supervisorMessage,
                        intentPreview: liveCommandPlan,
                        disabled: false,
                        focus: $commandFocused,
                        onSubmit: store.submitCommand
                    )
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(store.isListening ? WorkspaceVisualStyle.accent : .white.opacity(0.16)))
        }
        .padding(8)
        .frame(width: commandBarWidth(for: size.width))
        .workspaceGlassPanel(cornerRadius: 18, tintOpacity: 0.66, shadowRadius: 18)
        .help(speech.errorMessage ?? (speech.isTranscribing ? "Transcribing with Whisper" : (store.isListening ? "Stop recording and run" : "Start voice command")))
    }

    private func commandBarWidth(for viewportWidth: CGFloat) -> CGFloat {
        min(720, max(500, viewportWidth - (viewportWidth < 1_120 ? 270 : 420)))
    }

    private var commandTargetLabel: String {
        guard let selectedNodeID = store.selectedNodeID,
              let selected = store.activeWorkspace.nodes.first(where: { $0.id == selectedNodeID && $0.kind == .agent }) else {
            return "Workspace"
        }
        return selected.title
    }

    private var liveCommandPlan: WorkspaceCommandPlan? {
        let raw = store.commandText.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? nil : store.commandPlan(for: raw)
    }

    private var attentionCount: Int {
        store.activeWorkspace.nodes.filter { $0.status == .needsAttention }.count
    }

    private func presentLauncher(_ provider: SessionProvider) {
        launcherProvider = provider
        showsSessionLauncher = true
    }

    private func showGuardian(_ nodeID: UUID) {
        guardianNodeID = nodeID
        showsGuardian = true
    }

    private func workerName(_ nodeID: UUID) -> String {
        store.activeWorkspace.nodes.first(where: { $0.id == nodeID })?.title ?? "Unavailable agent"
    }

    private func zoomControl(in size: CGSize) -> some View {
        HStack(spacing: 0) {
            chromeButton("minus", label: "Zoom out") { changeZoom(-0.1, in: size) }
            Menu {
                ForEach([0.25, 0.50, 0.75, 1.0, 1.25, 1.50], id: \.self) { scale in
                    Button("\(Int(scale * 100))%") { setZoom(scale, in: size) }
                }
            } label: {
                Text("\(Int((store.activeWorkspace.camera.scale * 100).rounded()))%")
                    .font(.system(size: 10, design: .monospaced))
                    .frame(width: 46, height: 30)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Zoom level, \(Int((store.activeWorkspace.camera.scale * 100).rounded())) percent")
            .help("Choose zoom level")
            chromeButton("plus", label: "Zoom in") { changeZoom(0.1, in: size) }
        }
        .padding(.horizontal, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Color(red: 0.025, green: 0.055, blue: 0.10).opacity(0.42), in: Capsule())
        .overlay(Capsule().stroke(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom)))
    }

    private func chromeButton(
        _ symbol: String,
        label: String,
        isActive: Bool = false,
        showsHoverLabel: Bool = false,
        hoverCalloutPlacement: WorkspaceHoverCalloutPlacement = .trailing,
        action: @escaping () -> Void
    ) -> some View {
        WorkspaceIconButton(
            symbol: symbol,
            label: label,
            isActive: isActive,
            showsHoverLabel: showsHoverLabel,
            hoverCalloutPlacement: hoverCalloutPlacement,
            action: action
        )
    }

    private func backgroundGesture(camera: CameraTransform) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if NSEvent.modifierFlags.contains(.shift) {
                    if marqueeStart == nil { marqueeStart = value.startLocation }
                    guard let start = marqueeStart else { return }
                    marqueeRect = CGRect(
                        x: min(start.x, value.location.x),
                        y: min(start.y, value.location.y),
                        width: abs(value.location.x - start.x),
                        height: abs(value.location.y - start.y)
                    )
                    return
                }
                if panOrigin == nil { panOrigin = camera.offset.cgPoint }
                guard let origin = panOrigin else { return }
                var next = camera
                next.offset = PointValue(x: origin.x + value.translation.width, y: origin.y + value.translation.height)
                transientCamera = next
            }
            .onEnded { value in
                if let marqueeRect {
                    store.selectNodes(intersecting: marqueeRect)
                    self.marqueeRect = nil
                    marqueeStart = nil
                    transientCamera = nil
                    panOrigin = nil
                } else {
                    var settled = transientCamera ?? camera
                    if !reduceMotion {
                        let inertia = WorkspaceMotion.inertialPanDelta(
                            translation: value.translation,
                            predictedEndTranslation: value.predictedEndTranslation
                        )
                        settled.offset = PointValue(
                            x: settled.offset.x + inertia.width,
                            y: settled.offset.y + inertia.height
                        )
                    }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        if let current = transientCamera { store.setCamera(current) }
                        transientCamera = nil
                    }
                    withAnimation(WorkspaceMotion.animation(WorkspaceMotion.camera, reduceMotion: reduceMotion)) {
                        store.setCamera(settled)
                    }
                    panOrigin = nil
                    store.finishDirectManipulation()
                }
            }
    }

    private func magnificationGesture(camera: CameraTransform) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if cameraBeforeMagnification == nil { cameraBeforeMagnification = camera }
                guard var next = cameraBeforeMagnification else { return }
                next.zoom(to: next.scale * value.magnification, around: value.startLocation)
                transientCamera = next
            }
            .onEnded { _ in
                if let finalCamera = transientCamera {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        store.setCamera(finalCamera)
                        transientCamera = nil
                    }
                }
                cameraBeforeMagnification = nil
                store.finishDirectManipulation()
            }
    }

    private func changeZoom(_ delta: Double, in size: CGSize) {
        setZoom(store.activeWorkspace.camera.scale + delta, in: size)
    }

    private func setZoom(_ scale: Double, in size: CGSize) {
        var camera = store.activeWorkspace.camera
        camera.zoom(to: scale, around: CGPoint(x: size.width / 2, y: size.height / 2))
        withAnimation(WorkspaceMotion.animation(WorkspaceMotion.camera, reduceMotion: reduceMotion)) {
            store.setCamera(camera)
        }
        store.finishDirectManipulation()
    }

    private func toggleVoiceInput() async {
        guard !speech.isTranscribing else { return }
        if speech.isRecording {
            await finishVoiceCommand(execute: true)
            return
        }
        let started = await speech.start()
        store.setListening(started)
        if !started, let error = speech.errorMessage {
            store.supervisorMessage = error
        }
    }

    private func finishVoiceCommand(execute: Bool) async {
        store.setListening(false)
        store.supervisorMessage = "Transcribing with Whisper…"
        let contextTerms = [store.activeWorkspace.name]
            + store.activeWorkspace.nodes.filter { $0.kind == .agent }.map(\.title)
            + [URL(fileURLWithPath: store.activeWorkspace.rootPath ?? "").lastPathComponent]
        guard let transcript = await speech.stopAndTranscribe(contextTerms: contextTerms) else {
            store.supervisorMessage = speech.errorMessage ?? "Voice command was not captured"
            return
        }
        if !execute || VoiceCommandPolicy.isSleepCommand(transcript) {
            store.commandText = ""
            store.supervisorMessage = "Voice input asleep"
            return
        }
        store.commandText = transcript
        store.runCommand()
    }

    private func animate(_ dispatch: PromptDispatch, in viewportSize: CGSize) {
        guard let target = store.activeWorkspace.nodes.first(where: { $0.id == dispatch.targetNodeID }) else { return }
        flightCleanupTask?.cancel()
        receivingNodeID = nil

        let camera = store.activeWorkspace.camera
        let targetPoint: CGPoint
        if store.focusedNodeID == target.id {
            targetPoint = CGPoint(x: viewportSize.width / 2, y: 70)
        } else {
            targetPoint = CGPoint(
                x: (target.position.x + target.size.width / 2) * camera.scale + camera.offset.x,
                y: (target.position.y + 18) * camera.scale + camera.offset.y
            )
        }

        let startPoint = CGPoint(x: viewportSize.width / 2 + 245, y: viewportSize.height - 68)
        if reduceMotion {
            receivingNodeID = target.id
            flightCleanupTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard !Task.isCancelled else { return }
                receivingNodeID = nil
            }
            return
        }

        promptFlight = PromptFlight(
            targetNodeID: target.id,
            targetName: target.title,
            summary: dispatch.summary,
            start: startPoint,
            end: targetPoint
        )
        promptFlightProgress = 0
        flightCleanupTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.18, 0.76, 0.26, 1, duration: 0.78)) {
                promptFlightProgress = 1
            }
            try? await Task.sleep(nanoseconds: 790_000_000)
            guard !Task.isCancelled else { return }
            receivingNodeID = target.id
            promptFlight = nil
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            receivingNodeID = nil
        }
    }

    private func updateViewport(_ size: CGSize, reflow: Bool) {
        store.updateViewportSize(size)
        guard reflow else { return }
        viewportReflowTask?.cancel()
        viewportReflowTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            store.arrangeNodes(announce: false)
        }
    }

}

private struct ClearSurfaceView: View {
    let onRestoreAll: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(red: 0.78, green: 0.90, blue: 0.72))
                .shadow(color: Color(red: 0.42, green: 0.84, blue: 0.72).opacity(0.55), radius: 14)
            Text("Surface clear")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text("Your sessions are still running in the left dock.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button("Restore all sessions", action: onRestoreAll)
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.30, green: 0.53, blue: 0.48))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Color(red: 0.02, green: 0.06, blue: 0.10).opacity(0.46), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.18)))
        .shadow(color: .black.opacity(0.34), radius: 22, y: 10)
        .accessibilityElement(children: .contain)
    }
}

private struct MinimizedSessionDock: View {
    let nodes: [WorkspaceNode]
    let motionNamespace: Namespace.ID
    let reduceMotion: Bool
    let onRestore: (UUID) -> Void
    let onRestoreAll: () -> Void
    let onClose: (UUID) -> Void

    @State private var hoverLabel: String?

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(red: 0.78, green: 0.90, blue: 0.72))
                    .frame(width: 36, height: 32)
                Text("\(nodes.count)")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.82))
                    .frame(minWidth: 14, minHeight: 14)
                    .background(Color(red: 0.78, green: 0.90, blue: 0.72), in: Circle())
                    .offset(x: 2, y: -1)
            }
            .accessibilityLabel("\(nodes.count) minimized sessions")
            .onHover { hoverLabel = $0 ? "Minimized sessions" : nil }

            Divider().frame(width: 24)

            ScrollView(.vertical, showsIndicators: nodes.count > 7) {
                VStack(spacing: 8) {
                    ForEach(nodes) { node in
                        Button { onRestore(node.id) } label: {
                            ZStack(alignment: .topTrailing) {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill((providerColor(for: node) ?? Color.white).opacity(providerColor(for: node) == nil ? 0.06 : 0.11))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke((providerColor(for: node) ?? Color.white).opacity(providerColor(for: node) == nil ? 0.10 : 0.42))
                                    )
                                Image(systemName: node.kind.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(providerColor(for: node) ?? Color.white.opacity(0.78))
                                Circle()
                                    .fill(statusColor(for: node.status))
                                    .frame(width: 7, height: 7)
                                    .overlay(Circle().stroke(Color.black.opacity(0.7), lineWidth: 1.5))
                                    .offset(x: 2, y: -2)
                            }
                            .frame(width: 38, height: 38)
                            .workspaceGeometryMotion(
                                id: node.id,
                                in: motionNamespace,
                                enabled: node.kind != .browser,
                                isSource: false
                            )
                        }
                        .buttonStyle(WorkspacePressButtonStyle())
                        .accessibilityLabel("Restore \(node.title), \(node.subtitle)")
                        .help("Restore \(node.title)")
                        .onHover { hovering in
                            hoverLabel = hovering ? "\(node.title) · \(node.subtitle)" : nil
                        }
                        .contextMenu {
                            Button("Restore", action: { onRestore(node.id) })
                            Divider()
                            Button("Close session", role: .destructive, action: { onClose(node.id) })
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: WorkspaceChromeLayout.minimizedDockSessionSlotHeight)
            .layoutPriority(1)

            Divider().frame(width: 24)
            Button(action: onRestoreAll) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 30)
                    .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
                .buttonStyle(WorkspacePressButtonStyle())
                .accessibilityLabel("Restore all minimized sessions")
                .help("Restore all minimized sessions")
                .onHover { hoverLabel = $0 ? "Restore all sessions" : nil }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .background(Color(red: 0.02, green: 0.06, blue: 0.10).opacity(0.68), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.07)], startPoint: .leading, endPoint: .trailing)))
        .overlay(alignment: .leading) {
            if let hoverLabel {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 52, height: 1)
                    Text(hoverLabel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 9)
                        .frame(height: 27)
                        .background(.ultraThinMaterial, in: Capsule())
                        .background(WorkspaceVisualStyle.panelTint.opacity(0.90), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.16)))
                        .shadow(color: .black.opacity(0.42), radius: 10, y: 4)
                        .fixedSize()
                }
                .fixedSize()
                .allowsHitTesting(false)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .shadow(color: .black.opacity(0.34), radius: 16, x: 5, y: 5)
        .animation(WorkspaceMotion.animation(WorkspaceMotion.hover, reduceMotion: reduceMotion), value: hoverLabel)
    }

    private func providerColor(for node: WorkspaceNode) -> Color? {
        node.resolvedProvider?.workspaceAccent
    }

    private func statusColor(for status: NodeStatus) -> Color {
        switch status {
        case .idle: .white.opacity(0.38)
        case .working: Color(red: 0.94, green: 0.78, blue: 0.35)
        case .complete: Color(red: 0.49, green: 0.87, blue: 0.57)
        case .needsAttention: Color(red: 0.97, green: 0.42, blue: 0.39)
        }
    }
}

private struct PromptFlight: Identifiable {
    var id = UUID()
    var targetNodeID: UUID
    var targetName: String
    var summary: String
    var start: CGPoint
    var end: CGPoint
}

private struct PromptFlightView: View, Animatable {
    let flight: PromptFlight
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            FlightPathShape(start: flight.start, end: flight.end)
                .stroke(
                    Color(red: 0.39, green: 0.79, blue: 0.78).opacity(0.12),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 8])
                )

            FlightPathShape(start: flight.start, end: flight.end)
                .trim(from: max(0, progress - 0.22), to: max(0.001, progress))
                .stroke(
                    Color(red: 0.38, green: 0.96, blue: 0.82).opacity(0.22),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .blur(radius: 7)

            FlightPathShape(start: flight.start, end: flight.end)
                .trim(from: max(0, progress - 0.30), to: max(0.001, progress))
                .stroke(
                    LinearGradient(
                        colors: [.clear, Color(red: 0.48, green: 0.91, blue: 0.82).opacity(0.8), .white],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .shadow(color: Color(red: 0.42, green: 0.86, blue: 0.84), radius: 8)

            ForEach(1 ..< 5, id: \.self) { index in
                Circle()
                    .fill(Color(red: 0.56, green: 0.94, blue: 0.82).opacity(0.52 / Double(index)))
                    .frame(width: 8 - Double(index), height: 8 - Double(index))
                    .position(point(at: max(0, progress - Double(index) * 0.032)))
                    .blur(radius: Double(index) * 0.35)
            }

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white, Color(red: 0.67, green: 1.0, blue: 0.82), Color.cyan.opacity(0.08)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 11
                    )
                )
                .frame(width: 18, height: 18)
                .scaleEffect(0.82 + sin(progress * .pi * 8) * 0.10)
                .shadow(color: Color(red: 0.45, green: 0.96, blue: 0.80), radius: 12)
                .position(point(at: progress))

            HStack(spacing: 7) {
                Image(systemName: "paperplane.fill")
                    .foregroundStyle(Color(red: 0.82, green: 0.96, blue: 0.72))
                Text(flight.summary)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                Text(flight.targetName)
                    .fontWeight(.semibold)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .frame(height: 30)
            .frame(maxWidth: 280)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color(red: 0.03, green: 0.10, blue: 0.14).opacity(0.72), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.30)))
            .shadow(color: Color(red: 0.35, green: 0.88, blue: 0.77).opacity(0.75), radius: 16)
            .position(point(at: progress))
            .offset(y: -24)
            .scaleEffect(0.94 + min(progress * 0.06, 0.06))
        }
    }

    private func point(at progress: Double) -> CGPoint {
        let t = min(max(progress, 0), 1)
        let control = FlightPathShape.controlPoint(start: flight.start, end: flight.end)
        let inverse = 1 - t
        return CGPoint(
            x: inverse * inverse * flight.start.x + 2 * inverse * t * control.x + t * t * flight.end.x,
            y: inverse * inverse * flight.start.y + 2 * inverse * t * control.y + t * t * flight.end.y
        )
    }
}

private struct FlightPathShape: Shape {
    var start: CGPoint
    var end: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: start)
        path.addQuadCurve(to: end, control: Self.controlPoint(start: start, end: end))
        return path
    }

    static func controlPoint(start: CGPoint, end: CGPoint) -> CGPoint {
        CGPoint(
            x: (start.x + end.x) / 2 + (end.x - start.x) * 0.08,
            y: min(start.y, end.y) - max(80, abs(start.y - end.y) * 0.22)
        )
    }
}

private struct MiniMap: View {
    let workspace: WorkspaceDocument
    let selectedNodeIDs: Set<UUID>
    let viewportSize: CGSize

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 7).fill(.ultraThinMaterial)
                ForEach(workspace.nodes.filter { !$0.isMinimizedResolved }) { node in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(selectedNodeIDs.contains(node.id) ? Color(red: 0.80, green: 0.86, blue: 0.63) : .white.opacity(0.32))
                        .frame(width: max(5, node.size.width / 18), height: max(4, node.size.height / 18))
                        .offset(x: node.position.x / 18 + 4, y: node.position.y / 18 + 4)
                }
                let viewport = MiniMapProjection.viewport(camera: workspace.camera, screenSize: viewportSize)
                Rectangle()
                    .fill(.clear)
                    .stroke(.white.opacity(0.72), lineWidth: 1)
                    .frame(width: viewport.width, height: viewport.height)
                    .offset(x: viewport.minX, y: viewport.minY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.white.opacity(0.14)))
        }
        .accessibilityLabel("Workspace minimap")
    }
}

private struct HoverRevealMiniMap: View {
    let workspace: WorkspaceDocument
    let selectedNodeIDs: Set<UUID>
    let viewportSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
                .contentShape(Rectangle())
            MiniMap(
                workspace: workspace,
                selectedNodeIDs: selectedNodeIDs,
                viewportSize: viewportSize
            )
            .frame(width: 112, height: 76)
            .opacity(isHovered ? 1 : 0)
            .scaleEffect(isHovered ? 1 : 0.92, anchor: .bottomTrailing)
            .allowsHitTesting(isHovered)
        }
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isHovered)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspace overview")
        .help("Workspace overview")
    }
}

private struct LiveBroadcastBadge: View {
    let timecode: String
    let authoritative: Bool

    private var tone: Color { authoritative ? .red : .orange }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone)
                .frame(width: 7, height: 7)
                .shadow(color: tone.opacity(0.8), radius: 6)
            Text(authoritative ? "LIVE" : "LAST KNOWN LIVE")
                .font(WorkspacePageTypography.metadata)
                .tracking(0.8)
            if !timecode.isEmpty {
                Text(timecode)
                    .font(WorkspacePageTypography.metadata)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(tone.opacity(0.19), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(tone.opacity(0.55)))
        .shadow(color: tone.opacity(0.22), radius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            authoritative
                ? "Live stream active, \(timecode)"
                : "Last known stream state was live; current status is unavailable, \(timecode)"
        )
    }
}

enum MiniMapProjection {
    static let divisor = 18.0

    static func viewport(camera: CameraTransform, screenSize: CGSize) -> CGRect {
        CGRect(
            x: (-camera.offset.x / camera.scale) / divisor + 4,
            y: (-camera.offset.y / camera.scale) / divisor + 4,
            width: screenSize.width / camera.scale / divisor,
            height: screenSize.height / camera.scale / divisor
        )
    }
}

private extension View {
    func keyboardShortcutFocus(_ focus: FocusState<Bool>.Binding, key: KeyEquivalent) -> some View {
        background(
            Button("") { focus.wrappedValue = true }
                .keyboardShortcut(key, modifiers: .command)
                .hidden()
        )
    }

    func appPageShortcuts(_ selection: Binding<AppPage>) -> some View {
        background {
            Group {
                Button("") { selection.wrappedValue = .workspace }
                    .keyboardShortcut("1", modifiers: .command)
                Button("") { selection.wrappedValue = .stage }
                    .keyboardShortcut("2", modifiers: .command)
                Button("") { selection.wrappedValue = .jarvis }
                    .keyboardShortcut("3", modifiers: .command)
                Button("") { selection.wrappedValue = .vtuber }
                    .keyboardShortcut("4", modifiers: .command)
                Button("") { selection.wrappedValue = .obs }
                    .keyboardShortcut("5", modifiers: .command)
                Button("") { selection.wrappedValue = .signalDeck }
                    .keyboardShortcut("6", modifiers: .command)
            }
            .hidden()
        }
    }
}
