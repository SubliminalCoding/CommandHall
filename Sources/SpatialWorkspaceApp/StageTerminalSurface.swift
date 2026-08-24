import AppKit
import Foundation
import SwiftUI

enum StageSurfaceMode: String, CaseIterable, Identifiable {
    case summary
    case terminal

    var id: String { rawValue }
    var label: String { self == .summary ? "Summary" : "Terminal" }
    var symbol: String { self == .summary ? "sparkles.rectangle.stack" : "terminal" }
}

enum StageTerminalOutputWindow {
    static let maximumCharacters = 24_000
    static let maximumLines = 400

    static func visibleTail(_ output: String) -> String {
        let characterTail = String(output.suffix(maximumCharacters))
        let lines = characterTail.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > maximumLines else { return characterTail }
        return lines.suffix(maximumLines).joined(separator: "\n")
    }
}

enum StageTerminalActivity {
    static func summary(for output: String, runtimeState: String? = nil) -> String {
        switch runtimeState {
        case SessionRuntimeState.needsYou.rawValue, SessionRuntimeState.interrupted.rawValue:
            return "The selected terminal needs attention"
        case SessionRuntimeState.unavailable.rawValue:
            return "The selected terminal is unavailable"
        case SessionRuntimeState.exited.rawValue:
            return "The selected terminal has exited"
        default:
            break
        }

        let recent = String(output.suffix(8_000)).lowercased()
        guard !recent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "The selected terminal is open and quiet"
        }
        if recent.contains("error:") || recent.contains("fatal:") || recent.contains("command not found")
            || recent.contains("permission denied") || recent.contains("traceback")
            || (recent.contains("failed") && !recent.contains("0 failed")) {
            return "The selected terminal is reporting a failure"
        }
        if recent.contains("test suite") || recent.contains("swift test") || recent.contains("vitest")
            || recent.contains("tests passed") || recent.contains("test result:") {
            return "The selected terminal is running or reporting tests"
        }
        if recent.contains("building for") || recent.contains("build complete")
            || recent.contains("compiling") || recent.contains("npm run build")
            || recent.contains("pnpm build") {
            return "The selected terminal is building"
        }
        if recent.contains("git status") || recent.contains("git commit") || recent.contains("git push")
            || recent.contains("git pull") || recent.contains("git diff") {
            return "The selected terminal is working with Git"
        }
        return "The selected terminal produced new output"
    }
}

struct StageTerminalSource: Identifiable, Equatable {
    enum ID: Hashable {
        case workspace(UUID)
        case standalone(String)
    }

    enum Kind: Equatable {
        case terminal
        case agent
        case standalone
    }

    let id: ID
    let kind: Kind
    let title: String
    let subtitle: String
    let symbol: String

    var workspaceNodeID: UUID? {
        guard case .workspace(let id) = id else { return nil }
        return id
    }

    var standaloneID: String? {
        guard case .standalone(let id) = id else { return nil }
        return id
    }
}

