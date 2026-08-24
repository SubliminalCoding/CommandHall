import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class SpatialSelectionTests: XCTestCase {
    private func store() -> WorkspaceStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        return WorkspaceStore(persistenceURL: url)
    }

    func testSelectedNodesMoveAsAGroup() {
        let store = store()
        let first = store.activeWorkspace.nodes[0]
        let second = store.activeWorkspace.nodes[1]
        store.select(first.id)
        store.select(second.id, toggling: true)

        store.moveNode(first.id, to: CGPoint(x: first.position.x + 40, y: first.position.y - 15))

        let movedFirst = store.activeWorkspace.nodes.first(where: { $0.id == first.id })!
        let movedSecond = store.activeWorkspace.nodes.first(where: { $0.id == second.id })!
        XCTAssertEqual(movedFirst.position.x, first.position.x + 40)
        XCTAssertEqual(movedFirst.position.y, first.position.y - 15)
        XCTAssertEqual(movedSecond.position.x, second.position.x + 40)
        XCTAssertEqual(movedSecond.position.y, second.position.y - 15)
    }

    func testBeginningGroupManipulationPreservesSelection() {
        let store = store()
        let first = store.activeWorkspace.nodes[0]
        let second = store.activeWorkspace.nodes[1]
        store.select(first.id)
        store.select(second.id, toggling: true)

        store.beginDirectManipulation(first.id)

        XCTAssertEqual(store.selectedNodeIDs, Set([first.id, second.id]))
    }

    func testMarqueeSelectsIntersectingNodes() {
        let store = store()
        let first = store.activeWorkspace.nodes[0]
        let frame = CGRect(origin: first.position.cgPoint, size: first.size.cgSize).insetBy(dx: 10, dy: 10)
        store.selectNodes(intersecting: frame)
        XCTAssertTrue(store.selectedNodeIDs.contains(first.id))
    }

    func testResizingTerminalPreservesItsSpatialAnchor() throws {
        let store = store()
        let terminal = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.kind == .terminal }))
        let originalPosition = terminal.position

        store.resizeNode(terminal.id, to: CGSize(width: 920, height: 620))

        let resized = try XCTUnwrap(store.activeWorkspace.nodes.first(where: { $0.id == terminal.id }))
        XCTAssertEqual(resized.position, originalPosition)
        XCTAssertEqual(resized.size, SizeValue(width: 920, height: 620))
    }
}
