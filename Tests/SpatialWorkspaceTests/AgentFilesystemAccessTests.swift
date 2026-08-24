import Foundation
import XCTest
@testable import SpatialWorkspaceApp

final class AgentFilesystemAccessTests: XCTestCase {
    func testClaudeReceivesAdditionalDirectory() {
        XCTAssertEqual(
            AgentFilesystemAccess.commandArguments(for: .claude, root: "/Users/example"),
            ["--add-dir", "/Users/example"]
        )
    }

    func testCodexReceivesAdditionalDirectory() {
        XCTAssertEqual(
            AgentFilesystemAccess.commandArguments(for: .codex, root: "/Users/example/Projects"),
            ["--add-dir", "/Users/example/Projects"]
        )
    }

    func testBlankRootDoesNotBroadenAccess() {
        XCTAssertEqual(AgentFilesystemAccess.commandArguments(for: .claude, root: "  "), [])
    }

    func testUnrestrictedAuthorityUsesProviderSpecificBypassModes() {
        XCTAssertEqual(
            AgentCapabilitySettings.commandArguments(for: .codex, profile: .unrestricted),
            ["--dangerously-bypass-approvals-and-sandbox"]
        )
        XCTAssertEqual(
            AgentCapabilitySettings.commandArguments(for: .claude, profile: .unrestricted),
            ["--dangerously-skip-permissions"]
        )
    }

    func testLocalCommandAuthorityRetainsProviderReview() {
        XCTAssertEqual(
            AgentCapabilitySettings.commandArguments(for: .codex, profile: .localCommands),
            ["--approve-for-me"]
        )
        XCTAssertEqual(
            AgentCapabilitySettings.commandArguments(for: .claude, profile: .localCommands),
            ["--permission-mode", "auto"]
        )
    }

    func testReadOnlyAndWorkspaceEditAuthorityMapToInstalledProviderFlags() {
        XCTAssertEqual(
            AgentCapabilitySettings.commandArguments(for: .codex, profile: .readOnly),
            ["--sandbox", "read-only", "-c", "approval_policy=\"never\""]
        )
        XCTAssertEqual(
            AgentCapabilitySettings.commandArguments(for: .codex, profile: .workspaceEdits),
            ["--sandbox", "workspace-write", "-c", "approval_policy=\"never\""]
        )
        XCTAssertEqual(
            AgentCapabilitySettings.commandArguments(for: .claude, profile: .readOnly),
            ["--permission-mode", "plan"]
        )
        XCTAssertEqual(
            AgentCapabilitySettings.commandArguments(for: .claude, profile: .workspaceEdits),
            ["--permission-mode", "acceptEdits"]
        )
    }

    func testInstalledCodexAcceptsGeneratedAuthorityArgumentsWhenAvailable() throws {
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSString(string: "~/.local/bin/codex").expandingTildeInPath,
        ]
        guard let executable = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            throw XCTSkip("Codex CLI is not installed on this test host")
        }

        for profile in SessionAuthorityProfile.allCases {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = ["exec", "--strict-config"]
                + AgentCapabilitySettings.commandArguments(for: .codex, profile: profile)
                + ["--help"]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()

            XCTAssertEqual(
                process.terminationStatus,
                0,
                "Installed Codex rejected arguments for \(profile.rawValue)"
            )
        }
    }

    func testAgentEnvironmentContainsInteractiveToolLocationsWithoutCopyingClaudeAPIKey() {
        let codexEnvironment = AgentCapabilitySettings.processEnvironment(for: .codex)
        let claudeEnvironment = AgentCapabilitySettings.processEnvironment(for: .claude)

        XCTAssertTrue(codexEnvironment["PATH"]?.contains("/opt/homebrew/bin") == true)
        XCTAssertTrue(codexEnvironment["PATH"]?.contains("/.local/bin") == true)
        XCTAssertNil(claudeEnvironment["ANTHROPIC_API_KEY"])
    }
}