enum StageTerminalCatalog {
    static func sources(
        in workspace: WorkspaceDocument,
        standalone: [StandaloneTerminalSnapshot] = []
    ) -> [StageTerminalSource] {
        let workspaceSources = workspace.nodes.compactMap { node in
            if node.kind == .terminal {
                return StageTerminalSource(
                    id: .workspace(node.id),
                    kind: .terminal,
                    title: node.title,
                    subtitle: "Workspace · \(node.terminalSummary ?? node.subtitle)",
                    symbol: "terminal"
                )
            }
            if node.isCodingAgent {
                return StageTerminalSource(
                    id: .workspace(node.id),
                    kind: .agent,
                    title: node.title,
                    subtitle: "Workspace · \(node.resolvedProvider?.label ?? node.subtitle)",
                    symbol: "chevron.left.forwardslash.chevron.right"
                )
            }
            return nil
        }

        let standaloneSources = standalone.map { session in
            StageTerminalSource(
                id: .standalone(session.id),
                kind: .standalone,
                title: session.title,
                subtitle: "Terminal.app · \(session.tty)",
                symbol: "macwindow.and.cursorarrow"
            )
        }

        return (standaloneSources + workspaceSources).sorted {
            if rank($0.kind) != rank($1.kind) { return rank($0.kind) < rank($1.kind) }
            if $0.kind == .standalone {
                return $0.subtitle.localizedCaseInsensitiveCompare($1.subtitle) == .orderedAscending
            }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    static func selection(_ selectedID: StageTerminalSource.ID?, in sources: [StageTerminalSource]) -> StageTerminalSource? {
        let resolved = resolvedSelectionID(selectedID, sourceIDs: sources.map(\.id))
        return sources.first(where: { $0.id == resolved })
    }

    static func resolvedSelectionID(
        _ selectedID: StageTerminalSource.ID?,
        sourceIDs: [StageTerminalSource.ID]
    ) -> StageTerminalSource.ID? {
        if let selectedID, sourceIDs.contains(selectedID) { return selectedID }
        return sourceIDs.first
    }

    private static func rank(_ kind: StageTerminalSource.Kind) -> Int {
        switch kind {
        case .standalone: 0
        case .terminal: 1
        case .agent: 2
        }
    }
}

struct StageTerminalSurface: View {
    @ObservedObject var store: WorkspaceStore
    @ObservedObject var standalone: StandaloneTerminalController
    let source: StageTerminalSource

    private var node: WorkspaceNode? {
        guard let nodeID = source.workspaceNodeID else { return nil }
        return store.activeWorkspace.nodes.first(where: { $0.id == nodeID })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.32)
            switch source.kind {
            case .standalone:
                if let sessionID = source.standaloneID,
                   let session = standalone.snapshot(withID: sessionID) {
                    StageStandaloneTerminalView(snapshot: session)
                } else {
                    ContentUnavailableView("Terminal closed", systemImage: "macwindow.badge.xmark")
                }
            case .terminal, .agent:
                if let node {
                    switch source.kind {
                case .terminal:
                    StagePTYOutputView(session: store.terminalSession(for: node.id))
                case .agent:
                    StageAgentTranscriptView(node: node)
                case .standalone:
                    EmptyView()
                }
                } else {
                    ContentUnavailableView("Session closed", systemImage: "terminal.fill")
                }
            }
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.008, green: 0.018, blue: 0.035), .black.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WorkspaceVisualStyle.cyan.opacity(0.42), lineWidth: 1)
        )
        .shadow(color: WorkspaceVisualStyle.cyan.opacity(0.13), radius: 18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live terminal for \(source.title)")
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WorkspaceVisualStyle.cyan.opacity(0.10))
                Image(systemName: source.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WorkspaceVisualStyle.cyan)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(source.subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusColor.opacity(0.7), radius: 5)
                Text(statusLabel.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(0.6)
                Text("READ ONLY")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(.black.opacity(0.22))
    }

    private var statusLabel: String {
        if source.kind == .standalone { return "Live" }
        guard let node else { return "Closed" }
        return store.sessionRuntimeState(for: node).label
    }

    private var statusColor: Color {
        if source.kind == .standalone { return .green }
        guard let node else { return .red }
        switch store.sessionRuntimeState(for: node) {
        case .working, .launching: return .yellow
        case .attached: return .green
        case .needsYou, .interrupted, .unavailable: return .orange
        case .exited: return .red
        default: return .white.opacity(0.38)
        }
    }
}

private struct StageStandaloneTerminalView: View {
    let snapshot: StandaloneTerminalSnapshot

    var body: some View {
        StageTerminalTextView(text: output)
    }

    private var output: String {
        snapshot.content.isEmpty ? "Terminal is open. Waiting for output…" : snapshot.content
    }
}

struct StandaloneTerminalSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let tty: String
    let title: String
    let content: String
    var eventCount = 0
    var lastActivityAt = Date()
}

@MainActor
final class StandaloneTerminalController: ObservableObject {
    @Published private(set) var snapshots: [StandaloneTerminalSnapshot] = []
    private var pollingTask: Task<Void, Never>?
    private var focusedSessionID: String?

