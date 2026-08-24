import XCTest
@testable import SpatialWorkspaceApp

final class VoiceCommandPolicyTests: XCTestCase {
    func testSleepCommandToleratesSpeechPunctuationAndCapitalization() {
        XCTAssertTrue(VoiceCommandPolicy.isSleepCommand("Go to sleep."))
        XCTAssertTrue(VoiceCommandPolicy.isSleepCommand("Okay, go to sleep!"))
    }

    func testOrdinaryCommandDoesNotStopListening() {
        XCTAssertFalse(VoiceCommandPolicy.isSleepCommand("Switch to Test App and refresh the browser."))
    }
}
