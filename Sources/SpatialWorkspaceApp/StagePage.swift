import AppKit
import SwiftUI
import WebKit

struct StagePage: View {
    @ObservedObject var controller: StageServiceController
    @ObservedObject var store: WorkspaceStore
    var isActive = true
    @StateObject private var standaloneTerminals = StandaloneTerminalController()
    @State private var webState = WebPreviewState.idle
    @State private var measuredStageContentFrame = CGRect.zero
    @State private var surfaceMode = StageSurfaceMode.summary
    @State private var selectedTerminalID: StageTerminalSource.ID?

    private var terminalSources: [StageTerminalSource] {
        StageTerminalCatalog.sources(in: store.activeWorkspace, standalone: standaloneTerminals.snapshots)
    }

    private var selectedTerminal: StageTerminalSource? {
        StageTerminalCatalog.selection(selectedTerminalID, in: terminalSources)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if controller.state == .ready {
                    StageWebView(
                        url: controller.configuration.operatorURL,
                        revision: controller.webRevision,
                        isPlaybackSuspended: StagePlaybackPolicy.shouldSuspend(isStageActive: isActive),
                        viewportSize: proxy.size,
                        state: $webState,
                        stageContentFrame: $measuredStageContentFrame
                    )
                }

                if surfaceMode == .terminal, let selectedTerminal {
                    let frame = StageContentFramePolicy.resolvedFrame(
                        measured: measuredStageContentFrame,
                        viewport: proxy.size
                    )
                    StageTerminalSurface(
                        store: store,
                        standalone: standaloneTerminals,
                        source: selectedTerminal
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .transition(.opacity.combined(with: .scale(scale: 0.992)))
                }

                if surfaceMode == .summary, controller.state != .ready {
                    connectionOverlay
                } else if surfaceMode == .summary, let message = webState.errorMessage {
                    webError(message)
                } else if surfaceMode == .summary, webState.isLoading {
                    webLoadingOverlay
                }

                if surfaceMode == .terminal, controller.state != .ready || webState.errorMessage != nil {
                    terminalConnectionBanner
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 18)
                }

                stageToolbar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 10)
            }
        }
        .ignoresSafeArea()
        .background(Color(red: 0.008, green: 0.012, blue: 0.026))
        .onAppear {
            controller.start()
            if isActive { standaloneTerminals.start() }
            updateStandaloneFocus()
        }
        .onChange(of: isActive) { _, active in
            if active {
                standaloneTerminals.start()
            } else {
                standaloneTerminals.stop()
            }
        }
        .onChange(of: surfaceMode) { _, _ in
            updateStandaloneFocus()
            controller.selectLocalSession(
                publishedSelection(at: Date()),
                workspace: store.activeWorkspace
            )
        }
        .onDisappear { standaloneTerminals.stop() }
        .onChange(of: terminalSources.map(\.id), initial: true) { _, sources in
            selectedTerminalID = StageTerminalCatalog.resolvedSelectionID(
                selectedTerminalID,
                sourceIDs: sources
            )
            updateStandaloneFocus()
            if sources.isEmpty, surfaceMode == .terminal { surfaceMode = .summary }
        }
        .onChange(of: selectedTerminalID) { _, _ in
            updateStandaloneFocus()
        }
        .task(id: selectedTerminalID) {
            while !Task.isCancelled {
                controller.selectLocalSession(
                    publishedSelection(at: Date()),
                    workspace: store.activeWorkspace
                )
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .accessibilityLabel("The Stage autonomous watch page")
    }

    private func publishedSelection(at now: Date) -> StageLocalPublishedSession? {
        guard surfaceMode == .terminal, let selectedTerminal else { return nil }
        switch selectedTerminal.kind {
        case .standalone:
            guard let id = selectedTerminal.standaloneID,
                  let snapshot = standaloneTerminals.snapshot(withID: id) else { return nil }
            return StageLocalPublishedSession(
                id: StageLocalPublishedSession.standaloneID(for: snapshot.tty),
                title: snapshot.title,
                provider: SessionProvider.shell.rawValue,
                runtimeState: SessionRuntimeState.attached.rawValue,
                sessionId: nil,
                lastActivityAt: snapshot.lastActivityAt,
                eventCount: snapshot.eventCount,
                minimized: false,
                activitySummary: StageTerminalActivity.summary(
                    for: snapshot.content,
                    runtimeState: SessionRuntimeState.attached.rawValue
                )
            )
        case .terminal:
            guard let nodeID = selectedTerminal.workspaceNodeID,
                  let node = store.activeWorkspace.nodes.first(where: { $0.id == nodeID }) else { return nil }
            let session = store.terminalSession(for: nodeID)
            return StageLocalPublishedSession(
                id: nodeID.uuidString.lowercased(),
                title: node.title,
                provider: SessionProvider.shell.rawValue,
                runtimeState: terminalRuntimeState(session.state).rawValue,
                sessionId: node.sessionID,
                lastActivityAt: now,
                eventCount: StageLocalSessionSnapshot.eventCount(in: session.output),
                minimized: node.isMinimizedResolved,
                activitySummary: StageTerminalActivity.summary(
                    for: session.output,
                    runtimeState: terminalRuntimeState(session.state).rawValue
                )
            )
        case .agent:
            guard let nodeID = selectedTerminal.workspaceNodeID,
                  let node = store.activeWorkspace.nodes.first(where: { $0.id == nodeID }) else { return nil }
            return StageLocalPublishedSession(
                id: nodeID.uuidString.lowercased(),
                title: node.title,
                provider: node.resolvedProvider?.rawValue ?? SessionProvider.shell.rawValue,
                runtimeState: store.sessionRuntimeState(for: node).rawValue,
                sessionId: node.sessionID,
                lastActivityAt: node.runtimeUpdatedAt ?? now,
                eventCount: StageLocalSessionSnapshot.eventCount(in: node.activityLog),
                minimized: node.isMinimizedResolved,
                activitySummary: StageTerminalActivity.summary(
                    for: node.activityLog ?? "",
                    runtimeState: store.sessionRuntimeState(for: node).rawValue
                )
            )
        }
    }

    private func updateStandaloneFocus() {
        standaloneTerminals.setFocusedSessionID(
            surfaceMode == .terminal ? selectedTerminal?.standaloneID : nil
        )
    }

    private func terminalRuntimeState(_ state: TerminalSession.SessionState) -> SessionRuntimeState {
        switch state {
        case .idle: .idle
        case .running: .attached
        case .exited: .exited
        case .failed: .unavailable
        }
    }

    private var stageToolbar: some View {
        HStack(spacing: 5) {
            ForEach(StageSurfaceMode.allCases) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { surfaceMode = mode }
                } label: {
                    Label(mode.label, systemImage: mode.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .foregroundStyle(surfaceMode == mode ? Color.white.opacity(0.92) : Color.white.opacity(0.55))
                        .background(
                            surfaceMode == mode ? Color.white.opacity(0.11) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                }
                .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 7))
                .disabled(mode == .terminal && terminalSources.isEmpty)
                .opacity(mode == .terminal && terminalSources.isEmpty ? 0.38 : 1)
                .accessibilityLabel("Show \(mode.label.lowercased())")
            }

            if surfaceMode == .terminal, let selectedTerminal {
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)

                Menu {
                    ForEach(terminalSources) { source in
                        Button {
                            selectedTerminalID = source.id
                        } label: {
                            Label(source.title, systemImage: source.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: selectedTerminal.symbol)
                        Text(selectedTerminal.title)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Choose terminal session")
                    .help("Choose a standalone Terminal tab or a live Workspace session")
            }

            if controller.state != .ready {
                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(controller.state.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 2)

            stageButton("arrow.up.left.and.arrow.down.right", label: "Toggle full screen", action: toggleFullscreen)

            Menu {
                Button("Reconnect to Spark", systemImage: "arrow.clockwise", action: controller.reconnect)
                Button("Reload Stage", systemImage: "arrow.triangle.2.circlepath", action: controller.reloadPage)
                Divider()
                Button("Open in Browser", systemImage: "safari", action: controller.openInBrowser)
                Button("Copy OBS Overlay URL", systemImage: "rectangle.on.rectangle", action: controller.copyOBSSource)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Stage options")
            .help("Stage options")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.09)))
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
    }

    private var connectionOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .tint(statusColor)
            Text(controller.state.label)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text(controller.detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if case .failed = controller.state {
                Button("Try again", action: controller.reconnect)
                    .buttonStyle(.borderedProminent)
                    .tint(WorkspaceVisualStyle.accent)
            }
        }
        .padding(22)
        .frame(maxWidth: 340)
        .stageStatusSurface()
    }

    private func webError(_ message: String) -> some View {
        VStack(spacing: 11) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 20))
                .foregroundStyle(.orange)
            Text("Stage unavailable")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Reload", action: controller.reloadPage)
                .buttonStyle(.borderedProminent)
                .tint(WorkspaceVisualStyle.accent)
        }
        .padding(22)
        .frame(maxWidth: 340)
        .stageStatusSurface()
    }

    private var webLoadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView(value: webState.estimatedProgress)
                .progressViewStyle(.linear)
                .tint(WorkspaceVisualStyle.cyan)
                .frame(width: 190)
            Text("Loading Stage display…")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .padding(20)
        .frame(maxWidth: 320)
        .stageStatusSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Stage display")
    }

    private var terminalConnectionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
            Text("Terminal view is local. Stage summary is reconnecting in the background.")
                .font(.system(size: 10, weight: .medium))
            Button("Reconnect", action: controller.reconnect)
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WorkspaceVisualStyle.cyan)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(.orange.opacity(0.22)))
        .accessibilityElement(children: .combine)
    }

    private func stageButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(WorkspaceHoverButtonStyle(cornerRadius: 7))
        .accessibilityLabel(label)
        .help(label)
    }

    private var statusColor: Color {
        switch controller.state {
        case .ready: Color(red: 0.30, green: 0.90, blue: 0.62)
        case .failed: Color(red: 0.98, green: 0.43, blue: 0.39)
        case .degraded: Color.orange
        default: WorkspaceVisualStyle.cyan
        }
    }

    private func toggleFullscreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }
}

