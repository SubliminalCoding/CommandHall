import AppKit
import SwiftUI

struct OBSControlPage: View {
    @ObservedObject var controller: ClawStudioOBSController
    @ObservedObject var store: WorkspaceStore
    @StateObject private var preview = OBSVirtualCameraController()
    @State private var pendingRecordingAction: RecordingConfirmation?
    @State private var directorCommand = ""
    @State private var showsDirectorSuggestions = false
    @State private var showsDirectorLog = false
    @FocusState private var directorInputFocused: Bool
    private let directorSuggestions = OBSDirectorSuggestion.defaults

    var body: some View {
        WorkspacePageScaffold(theme: activeTheme) {
            pageHeader
            systemAlert
            liveStatus
            directorConsole
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            controlSurface
        }
        .onAppear {
            controller.start()
            preview.start()
        }
        .onDisappear {
            preview.stop()
        }
        .alert(item: $pendingRecordingAction) { action in
            switch action {
            case .start:
                Alert(
                    title: Text("Start OBS recording?"),
                    message: Text("The take will be bound to the selected ClawStudio production and current OBS scene."),
                    primaryButton: .default(Text("Start recording")) {
                        Task { await controller.startRecording() }
                    },
                    secondaryButton: .cancel()
                )
            case .stop:
                Alert(
                    title: Text("Stop OBS recording?"),
                    message: Text("ClawStudio will preserve the completed take in its production ledger."),
                    primaryButton: .destructive(Text("Stop and save")) {
                        Task { await controller.stopRecording() }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .accessibilityLabel("OBS control page")
    }

    private var activeTheme: WorkspaceTheme {
        WorkspaceTheme.resolve(store.activeWorkspace.theme)
    }

    private var pageHeader: some View {
        WorkspacePageHeader(
            eyebrow: "Live production",
            symbol: "dot.radiowaves.left.and.right",
            title: "OBS",
            subtitle: "Watch Program and make controlled production changes.",
            accent: activeTheme.accent
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    connectionPill
                    headerActions
                }
                VStack(alignment: .leading, spacing: 8) {
                    connectionPill
                    headerActions
                }
            }
        }
    }

    private var connectionPill: some View {
        WorkspaceStatusPill(
            controller.state.label,
            detail: snapshotDetail,
            tone: connectionTone,
            symbol: controller.connected ? "checkmark.circle.fill" : nil
        )
    }

    private var headerActions: some View {
        Menu {
            Button("Reconnect ClawStudio and OBS", systemImage: "arrow.clockwise", action: controller.reconnect)
            Divider()
            Button("Open OBS", systemImage: "display", action: controller.openOBS)
            Button("Open ClawStudio", systemImage: "safari", action: controller.openClawStudio)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help("OBS and ClawStudio actions")
        .accessibilityLabel("OBS and ClawStudio actions")
        .workspaceTopToolbar()
    }

    @ViewBuilder
    private var systemAlert: some View {
        if let actionError = controller.actionError, controller.connected {
            WorkspaceInlineAlert(
                title: "The requested OBS change was not applied",
                message: actionError,
                tone: .danger,
                symbol: "exclamationmark.triangle.fill"
            ) {
                HStack(spacing: 8) {
                    Button("Reconnect", action: controller.reconnect)
                        .buttonStyle(.bordered)
                    Button("Dismiss", action: controller.dismissActionError)
                        .buttonStyle(.bordered)
                }
            }
        } else if controller.state == .checking {
            WorkspaceInlineAlert(
                title: "Checking the local production stack",
                message: controller.detail,
                tone: .working,
                symbol: "arrow.triangle.2.circlepath"
            )
        } else if !controller.connected {
            WorkspaceInlineAlert(
                title: controller.state.label,
                message: disconnectedMessage,
                tone: controller.state == .failed ? .danger : .warning
            ) {
                HStack(spacing: 8) {
                    Button("Reconnect", action: controller.reconnect)
                        .buttonStyle(.borderedProminent)
                        .tint(activeTheme.accent)
                    Button("Open OBS", action: controller.openOBS)
                        .buttonStyle(.bordered)
                    Button("Open ClawStudio", action: controller.openClawStudio)
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var liveStatus: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                liveStatusContent
            }
            VStack(alignment: .leading, spacing: 8) {
                liveStatusContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var liveStatusContent: some View {
        WorkspaceStatusPill(
            controller.snapshotIsAuthoritative ? recordingLabel : observedStatusLabel("Recording"),
            detail: controller.recording?.active == true ? controller.recording?.timecode : "No active take",
            tone: recordingTone,
            symbol: controller.recording?.active == true ? "record.circle.fill" : "record.circle"
        )
        WorkspaceStatusPill(
            controller.snapshotIsAuthoritative ? streamLabel : observedStatusLabel("Stream"),
            detail: controller.stream?.active == true ? controller.stream?.timecode : "Not live",
            tone: streamTone
        )
        if !controller.snapshotIsAuthoritative {
            WorkspaceStatusPill(
                snapshotDetail,
                tone: .warning,
                symbol: "clock.badge.exclamationmark"
            )
        }
    }

    private var controlSurface: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: WorkspacePageMetrics.sectionSpacing) {
                VStack(spacing: WorkspacePageMetrics.sectionSpacing) {
                    programPreview
                    sceneControl
                }
                .frame(minWidth: 560, maxWidth: .infinity)

                VStack(spacing: WorkspacePageMetrics.sectionSpacing) {
                    productionControl
                    recordingControl
                    spatialCameraControl
                }
                .frame(width: 390)
            }

            VStack(spacing: WorkspacePageMetrics.sectionSpacing) {
                programPreview
                sceneControl
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: WorkspacePageMetrics.sectionSpacing) {
                        VStack(spacing: WorkspacePageMetrics.sectionSpacing) {
                            productionControl
                            recordingControl
                        }
                        .frame(maxWidth: .infinity)
                        spatialCameraControl
                            .frame(maxWidth: .infinity)
                    }
                    VStack(spacing: WorkspacePageMetrics.sectionSpacing) {
                        productionControl
                        recordingControl
                        spatialCameraControl
                    }
                }
            }
        }
    }

    private var programPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                WorkspaceSectionHeading(
                    title: "Program Monitor",
                    detail: programSceneDetail,
                    accent: activeTheme.accent
                )
                Spacer()
                WorkspaceStatusPill(
                    preview.state == .live ? "Preview live" : preview.state.label,
                    tone: previewTone,
                    symbol: preview.state == .live ? "video.fill" : "video.slash.fill"
                )
            }

            ZStack {
                OBSVirtualCameraPreview(session: preview.session)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)

                if preview.state != .live {
                    VStack(spacing: 10) {
                        if preview.state == .connecting || preview.state == .requestingPermission {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "display.trianglebadge.exclamationmark")
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(.orange)
                        }
                        Text(preview.detail)
                            .font(WorkspacePageTypography.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                        HStack(spacing: 8) {
                            Button("Reconnect preview", action: preview.reconnect)
                                .buttonStyle(.borderedProminent)
                                .tint(activeTheme.accent)
                            if preview.state == .denied {
                                Button("Camera settings", action: openCameraPrivacySettings)
                                    .buttonStyle(.bordered)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(24)
                }

                HStack(spacing: 7) {
                    Image(systemName: programBadgeSymbol)
                        .foregroundStyle(programBadgeColor)
                    Text(programBadgeLabel)
                        .font(WorkspacePageTypography.metadata)
                        .tracking(0.8)
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Color.black.opacity(0.72), in: Capsule())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.white.opacity(0.10)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("OBS Program monitor")
            .accessibilityValue(programAccessibilityValue)
        }
        .workspaceSectionCard(padding: 14, cornerRadius: 16, tintOpacity: 0.68)
    }

    private var directorConsole: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WorkspaceSectionHeading(
                    title: "OBS Director",
                    detail: "Audited commands through the ClawStudio Live MCP boundary.",
                    accent: activeTheme.accent
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .bottom, spacing: 9) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(">")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(activeTheme.accent)
                            .padding(.top, 1)
                        TextField(
                            "Tell OBS Director what you want to change or verify…",
                            text: $directorCommand,
                            axis: .vertical
                        )
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .lineLimit(1 ... 5)
                        .focused($directorInputFocused)
                        .onKeyPress(.return, phases: .down) { event in
                            guard !event.modifiers.contains(.shift) else { return .ignored }
                            submitDirectorCommand()
                            return .handled
                        }
                        .accessibilityLabel("OBS Director command input")
                        .accessibilityHint("Press Return to send. Press Shift and Return for a new line.")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(minHeight: 46)
                    .workspaceFocusSurface(isFocused: directorInputFocused, accent: activeTheme.accent, cornerRadius: 12)
                    .onTapGesture { directorInputFocused = true }

                    Button(action: submitDirectorCommand) {
                        Image(systemName: directorNode?.status == .working ? "hourglass" : "arrow.up")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(canSubmitDirectorCommand ? Color.black : .secondary)
                            .frame(width: 36, height: 36)
                            .background(canSubmitDirectorCommand ? activeTheme.accent : .white.opacity(0.08), in: Circle())
                    }
                    .buttonStyle(WorkspacePressButtonStyle())
                    .disabled(!canSubmitDirectorCommand)
                    .accessibilityLabel("Send command to OBS Director")
                    .accessibilityHint("The draft clears only after the Director accepts the command.")
                }

                ViewThatFits(in: .horizontal) {
                    directorStatusFooter(compact: false)
                    directorStatusFooter(compact: true)
                }
            }
            .padding(10)
            .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            DisclosureGroup(isExpanded: $showsDirectorSuggestions) {
                ScrollView(.horizontal, showsIndicators: true) {
                    LazyHStack(spacing: 8) {
                        ForEach(directorSuggestions) { suggestion in
                            directorSuggestion(suggestion)
                        }
                    }
                    .padding(.vertical, 7)
                }
            } label: {
                Label("Suggested prompts", systemImage: "sparkles")
                    .font(WorkspacePageTypography.body.weight(.semibold))
            }
            .tint(activeTheme.accent)

