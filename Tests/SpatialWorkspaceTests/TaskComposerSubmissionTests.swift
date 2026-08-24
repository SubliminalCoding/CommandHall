import XCTest
@testable import SpatialWorkspaceApp

final class TaskComposerSubmissionTests: XCTestCase {
    func testAcceptedSubmissionClearsDraftAndTrimsRequest() {
        var draft = "  Ask Marshall to review this  \n"
        var received = ""

        let accepted = TaskComposerSubmission.submit(text: &draft, disabled: false) { request in
            received = request
            return true
        }

        XCTAssertTrue(accepted)
        XCTAssertEqual(received, "Ask Marshall to review this")
        XCTAssertEqual(draft, "")
    }

    func testRejectedSubmissionRestoresExactDraft() {
        var draft = "Keep this prompt available"

        let accepted = TaskComposerSubmission.submit(text: &draft, disabled: false) { _ in false }

        XCTAssertFalse(accepted)
        XCTAssertEqual(draft, "Keep this prompt available")
    }

    func testDisabledSubmissionDoesNotChangeDraft() {
        var draft = "Wait until the worker is ready"
        var handlerWasCalled = false

        let accepted = TaskComposerSubmission.submit(text: &draft, disabled: true) { _ in
            handlerWasCalled = true
            return true
        }

        XCTAssertFalse(accepted)
        XCTAssertFalse(handlerWasCalled)
        XCTAssertEqual(draft, "Wait until the worker is ready")
    }
}
