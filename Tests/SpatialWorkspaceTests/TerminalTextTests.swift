import XCTest
@testable import SpatialWorkspaceApp

final class TerminalTextTests: XCTestCase {
    func testANSIEscapeSequencesAreRemoved() {
        XCTAssertEqual(TerminalText.clean("\u{1B}[31mred\u{1B}[0m\r\n"), "red\n")
    }

    func testOSCWindowTitleIsRemoved() {
        XCTAssertEqual(TerminalText.clean("before\u{1B}]0;title\u{7}after"), "beforeafter")
    }
}
