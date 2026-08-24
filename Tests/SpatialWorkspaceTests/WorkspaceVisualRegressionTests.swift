import SwiftUI
import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class WorkspaceVisualRegressionTests: XCTestCase {
    func testCompactWorkspaceOverviewMatchesGolden() throws {
        let size = CGSize(width: 980, height: 640)
        let store = makeStore(viewportSize: size)

        try VisualGoldenTestSupport.assertView(
            named: "workspace-overview-980x640",
            size: size,
            scale: 0.75
        ) {
            rootView(store: store)
        }
    }

    func testFocusedAgentIsCenteredAtStandardDesktopSize() throws {
        let size = CGSize(width: 1_440, height: 900)
        let store = makeStore(viewportSize: size)
        let agentID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.kind == .agent })?.id)
        store.focusNode(agentID)

        try VisualGoldenTestSupport.assertView(
            named: "focused-agent-1440x900",
            size: size,
            scale: 0.65
        ) {
            rootView(store: store)
        }
    }

    func testFocusedAgentIsCenteredOnWideDesktop() throws {
        let size = CGSize(width: 2_048, height: 1_166)
        let store = makeStore(viewportSize: size)
        let agentID = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.kind == .agent })?.id)
        store.focusNode(agentID)

        try VisualGoldenTestSupport.assertView(
            named: "focused-agent-2048x1166",
            size: size,
            scale: 0.5
        ) {
            rootView(store: store)
        }
    }

    func testDestructiveCommandReviewMatchesGolden() throws {
        let size = CGSize(width: 980, height: 640)
        let store = makeStore(viewportSize: size)
        XCTAssertTrue(store.submitCommand("Close Marshall"))

        try VisualGoldenTestSupport.assertView(
            named: "command-review-980x640",
            size: size,
            scale: 0.75
        ) {
            rootView(store: store)
        }
    }

    func testLiveCommandIntentMatchesGolden() throws {
        let size = CGSize(width: 980, height: 640)
        let store = makeStore(viewportSize: size)
        store.commandText = "Switch to Test App and refresh the browser"

        try VisualGoldenTestSupport.assertView(
            named: "command-intent-980x640",
            size: size,
            scale: 0.75
        ) {
            rootView(store: store)
        }
    }

    private func makeStore(viewportSize: CGSize) -> WorkspaceStore {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: false)
        for node in store.activeWorkspace.nodes where node.kind == .terminal {
            store.removeNode(node.id)
        }
        store.addNode(
            kind: .note,
            title: "Release Notes",
            content: "Keep the operator in control.\nMake every state honest."
        )
        store.setTheme(.aurora)
        store.updateViewportSize(viewportSize)
        store.arrangeNodes(mode: .balanced, announce: false)
        return store
    }

    private func rootView(store: WorkspaceStore) -> some View {
        WorkspaceRootView(
            store: store,
            signalDeckController: SignalDeckController(),
            configuration: .visualTest()
        )
    }
}
