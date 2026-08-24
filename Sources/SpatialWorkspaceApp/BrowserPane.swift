import SwiftUI

struct BrowserPane: View {
    let node: WorkspaceNode
    let onNavigate: (String) -> Void
    let onRefresh: () -> Void
    let usesFullDisplay: Bool
    let onRequestFullDisplay: () -> Void
    @Binding var isContainedFullscreen: Bool

    @State private var address: String
    @State private var browserState = WebPreviewState.idle
    @State private var command: WebPreviewCommand?
    @State private var pageZoom = 1.0
    @State private var theaterToolbarRevealed = false
    @FocusState private var addressFocused: Bool

    init(
        node: WorkspaceNode,
        isContainedFullscreen: Binding<Bool> = .constant(false),
        usesFullDisplay: Bool = false,
        onNavigate: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void,
        onRequestFullDisplay: @escaping () -> Void = {}
    ) {
        self.node = node
        self.onNavigate = onNavigate
        self.onRefresh = onRefresh
        self.usesFullDisplay = usesFullDisplay
        self.onRequestFullDisplay = onRequestFullDisplay
        _isContainedFullscreen = isContainedFullscreen
        _address = State(initialValue: node.url ?? "about:blank")
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isContainedFullscreen { browserToolbar }
            ZStack {
                WebPreview(
                    urlString: node.url ?? "about:blank",
                    revision: node.revision,
                    state: $browserState,
                    isContainedFullscreen: $isContainedFullscreen,
                    pageZoom: pageZoom,
                    command: command
                )

                if isBlank {
                    browserStart
                } else if let errorMessage = browserState.errorMessage {
                    browserError(errorMessage)
                }

                if isContainedFullscreen {
                    HStack(spacing: 7) {
                        if !usesFullDisplay {
                            Button(action: onRequestFullDisplay) {
                                Label("Full display", systemImage: "arrow.up.left.and.arrow.down.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().stroke(.white.opacity(0.22)))
                            }
                            .buttonStyle(.plain)
                            .help("Show only this video across the entire display")
                        }
                        Button {
                            command = WebPreviewCommand(action: .exitContainedFullscreen)
                        } label: {
                            Label(usesFullDisplay ? "Exit full display" : "Exit video", systemImage: "arrow.down.right.and.arrow.up.left")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(Capsule().stroke(.white.opacity(0.22)))
                        }
                        .buttonStyle(.plain)
                        .help(usesFullDisplay ? "Return to the featured workspace" : "Return to the regular workspace")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, theaterToolbarRevealed || addressFocused ? 50 : 10)
                    .padding(.trailing, 10)
                    .help("Return to browser controls")

                    if theaterToolbarRevealed || addressFocused {
                        browserToolbar
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .zIndex(2)
                    } else {
                        Capsule()
                            .fill(.white.opacity(0.28))
                            .frame(width: 42, height: 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 5)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard isContainedFullscreen else {
                theaterToolbarRevealed = false
                return
            }
            switch phase {
            case let .active(location):
                let shouldReveal = location.y <= 58 || addressFocused
                guard shouldReveal != theaterToolbarRevealed else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    theaterToolbarRevealed = shouldReveal
                }
            case .ended:
                if !addressFocused, theaterToolbarRevealed {
                    withAnimation(.easeOut(duration: 0.16)) {
                        theaterToolbarRevealed = false
                    }
                }
            }
        }
        .onChange(of: node.url) { _, newValue in
            address = newValue ?? "about:blank"
        }
        .onChange(of: browserState.currentURL) { _, currentURL in
            guard let currentURL, !addressFocused else { return }
            address = currentURL
        }
        .accessibilityLabel("Browser preview")
    }

    private var browserToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                browserButton("chevron.left", label: "Back", disabled: !browserState.canGoBack) {
                    command = WebPreviewCommand(action: .back)
                }
                browserButton("chevron.right", label: "Forward", disabled: !browserState.canGoForward) {
                    command = WebPreviewCommand(action: .forward)
                }
                browserButton(browserState.isLoading ? "xmark" : "arrow.clockwise", label: browserState.isLoading ? "Stop loading" : "Reload") {
                    if browserState.isLoading {
                        command = WebPreviewCommand(action: .stop)
                    } else {
                        onRefresh()
                    }
                }

                HStack(spacing: 7) {
                    Image(systemName: addressSymbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(address.hasPrefix("https://") ? Color.green.opacity(0.82) : .secondary)
                    TextField("Search or enter an address", text: $address)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .focused($addressFocused)
                        .onSubmit(navigate)
                    if browserState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Loading page")
                    }
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(addressFocused ? WorkspaceVisualStyle.cyan.opacity(0.55) : .white.opacity(0.08)))

                Button(action: navigate) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(WorkspaceVisualStyle.accent.opacity(0.14), in: Circle())
                }
                .buttonStyle(WorkspacePressButtonStyle())
                .accessibilityLabel("Open address")

                Button {
                    command = WebPreviewCommand(
                        action: isContainedFullscreen ? .exitContainedFullscreen : .enterContainedFullscreen
                    )
                } label: {
                    Label(isContainedFullscreen ? "Exit theater" : "Theater", systemImage: "play.rectangle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(WorkspaceVisualStyle.browser.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(WorkspaceVisualStyle.browser.opacity(0.28)))
                }
                .buttonStyle(WorkspacePressButtonStyle())
                .accessibilityLabel(isContainedFullscreen ? "Exit browser theater mode" : "Enter browser theater mode")
                .help(isContainedFullscreen ? "Return to the regular browser tile" : "Feature this browser in a watchable 16 by 9 layout")

                braveMenu

                Menu {
                    Button("Zoom in") { changePageZoom(0.1) }
                    Button("Zoom out") { changePageZoom(-0.1) }
                    Button("Actual size") { pageZoom = 1 }
                    Divider()
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { zoom in
                        Button("\(Int(zoom * 100))%") { pageZoom = zoom }
                    }
                } label: {
                    Text("\(Int((pageZoom * 100).rounded()))%")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .frame(width: 42, height: 28)
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Web page zoom, \(Int((pageZoom * 100).rounded())) percent")
                .help("Web page zoom")
            }
            .padding(.horizontal, 8)
            .frame(height: 40)

            if browserState.isLoading {
                ProgressView(value: browserState.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(WorkspaceVisualStyle.cyan)
                    .frame(height: 1)
                    .transition(.opacity)
            } else {
                Divider().opacity(0.25)
            }
        }
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.48))
        .shadow(color: .black.opacity(isContainedFullscreen ? 0.42 : 0), radius: 18, y: 8)
    }

    private var braveMenu: some View {
        Menu {
            if BraveBrowserSupport.isInstalled {
                Button {
                    BraveBrowserSupport.open(BraveBrowserSupport.destinationURL(for: node.url))
                } label: {
                    Label("Open current page in Brave", systemImage: "arrow.up.right.square")
                }

                Button {
                    BraveBrowserSupport.open(BraveBrowserSupport.uBlockOriginStoreURL)
                } label: {
                    Label(
                        BraveBrowserSupport.isUBlockOriginInstalled ? "uBlock Origin installed" : "Install uBlock Origin",
                        systemImage: BraveBrowserSupport.isUBlockOriginInstalled ? "checkmark.shield.fill" : "shield.lefthalf.filled"
                    )
                }
                .disabled(BraveBrowserSupport.isUBlockOriginInstalled)

                Divider()
                Text("Uses your regular Brave profile, including cookies, logins, history, and extensions.")
            } else {
                Button {
                    NSWorkspace.shared.open(BraveBrowserSupport.downloadURL)
                } label: {
                    Label("Install Brave", systemImage: "square.and.arrow.down")
                }
            }
        } label: {
            Image(systemName: BraveBrowserSupport.isInstalled ? "checkmark.shield.fill" : "shield.slash")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BraveBrowserSupport.isInstalled ? Color.green.opacity(0.9) : .secondary)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.045), in: Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(BraveBrowserSupport.isInstalled ? "Brave protected browser options" : "Install Brave browser")
        .help(BraveBrowserSupport.isInstalled ? "Open in Brave with extension support" : "Install Brave for extension support")
    }

    private var browserStart: some View {
        VStack(spacing: 11) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(WorkspaceVisualStyle.cyan)
            Text("Open a page")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Enter a URL, localhost address, or search above.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Focus address bar") { addressFocused = true }
                    .buttonStyle(.bordered)
                if BraveBrowserSupport.isInstalled {
                    Button {
                        BraveBrowserSupport.open(BraveBrowserSupport.destinationURL(for: node.url))
                    } label: {
                        Label("Open Brave", systemImage: "checkmark.shield.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.green.opacity(0.72))
                }
            }
            if BraveBrowserSupport.isInstalled {
                Text("Brave keeps your saved sessions, cookies, logins, and extensions between launches.")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func browserError(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 25))
                .foregroundStyle(.orange)
            Text("Page could not load")
                .font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            HStack {
                Button("Try again") { onRefresh() }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.34, green: 0.56, blue: 0.51))
                Button("Edit address") { addressFocused = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .frame(maxWidth: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.white.opacity(0.12)))
    }

    private var isBlank: Bool {
        (node.url ?? "about:blank") == "about:blank"
    }

    private var addressSymbol: String {
        if address.hasPrefix("https://") { return "lock.fill" }
        if address.hasPrefix("file://") { return "doc.fill" }
        return "globe"
    }

    private func browserButton(
        _ symbol: String,
        label: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(disabled ? 0.015 : 0.045), in: Circle())
        }
        .buttonStyle(WorkspacePressButtonStyle())
        .disabled(disabled)
        .foregroundStyle(disabled ? .tertiary : .secondary)
        .accessibilityLabel(label)
        .help(label)
    }

    private func navigate() {
        let normalized = BrowserAddress.normalize(address)
        address = normalized
        addressFocused = false
        onNavigate(normalized)
    }

    private func changePageZoom(_ delta: Double) {
        pageZoom = min(2, max(0.5, pageZoom + delta))
    }
}

