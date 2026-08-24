import AppKit
import Foundation
import SwiftUI

/// Native Workspace-page port of the-stage's "Autonomous Mission" spine
/// (packages/ui/src/panels/scoreboard/MissionSpine.tsx). The-stage renders it
/// from a live AMC event pipeline on the Spark; here we drive the same layout
/// from the local `WorkspaceStore` and compute commit/file/line telemetry for
/// real by running `git` against the active run's working directory. Tokens have
/// no native source yet, so that tile reads as "no source".
struct AutonomousMissionPanel: View {
    @ObservedObject var store: WorkspaceStore
    @StateObject private var metricsLoader = MissionMetricsLoader()

    var body: some View {
        if let context = context {
            panel(context)
                .task(id: context.refreshKey) {
                    await metricsLoader.watch(
                        directory: context.workingDirectory,
                        since: context.since
                    )
                }
        }
    }

    // MARK: - Derived context

    /// The mission the panel currently speaks for: the focused/selected node's
    /// mission when present, else the most recent still-open mission, else the
    /// most recent mission of any state.
    private var activeMission: WorkspaceMission? {
        let workspace = store.activeWorkspace
        if let nodeID = store.focusedNodeID ?? store.selectedNodeID,
           let node = workspace.nodes.first(where: { $0.id == nodeID }),
           let mission = store.mission(for: node) {
            return mission
        }
        let open = workspace.missionHistory.filter { !$0.state.isFinished }
        if let latestOpen = open.max(by: { $0.sortDate < $1.sortDate }) {
            return latestOpen
        }
        return workspace.missionHistory.max(by: { $0.sortDate < $1.sortDate })
    }

    private var context: MissionContext? {
        guard let mission = activeMission else { return nil }
        let workspace = store.activeWorkspace
        let node = workspace.nodes.first(where: { $0.id == mission.nodeID })
        let run = store.latestRun(for: mission.nodeID)
        let workingDirectory = run?.workingDirectory ?? node?.workingFolderPath
        let anyWorking = workspace.nodes.contains { $0.resolvedRuntimeState == .working }
        let isActive = mission.state == .working
            || node?.resolvedRuntimeState == .working
            || anyWorking
        return MissionContext(
            mission: mission,
            node: node,
            run: run,
            workingDirectory: workingDirectory,
            isActive: isActive,
            supervisorMessage: store.supervisorMessage
        )
    }

    // MARK: - Panel

    private func panel(_ context: MissionContext) -> some View {
        let metrics = metricsLoader.metrics
        let now = context.nowCard
        let proof = context.proofCard(metrics: metrics)
        let attention = context.attentionCard

        return VStack(alignment: .leading, spacing: 8) {
            header(context)
            missionCard(context)
            HStack(spacing: 7) {
                PulseCard(label: "NOW", card: now)
                PulseCard(label: "PROOF", card: proof)
                PulseCard(label: "ATTENTION", card: attention)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)], spacing: 7) {
                ForEach(context.metricTiles(metrics: metrics)) { tile in
                    StatTile(tile: tile)
                }
            }
            actions(context, now: now, proof: proof, attention: attention)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(WorkspaceVisualStyle.accent.opacity(0.16)))
    }

    private func header(_ context: MissionContext) -> some View {
        HStack(alignment: .center) {
            Text("AUTONOMOUS MISSION")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.92))
            Spacer(minLength: 8)
            FreshnessPill(isActive: context.isActive, label: context.freshnessLabel)
        }
    }

    private func missionCard(_ context: MissionContext) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("MISSION")
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(WorkspaceVisualStyle.accent.opacity(0.85))
            Text(context.mission.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.96))
                .lineLimit(2)
            if !context.mission.objective.isEmpty {
                Text(context.mission.objective)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WorkspaceVisualStyle.accent.opacity(0.22))
        )
    }

    private func actions(
        _ context: MissionContext,
        now: MissionPulse,
        proof: MissionPulse,
        attention: MissionPulse
    ) -> some View {
        HStack(spacing: 7) {
            Spacer(minLength: 0)
            ActionButton(title: "Review evidence") {
                store.reviewMission(context.mission.id)
            }
            ActionButton(title: copyTitle) {
                copyBriefing(context, now: now, proof: proof, attention: attention)
            }
        }
    }

    @State private var copyTitle = "Copy briefing"

    private func copyBriefing(
        _ context: MissionContext,
        now: MissionPulse,
        proof: MissionPulse,
        attention: MissionPulse
    ) {
        let m = metricsLoader.metrics
        let lines = [
            "Mission: \(context.mission.title).",
            "Now: \(now.headline); \(now.detail).",
            "Proof: \(proof.headline); \(proof.detail).",
            "Attention: \(attention.headline); \(attention.detail).",
            "Run telemetry: \(m.commits) commits, \(m.filesTouched) files, +\(m.linesAdded)/-\(m.linesRemoved) lines.",
            "Freshness: \(context.freshnessLabel).",
        ]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: " "), forType: .string)
        copyTitle = "Briefing copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copyTitle = "Copy briefing" }
    }
}