            DisclosureGroup(isExpanded: $showsDirectorLog) {
                ScrollView {
                    Text(directorTranscript)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.82))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
                }
                .frame(maxHeight: 150)
                .padding(10)
                .workspaceFocusSurface(isFocused: false, accent: activeTheme.accent, cornerRadius: 10)
                .padding(.top, 7)
            } label: {
                Label("Director log · read only", systemImage: "text.alignleft")
                    .font(WorkspacePageTypography.body.weight(.semibold))
            }
            .tint(activeTheme.accent)

            Label(
                "Going live still requires the protected ClawStudio/HQ confirmation flow.",
                systemImage: "lock.shield"
            )
            .font(WorkspacePageTypography.body)
            .foregroundStyle(.secondary)
        }
        .workspaceSectionCard(padding: 14, cornerRadius: 16, tintOpacity: 0.66)
    }

    private func directorSuggestion(_ suggestion: OBSDirectorSuggestion) -> some View {
        Button {
            submitDirectorCommand(suggestion.command)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: suggestion.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(activeTheme.accent)
                    .frame(width: 22, height: 22)
                    .background(activeTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(suggestion.detail)
                        .font(WorkspacePageTypography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(10)
            .frame(width: 218, alignment: .topLeading)
            .frame(minHeight: 76, alignment: .topLeading)
            .workspaceSelectableSurface(selected: false, accent: activeTheme.accent, cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .help(suggestion.command)
        .accessibilityLabel("Suggested prompt: \(suggestion.title). \(suggestion.command)")
        .accessibilityHint("Runs this prompt immediately through OBS Director.")
        .disabled(directorNode?.status == .working)
    }

    private var directorNode: WorkspaceNode? {
        store.activeWorkspace.nodes.first {
            $0.resolvedProvider == .codex && $0.title.caseInsensitiveCompare("OBS Director") == .orderedSame
        }
    }

    private var directorTranscript: String {
        guard let node = directorNode else {
            return "Ready. Ask for a scene change, recording, status check, or stream-readiness review. The first command creates a dedicated OBS Director agent."
        }
        if let run = store.latestRun(for: node.id) {
            let output = run.summary ?? node.activityLog ?? node.content
            let state = run.state.rawValue.uppercased()
            return "[\(state)] \(String(output.suffix(5_000)))"
        }
        return String((node.activityLog ?? node.content).suffix(5_000))
    }

    private func submitDirectorCommand() {
        submitDirectorCommand(directorCommand)
    }

    private func submitDirectorCommand(_ rawCommand: String) {
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, directorNode?.status != .working else { return }
        let nodeID = directorNode?.id ?? store.createSession(
            provider: .codex,
            name: "OBS Director",
            purpose: "Operate OBS only through the audited ClawStudio Live MCP boundary",
            workingFolderMode: .custom,
            workingFolderPath: controller.configuration.projectURL.path
        )
        if store.sendTask(OBSDirectorPrompt.task(
            for: command,
            selectedProductionID: controller.selectedProductionID,
            currentScene: controller.currentProgramScene
        ), to: nodeID) {
            directorCommand = ""
        }
    }

    private var productionControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionHeading(
                title: "Production",
                detail: "Every scene and recording action is bound to this durable ClawStudio identity.",
                accent: activeTheme.accent
            )
            Picker("Active production", selection: $controller.selectedProductionID) {
                Text("Choose a production").tag(String?.none)
                ForEach(controller.productions) { production in
                    Text("\(production.shortLabel) · \(production.artifactCount) artifacts")
                        .tag(Optional(production.productionId))
                }
            }
            .pickerStyle(.menu)
            .disabled(controller.busy || controller.productions.isEmpty)
            .help(controller.busy ? "Wait for \(controller.busyAction ?? "the current OBS action") to finish." : "Choose the production that owns this work.")
            if controller.productions.isEmpty {
                Label(
                    "No productions are available. Create or import one in ClawStudio before switching scenes or recording.",
                    systemImage: "folder.badge.questionmark"
                )
                .font(WorkspacePageTypography.body)
                .foregroundStyle(.orange)
            }
        }
        .workspaceSectionCard(padding: 14, cornerRadius: 16, tintOpacity: 0.64)
    }

    private var sceneControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionHeading(
                title: "Scenes",
                detail: controller.snapshotIsAuthoritative
                    ? "The selected scene is the authoritative OBS Program output."
                    : "Scene values are last known until OBS reconnects.",
                accent: activeTheme.accent
            )
            if controller.scenes.isEmpty {
                Label(
                    controller.connected ? "OBS returned no scenes. Add a scene in OBS, then reconnect." : "Scenes appear after OBS reconnects.",
                    systemImage: "rectangle.3.group.bubble.left"
                )
                .font(WorkspacePageTypography.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 9)], spacing: 9) {
                    ForEach(controller.scenes) { scene in
                        let selected = scene.uuid == controller.currentProgramScene?.uuid
                        Button {
                            if !selected {
                                Task { await controller.switchToScene(scene) }
                            }
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "rectangle.inset.filled")
                                    .foregroundStyle(selected ? Color.green : .secondary)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(scene.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .lineLimit(1)
                                    Text(selected ? "On Program" : "Take scene")
                                        .font(WorkspacePageTypography.metadata)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 52)
                            .workspaceSelectableSurface(selected: selected, accent: activeTheme.accent, cornerRadius: 10)
                        }
                        .buttonStyle(WorkspacePressButtonStyle())
                        .disabled(!controller.canSwitchScene)
                        .accessibilityLabel(selected ? "\(scene.name), current Program scene" : "Take \(scene.name)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .help(sceneActionHelp(for: scene, selected: selected))
                    }
                }
            }
        }
        .workspaceSectionCard(padding: 14, cornerRadius: 16, tintOpacity: 0.64)
    }

    private var spatialCameraControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionHeading(
                title: "On-camera look",
                detail: "Keep Spatial Workspace full-screen while switching the corner overlay between you and your VTuber.",
                accent: activeTheme.accent
            )

            if let layout = controller.spatialLayout, layout.configured {
                HStack {
                    WorkspaceStatusPill(
                        layout.cameraVisible ? "\(layout.cameraMode.label) camera visible" : "Camera overlay hidden",
                        tone: layout.cameraVisible ? .success : .warning,
                        symbol: layout.cameraVisible ? "video.fill" : "video.slash.fill"
                    )
                    Spacer()
                    Button(layout.cameraVisible ? "Hide camera" : "Show camera") {
                        Task {
                            await controller.setSpatialLayout(
                                corner: layout.cameraCorner,
                                size: layout.cameraSize,
                                mode: layout.cameraMode,
                                cameraVisible: !layout.cameraVisible
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!controller.canAdjustSpatialLayout)
                }

                Text("CAMERA SOURCE")
                    .font(WorkspacePageTypography.metadata)
                    .tracking(1)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ForEach(ClawStudioOBSCameraMode.allCases) { mode in
                        let selected = layout.cameraMode == mode
                        Button {
                            if !selected || !layout.cameraVisible {
                                Task {
                                    await controller.setSpatialLayout(
                                        corner: layout.cameraCorner,
                                        size: layout.cameraSize,
                                        mode: mode,
                                        cameraVisible: true
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: mode.symbol)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.label)
                                        .font(.system(size: 11, weight: .bold))
                                    Text(mode.detail)
                                        .font(WorkspacePageTypography.body)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if selected { Image(systemName: "checkmark.circle.fill") }
                            }
                            .padding(.horizontal, 11)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .workspaceSelectableSurface(selected: selected, accent: activeTheme.accent, cornerRadius: 9)
                        }
                        .buttonStyle(.plain)
                        .disabled(!controller.canAdjustSpatialLayout)
                        .accessibilityLabel(selected ? "\(mode.label) camera selected" : "Switch to \(mode.label) camera")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }

                if layout.cameraMode == .vtuber {
                    Label("Choose the character and its background on the VTuber page; this OBS view updates automatically.", systemImage: "paintpalette.fill")
                        .font(WorkspacePageTypography.body)
                        .foregroundStyle(.secondary)
                }

                Text("POSITION")
                    .font(WorkspacePageTypography.metadata)
                    .tracking(1)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 7) {
                    ForEach(ClawStudioOBSCameraCorner.allCases) { corner in
                        let selected = layout.cameraCorner == corner
                        Button {
                            if !selected {
                                Task {
                                    await controller.setSpatialLayout(
                                        corner: corner,
                                        size: layout.cameraSize,
                                        mode: layout.cameraMode,
                                        cameraVisible: layout.cameraVisible
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Label(corner.label, systemImage: corner.symbol)
                                Spacer(minLength: 0)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                                .font(.system(size: 11, weight: .semibold))
                                .padding(.horizontal, 9)
                                .frame(maxWidth: .infinity)
                                .frame(height: 34)
                                .workspaceSelectableSurface(selected: selected, accent: activeTheme.accent, cornerRadius: 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(!controller.canAdjustSpatialLayout)
                        .accessibilityLabel(selected ? "\(corner.label), selected camera position" : "Move camera to \(corner.label)")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }

                HStack {
                    Text("SIZE")
                        .font(WorkspacePageTypography.metadata)
                        .tracking(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    ForEach(ClawStudioOBSCameraSize.allCases) { size in
                        let selected = layout.cameraSize == size
                        Button {
                            if !selected {
                                Task {
                                    await controller.setSpatialLayout(
                                        corner: layout.cameraCorner,
                                        size: size,
                                        mode: layout.cameraMode,
                                        cameraVisible: layout.cameraVisible
                                    )
                                }
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(size.label)
                                if selected {
                                    Image(systemName: "checkmark")
                                        .accessibilityHidden(true)
                                }
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .workspaceSelectableSurface(selected: selected, accent: activeTheme.accent, cornerRadius: 8)
                        }
                        .buttonStyle(.plain)
                        .disabled(!controller.canAdjustSpatialLayout)
                        .accessibilityLabel(selected ? "\(size.label) camera size selected" : "Use \(size.label.lowercased()) camera size")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }

                Text(controller.currentProgramScene?.name == layout.sceneName
                    ? "Changes appear immediately in the Program Monitor and Discord virtual camera."
                    : "Take \(layout.sceneName) above to put this layout on program.")
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    controller.spatialLayout?.message ?? "Start the updated ClawStudio cockpit to enable Spatial Workspace camera controls.",
                    systemImage: "camera.metering.unknown"
                )
                .font(WorkspacePageTypography.body)
                .foregroundStyle(.orange)
            }
        }
        .workspaceSectionCard(padding: 14, cornerRadius: 16, tintOpacity: 0.64)
    }

    private var recordingControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            WorkspaceSectionHeading(
                title: "Recording",
                detail: "ClawStudio verifies ownership and preserves the take when recording stops.",
                accent: activeTheme.accent
            )
            if let lastTake = controller.lastTake {
                HStack(spacing: 8) {
                    Label("Saved take", systemImage: "checkmark.circle.fill")
                        .font(WorkspacePageTypography.body.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(lastTake)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(lastTake)
                    Spacer(minLength: 4)
                    Button("Reveal", action: revealLastTake)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(controller.busyAction ?? recordingLabel)
                        .font(.system(size: 13, weight: .semibold))
                    Text(recordingHelp)
                        .font(WorkspacePageTypography.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if controller.busy { ProgressView().controlSize(.small) }
                Button(controller.recording?.active == true ? "Stop recording" : "Start recording") {
                    pendingRecordingAction = controller.recording?.active == true ? .stop : .start
                }
                .buttonStyle(.borderedProminent)
                .tint(controller.recording?.active == true ? .red : activeTheme.accent)
                .disabled(controller.recording?.active == true ? !controller.canStopRecording : !controller.canStartRecording)
                .help(recordingHelp)
            }
        }
        .workspaceSectionCard(padding: 14, cornerRadius: 16, tintOpacity: 0.64)
    }

    private var snapshotDetail: String {
        if controller.snapshotIsAuthoritative { return "Authoritative" }
        if let lastRefresh = controller.lastSuccessfulRefreshAt {
            return "Last known \(lastRefresh.formatted(date: .omitted, time: .standard))"
        }
        return "No snapshot"
    }

    private var programSceneDetail: String {
        let scene = controller.currentProgramScene?.name ?? "Unavailable"
        return controller.snapshotIsAuthoritative ? scene : "\(scene) · last known"
    }

    private var programBadgeLabel: String {
        if !controller.snapshotIsAuthoritative {
            return controller.recording?.active == true ? "REC · LAST KNOWN" : "PROGRAM · LAST KNOWN"
        }
        return controller.recording?.active == true
            ? "REC  \(controller.recording?.timecode ?? "")"
            : "PROGRAM"
    }

    private var programBadgeSymbol: String {
        if !controller.snapshotIsAuthoritative { return "clock.badge.exclamationmark" }
        return controller.recording?.active == true ? "record.circle.fill" : "play.rectangle.fill"
    }

    private var programBadgeColor: Color {
        if !controller.snapshotIsAuthoritative { return .orange }
        return controller.recording?.active == true ? .red : .green
    }

    private var programAccessibilityValue: String {
        let scene = controller.currentProgramScene?.name ?? "scene unavailable"
        let previewState = preview.state == .live ? "preview live" : preview.state.label
        return "\(scene), \(programBadgeLabel), \(previewState)"
    }

    @ViewBuilder
    private func directorStatusFooter(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 6) {
                directorIdentity
                Text(directorStatusDetail)
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Return sends · Shift-Return adds a line")
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.tertiary)
            }
        } else {
            HStack(spacing: 7) {
                directorIdentity
                Text(directorStatusDetail)
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text("Return sends · Shift-Return adds a line")
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var directorIdentity: some View {
        Label(
            directorStatusLabel,
            systemImage: directorNode?.status == .working ? "bolt.fill" : "scope"
        )
            .font(WorkspacePageTypography.metadata)
            .foregroundStyle(directorStatusTone.color)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(directorStatusTone.color.opacity(0.08), in: Capsule())
    }

    private func observedStatusLabel(_ label: String) -> String {
        if controller.snapshotIsAuthoritative { return label }
        return controller.lastSuccessfulRefreshAt == nil ? "\(label) · unavailable" : "\(label) · last known"
    }

    private var connectionTone: WorkspaceStatusTone {
        switch controller.state {
        case .stopped: .neutral
        case .checking: .working
        case .connected: .success
        case .offline: .warning
        case .failed: .danger
        }
    }

    private var disconnectedMessage: String {
        if controller.lastSuccessfulRefreshAt != nil {
            return "\(controller.detail). Scene, stream, and recording values below are labeled as last known until a fresh snapshot arrives."
        }
        return controller.detail
    }

    private var recordingTone: WorkspaceStatusTone {
        guard controller.snapshotIsAuthoritative else { return .warning }
        if controller.recording?.active == true { return .live }
        return controller.recording == nil ? .neutral : .success
    }

    private var streamTone: WorkspaceStatusTone {
        guard controller.snapshotIsAuthoritative else { return .warning }
        if controller.stream?.reconnecting == true { return .warning }
        if controller.stream?.active == true { return .live }
        return .neutral
    }

    private var previewTone: WorkspaceStatusTone {
        switch preview.state {
        case .idle: .neutral
        case .requestingPermission, .connecting: .working
        case .live: .success
        case .unavailable: .warning
        case .denied: .danger
        }
    }

    private var directorStatusLabel: String {
        guard let node = directorNode else { return "Ready to create" }
        switch node.status {
        case .idle: return "Ready"
        case .working: return "Working"
        case .complete: return "Complete"
        case .needsAttention: return "Needs attention"
        }
    }

    private var directorStatusTone: WorkspaceStatusTone {
        guard let node = directorNode else { return .info }
        switch node.status {
        case .idle: return .success
        case .working: return .working
        case .complete: return .success
        case .needsAttention: return .warning
        }
    }

    private var directorStatusDetail: String {
        guard let node = directorNode else {
            return "Your first command creates a dedicated Codex session."
        }
        switch node.status {
        case .working: return "The Director is working; you can draft the next command while it finishes."
        case .needsAttention: return "Open the Director log for the latest interruption."
        case .complete: return "The last command completed; evidence is available in the log."
        case .idle: return "Ready for a scene, recording, status, or readiness request."
        }
    }

    private var canSubmitDirectorCommand: Bool {
        !directorCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && directorNode?.status != .working
    }

    private func sceneActionHelp(for scene: ClawStudioOBSScene, selected: Bool) -> String {
        if selected { return "\(scene.name) is already on Program." }
        if controller.busy { return "Wait for \(controller.busyAction ?? "the current OBS action") to finish." }
        if !controller.connected { return "Reconnect OBS before taking a scene." }
        if controller.selectedProductionID == nil { return "Choose a production before taking a scene." }
        return "Take \(scene.name) to Program."
    }

    private func openCameraPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") else { return }
        NSWorkspace.shared.open(url)
    }

    private func revealLastTake() {
        guard let lastTake = controller.lastTake else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: lastTake)])
    }

    private var recordingLabel: String {
        guard let recording = controller.recording else { return "Unavailable" }
        if recording.active { return recording.paused ? "Paused" : "Recording" }
        return "Ready"
    }

    private var streamLabel: String {
        guard let stream = controller.stream else { return "Unavailable" }
        if stream.active { return stream.reconnecting ? "Reconnecting" : "Live" }
        return "Offline"
    }

    private var recordingHelp: String {
        if controller.recording?.active == true,
           controller.recording?.productionId != controller.selectedProductionID {
            return "The active recording belongs to another production. Open that production in ClawStudio to stop it safely."
        }
        return controller.recording?.active == true
            ? "Stop only after the take is complete."
            : "Uses the selected production and current program scene."
    }
}

private struct OBSDirectorSuggestion: Identifiable {
    let title: String
    let detail: String
    let icon: String
    let command: String

    var id: String { title }

    static let defaults: [OBSDirectorSuggestion] = [
        OBSDirectorSuggestion(
            title: "Full preflight",
            detail: "Check the scene, camera, production, and recording readiness.",
            icon: "checklist",
            command: "Run a complete stream preflight. Verify the current program scene, ClawStudio connection, virtual-camera readiness, selected production, and recording state. Report the most important fixes first. Do not start streaming or recording."
        ),
        OBSDirectorSuggestion(
            title: "Discord-ready VTuber",
            detail: "Prepare the strongest available scene for Discord.",
            icon: "person.crop.rectangle",
            command: "Prepare the cleanest available VTuber scene for Discord. Prefer VTuber Studio V2 when it is healthy, confirm the final program scene, and verify virtual-camera readiness. Do not start a public stream or recording."
        ),
        OBSDirectorSuggestion(
            title: "Choose my best scene",
            detail: "Review available scenes and recommend the strongest option.",
            icon: "rectangle.3.group",
            command: "Inspect the available OBS scenes and recommend the best one for a polished VTuber presentation. Explain the choice briefly, but do not switch scenes yet."
        ),
        OBSDirectorSuggestion(
            title: "Composition audit",
            detail: "Check framing, clutter, readability, and visual hierarchy.",
            icon: "viewfinder",
            command: "Audit the current stream composition for professional VTuber presentation: character framing, safe margins, visual clutter, overlay readability, and focal hierarchy. Make safe supported improvements and clearly report anything that needs a capability not yet available. Do not go live."
        ),
        OBSDirectorSuggestion(
            title: "Background fit",
            detail: "Look for cropping, stretching, borders, or poor contrast.",
            icon: "photo.on.rectangle.angled",
            command: "Review the current background fit for Discord and OBS. Check for cropping, stretching, empty borders, distracting details, or weak contrast behind the character. Recommend the exact correction and apply it only if the audited tools support it."
        ),
        OBSDirectorSuggestion(
            title: "Audio comfort check",
            detail: "Keep speech clear and reaction sounds comfortable.",
            icon: "waveform",
            command: "Review the stream audio setup for clear speech, safe headroom, and comfortable reaction sounds. Speech should remain dominant and effects should not sound sharp or piercing. Report recommended level, limiter, and EQ changes; use only supported audited controls."
        ),
        OBSDirectorSuggestion(
            title: "Recording preflight",
            detail: "Confirm a clean take can be recorded safely.",
            icon: "record.circle",
            command: "Verify the correct ClawStudio production and current OBS program scene for a clean recorded take. Report whether recording can safely begin, but do not start it yet."
        ),
        OBSDirectorSuggestion(
            title: "Status snapshot",
            detail: "Summarize the live scene and all important states.",
            icon: "gauge.with.dots.needle.50percent",
            command: "Give me a concise control-room status: current program scene, selected production, virtual-camera readiness, recording state, stream state, and any blocker that needs attention. Do not change anything."
        )
    ]
}

private enum RecordingConfirmation: String, Identifiable {
    case start
    case stop
    var id: String { rawValue }
}

enum OBSDirectorPrompt {
    static func task(
        for rawCommand: String,
        selectedProductionID: String? = nil,
        currentScene: ClawStudioOBSScene? = nil
    ) -> String {
        let command = normalized(rawCommand)
        let production = selectedProductionID ?? "none selected"
        let scene = currentScene.map { "\($0.name) | \($0.uuid)" } ?? "unavailable"
        return """
        You are the dedicated OBS Director for this private workstation.

        Use the configured ClawStudio Live MCP tools as the only OBS mutation boundary. Start with live_capabilities and live_context. Copy production IDs, scene names, and scene UUIDs exactly from fresh tool results. Never call OBS WebSocket directly, reveal credentials, edit OBS configuration files, or bypass ClawStudio ownership checks.

        A scene Take is allowed when requested. Start or stop recording only when the operator explicitly requests it. You may inspect and arm a stream only when explicitly requested, but never claim that arming means live and never bypass the separate HQ human confirmation required to create a public stream. If the current MCP tool set cannot perform a requested source or mixer action, explain the missing capability and recommend the narrow tool addition instead of using shell scripts as a workaround.

        The embedded control room currently shows productionId \(production) and Program scene \(scene). Treat this only as a UI hint: revalidate both through a fresh live_context result before every mutation.

        <operator_request>
        \(command)
        </operator_request>

        After acting, report the observed final scene, recording state, stream state, and any remaining confirmation.
        """
    }

    static func normalized(_ rawCommand: String) -> String {
        let noControls = rawCommand.unicodeScalars.filter { scalar in
            scalar.value == 0x0A || scalar.value == 0x09 || scalar.value >= 0x20
        }.map(String.init).joined()
        let trimmed = noControls
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return String(trimmed.prefix(2_000))
    }
}