    func setFocusedSessionID(_ id: String?) {
        guard focusedSessionID != id else { return }
        focusedSessionID = id
        snapshots = snapshots.map { snapshot in
            guard snapshot.id != id, !snapshot.content.isEmpty else { return snapshot }
            return StandaloneTerminalSnapshot(
                id: snapshot.id,
                tty: snapshot.tty,
                title: snapshot.title,
                content: "",
                eventCount: snapshot.eventCount,
                lastActivityAt: snapshot.lastActivityAt
            )
        }
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let next = await Self.readTerminalTabs(focusedSessionID: self.focusedSessionID)
                guard !Task.isCancelled else { return }
                let previous = self.snapshots
                    let merged = next.map { snapshot in
                        guard let prior = previous.first(where: { $0.id == snapshot.id }),
                              prior.content == snapshot.content else { return snapshot }
                        var unchanged = snapshot
                        unchanged.lastActivityAt = prior.lastActivityAt
                        return unchanged
                    }
                    if previous != merged { self.snapshots = merged }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func snapshot(withID id: String) -> StandaloneTerminalSnapshot? {
        snapshots.first(where: { $0.id == id })
    }

    private nonisolated static func readTerminalTabs(focusedSessionID: String?) async -> [StandaloneTerminalSnapshot] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: queryTerminalTabs(focusedSessionID: focusedSessionID))
            }
        }
    }

    private nonisolated static func queryTerminalTabs(focusedSessionID: String?) -> [StandaloneTerminalSnapshot] {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty else {
            return []
        }

        let script = """
        on run argv
        set focusedTTY to ""
        if (count of argv) > 0 then set focusedTTY to item 1 of argv
        set unitSeparator to character id 31
        set recordSeparator to character id 30
        set terminalRows to ""
        tell application "Terminal"
                repeat with terminalWindow in windows
                    repeat with terminalTab in tabs of terminalWindow
                    set actualTab to contents of terminalTab
                    set ttyValue to tty of actualTab
                    set titleValue to custom title of actualTab
                    if titleValue is missing value or titleValue is "" then set titleValue to "Terminal " & ttyValue
                    set contentValue to ""
                    if ttyValue is focusedTTY then
                        set contentValue to history of actualTab
                        if length of contentValue > 24000 then set contentValue to text -24000 thru -1 of contentValue
                    end if
                    set terminalRows to terminalRows & ttyValue & unitSeparator & titleValue & unitSeparator & contentValue & recordSeparator
                end repeat
            end repeat
        end tell
        return terminalRows
        end run
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, focusedSessionID ?? ""]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let data: Data
        do {
            try process.run()
            data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        } catch {
            return []
        }
        guard process.terminationStatus == 0 else { return [] }
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return text.split(separator: "\u{1E}", omittingEmptySubsequences: true).compactMap { row in
            let fields = row.split(separator: "\u{1F}", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { return nil }
            let tty = String(fields[0])
            let title = String(fields[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let content = StageTerminalOutputWindow.visibleTail(String(fields[2]))
            return StandaloneTerminalSnapshot(
                id: tty,
                tty: tty,
                title: title.isEmpty ? "Terminal \(tty)" : title,
                content: content,
                eventCount: StageLocalSessionSnapshot.eventCount(in: content)
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

private struct StagePTYOutputView: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        StageTerminalTextView(text: output)
    }

    private var output: String {
        session.output.isEmpty
            ? "Terminal is ready. Waiting for output…"
            : StageTerminalOutputWindow.visibleTail(session.output)
    }
}

private struct StageAgentTranscriptView: View {
    let node: WorkspaceNode

    var body: some View {
        StageTerminalTextView(text: transcript)
    }

    private var transcript: String {
        guard let activity = node.activityLog, !activity.isEmpty else {
            return "No execution activity yet. Commands, tool calls, file edits, and output will appear here while this agent works."
        }
        return StageTerminalOutputWindow.visibleTail(activity)
    }
}

private struct StageTerminalTextView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 22, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        scrollView.documentView = textView
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard context.coordinator.lastText != text,
              let textView = context.coordinator.textView else { return }
        context.coordinator.lastText = text
        textView.textStorage?.setAttributedString(Self.attributed(text))
        textView.scrollToEndOfDocument(nil)
    }

    private static func attributed(_ text: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2.6
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let kind = TerminalTypography.classify(line)
            let font = NSFont(name: TerminalTypography.fontName, size: 13)
                ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            result.append(NSAttributedString(
                string: line,
                attributes: [
                    .font: font,
                    .foregroundColor: color(for: kind),
                    .paragraphStyle: paragraph,
                ]
            ))
            if index < lines.count - 1 { result.append(NSAttributedString(string: "\n")) }
        }
        return result
    }

    private static func color(for kind: TerminalLineKind) -> NSColor {
        switch kind {
        case .command: return NSColor(red: 0.60, green: 0.95, blue: 0.80, alpha: 1)
        case .error: return NSColor(red: 1.00, green: 0.47, blue: 0.45, alpha: 1)
        case .warning: return NSColor(red: 1.00, green: 0.80, blue: 0.42, alpha: 1)
        case .success: return NSColor(red: 0.53, green: 0.92, blue: 0.60, alpha: 1)
        case .output: return NSColor(red: 0.79, green: 0.90, blue: 0.83, alpha: 1)
        }
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var lastText: String?
    }
}
