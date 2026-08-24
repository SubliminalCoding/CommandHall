import AppKit
import SwiftUI

/// A live preview surface for things you're building in the workspace — a local
/// HTML file (loaded over `file://`) or a dev-server URL (e.g. `localhost:8777`).
/// Reload re-reads from disk / refetches, so edits show up without leaving the app.
struct PreviewPane: View {
    let node: WorkspaceNode
    let onNavigate: (String) -> Void
    let onRefresh: () -> Void

    @State private var source: String
    @State private var previewState = WebPreviewState.idle
    @State private var command: WebPreviewCommand?
    @FocusState private var sourceFocused: Bool

    init(
        node: WorkspaceNode,
        onNavigate: @escaping (String) -> Void,
        onRefresh: @escaping () -> Void
    ) {
        self.node = node
        self.onNavigate = onNavigate
        self.onRefresh = onRefresh
        _source = State(initialValue: node.url ?? "about:blank")
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ZStack {
                WebPreview(
                    urlString: node.url ?? "about:blank",
                    revision: node.revision,
                    state: $previewState,
                    command: command
                )

                if isBlank {
                    emptyState
                } else if let errorMessage = previewState.errorMessage {
                    errorView(errorMessage)
                }
            }
        }
        .onChange(of: node.url) { _, newValue in
            source = newValue ?? "about:blank"
        }
        .accessibilityLabel("Live preview")
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            iconButton(
                previewState.isLoading ? "xmark" : "arrow.clockwise",
                label: previewState.isLoading ? "Stop" : "Reload"
            ) {
                if previewState.isLoading {
                    command = WebPreviewCommand(action: .stop)
                } else {
                    onRefresh()
                }
            }

            HStack(spacing: 7) {
                Image(systemName: sourceSymbol)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("File path or localhost URL", text: $source)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .focused($sourceFocused)
                    .onSubmit(loadSource)
                if previewState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading preview")
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(sourceFocused ? WorkspaceVisualStyle.cyan.opacity(0.55) : .white.opacity(0.08))
            )

            iconButton("arrow.right", label: "Load", action: loadSource)
            iconButton("folder", label: "Choose file…", action: chooseFile)
        }
        .padding(.horizontal, 8)
        .frame(height: 40)
        .background(.ultraThinMaterial)
        .background(Color.black.opacity(0.42))
        .overlay(alignment: .bottom) {
            if previewState.isLoading {
                ProgressView(value: previewState.estimatedProgress)
                    .progressViewStyle(.linear)
                    .tint(WorkspaceVisualStyle.cyan)
                    .frame(height: 1)
            } else {
                Divider().opacity(0.25)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "play.rectangle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(WorkspaceVisualStyle.cyan)
            Text("Preview what you're building")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            Text("Choose a local HTML file, or type a dev-server address\nlike localhost:8777. Reload picks up your latest edits.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("Choose file…", action: chooseFile)
                    .buttonStyle(.borderedProminent)
                    .tint(WorkspaceVisualStyle.cyan.opacity(0.72))
                Button("Enter address") { sourceFocused = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 25))
                .foregroundStyle(.orange)
            Text("Preview could not load")
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
                Button("Choose file…", action: chooseFile)
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

    private var sourceSymbol: String {
        if source.hasPrefix("file://") || source.hasPrefix("/") || source.hasPrefix("~") { return "doc.fill" }
        if source.hasPrefix("https://") { return "lock.fill" }
        return "globe"
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.045), in: Circle())
        }
        .buttonStyle(WorkspacePressButtonStyle())
        .foregroundStyle(.secondary)
        .accessibilityLabel(label)
        .help(label)
    }

    private func loadSource() {
        let normalized = PreviewSource.normalize(source)
        source = normalized
        sourceFocused = false
        onNavigate(normalized)
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose an HTML file to preview"
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [.html]
        } else {
            panel.allowedFileTypes = ["html", "htm"]
        }
        if panel.runModal() == .OK, let url = panel.url {
            let normalized = url.absoluteString
            source = normalized
            onNavigate(normalized)
        }
    }
}

/// Turns whatever the user typed into a loadable address. Absolute filesystem
/// paths become `file://` URLs; everything else defers to the shared browser
/// address logic (which handles `localhost`, bare domains, and search).
enum PreviewSource {
    static func normalize(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "about:blank" }
        if trimmed.hasPrefix("file://") || trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            let expanded = (trimmed as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded).absoluteString
        }
        return BrowserAddress.normalize(trimmed)
    }
}
