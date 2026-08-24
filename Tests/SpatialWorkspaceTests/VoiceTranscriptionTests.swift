import Foundation
import XCTest
@testable import SpatialWorkspaceApp

final class VoiceTranscriptionTests: XCTestCase {
    func testMultipartBodyCarriesAudioModelLanguageAndPrompt() throws {
        let boundary = "test-boundary"
        let audio = Data([0, 1, 2, 3, 255])
        let body = GroqVoiceTranscriber.multipartBody(
            boundary: boundary,
            audio: audio,
            filename: "voice.m4a",
            language: "en",
            prompt: "Codex and Claude Code"
        )
        let rendered = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(rendered.contains("name=\"file\"; filename=\"voice.m4a\""))
        XCTAssertTrue(rendered.contains("audio/mp4"))
        XCTAssertTrue(rendered.contains("whisper-large-v3-turbo"))
        XCTAssertTrue(rendered.contains("verbose_json"))
        XCTAssertTrue(rendered.contains("name=\"language\"\r\n\r\nen"))
        XCTAssertTrue(rendered.contains("Codex and Claude Code"))
        XCTAssertTrue(body.range(of: audio) != nil)
        XCTAssertTrue(rendered.hasSuffix("--test-boundary--\r\n"))
    }

    func testMultipartOmitsBlankOptionalFields() {
        let body = GroqVoiceTranscriber.multipartBody(
            boundary: "b",
            audio: Data([1]),
            filename: "voice.m4a",
            language: "auto",
            prompt: "  "
        )
        let rendered = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(rendered.contains("name=\"language\""))
        XCTAssertFalse(rendered.contains("name=\"prompt\""))
    }

    func testHQMultipartCarriesTheRecordedClipWithoutCredentials() {
        let audio = Data([9, 8, 7, 6, 5])
        let body = HQVoiceTranscriber.multipartBody(
            boundary: "hq-boundary",
            audio: audio,
            filename: "jarvis.m4a"
        )
        let rendered = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(rendered.contains("name=\"file\"; filename=\"jarvis.m4a\""))
        XCTAssertTrue(rendered.contains("Content-Type: audio/mp4"))
        XCTAssertTrue(body.range(of: audio) != nil)
        XCTAssertTrue(rendered.hasSuffix("--hq-boundary--\r\n"))
        XCTAssertFalse(rendered.contains("api_key"))
    }

    func testTranscriptPolicyKeepsRealCommands() {
        XCTAssertEqual(
            VoiceTranscriptPolicy.cleaned("  Marshall, build the browser preview and run its tests.  "),
            "Marshall, build the browser preview and run its tests."
        )
    }

    func testTranscriptPolicyDropsCommonSilenceHallucinationsAndLoops() {
        XCTAssertEqual(VoiceTranscriptPolicy.cleaned("Thank you."), "")
        XCTAssertEqual(VoiceTranscriptPolicy.cleaned("you you you you"), "")
        XCTAssertEqual(VoiceTranscriptPolicy.cleaned("♪ ♪ ♪"), "")
    }

    func testRetryPolicyRetriesTransientFailuresOnly() {
        XCTAssertTrue(GroqVoiceTranscriber.shouldRetry(URLError(.timedOut)))
        XCTAssertTrue(GroqVoiceTranscriber.shouldRetry(GroqVoiceTranscriber.TranscriptionError.httpStatus(503, nil)))
        XCTAssertTrue(GroqVoiceTranscriber.shouldRetry(GroqVoiceTranscriber.TranscriptionError.httpStatus(429, nil)))
        XCTAssertFalse(GroqVoiceTranscriber.shouldRetry(GroqVoiceTranscriber.TranscriptionError.httpStatus(401, nil)))
        XCTAssertFalse(GroqVoiceTranscriber.shouldRetry(GroqVoiceTranscriber.TranscriptionError.invalidResponse))
    }

    func testRecognitionPromptPrioritizesActiveAgentNamesAndStaysBounded() {
        let preferences = VoiceTranscriptionPreferences(language: "en", prompt: String(repeating: "x", count: 600))
        let prompt = preferences.prompt(including: ["Marshall", "Skye", "Marshall", "HQ"])

        XCTAssertTrue(prompt.hasPrefix("Active workspace names: Marshall, Skye, HQ."))
        XCTAssertEqual(prompt.count, 500)
    }
}
