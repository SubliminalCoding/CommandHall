import XCTest
@testable import SpatialWorkspaceApp

final class WorkspaceMotionTests: XCTestCase {
    func testDragTiltUsesHorizontalMomentumAndStaysSubtle() {
        XCTAssertEqual(
            WorkspaceMotion.dragTilt(
                translation: CGSize(width: 20, height: 100),
                predictedEndTranslation: CGSize(width: 300, height: 100)
            ),
            1.6,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            WorkspaceMotion.dragTilt(
                translation: CGSize(width: 20, height: 0),
                predictedEndTranslation: CGSize(width: -260, height: 0)
            ),
            -1.6,
            accuracy: 0.0001
        )
    }

    func testInertialPanIsCappedWithoutChangingDirection() {
        let delta = WorkspaceMotion.inertialPanDelta(
            translation: .zero,
            predictedEndTranslation: CGSize(width: 900, height: 1_200)
        )
        XCTAssertEqual(hypot(delta.width, delta.height), 180, accuracy: 0.0001)
        XCTAssertEqual(delta.width / delta.height, 0.75, accuracy: 0.0001)
    }

    func testSmallInertialPanPreservesMomentum() {
        let delta = WorkspaceMotion.inertialPanDelta(
            translation: CGSize(width: 40, height: -10),
            predictedEndTranslation: CGSize(width: 90, height: 10)
        )
        XCTAssertEqual(delta.width, 21, accuracy: 0.0001)
        XCTAssertEqual(delta.height, 8.4, accuracy: 0.0001)
    }

    func testParallaxIsOpposedAndBounded() {
        let offset = WorkspaceMotion.parallaxOffset(for: CGPoint(x: 2_000, y: -2_000))
        XCTAssertEqual(offset.width, -7)
        XCTAssertEqual(offset.height, 7)
    }

    func testResizeHonorsMinimumSize() {
        let size = WorkspaceMotion.constrainedSize(
            CGSize(width: 110, height: 900),
            minimum: CGSize(width: 320, height: 220)
        )
        XCTAssertEqual(size.width, 320)
        XCTAssertEqual(size.height, 900)
    }
}