enum BrowserAddress {
    static func normalize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "about:blank" }
        if trimmed == "about:blank" || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("file://") {
            return trimmed
        }
        if trimmed.contains(".") || trimmed.hasPrefix("localhost") || trimmed.hasPrefix("127.0.0.1") {
            return "\(scheme(for: trimmed))://\(trimmed)"
        }
        return "https://www.google.com/search?q=\(trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed)"
    }

    /// Local development hosts answer only over plain HTTP; every public
    /// domain defaults to HTTPS so App Transport Security doesn't block the
    /// cleartext load (and so a bare domain behaves like it does in Safari).
    static func scheme(for address: String) -> String {
        isLocalHost(host(of: address)) ? "http" : "https"
    }

    /// The bare `host` portion of a `host[:port][/path]` authority, lowercased.
    private static func host(of address: String) -> String {
        let authority = address.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init) ?? address
        return authority.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first.map(String.init)?.lowercased() ?? ""
    }

    /// Loopback, link-local, and RFC 1918 private ranges (plus `.local`
    /// Bonjour names) are the addresses a dev server is reachable at over HTTP.
    private static func isLocalHost(_ host: String) -> Bool {
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") || host.hasSuffix(".localhost") {
            return true
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false).map { UInt8($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 != nil }) else { return false }
        let octet = parts.map { $0! }
        switch (octet[0], octet[1]) {
        case (127, _), (10, _), (0, _): return true              // loopback / private A / unspecified
        case (192, 168): return true                             // private C
        case (169, 254): return true                             // link-local
        case (172, 16...31): return true                         // private B
        default: return false
        }
    }
}
