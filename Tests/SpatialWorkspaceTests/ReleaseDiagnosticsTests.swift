import XCTest
@testable import SpatialWorkspaceApp

final class ReleaseDiagnosticsTests: XCTestCase {
    func testCrashReportRecognitionIsNarrowAndCaseInsensitive() {
        XCTAssertTrue(SpatialWorkspaceReleaseDiagnostics.isSpatialWorkspaceCrashReport(
            URL(fileURLWithPath: "/tmp/CommandHall-2026-08-24.ips")
        ))
        XCTAssertTrue(SpatialWorkspaceReleaseDiagnostics.isSpatialWorkspaceCrashReport(
            URL(fileURLWithPath: "/tmp/SpatialWorkspace-2026-08-24.ips")
        ))
        XCTAssertTrue(SpatialWorkspaceReleaseDiagnostics.isSpatialWorkspaceCrashReport(
            URL(fileURLWithPath: "/tmp/spatialworkspace-legacy.crash")
        ))
        XCTAssertFalse(SpatialWorkspaceReleaseDiagnostics.isSpatialWorkspaceCrashReport(
            URL(fileURLWithPath: "/tmp/OtherApp-2026-08-24.ips")
        ))
        XCTAssertFalse(SpatialWorkspaceReleaseDiagnostics.isSpatialWorkspaceCrashReport(
            URL(fileURLWithPath: "/tmp/SpatialWorkspace-notes.txt")
        ))
    }
}
