import SwiftUI

enum VTuberPageNavigation {
    static func isControlPanel(_ currentURL: String?, controlsURL: URL) -> Bool {
        guard let currentURL else { return true }
        guard let current = URLComponents(string: currentURL),
              let controls = URLComponents(url: controlsURL, resolvingAgainstBaseURL: false) else {
            return false
        }

        let panel = current.queryItems?.first(where: { $0.name == "panel" })?.value
        return current.scheme?.lowercased() == controls.scheme?.lowercased()
            && current.host?.lowercased() == controls.host?.lowercased()
            && current.port == controls.port
            && current.path == controls.path
            && panel == "1"
    }

    static func shouldOfferReturn(
        currentURL: String?,
        controlsURL: URL,
        isContainedFullscreen: Bool
    ) -> Bool {
        isContainedFullscreen || !isControlPanel(currentURL, controlsURL: controlsURL)
    }
}

struct VTuberControlsPage: View {
    @ObservedObject var controller: VTuberServiceController
    let theme: WorkspaceTheme
    @Binding var isContainedFullscreen: Bool
    let exitFullscreenRequest: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var webState = WebPreviewState.idle
    @State private var webCommand: WebPreviewCommand?

    var body: some View {
        WorkspacePageScaffold(theme: theme, mode: .immersive) {
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: isContainedFullscreen ? 0 : WorkspacePageMetrics.sectionSpacing) {
                    if !isContainedFullscreen {
                        pageHeader

                        if controller.state == .degraded {
                            degradedAlert
                        }
                    }

                    studioSurface
                }
                .padding(.horizontal, isContainedFullscreen ? 0 : horizontalInset(for: proxy.size.width))
                .padding(.top, WorkspacePageMetrics.topInset)
                .padding(.bottom, isContainedFullscreen ? 0 : 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isContainedFullscreen)
            }
        }
        .onAppear {
            isContainedFullscreen = false
            controller.start()
        }
        .onDisappear {
            isContainedFullscreen = false
            controller.stop()
        }
        .onChange(of: exitFullscreenRequest) { _, _ in
            guard isContainedFullscreen else { return }
            returnToControls()
        }
        .accessibilityLabel("VTuber Studio controls")
    }

    private var pageHeader: some View {
        WorkspacePageHeader(
            eyebrow: "Creator studio",
            symbol: "person.crop.rectangle.fill",
            title: "VTuber",
            subtitle: "Shape the live character, verify its camera-free output, and keep the renderer ready for OBS.",
            accent: theme.accent
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    healthPills
                    pageActions
                }

                VStack(alignment: .trailing, spacing: 8) {
                    healthPills
                    pageActions
                }
            }
        }
    }

    private var healthPills: some View {
        ViewThatFits(in: .horizontal) {
            healthPillRow
            VStack(alignment: .trailing, spacing: 7) {
                healthPillRow
            }
        }
    }

    private var healthPillRow: some View {
        HStack(spacing: 7) {
            WorkspaceStatusPill(
                controller.state.label,
                tone: connectionTone,
                symbol: connectionSymbol
            )

            if let health = controller.health {
                WorkspaceStatusPill(
                    "Camera",
                    detail: health.cameraStatus?.cameraLabel ?? health.cameraStatus?.state.capitalized,
                    tone: health.cameraStatus?.state == "ready" ? .success : .warning,
                    symbol: "camera.fill"
                )
                .frame(maxWidth: 190)
                WorkspaceStatusPill(
                    "Output",
                    detail: "\(health.rendererConnections) renderer\(health.rendererConnections == 1 ? "" : "s")",
                    tone: health.streamStatus == "live" && health.rendererConnections > 0 ? .success : .warning,
                    symbol: "rectangle.on.rectangle.angled"
                )
                .frame(maxWidth: 170)
            }
        }
    }

    private var pageActions: some View {
        HStack(spacing: 2) {
            if showsReturnToControls {
                returnButton
            }
            WorkspaceIconButton(
                symbol: controller.stackPoweredOff ? "power.circle" : "power.circle.fill",
                label: controller.stackPoweredOff
                    ? "Power the VTuber stack on"
                    : "Power the VTuber stack off to free CPU and memory",
                isActive: !controller.stackPoweredOff,
                showsHoverLabel: true,
                hoverCalloutPlacement: .below,
                action: controller.stackPoweredOff ? controller.powerOnStack : controller.powerOffStack
            )
            WorkspaceIconButton(
                symbol: "arrow.clockwise",
                label: "Reconnect to VTuber Studio",
                showsHoverLabel: true,
                hoverCalloutPlacement: .below,
                action: controller.reconnect
            )
            WorkspaceIconButton(
                symbol: "arrow.triangle.2.circlepath",
                label: "Reload VTuber controls",
                showsHoverLabel: true,
                hoverCalloutPlacement: .below,
                action: controller.reloadPage
            )
            WorkspaceIconButton(
                symbol: "video.fill",
                label: "Open camera-free VTuber preview in browser",
                showsHoverLabel: true,
                hoverCalloutPlacement: .below,
                action: controller.openStudioInBrowser
            )
            WorkspaceIconButton(
                symbol: "safari",
                label: "Open VTuber controls in browser",
                showsHoverLabel: true,
                hoverCalloutPlacement: .below,
                action: controller.openControlsInBrowser
            )
        }
        .workspaceTopToolbar()
    }

    private var returnButton: some View {
        Button(action: returnToControls) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 11, weight: .bold))
                Text("Controls")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text("esc")
                    .font(WorkspacePageTypography.metadata)
                    .foregroundStyle(.white.opacity(0.58))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(theme.accent.opacity(0.22), in: Capsule())
            .overlay(Capsule().stroke(theme.accent.opacity(0.48), lineWidth: 1))
        }
        .buttonStyle(WorkspacePressButtonStyle())
        .accessibilityLabel("Back to VTuber controls")
        .accessibilityHint("Returns from the large preview to character settings")
        .help("Back to VTuber controls · Escape")
    }

    private var studioSurface: some View {
        ZStack {
            WebPreview(
                urlString: controller.configuration.embeddedControlsURL.absoluteString,
                revision: controller.webRevision,
                state: $webState,
                isContainedFullscreen: $isContainedFullscreen,
                command: webCommand
            )

            if !controller.state.canShowControls {
                connectionOverlay
            } else if let message = webState.errorMessage {
                webError(message)
            }

            if isContainedFullscreen, showsReturnToControls {
                returnButton
                    .padding(6)
                    .workspaceTopToolbar()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, 10)
                    .padding(.trailing, 14)
                    .zIndex(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(
            RoundedRectangle(
                cornerRadius: isContainedFullscreen ? 0 : 18,
                style: .continuous
            )
        )
        .workspaceSectionCard(
            padding: 0,
            cornerRadius: isContainedFullscreen ? 0 : 18,
            tintOpacity: isContainedFullscreen ? 0 : 0.68
        )
        .accessibilityElement(children: .contain)
    }

    private var showsReturnToControls: Bool {
        VTuberPageNavigation.shouldOfferReturn(
            currentURL: webState.currentURL,
            controlsURL: controller.configuration.embeddedControlsURL,
            isContainedFullscreen: isContainedFullscreen
        )
    }

    private func returnToControls() {
        isContainedFullscreen = false
        webCommand = WebPreviewCommand(
            action: .navigate(controller.configuration.embeddedControlsURL.absoluteString)
        )
    }

    private var degradedAlert: some View {
        WorkspaceInlineAlert(
            title: "The studio needs attention",
            message: controller.detail,
            tone: .warning,
            symbol: "exclamationmark.triangle.fill"
        ) {
            Button("Check again", action: controller.reconnect)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var connectionOverlay: some View {
        ZStack {
            Color.black.opacity(0.34)
            VStack(spacing: 15) {
                ZStack {
                    Circle()
                        .fill(connectionTone.color.opacity(0.08))
                        .overlay(Circle().stroke(connectionTone.color.opacity(0.26)))
                        .frame(width: 72, height: 72)
                    if controller.state == .checking {
                        ProgressView().controlSize(.small).tint(connectionTone.color)
                    } else {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(connectionTone.color)
                    }
                }
                Text(controller.state.label)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text(controller.detail)
                    .font(WorkspacePageTypography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                HStack(spacing: 8) {
                    Button("Try again", action: controller.reconnect)
                        .buttonStyle(.borderedProminent)
                        .tint(theme.accent)
                    if controller.canLaunchStudio {
                        Button("Open VTuber Studio", action: controller.launchStudio)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(26)
            .workspaceGlassPanel(cornerRadius: 20, tintOpacity: 0.82, shadowRadius: 24)
        }
    }

    private func webError(_ message: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 25))
                .foregroundStyle(.orange)
            Text("VTuber controls did not load")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(WorkspacePageTypography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reload", action: controller.reloadPage)
                .buttonStyle(.borderedProminent)
                .tint(theme.accent)
        }
        .padding(22)
        .frame(maxWidth: 360)
        .workspaceGlassPanel(cornerRadius: 18, tintOpacity: 0.78, shadowRadius: 24)
    }

    private func horizontalInset(for width: CGFloat) -> CGFloat {
        width < 1_180 ? 18 : WorkspacePageMetrics.horizontalInset
    }

    private var connectionTone: WorkspaceStatusTone {
        switch controller.state {
        case .ready: .success
        case .degraded: .warning
        case .offline: .danger
        case .checking: .working
        case .stopped: .neutral
        }
    }

    private var connectionSymbol: String {
        switch controller.state {
        case .ready: "video.fill"
        case .degraded: "exclamationmark.triangle.fill"
        case .offline: "video.slash.fill"
        case .checking: "arrow.triangle.2.circlepath"
        case .stopped: "pause.circle.fill"
        }
    }
}
