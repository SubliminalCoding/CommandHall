import AppKit
import SwiftUI

enum SpatialWorkspaceReleaseDiagnostics {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
    }

    static var diagnosticReportsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)
    }

    static func isSpatialWorkspaceCrashReport(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return (name.hasPrefix("commandhall-") || name.hasPrefix("spatialworkspace-"))
            && (name.hasSuffix(".ips") || name.hasSuffix(".crash"))
    }

    static func recentCrashReports(now: Date = Date(), days: Double = 30) -> [URL] {
        let cutoff = now.addingTimeInterval(-days * 86_400)
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: diagnosticReportsDirectory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files.filter { url in
            guard isSpatialWorkspaceCrashReport(url),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let modified = values.contentModificationDate else { return false }
            return modified >= cutoff
        }.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    static func openReleasePage() {
        guard let url = URL(string: "https://bilbroswagginz.com/commandhall") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct ReleaseDiagnosticsView: View {
    @Binding var isPresented: Bool
    private let reports = SpatialWorkspaceReleaseDiagnostics.recentCrashReports()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Release diagnostics")
                        .font(.system(size: 20, weight: .bold))
                    Text("CommandHall \(SpatialWorkspaceReleaseDiagnostics.version) (\(SpatialWorkspaceReleaseDiagnostics.build))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }

            GroupBox("Updates") {
                HStack {
                    Text("Releases are signed and notarized before publication. The CommandHall product page is the authoritative update source.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for updates", action: SpatialWorkspaceReleaseDiagnostics.openReleasePage)
                }
                .padding(6)
            }

            GroupBox("Local crash reports") {
                VStack(alignment: .leading, spacing: 9) {
                    Text(reports.isEmpty
                        ? "No CommandHall crash reports were written in the last 30 days."
                        : "\(reports.count) report\(reports.count == 1 ? "" : "s") in the last 30 days. Reports stay local unless you choose to share them.")
                        .font(.system(size: 11))
                    ForEach(reports.prefix(5), id: \.path) { report in
                        Text(report.lastPathComponent)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Button("Open DiagnosticReports folder") {
                        NSWorkspace.shared.open(SpatialWorkspaceReleaseDiagnostics.diagnosticReportsDirectory)
                    }
                    .disabled(!FileManager.default.fileExists(atPath: SpatialWorkspaceReleaseDiagnostics.diagnosticReportsDirectory.path))
                }
                .padding(6)
            }

            Text("The app does not upload crash logs, workspace history, prompts, or memory automatically.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(22)
        .frame(width: 650)
        .background(WorkspaceVisualStyle.panelTint.opacity(0.97))
    }
}
