import XCTest
@testable import SpatialWorkspaceApp

final class CameraTransformTests: XCTestCase {
    func testWorldTranslationAccountsForScale() {
        let camera = CameraTransform(offset: PointValue(x: 0, y: 0), scale: 2)
        let translation = camera.worldTranslation(forScreenTranslation: CGSize(width: 80, height: -30))
        XCTAssertEqual(translation.width, 40, accuracy: 0.0001)
        XCTAssertEqual(translation.height, -15, accuracy: 0.0001)
    }

    func testScaleIsClampedToSupportedRange() {
        var camera = CameraTransform(offset: PointValue(x: 0, y: 0), scale: 20)
        camera.clampScale()
        XCTAssertEqual(camera.scale, CameraTransform.scaleRange.upperBound)

        camera.scale = 0.01
        camera.clampScale()
        XCTAssertEqual(camera.scale, CameraTransform.scaleRange.lowerBound)
    }

    func testZoomPreservesWorldPointUnderPointer() {
        var camera = CameraTransform(offset: PointValue(x: 50, y: 30), scale: 1)
        let pointer = CGPoint(x: 250, y: 130)
        camera.zoom(to: 2, around: pointer)
        XCTAssertEqual(camera.scale, 1.8)
        let projectedX = 200 * camera.scale + camera.offset.x
        let projectedY = 100 * camera.scale + camera.offset.y
        XCTAssertEqual(projectedX, pointer.x, accuracy: 0.0001)
        XCTAssertEqual(projectedY, pointer.y, accuracy: 0.0001)
    }
}
