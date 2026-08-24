import XCTest
@testable import SpatialWorkspaceApp

final class TerminalTypographyTests: XCTestCase {
    func testClassifiesCommandPrompts() {
        XCTAssertEqual(TerminalTypography.classify("❯ swift build"), .command)
        XCTAssertEqual(TerminalTypography.classify("➜  swift test"), .command)
        XCTAssertEqual(TerminalTypography.classify("$ ls -la"), .command)
    }

    func testClassifiesErrors() {
        XCTAssertEqual(TerminalTypography.classify("error: no such module 'Foo'"), .error)
        XCTAssertEqual(TerminalTypography.classify("zsh: command not found: fooo"), .error)
        XCTAssertEqual(TerminalTypography.classify("Permission denied"), .error)
        XCTAssertEqual(TerminalTypography.classify("✗ 3 tests failed"), .error)
    }

    func testClassifiesWarningsAndSuccess() {
        XCTAssertEqual(TerminalTypography.classify("warning: deprecated API"), .warning)
        XCTAssertEqual(TerminalTypography.classify("Build complete! (3.40s)"), .success)
        XCTAssertEqual(TerminalTypography.classify("✓ all tests passed"), .success)
    }

    func testOrdinaryOutputStaysNeutral() {
        XCTAssertEqual(TerminalTypography.classify("total 128"), .output)
        XCTAssertEqual(TerminalTypography.classify("drwxr-xr-x  19 matt  staff"), .output)
        XCTAssertEqual(TerminalTypography.classify(""), .output)
    }

    func testAttributedPreservesLineCount() {
        let raw = "❯ swift build\nerror: boom\ntotal 3"
        let attributed = TerminalTypography.attributed(raw, size: 12)
        XCTAssertEqual(String(attributed.characters), raw)
    }
}
