import XCTest
@testable import SpatialWorkspaceApp

final class AgentStreamDecoderTests: XCTestCase {
    func testCodexAgentMessageIsRenderedWithoutProtocolEnvelope() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"Finished the task."}}"#
        XCTAssertEqual(AgentStreamDecoder.displayText(from: line), "Finished the task.")
    }

    func testClaudeAssistantTextIsRenderedWithoutProtocolEnvelope() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"I updated the page."}]}}"#
        XCTAssertEqual(AgentStreamDecoder.displayText(from: line), "I updated the page.")
    }

    func testLifecycleEventWithNoDisplayTextIsHidden() {
        let line = #"{"type":"thread.started","thread_id":"thread_1"}"#
        XCTAssertNil(AgentStreamDecoder.displayText(from: line))
        XCTAssertEqual(AgentStreamDecoder.decode(line).sessionID, "thread_1")
    }

    func testPlainTextPassesThrough() {
        XCTAssertEqual(AgentStreamDecoder.displayText(from: "Build complete"), "Build complete")
    }

    func testClaudeResultDoesNotDuplicateAssistantText() {
        let line = #"{"type":"result","session_id":"session_1","result":"Already rendered"}"#
        let decoded = AgentStreamDecoder.decode(line)
        XCTAssertNil(decoded.displayText)
        XCTAssertEqual(decoded.sessionID, "session_1")
    }

    func testCodexCommandEventsProduceReadableTerminalActivity() {
        let started = #"{"type":"item.started","item":{"type":"command_execution","command":"npm test"}}"#
        let completed = #"{"type":"item.completed","item":{"type":"command_execution","aggregated_output":"12 tests passed\n","exit_code":0,"status":"completed"}}"#

        XCTAssertEqual(AgentStreamDecoder.decode(started).activityText, "$ npm test")
        XCTAssertEqual(AgentStreamDecoder.decode(completed).activityText, "12 tests passed\n[exit 0]")
    }

    func testClaudeWriteToolShowsFileAndContentInTerminalActivity() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/app.swift","content":"let answer = 42"}}]}}"#

        XCTAssertEqual(
            AgentStreamDecoder.decode(line).activityText,
            "◆ Write /tmp/app.swift\nlet answer = 42"
        )
    }

    func testClaudeBashToolLooksLikeTraditionalTerminalCommand() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"swift test"}}]}}"#

        XCTAssertEqual(AgentStreamDecoder.decode(line).activityText, "$ swift test")
    }
}
