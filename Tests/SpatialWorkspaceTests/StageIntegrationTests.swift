import SwiftUI
import WebKit
import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class StageIntegrationTests: XCTestCase {
    private func makeStore() -> WorkspaceStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("stage-integration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return WorkspaceStore(persistenceURL: directory.appendingPathComponent("state.json"))
    }

    func testStageTunnelIsLoopbackOnlyAndDoesNotReuseSSHControlMaster() {
        let configuration = StageServiceConfiguration()

        XCTAssertEqual(configuration.operatorURL.absoluteString, "http://127.0.0.1:55173/")
        XCTAssertTrue(configuration.tunnelArguments.contains("127.0.0.1:55173:127.0.0.1:5173"))
        XCTAssertTrue(configuration.tunnelArguments.contains("ControlMaster=no"))
        XCTAssertTrue(configuration.tunnelArguments.contains("ControlPath=none"))
        XCTAssertTrue(configuration.tunnelArguments.contains("ExitOnForwardFailure=yes"))
        XCTAssertFalse(configuration.tunnelArguments.contains("0.0.0.0:55173:127.0.0.1:5173"))
    }

    func testRemoteStartTargetsOnlyTheManagedUserService() {
        let configuration = StageServiceConfiguration()

        XCTAssertEqual(
            Array(configuration.remoteStartArguments.suffix(5)),
            ["spark", "systemctl", "--user", "start", "spatial-stage.service"]
        )
    }

    func testStageMediaIsSuspendedOutsideTheStagePage() {
        XCTAssertFalse(StagePlaybackPolicy.shouldSuspend(isStageActive: true))
        XCTAssertTrue(StagePlaybackPolicy.shouldSuspend(isStageActive: false))
    }

    func testOperatorFocusStyleKeepsTheOBSURLSeparate() {
        let script = StageOperatorFocusStyle.injectionScript

        XCTAssertTrue(script.contains("command-hall-stage-focus"))
        XCTAssertTrue(script.contains("dashboard-stage-xp-target"))
        XCTAssertTrue(script.contains("recent-moments-section"))
        XCTAssertEqual(StageServiceConfiguration().obsSourceURL, "http://127.0.0.1:5173/?overlay=1")
    }

    func testStageFitShrinksTallDashboardIntoViewport() {
        XCTAssertEqual(
            StageFitPolicy.zoom(viewportHeight: 800, contentHeight: 1_080),
            0.7333333333,
            accuracy: 0.0001
        )
    }

    func testStageFitNeverEnlargesOrShrinksPastReadableFloor() {
        XCTAssertEqual(StageFitPolicy.zoom(viewportHeight: 1_200, contentHeight: 900), 1)
        XCTAssertEqual(StageFitPolicy.zoom(viewportHeight: 500, contentHeight: 2_000), 0.72)
    }

    func testStageContentFrameProjectsDOMCoordinatesIntoNativeViewport() {
        let metrics = StageDOMFrameMetrics(
            x: 100,
            y: 200,
            width: 1_200,
            height: 1_000,
            viewportWidth: 1_400,
            viewportHeight: 1_800
        )

        let frame = StageContentFramePolicy.project(
            metrics: metrics,
            viewport: CGSize(width: 700, height: 900)
        )

        XCTAssertEqual(frame, CGRect(x: 50, y: 100, width: 600, height: 500))
    }

    func testStageContentFrameUsesCenteredFallbackUntilWebCardIsMeasured() {
        let frame = StageContentFramePolicy.resolvedFrame(
            measured: .zero,
            viewport: CGSize(width: 1_400, height: 900)
        )

        XCTAssertEqual(frame.origin.x, 98, accuracy: 0.01)
        XCTAssertEqual(frame.origin.y, 171, accuracy: 0.01)
        XCTAssertEqual(frame.width, 1_232, accuracy: 0.01)
        XCTAssertEqual(frame.height, 639, accuracy: 0.01)
    }

    func testTerminalCatalogKeepsOnlyViewableSessionsAndPrefersTerminals() {
        var workspace = WorkspaceStore.defaultState().workspaces[0]
        let terminal = WorkspaceNode(
            kind: .terminal,
            title: "Build Shell",
            subtitle: "Terminal",
            position: .zero,
            size: CGSize(width: 400, height: 300),
            zIndex: 1
        )
        let agent = WorkspaceNode(
            kind: .agent,
            title: "Codex",
            subtitle: "Codex",
            position: .zero,
            size: CGSize(width: 400, height: 300),
            zIndex: 2,
            provider: .codex
        )
        let note = WorkspaceNode(
            kind: .note,
            title: "Notes",
            subtitle: "Note",
            position: .zero,
            size: CGSize(width: 400, height: 300),
            zIndex: 3
        )
        workspace.nodes = [note, agent, terminal]

        let sources = StageTerminalCatalog.sources(in: workspace)

        XCTAssertEqual(sources.map(\.id), [.workspace(terminal.id), .workspace(agent.id)])
        XCTAssertEqual(sources.map(\.kind), [.terminal, .agent])
    }

    func testTerminalCatalogPreservesSelectionAndFallsBackWhenSessionCloses() {
        let first = StageTerminalSource.ID.workspace(UUID())
        let second = StageTerminalSource.ID.standalone("/dev/ttys002")

        XCTAssertEqual(
            StageTerminalCatalog.resolvedSelectionID(second, sourceIDs: [first, second]),
            second
        )
        XCTAssertEqual(
            StageTerminalCatalog.resolvedSelectionID(second, sourceIDs: [first]),
            first
        )
        XCTAssertNil(StageTerminalCatalog.resolvedSelectionID(second, sourceIDs: []))
    }

    func testTerminalCatalogCombinesStandaloneAndWorkspaceSessions() {
        var workspace = WorkspaceStore.defaultState().workspaces[0]
        let terminal = WorkspaceNode(
            kind: .terminal,
            title: "Workspace Shell",
            subtitle: "Terminal",
            position: .zero,
            size: CGSize(width: 400, height: 300),
            zIndex: 1
        )
        workspace.nodes = [terminal]
        let standalone = StandaloneTerminalSnapshot(
            id: "/dev/ttys002",
            tty: "/dev/ttys002",
            title: "Release session",
            content: "swift test"
        )

        let sources = StageTerminalCatalog.sources(in: workspace, standalone: [standalone])

        XCTAssertEqual(sources.map(\.id), [.standalone("/dev/ttys002"), .workspace(terminal.id)])
        XCTAssertEqual(sources.first?.subtitle, "Terminal.app · /dev/ttys002")
    }

    func testTerminalOutputWindowBoundsCharactersAndLines() {
        let longLines = (0..<650).map { "line-\($0)-" + String(repeating: "x", count: 80) }.joined(separator: "\n")
        let tail = StageTerminalOutputWindow.visibleTail(longLines)

        XCTAssertLessThanOrEqual(tail.count, StageTerminalOutputWindow.maximumCharacters)
        XCTAssertLessThanOrEqual(
            tail.split(separator: "\n", omittingEmptySubsequences: false).count,
            StageTerminalOutputWindow.maximumLines
        )
        XCTAssertTrue(tail.contains("line-649"))
        XCTAssertFalse(tail.contains("line-0-"))
    }

    func testTerminalActivityUsesOnlyPrivacySafeCategories() {
        let secret = "fatal: token example-private-value in /Users/example/secret/project"
        let summary = StageTerminalActivity.summary(for: secret)

        XCTAssertEqual(summary, "The selected terminal is reporting a failure")
        XCTAssertFalse(summary.contains("example-private-value"))
        XCTAssertFalse(summary.contains("/Users/example"))
    }

    func testLiveStandaloneTerminalDiscoveryWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_TERMINAL_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_TERMINAL_E2E=1 to verify open Terminal.app tabs")
        }

        let controller = StandaloneTerminalController()
        controller.start()
        defer { controller.stop() }
        let deadline = Date().addingTimeInterval(8)
        while controller.snapshots.isEmpty, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertFalse(controller.snapshots.isEmpty)
        XCTAssertTrue(controller.snapshots.allSatisfy { !$0.tty.isEmpty && !$0.title.isEmpty })
    }

    func testLiveSparkStageLoadsInEmbeddedWebKitWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_REAL_STAGE_E2E"] == "1" else {
            throw XCTSkip("Set RUN_REAL_STAGE_E2E=1 to verify The Stage on Spark")
        }

        let controller = StageServiceController()
        let host = NSHostingView(rootView: StagePage(controller: controller, store: makeStore()))
        host.frame = CGRect(x: 0, y: 0, width: 1_280, height: 800)
        host.layoutSubtreeIfNeeded()
        defer { controller.stop() }

        let deadline = Date().addingTimeInterval(30)
        while controller.state != .ready, Date() < deadline {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(controller.state, .ready)

        let webView = try await waitForWebView(in: host)
        var body = ""
        while body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, Date() < deadline {
            body = (try? await webView.evaluateJavaScript("document.body.innerText") as? String) ?? ""
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        while body.contains("Connecting to server"), Date() < deadline {
            try await Task.sleep(nanoseconds: 200_000_000)
            body = (try? await webView.evaluateJavaScript("document.body.innerText") as? String) ?? ""
        }

        XCTAssertFalse(body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertFalse(body.contains("Connecting to server"))
        XCTAssertEqual(webView.url?.host, "127.0.0.1")
        XCTAssertEqual(webView.url?.port, 55_173)

        let layoutMetrics = try await webView.evaluateJavaScript(
            "({innerHeight: innerHeight, scrollHeight: Math.max(document.documentElement.scrollHeight, document.body?.scrollHeight || 0)})"
        )
        if let metrics = layoutMetrics as? [String: NSNumber] {
            let fittedHeight = metrics["scrollHeight", default: 0].doubleValue * webView.pageZoom
            XCTAssertLessThanOrEqual(
                fittedHeight,
                Double(webView.bounds.height) + 12,
                "The Stage should fit vertically without clipping its lower panels"
            )
        }

        if let snapshotPath = ProcessInfo.processInfo.environment["STAGE_SNAPSHOT_PATH"] {
            let image = try await webView.takeSnapshot(configuration: nil)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: image.tiffRepresentation ?? Data()))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
        }
    }

    private func waitForWebView(in root: NSView) async throws -> WKWebView {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let webView = findWebView(in: root) { return webView }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw NSError(
            domain: "StageIntegrationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "The Stage WKWebView was not created"]
        )
    }

    private func findWebView(in view: NSView) -> WKWebView? {
        if let webView = view as? WKWebView { return webView }
        return view.subviews.lazy.compactMap(findWebView).first
    }
}
