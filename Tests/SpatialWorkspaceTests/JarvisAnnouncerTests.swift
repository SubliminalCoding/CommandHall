import XCTest
@testable import SpatialWorkspaceApp

final class JarvisAnnouncerTests: XCTestCase {
    func testJarvisDefaultsToServerOwnedHQBackend() {
        let saved = UserDefaults.standard.object(forKey: JarvisBackend.kindKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: JarvisBackend.kindKey)
            } else {
                UserDefaults.standard.removeObject(forKey: JarvisBackend.kindKey)
            }
        }
        UserDefaults.standard.removeObject(forKey: JarvisBackend.kindKey)

        XCTAssertEqual(JarvisBackend.kind, .hq)
    }

    func testProcessingSoundIsBoundedAndLoopsWithoutAnEdgeClick() {
        let samples = JarvisProcessingSoundPattern.samples(sampleRate: 8_000, duration: 1.6)

        XCTAssertEqual(samples.count, 12_800)
        XCTAssertLessThanOrEqual(samples.map { abs($0) }.max() ?? 1, 0.42)
        XCTAssertEqual(samples.first ?? 1, 0, accuracy: 0.0001)
        XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.002)
        XCTAssertTrue(samples.contains { abs($0) > 0.2 })
    }

    func testSpeechRequestUsesHQVoiceProxyWithoutCopyingCredentials() throws {
        let endpoint = URL(string: "http://127.0.0.1:3200/api/voice/tts")!
        let request = try JarvisSpeechRequest.makeHQ(text: "Nova is ready.", endpoint: endpoint)
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(HQJarvisSpeechPayload.self, from: body)

        XCTAssertEqual(request.url, URL(string: "http://127.0.0.1:3200/api/voice/tts"))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(payload.text, "Nova is ready.")
        XCTAssertFalse(String(decoding: body, as: UTF8.self).localizedCaseInsensitiveContains("api_key"))
    }

    func testLocalKokoroFallbackRetainsJarvisVoice() throws {
        let request = try JarvisSpeechRequest.makeLocalKokoro(text: "Nova is ready.")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try JSONDecoder().decode(JarvisSpeechPayload.self, from: body)

        XCTAssertEqual(request.url, URL(string: "http://127.0.0.1:8880/v1/audio/speech"))
        XCTAssertEqual(payload.model, "kokoro")
        XCTAssertEqual(payload.input, "Nova is ready.")
        XCTAssertEqual(payload.voice, "am_michael")
        XCTAssertEqual(payload.responseFormat, "mp3")
    }

    func testHQJarvisStreamParsesContentAndIgnoresHeartbeats() {
        XCTAssertNil(HQJarvisStream.event(from: ": hb"))
        XCTAssertEqual(
            HQJarvisStream.event(from: "data: {\"type\":\"chunk\",\"content\":\"Straight answer.\"}"),
            HQJarvisStreamEvent(type: "chunk", content: "Straight answer.", replace: nil, message: nil)
        )
    }

    func testStreamingSpeechEmitsFirstSentenceBeforeReplyFinishes() {
        var buffer = JarvisSpeechChunkBuffer()

        XCTAssertEqual(buffer.append("Nova is on it."), ["Nova is on it."])
        XCTAssertEqual(buffer.append(" She is checking"), [])
        XCTAssertEqual(buffer.finish(), ["She is checking"])
    }

    func testPreferredVoiceKeepsHQKokoroAndLocalFallbackOrder() {
        XCTAssertEqual(
            JarvisSpeechClient.providerOrder(for: .kokoro),
            [.hqKokoro, .kokoro]
        )
        XCTAssertEqual(
            JarvisSpeechClient.providerOrder(for: .automatic),
            [.hqKokoro, .kokoro]
        )
    }

    func testStreamingSpeechNeverReadsDelegationControlBlock() {
        var buffer = JarvisSpeechChunkBuffer()

        XCTAssertEqual(buffer.append("I'll put Nova on it. <spatial_"), ["I'll put Nova on it."])
        XCTAssertEqual(
            buffer.append("delegations>{\"version\":1,\"delegations\":[{\"agent\":\"Nova\",\"task\":\"Build it\"}]}</spatial_delegations>"),
            []
        )
        XCTAssertEqual(buffer.finish(), [])
    }

    func testStreamingSpeechBoundsLongClausesAtAWordBoundary() {
        var buffer = JarvisSpeechChunkBuffer()
        let clause = Array(repeating: "steady", count: 35).joined(separator: " ")

        let chunks = buffer.append(clause)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertGreaterThanOrEqual(chunks[0].count, 100)
        XCTAssertLessThanOrEqual(chunks[0].count, 180)
    }

    @MainActor
    func testCompletionAnnouncementsUseJarvisStyleStatusLanguage() {
        XCTAssertEqual(
            WorkspaceStore.completionAnnouncement(nodeName: "Nova", reviewState: .readyToReview, artifactCount: 2),
            "Nova is done. I found 2 artifacts ready for review."
        )
        XCTAssertEqual(
            WorkspaceStore.completionAnnouncement(nodeName: "Maya", reviewState: .needsEvidence, artifactCount: 0),
            "Maya finished, but I couldn't find proof of the work. It needs a look."
        )
        XCTAssertEqual(
            WorkspaceStore.completionAnnouncement(nodeName: "Marshall", reviewState: .failed, artifactCount: 0),
            "Marshall hit a problem and needs your attention."
        )
    }

    @MainActor
    func testLiaisonPromptSeparatesAgentWorkFromJarvisNarration() {
        let prompt = WorkspaceStore.liaisonPrompt(
            nodeName: "Nova",
            request: "Build the preview",
            reviewState: .readyToReview,
            summary: "Added the preview and verified the build.",
            evidence: [RunEvidence(label: "Build", detail: "Passed", passed: true)],
            artifacts: [
                WorkspaceArtifact(kind: .html, title: "Preview", location: "/tmp/preview.html", verified: true),
            ]
        )

        XCTAssertTrue(prompt.contains("Speak on Nova's behalf"))
        XCTAssertTrue(prompt.contains("Never claim success beyond the evidence"))
        XCTAssertTrue(prompt.contains("Added the preview"))
        XCTAssertTrue(prompt.contains("Preview (Web page)"))
    }

    @MainActor
    func testLiaisonFallbackIncludesResultAndProof() {
        let message = WorkspaceStore.liaisonFallbackAnnouncement(
            nodeName: "Marshall",
            reviewState: .readyToReview,
            summary: "The snake game now runs in the browser.",
            artifacts: [
                WorkspaceArtifact(kind: .html, title: "Snake", location: "/tmp/snake.html", verified: true),
            ]
        )

        XCTAssertTrue(message.contains("The snake game now runs in the browser"))
        XCTAssertTrue(message.contains("including Snake"))
        XCTAssertTrue(message.contains("Review Room"))
    }

    @MainActor
    func testPlaybackMeterNormalizesSilenceAndSpeech() {
        XCTAssertLessThan(JarvisAnnouncer.normalizedLevel(fromDecibels: -55), 0.03)
        XCTAssertGreaterThan(JarvisAnnouncer.normalizedLevel(fromDecibels: -8), 0.5)
    }
}