// MARK: - Context + card derivation

private struct MissionContext {
    let mission: WorkspaceMission
    let node: WorkspaceNode?
    let run: WorkspaceRun?
    let workingDirectory: String?
    let isActive: Bool
    let supervisorMessage: String

    var since: Date { run?.startedAt ?? mission.startedAt ?? mission.createdAt }

    var refreshKey: String {
        "\(run?.id.uuidString ?? "none")|\(workingDirectory ?? "none")|\(isActive)"
    }

    var freshnessLabel: String {
        guard isActive else { return "ready · no agent" }
        let age = Date().timeIntervalSince(since)
        return "live · \(formatAge(age))"
    }

    var nowCard: MissionPulse {
        guard isActive else {
            return MissionPulse(headline: "No active agent", detail: "Waiting for a verified heartbeat", tone: .quiet)
        }
        if let working = mission.tasks.first(where: { $0.state == .working }) {
            let detail = node?.terminalSummary ?? node?.title ?? "Working"
            return MissionPulse(headline: working.title, detail: detail, tone: .live)
        }
        if let summary = node?.terminalSummary, !summary.isEmpty {
            let detail = workingDirectory.map { ($0 as NSString).lastPathComponent } ?? "Working"
            return MissionPulse(headline: summary, detail: detail, tone: .live)
        }
        return MissionPulse(headline: mission.state.label, detail: "Waiting for the next file event", tone: .quiet)
    }

    func proofCard(metrics: MissionMetrics) -> MissionPulse {
        let passedEvidence = run?.evidence.filter(\.passed).count ?? 0
        let verifiedTasks = mission.tasks.filter { $0.state.isSuccessful }.count
        let proofCount = passedEvidence + metrics.commits + verifiedTasks
        guard proofCount > 0 else {
            return MissionPulse(headline: "No proof yet", detail: "Checks and commits appear here", tone: .quiet)
        }
        let detail: String
        if passedEvidence > 0 {
            detail = "\(passedEvidence) check\(passedEvidence == 1 ? "" : "s") passed"
        } else if metrics.commits > 0 {
            detail = "\(metrics.commits) commit\(metrics.commits == 1 ? "" : "s") landed"
        } else {
            detail = "\(verifiedTasks) task\(verifiedTasks == 1 ? "" : "s") verified"
        }
        return MissionPulse(headline: "\(proofCount) verified signals", detail: detail, tone: .live)
    }

    var attentionCard: MissionPulse {
        guard isActive else {
            return MissionPulse(headline: "Ready", detail: "No active agent heartbeat", tone: .quiet)
        }
        let blocked = mission.tasks.filter { $0.state == .failed || $0.state == .blocked }.count
        let needsAttention = mission.state == .needsAttention || mission.state == .failed
        if blocked > 0 || needsAttention {
            let detail = blocked > 0 ? "\(blocked) task\(blocked == 1 ? "" : "s") need review" : supervisorMessage
            return MissionPulse(headline: "Needs review", detail: detail, tone: .danger)
        }
        return MissionPulse(headline: "Clear", detail: "No blockers detected", tone: .live)
    }

    func metricTiles(metrics: MissionMetrics) -> [MissionTile] {
        [
            MissionTile(
                id: "commits",
                label: "COMMITS",
                value: metrics.ready ? metrics.commits.formatted() : "—",
                scope: "this run",
                detail: nil,
                tone: .gold
            ),
            MissionTile(
                id: "files",
                label: "FILES",
                value: metrics.ready ? metrics.filesTouched.formatted() : "—",
                scope: "working tree",
                detail: nil,
                tone: .cyan
            ),
            MissionTile(
                id: "lines",
                label: "LINES",
                value: metrics.ready ? "+\(metrics.linesAdded.formatted())" : "—",
                scope: "working tree",
                detail: metrics.linesRemoved > 0 ? "-\(metrics.linesRemoved.formatted())" : nil,
                tone: .gold
            ),
            MissionTile(
                id: "tokens",
                label: "TOKENS",
                value: "—",
                scope: "no source",
                detail: "n/a",
                tone: .cyan
            ),
        ]
    }
}

// MARK: - Tones + value types

private enum MissionTone {
    case live, quiet, warning, danger

    var color: Color {
        switch self {
        case .live: Color(red: 0.29, green: 0.95, blue: 0.28)
        case .quiet: WorkspaceVisualStyle.cyan.opacity(0.85)
        case .warning: Color(red: 1.0, green: 0.83, blue: 0.42)
        case .danger: WorkspaceVisualStyle.claude
        }
    }
}

private enum MetricTone {
    case gold, cyan

    var color: Color {
        switch self {
        case .gold: WorkspaceVisualStyle.accent
        case .cyan: WorkspaceVisualStyle.cyan
        }
    }
}

private struct MissionPulse {
    let headline: String
    let detail: String
    let tone: MissionTone
}

