import XCTest
@testable import SpatialWorkspaceApp

@MainActor
final class PerformanceAcceptanceTests: XCTestCase {
    func testSixtyNodeGroupManipulationStaysWithinInteractiveBudget() throws {
        let persistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let workspaceID = UUID()
        let nodes = (0 ..< 60).map { index in
            WorkspaceNode(
                kind: .note,
                title: "Node \(index)",
                subtitle: "Note",
                position: CGPoint(x: Double(index % 10) * 150, y: Double(index / 10) * 110),
                size: CGSize(width: 120, height: 80),
                zIndex: index
            )
        }
        try WorkspacePersistence.save(
            PersistedWorkspaceState(
                activeWorkspaceID: workspaceID,
                workspaces: [WorkspaceDocument(id: workspaceID, name: "Load", theme: "nocturne", rootPath: "/tmp", camera: CameraTransform(), nodes: nodes)]
            ),
            to: persistenceURL
        )
        let store = WorkspaceStore(persistenceURL: persistenceURL)
        store.selectNodes(intersecting: CGRect(x: -10, y: -10, width: 2_000, height: 1_000))
        let firstID = try XCTUnwrap(store.activeWorkspace.nodes.first?.id)
        let original = try XCTUnwrap(store.activeWorkspace.nodes.first?.position)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for step in 1 ... 100 {
                store.moveNode(firstID, to: CGPoint(x: original.x + Double(step), y: original.y + Double(step)))
            }
            store.finishDirectManipulation()
        }

        XCTAssertLessThan(elapsed, .seconds(1))
        XCTAssertEqual(store.activeWorkspace.nodes.count, 60)
        XCTAssertTrue(store.activeWorkspace.nodes.allSatisfy { $0.position.x >= 100 && $0.position.y >= 100 })
    }
}
