import XCTest
@testable import SpatialWorkspaceApp

final class MiniMapProjectionTests: XCTestCase {
    func testViewportReflectsCameraPanAndZoom() {
        let camera = CameraTransform(offset: PointValue(x: -180, y: -90), scale: 2)
        let viewport = MiniMapProjection.viewport(camera: camera, screenSize: CGSize(width: 720, height: 360))

        XCTAssertEqual(viewport.origin.x, 9, accuracy: 0.000_001)
        XCTAssertEqual(viewport.origin.y, 6.5, accuracy: 0.000_001)
        XCTAssertEqual(viewport.width, 20, accuracy: 0.000_001)
        XCTAssertEqual(viewport.height, 10, accuracy: 0.000_001)
    }
}