private extension View {
    func stageStatusSurface() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.09)))
            .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}

enum StageOperatorFocusStyle {
    static let injectionScript = #"""
    (() => {
      const styleID = "command-hall-stage-focus";
      if (document.getElementById(styleID)) return;
      document.documentElement.dataset.commandHallFocus = "true";
      const style = document.createElement("style");
      style.id = styleID;
      style.textContent = `
        :root[data-command-hall-focus="true"] {
          --stage-panel-border: rgba(255, 255, 255, 0.09);
        }

        :root[data-command-hall-focus="true"] body,
        :root[data-command-hall-focus="true"] #root {
          background: #0b0e13 !important;
        }

        :root[data-command-hall-focus="true"] .stage-ambient::before,
        :root[data-command-hall-focus="true"] .os-panel-grain,
        :root[data-command-hall-focus="true"] [data-testid="show-effects-layer"],
        :root[data-command-hall-focus="true"] [data-testid="stage-game-layer-root"],
        :root[data-command-hall-focus="true"] [data-testid="code-river"],
        :root[data-command-hall-focus="true"] [data-testid="stage-marquee-header"],
        :root[data-command-hall-focus="true"] [data-testid="watching-chip-positionable"],
        :root[data-command-hall-focus="true"] [data-testid="dashboard-stage-xp-target"],
        :root[data-command-hall-focus="true"] [data-testid="stage-explain-ribbon"],
        :root[data-command-hall-focus="true"] [data-testid="obs-director-positionable"],
        :root[data-command-hall-focus="true"] [data-testid="recent-moments-section"],
        :root[data-command-hall-focus="true"] [data-testid="recent-moments-section"] ~ .amc-scroll-panel,
        :root[data-command-hall-focus="true"] [data-testid="mission-pulse-grid"] {
          display: none !important;
        }

        :root[data-command-hall-focus="true"] [data-testid="panel-trim"] {
          opacity: 0.18 !important;
        }

        :root[data-command-hall-focus="true"] .amc-panel,
        :root[data-command-hall-focus="true"] .stage-panel {
          border-color: var(--stage-panel-border) !important;
          box-shadow: 0 12px 28px rgba(0, 0, 0, 0.2) !important;
        }

        :root[data-command-hall-focus="true"] [data-testid="live-dashboard-grid"] {
          gap: 12px !important;
          padding: 12px !important;
        }

        :root[data-command-hall-focus="true"] [data-testid="dashboard-center-stage"] {
          padding-top: 54px !important;
        }

        :root[data-command-hall-focus="true"] [data-testid="dashboard-chrome-controls"] {
          position: fixed !important;
          top: auto !important;
          right: 14px !important;
          bottom: 14px !important;
          border-color: rgba(255, 255, 255, 0.08) !important;
          background: rgba(11, 14, 19, 0.78) !important;
          box-shadow: none !important;
          opacity: 0.16;
          transition: opacity 160ms ease;
        }

        :root[data-command-hall-focus="true"] [data-testid="dashboard-chrome-controls"]:hover,
        :root[data-command-hall-focus="true"] [data-testid="dashboard-chrome-controls"]:focus-within {
          opacity: 1;
        }

        :root[data-command-hall-focus="true"] [data-testid="bilbro-gutter"] {
          filter: saturate(0.88);
        }

        :root[data-command-hall-focus="true"] .bilbro-frame {
          border-color: rgba(255, 255, 255, 0.1) !important;
          box-shadow: none !important;
        }

        :root[data-command-hall-focus="true"] [data-testid="mission-telemetry-grid"] {
          grid-template-columns: repeat(4, minmax(0, 1fr)) !important;
        }

        @media (prefers-reduced-motion: reduce) {
          :root[data-command-hall-focus="true"] [data-testid="dashboard-chrome-controls"] {
            transition: none;
          }
        }
      `;
      document.head.appendChild(style);
    })();
    """#
}

private struct StageWebView: NSViewRepresentable {
    let url: URL
    let revision: Int
    let isPlaybackSuspended: Bool
    let viewportSize: CGSize
    @Binding var state: WebPreviewState
    @Binding var stageContentFrame: CGRect

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: StageOperatorFocusStyle.injectionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.onStageContentFrameChange = { frame in
            if stageContentFrame != frame { stageContentFrame = frame }
        }
        context.coordinator.lastRevision = revision
        context.coordinator.lastViewportSize = viewportSize
        context.coordinator.setPlaybackSuspended(isPlaybackSuspended, in: webView)
        webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onStateChange = { next in
            if state != next { state = next }
        }
        context.coordinator.onStageContentFrameChange = { frame in
            if stageContentFrame != frame { stageContentFrame = frame }
        }
        context.coordinator.setPlaybackSuspended(isPlaybackSuspended, in: webView)
        context.coordinator.updateViewport(viewportSize, in: webView)
        if context.coordinator.lastRevision != revision {
            context.coordinator.lastRevision = revision
            webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onStateChange: { next in
                if state != next { state = next }
            },
            onStageContentFrameChange: { frame in
                if stageContentFrame != frame { stageContentFrame = frame }
            }
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        weak var webView: WKWebView?
        var lastRevision = 0
        var lastViewportSize = CGSize.zero
        var playbackSuspended: Bool?
        var fitTask: Task<Void, Never>?
        var onStateChange: (WebPreviewState) -> Void
        var onStageContentFrameChange: (CGRect) -> Void

        init(
            onStateChange: @escaping (WebPreviewState) -> Void,
            onStageContentFrameChange: @escaping (CGRect) -> Void
        ) {
            self.onStateChange = onStateChange
            self.onStageContentFrameChange = onStageContentFrameChange
        }

        func setPlaybackSuspended(_ suspended: Bool, in webView: WKWebView) {
            guard playbackSuspended != suspended else { return }
            playbackSuspended = suspended
            Task { await webView.setAllMediaPlaybackSuspended(suspended) }
        }

        func updateViewport(_ size: CGSize, in webView: WKWebView) {
            guard abs(size.width - lastViewportSize.width) > 2 || abs(size.height - lastViewportSize.height) > 2 else {
                return
            }
            lastViewportSize = size
            scheduleFit(in: webView)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            publish(isLoading: true, error: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            publish(isLoading: false, error: nil)
            scheduleFit(in: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            publishFailure(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            publishFailure(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if destination.host != "127.0.0.1", destination.scheme != "about" {
                NSWorkspace.shared.open(destination)
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let destination = navigationAction.request.url {
                NSWorkspace.shared.open(destination)
            }
            return nil
        }

        private func publish(isLoading: Bool, error: String?) {
            guard let webView else { return }
            onStateChange(
                WebPreviewState(
                    currentURL: webView.url?.absoluteString,
                    title: webView.title,
                    canGoBack: webView.canGoBack,
                    canGoForward: webView.canGoForward,
                    isLoading: isLoading,
                    estimatedProgress: webView.estimatedProgress,
                    errorMessage: error
                )
            )
        }

        private func publishFailure(_ error: Error) {
            let nsError = error as NSError
            guard nsError.code != NSURLErrorCancelled else { return }
            publish(isLoading: false, error: nsError.localizedDescription)
        }

        private func scheduleFit(in webView: WKWebView) {
            fitTask?.cancel()
            fitTask = Task { @MainActor [weak self, weak webView] in
                try? await Task.sleep(nanoseconds: 220_000_000)
                guard !Task.isCancelled, let self, let webView else { return }
                self.fitPage(in: webView)
            }
        }

        private func fitPage(in webView: WKWebView) {
            webView.pageZoom = 1
            let script = "Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight || 0)"
            webView.evaluateJavaScript(script) { [weak webView] value, _ in
                guard let webView, let contentHeight = (value as? NSNumber)?.doubleValue else { return }
                webView.pageZoom = StageFitPolicy.zoom(
                    viewportHeight: webView.bounds.height,
                    contentHeight: contentHeight
                )
                Task { @MainActor [weak self, weak webView] in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard let self, let webView else { return }
                    self.publishStageContentFrame(in: webView)
                }
            }
        }

        private func publishStageContentFrame(in webView: WKWebView) {
            let script = """
            (() => {
              const element = document.querySelector('[data-testid="stage-terminal"]');
              if (!element) return null;
              const rect = element.getBoundingClientRect();
              return {
                x: rect.left,
                y: rect.top,
                width: rect.width,
                height: rect.height,
                viewportWidth: window.innerWidth,
                viewportHeight: window.innerHeight
              };
            })()
            """
            webView.evaluateJavaScript(script) { [weak self, weak webView] value, _ in
                guard let self,
                      let webView,
                      let values = value as? [String: NSNumber],
                      let metrics = StageDOMFrameMetrics(values: values) else { return }
                let frame = StageContentFramePolicy.project(metrics: metrics, viewport: webView.bounds.size)
                guard frame.width > 100, frame.height > 100 else { return }
                self.onStageContentFrameChange(frame)
            }
        }
    }
}

enum StagePlaybackPolicy {
    static func shouldSuspend(isStageActive: Bool) -> Bool {
        !isStageActive
    }
}

enum StageFitPolicy {
    static let minimumZoom = 0.72

    static func zoom(viewportHeight: CGFloat, contentHeight: Double) -> Double {
        guard viewportHeight > 0, contentHeight > 0 else { return 1 }
        let availableHeight = max(0, Double(viewportHeight) - 8)
        return min(1, max(minimumZoom, availableHeight / contentHeight))
    }
}

struct StageDOMFrameMetrics: Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    let viewportWidth: CGFloat
    let viewportHeight: CGFloat

    init? (values: [String: NSNumber]) {
        guard let x = values["x"],
              let y = values["y"],
              let width = values["width"],
              let height = values["height"],
              let viewportWidth = values["viewportWidth"],
              let viewportHeight = values["viewportHeight"],
              viewportWidth.doubleValue > 0,
              viewportHeight.doubleValue > 0 else { return nil }
        self.x = x.doubleValue
        self.y = y.doubleValue
        self.width = width.doubleValue
        self.height = height.doubleValue
        self.viewportWidth = viewportWidth.doubleValue
        self.viewportHeight = viewportHeight.doubleValue
    }

    init(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        viewportWidth: CGFloat,
        viewportHeight: CGFloat
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.viewportWidth = viewportWidth
        self.viewportHeight = viewportHeight
    }
}

enum StageContentFramePolicy {
    static func project(metrics: StageDOMFrameMetrics, viewport: CGSize) -> CGRect {
        let xScale = viewport.width / metrics.viewportWidth
        let yScale = viewport.height / metrics.viewportHeight
        return CGRect(
            x: metrics.x * xScale,
            y: metrics.y * yScale,
            width: metrics.width * xScale,
            height: metrics.height * yScale
        )
    }

    static func resolvedFrame(measured: CGRect, viewport: CGSize) -> CGRect {
        guard measured.width > 100,
              measured.height > 100,
              measured.maxX <= viewport.width + 2,
              measured.maxY <= viewport.height + 2 else {
            return CGRect(
                x: viewport.width * 0.07,
                y: viewport.height * 0.19,
                width: viewport.width * 0.88,
                height: viewport.height * 0.71
            )
        }
        return measured
    }
}