private struct MissionTile: Identifiable {
    let id: String
    let label: String
    let value: String
    let scope: String
    let detail: String?
    let tone: MetricTone
}

// MARK: - Subviews

private struct FreshnessPill: View {
    let isActive: Bool
    let label: String

    var body: some View {
        let color = isActive ? MissionTone.live.color : MissionTone.warning.color
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(0.8), radius: 4)
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(color)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(Color.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3)))
    }
}

private struct PulseCard: View {
    let label: String
    let card: MissionPulse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .tracking(1.0)
                .foregroundStyle(card.tone.color)
            Text(card.headline)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
            Text(card.detail)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .padding(9)
        .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(card.tone.color.opacity(0.28))
        )
    }
}

private struct StatTile: View {
    let tile: MissionTile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tile.label)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
            Text(tile.value)
                .font(.system(size: 22, weight: .heavy, design: .monospaced))
                .foregroundStyle(tile.tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack {
                Text(tile.scope.uppercased())
                if let detail = tile.detail {
                    Spacer(minLength: 4)
                    Text(detail.uppercased())
                }
            }
            .font(.system(size: 8, design: .monospaced))
            .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.1))
        )
    }
}

private struct ActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(0.4)
                .foregroundStyle(WorkspaceVisualStyle.cyan)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(WorkspaceVisualStyle.cyan.opacity(isHovered ? 0.14 : 0.06), in: Capsule())
                .overlay(Capsule().stroke(WorkspaceVisualStyle.cyan.opacity(0.28)))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Live git telemetry

struct MissionMetrics: Sendable, Equatable {
    var commits = 0
    var filesTouched = 0
    var linesAdded = 0
    var linesRemoved = 0
    /// False until the first successful git read for a real repository.
    var ready = false

    static let empty = MissionMetrics()
}

@MainActor
final class MissionMetricsLoader: ObservableObject {
    @Published private(set) var metrics: MissionMetrics = .empty

    /// Refreshes telemetry immediately, then every 15s, until the enclosing
    /// `.task(id:)` is cancelled (i.e. the active run/directory changed).
    func watch(directory: String?, since: Date) async {
        metrics = .empty
        guard let directory, !directory.isEmpty else { return }
        while !Task.isCancelled {
            let next = await Self.compute(directory: directory, since: since)
            if !Task.isCancelled { metrics = next }
            try? await Task.sleep(nanoseconds: 15_000_000_000)
        }
    }

    private nonisolated static func compute(directory: String, since: Date) async -> MissionMetrics {
        await Task.detached(priority: .utility) {
            computeBlocking(directory: directory, since: since)
        }.value
    }

    private nonisolated static func computeBlocking(directory: String, since: Date) -> MissionMetrics {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return .empty
        }

        // Confirm this is a git work tree before trusting any numbers.
        guard let inside = runGit(root: root, ["rev-parse", "--is-inside-work-tree"]),
              inside.status == 0,
              inside.text.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return .empty
        }

        var metrics = MissionMetrics()
        metrics.ready = true

        let iso = ISO8601DateFormatter().string(from: since)
        if let commits = runGit(root: root, ["rev-list", "--count", "--since=\(iso)", "HEAD"]),
           commits.status == 0,
           let value = Int(commits.text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            metrics.commits = value
        }

        // Working-tree changes vs HEAD (staged + unstaged) — the live surface
        // of what the agent has touched this run.
        if let diff = runGit(root: root, ["diff", "HEAD", "--shortstat"]), diff.status == 0 {
            let parsed = parseShortstat(diff.text)
            metrics.filesTouched = parsed.files
            metrics.linesAdded = parsed.added
            metrics.linesRemoved = parsed.removed
        }

        return metrics
    }

    /// Parses e.g. " 3 files changed, 45 insertions(+), 12 deletions(-)".
    private nonisolated static func parseShortstat(_ text: String) -> (files: Int, added: Int, removed: Int) {
        var files = 0, added = 0, removed = 0
        for part in text.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = Int(trimmed.prefix { $0.isNumber }) ?? 0
            if trimmed.contains("file") {
                files = number
            } else if trimmed.contains("insertion") {
                added = number
            } else if trimmed.contains("deletion") {
                removed = number
            }
        }
        return (files, added, removed)
    }

    private nonisolated static func runGit(root: URL, _ arguments: [String]) -> (status: Int32, text: String)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", root.path] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

// MARK: - Model helpers

private extension MissionState {
    var isFinished: Bool {
        switch self {
        case .verified, .cancelled, .failed: true
        case .drafted, .working, .needsAttention, .readyForReview: false
        }
    }
}

private extension WorkspaceMission {
    var sortDate: Date { startedAt ?? createdAt }
}

private func formatAge(_ seconds: TimeInterval) -> String {
    let value = max(0, Int(seconds))
    if value < 60 { return "\(value)s" }
    if value < 3_600 { return "\(value / 60)m" }
    return "\(value / 3_600)h"
}
