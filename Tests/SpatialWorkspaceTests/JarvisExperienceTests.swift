import XCTest
@testable import SpatialWorkspaceApp

final class JarvisExperienceTests: XCTestCase {
    func testExperienceOrderKeepsVoiceFirstAndAddsBothVisualModes() {
        XCTAssertEqual(
            JarvisExperienceMode.allCases,
            [.voice, .barehands, .particleField]
        )
        XCTAssertEqual(JarvisExperienceMode.barehands.title, "Barehands")
        XCTAssertEqual(JarvisExperienceMode.particleField.title, "Particle Field")
    }

    func testHandsFreeConversationListensOnlyWhenJarvisIsIdle() {
        XCTAssertTrue(
            JarvisHandsFreeConversationPolicy.shouldStartListening(
                isJarvisEnabled: true,
                isEnabled: true,
                voiceState: .idle,
                isRecording: false,
                isTranscribing: false,
                hasBlockingError: false
            )
        )

        for state in [JarvisVoiceState.listening, .thinking, .speaking, .error] {
            XCTAssertFalse(
                JarvisHandsFreeConversationPolicy.shouldStartListening(
                    isJarvisEnabled: true,
                    isEnabled: true,
                    voiceState: state,
                    isRecording: false,
                    isTranscribing: false,
                    hasBlockingError: false
                )
            )
        }
    }

    func testHandsFreeConversationDoesNotCompeteWithCaptureOrRetryErrors() {
        XCTAssertFalse(
            JarvisHandsFreeConversationPolicy.shouldStartListening(
                isJarvisEnabled: true,
                isEnabled: false,
                voiceState: .idle,
                isRecording: false,
                isTranscribing: false,
                hasBlockingError: false
            )
        )
        XCTAssertFalse(
            JarvisHandsFreeConversationPolicy.shouldStartListening(
                isJarvisEnabled: true,
                isEnabled: true,
                voiceState: .idle,
                isRecording: true,
                isTranscribing: false,
                hasBlockingError: false
            )
        )
        XCTAssertFalse(
            JarvisHandsFreeConversationPolicy.shouldStartListening(
                isJarvisEnabled: true,
                isEnabled: true,
                voiceState: .idle,
                isRecording: false,
                isTranscribing: true,
                hasBlockingError: false
            )
        )
        XCTAssertFalse(
            JarvisHandsFreeConversationPolicy.shouldStartListening(
                isJarvisEnabled: true,
                isEnabled: true,
                voiceState: .idle,
                isRecording: false,
                isTranscribing: false,
                hasBlockingError: true
            )
        )
        XCTAssertGreaterThanOrEqual(JarvisHandsFreeConversationPolicy.restartDelayNanoseconds, 300_000_000)
        XCTAssertGreaterThan(
            JarvisHandsFreeConversationPolicy.retryDelayNanoseconds,
            JarvisHandsFreeConversationPolicy.restartDelayNanoseconds
        )
    }

    func testJarvisMasterPowerPreventsAutomaticListening() {
        XCTAssertFalse(
            JarvisHandsFreeConversationPolicy.shouldStartListening(
                isJarvisEnabled: false,
                isEnabled: true,
                voiceState: .idle,
                isRecording: false,
                isTranscribing: false,
                hasBlockingError: false
            )
        )
    }

    func testConversationGovernorAssignsRecoveryDeadlinesToBlockingPhases() {
        XCTAssertNil(JarvisConversationPolicy.timeout(for: .idle))
        XCTAssertNil(JarvisConversationPolicy.timeout(for: .error))
        XCTAssertNotNil(JarvisConversationPolicy.timeout(for: .thinking))
        XCTAssertNotNil(JarvisConversationPolicy.timeout(for: .speaking))
        XCTAssertLessThan(
            try XCTUnwrap(JarvisConversationPolicy.timeout(for: .recovering)),
            try XCTUnwrap(JarvisConversationPolicy.timeout(for: .thinking))
        )
        XCTAssertEqual(JarvisConversationPolicy.defaultDetail(for: .transcribing), "Turning speech into a request")
    }

    func testVoiceHealthReportExplainsDegradedPipeline() {
        let report = JarvisVoiceHealthReport(
            checkedAt: Date(),
            checks: [
                JarvisVoiceHealthCheck(id: "mic", title: "Microphone", detail: "Ready", state: .ready),
                JarvisVoiceHealthCheck(id: "hq", title: "HQ", detail: "Offline", state: .unavailable),
                JarvisVoiceHealthCheck(id: "kokoro", title: "Kokoro", detail: "Ready", state: .fallback),
            ]
        )

        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.unavailableCount, 1)
        XCTAssertEqual(report.summary, "1 voice check needs attention")
    }

    @MainActor
    func testWorkspaceStorePublishesOneAuthoritativeVoiceSnapshot() throws {
        let persistence = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("workspaces.json")
        let store = WorkspaceStore(persistenceURL: persistence, runtimeEnabled: false)

        store.setListening(true)
        XCTAssertEqual(store.jarvisVoiceState, .listening)
        XCTAssertEqual(store.jarvisConversation.state, .listening)

        store.setTranscribing(true)
        XCTAssertEqual(store.jarvisVoiceState, .transcribing)
        XCTAssertEqual(store.jarvisConversation.detail, "Turning speech into a request")

        store.reportVoiceFailure("Microphone unavailable", retryable: false)
        XCTAssertEqual(store.jarvisVoiceState, .error)
        XCTAssertEqual(store.jarvisConversation.lastFailure, "Microphone unavailable")

        store.clearVoiceFailure()
        XCTAssertEqual(store.jarvisVoiceState, .idle)
        XCTAssertEqual(store.jarvisConversation.state, .idle)
    }

    func testBarehandsConfigurationStaysOnLoopback() {
        let configuration = BarehandsServiceConfiguration(
            repositoryURL: URL(fileURLWithPath: "/tmp/barehands", isDirectory: true),
            port: 9_123
        )

        XCTAssertEqual(
            configuration.stageURL.absoluteString,
            "http://127.0.0.1:9123/stage.html?mode=mirror&cam=Brio%20101&res=1920x1080&host=spatial"
        )
        XCTAssertEqual(
            configuration.hostedStageURL(trackerID: "spatial.test-1")?.absoluteString,
            "http://127.0.0.1:9123/stage.html?mode=mirror&cam=Brio%20101&res=1920x1080&host=spatial&trackerId=spatial.test-1"
        )
        XCTAssertEqual(
            configuration.standaloneStageURL.absoluteString,
            "http://127.0.0.1:9123/stage.html?mode=mirror&cam=Brio%20101&res=1920x1080"
        )
        XCTAssertEqual(configuration.healthURL.absoluteString, "http://127.0.0.1:9123/config")
        XCTAssertEqual(configuration.sceneStateURL.absoluteString, "http://127.0.0.1:9123/state")
        XCTAssertEqual(
            configuration.sceneStateURL(trackerID: "spatial.test-1")?.absoluteString,
            "http://127.0.0.1:9123/state?trackerId=spatial.test-1"
        )
        XCTAssertEqual(configuration.commandURL.absoluteString, "http://127.0.0.1:9123/cmd")
        XCTAssertEqual(configuration.serverURL.path, "/tmp/barehands/server.py")
    }

    func testBarehandsBoardRequestsAreBoundedAndLoopbackOnly() throws {
        let configuration = BarehandsServiceConfiguration(
            repositoryURL: URL(fileURLWithPath: "/tmp/barehands", isDirectory: true),
            port: 9_123
        )
        let trackerID = "spatial.test-1"

        for command in BarehandsBoardCommand.allCases {
            let commandID = "command.\(command.rawValue)"
            let request = try XCTUnwrap(
                configuration.boardCommandRequest(
                    command,
                    trackerID: trackerID,
                    commandID: commandID
                )
            )
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:9123/cmd")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 2)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let payload = try XCTUnwrap(
                try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
            )
            XCTAssertEqual(payload["a"] as? String, command.rawValue)
            XCTAssertEqual(payload["trackerId"] as? String, trackerID)
            XCTAssertEqual(payload["commandId"] as? String, commandID)
            XCTAssertEqual(payload["confirmed"] as? Bool, command == .clearBoard ? true : nil)
        }

        XCTAssertNil(
            configuration.boardCommandRequest(
                .findRing,
                trackerID: "contains a space",
                commandID: "valid-id"
            )
        )
        XCTAssertNil(configuration.hostedStageURL(trackerID: String(repeating: "a", count: 65)))
    }

    func testBarehandsTrackingSnapshotDecodesHandsPinchesAndItems() {
        let data = Data(#"{"updatedAtMs":1776556800000,"cursors":[{"x":0.2,"y":0.4,"p":1,"hover":{"id":1,"type":"widget","title":"Jarvis"}},{"x":0.7,"y":0.3,"p":0}],"items":[{"id":1},{"id":2}]}"#.utf8)

        XCTAssertEqual(
            BarehandsTrackingSnapshot.decode(data),
            BarehandsTrackingSnapshot(
                handCount: 2,
                pinchedHandCount: 1,
                itemCount: 2,
                hoveredTargets: [BarehandsHoverTarget(id: 1, type: "widget", title: "Jarvis")],
                updatedAtMilliseconds: 1_776_556_800_000
            )
        )
    }

    func testBarehandsTrackingSnapshotDecodesProgressiveCoachAndUndoState() throws {
        let data = Data(
            #"""
            {
              "updatedAtMs": 1776556800000,
              "cursors": [{"x":0.2,"y":0.4,"p":1}],
              "items": [{"id":1}],
              "interaction": {
                "phase":"rejected",
                "reason":"use_one_hand",
                "target":{"id":1,"type":"widget","title":"Jarvis"}
              },
              "coach":{"step":"make_ok_sign","completed":false},
              "board":{"undoClearAvailable":true,"undoExpiresAtMs":1776556812000}
            }
            """#.utf8
        )

        let snapshot = try XCTUnwrap(BarehandsTrackingSnapshot.decode(data))
        XCTAssertEqual(
            snapshot.interaction,
            BarehandsInteractionSnapshot(
                phase: .rejected,
                reason: .useOneHand,
                target: BarehandsHoverTarget(id: 1, type: "widget", title: "Jarvis")
            )
        )
        XCTAssertEqual(
            snapshot.coach,
            BarehandsCoachSnapshot(step: .makeOKSign, completed: false)
        )
        XCTAssertEqual(
            snapshot.board,
            BarehandsBoardSnapshot(
                undoClearAvailable: true,
                undoExpiresAtMilliseconds: 1_776_556_812_000
            )
        )
    }

    func testBarehandsTrackingSnapshotDecodesScopedCommandResultAndClearableItems() throws {
        let data = Data(
            #"{"updatedAtMs":1776556800000,"trackerId":"spatial.test-1","commandResult":{"commandId":"command-1","action":"clear_board","status":"rejected","reason":"nothing_to_clear"},"cursors":[],"items":[{"id":1,"type":"widget","w":"ring"},{"id":2,"type":"card"}]}"#.utf8
        )

        let snapshot = try XCTUnwrap(BarehandsTrackingSnapshot.decode(data))
        XCTAssertEqual(snapshot.trackerID, "spatial.test-1")
        XCTAssertEqual(snapshot.itemCount, 2)
        XCTAssertEqual(snapshot.clearableItemCount, 1)
        XCTAssertTrue(snapshot.hasClearableContent)
        XCTAssertEqual(
            snapshot.commandResult,
            BarehandsCommandResult(
                commandID: "command-1",
                action: .clearBoard,
                status: .rejected,
                reason: "nothing_to_clear"
            )
        )
    }

    func testBarehandsTrackingSnapshotFailsClosedForMalformedAdditiveState() {
        let unknownPhase = Data(
            #"{"cursors":[],"items":[],"interaction":{"phase":"future_success"}}"#.utf8
        )
        let unknownReason = Data(
            #"{"cursors":[],"items":[],"interaction":{"phase":"rejected","reason":"future_reason"}}"#.utf8
        )
        let unknownCoach = Data(
            #"{"cursors":[],"items":[],"coach":{"step":"future_step","completed":false}}"#.utf8
        )
        let numericBoolean = Data(
            #"{"cursors":[],"items":[],"board":{"undoClearAvailable":1,"undoExpiresAtMs":1776556812000}}"#.utf8
        )
        let missingUndoDeadline = Data(
            #"{"cursors":[],"items":[],"board":{"undoClearAvailable":true}}"#.utf8
        )
        let invalidTracker = Data(
            #"{"trackerId":"not valid","cursors":[],"items":[]}"#.utf8
        )
        let resultWithoutTracker = Data(
            #"{"commandResult":{"commandId":"command-1","action":"fit_board","status":"applied"},"cursors":[],"items":[]}"#.utf8
        )
        let invalidCommandID = Data(
            #"{"trackerId":"spatial-1","commandResult":{"commandId":"bad command","action":"fit_board","status":"applied"},"cursors":[],"items":[]}"#.utf8
        )
        let unknownCommandStatus = Data(
            #"{"trackerId":"spatial-1","commandResult":{"commandId":"command-1","action":"fit_board","status":"queued"},"cursors":[],"items":[]}"#.utf8
        )
        let controlCharacterReason = Data(
            #"{"trackerId":"spatial-1","commandResult":{"commandId":"command-1","action":"fit_board","status":"rejected","reason":"bad\nreason"},"cursors":[],"items":[]}"#.utf8
        )

        XCTAssertNil(BarehandsTrackingSnapshot.decode(unknownPhase))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(unknownReason))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(unknownCoach))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(numericBoolean))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(missingUndoDeadline))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(invalidTracker))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(resultWithoutTracker))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(invalidCommandID))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(unknownCommandStatus))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(controlCharacterReason))
    }

    func testBarehandsCommandAcknowledgementRequiresExactTrackerCommandAndAction() throws {
        let data = Data(
            #"{"trackerId":"spatial-1","commandResult":{"commandId":"command-1","action":"fit_board","status":"applied"},"cursors":[],"items":[{"type":"widget","w":"ring"}]}"#.utf8
        )
        let snapshot = try XCTUnwrap(BarehandsTrackingSnapshot.decode(data))

        XCTAssertTrue(snapshot.isAuthoritative(for: "spatial-1"))
        XCTAssertFalse(snapshot.isAuthoritative(for: "another-tracker"))

        XCTAssertEqual(
            snapshot.commandAcknowledgement(
                trackerID: "spatial-1",
                commandID: "command-1",
                command: .fitBoard
            ),
            .applied
        )
        XCTAssertNil(
            snapshot.commandAcknowledgement(
                trackerID: "another-tracker",
                commandID: "command-1",
                command: .fitBoard
            )
        )
        XCTAssertNil(
            snapshot.commandAcknowledgement(
                trackerID: "spatial-1",
                commandID: "another-command",
                command: .fitBoard
            )
        )
        XCTAssertNil(
            snapshot.commandAcknowledgement(
                trackerID: "spatial-1",
                commandID: "command-1",
                command: .findRing
            )
        )
    }

    func testBarehandsFreshSnapshotForAnotherTrackerIsNotActionable() throws {
        let updatedAtMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)
        let snapshot = try XCTUnwrap(
            BarehandsTrackingSnapshot.decode(
                Data(
                    "{\"updatedAtMs\":\(updatedAtMilliseconds),\"trackerId\":\"another-tracker\",\"cursors\":[],\"items\":[{\"type\":\"card\"}]}".utf8
                )
            )
        )

        XCTAssertTrue(snapshot.isFresh())
        XCTAssertFalse(
            BarehandsBoardCommandAvailability.isActionable(
                connectionState: .ready,
                snapshot: snapshot,
                snapshotIsStale: false,
                trackerID: "spatial-1"
            )
        )
        XCTAssertTrue(
            BarehandsBoardCommandAvailability.isActionable(
                connectionState: .ready,
                snapshot: snapshot,
                snapshotIsStale: false,
                trackerID: "another-tracker"
            )
        )
    }

    @MainActor
    func testBarehandsCommandAcknowledgerReportsRejectionAndTimeout() async throws {
        let rejected = try XCTUnwrap(
            BarehandsTrackingSnapshot.decode(
                Data(
                    #"{"trackerId":"spatial-1","commandResult":{"commandId":"command-1","action":"clear_board","status":"rejected","reason":"nothing_to_clear"},"cursors":[],"items":[]}"#.utf8
                )
            )
        )
        let rejection = await BarehandsCommandAcknowledger.wait(
            trackerID: "spatial-1",
            commandID: "command-1",
            command: .clearBoard,
            timeout: 0.05,
            pollIntervalNanoseconds: 1_000_000
        ) { rejected }
        XCTAssertEqual(rejection, .rejected("nothing_to_clear"))

        let mismatched = await BarehandsCommandAcknowledger.wait(
            trackerID: "another-tracker",
            commandID: "command-1",
            command: .clearBoard,
            timeout: 0.01,
            pollIntervalNanoseconds: 1_000_000
        ) { rejected }
        XCTAssertEqual(mismatched, .timedOut)

        let timeout = await BarehandsCommandAcknowledger.wait(
            trackerID: "spatial-1",
            commandID: "command-1",
            command: .fitBoard,
            timeout: 0.01,
            pollIntervalNanoseconds: 1_000_000
        ) { nil }
        XCTAssertEqual(timeout, .timedOut)
    }

    func testBarehandsReloadConfirmationProtectsContentAndUndoState() throws {
        let jarvisOnly = try XCTUnwrap(
            BarehandsTrackingSnapshot.decode(
                Data(#"{"cursors":[],"items":[{"type":"widget","w":"ring"}],"board":{"undoClearAvailable":false}}"#.utf8)
            )
        )
        XCTAssertEqual(jarvisOnly.clearableItemCount, 0)
        XCTAssertFalse(jarvisOnly.requiresReloadConfirmation)

        let openContent = try XCTUnwrap(
            BarehandsTrackingSnapshot.decode(
                Data(#"{"cursors":[],"items":[{"type":"widget","w":"ring"},{"type":"card"}],"board":{"undoClearAvailable":false}}"#.utf8)
            )
        )
        XCTAssertTrue(openContent.requiresReloadConfirmation)

        let undoAvailable = try XCTUnwrap(
            BarehandsTrackingSnapshot.decode(
                Data(#"{"cursors":[],"items":[{"type":"widget","w":"ring"}],"board":{"undoClearAvailable":true,"undoExpiresAtMs":1776556812000}}"#.utf8)
            )
        )
        XCTAssertTrue(undoAvailable.requiresReloadConfirmation)
    }

    func testBarehandsReloadConfirmationFailsClosedForMismatchedTracker() throws {
        let ringOnly = try XCTUnwrap(
            BarehandsTrackingSnapshot.decode(
                Data(
                    #"{"trackerId":"another-tracker","cursors":[],"items":[{"type":"widget","w":"ring"}],"board":{"undoClearAvailable":false}}"#.utf8
                )
            )
        )
        XCTAssertFalse(ringOnly.requiresReloadConfirmation)
        XCTAssertTrue(
            BarehandsReloadProtection.requiresConfirmation(
                snapshot: ringOnly,
                snapshotIsStale: false,
                trackerID: "spatial-1"
            )
        )
        XCTAssertFalse(
            BarehandsReloadProtection.requiresConfirmation(
                snapshot: ringOnly,
                snapshotIsStale: false,
                trackerID: "another-tracker"
            )
        )
    }

    func testBarehandsTrackingSnapshotAcceptsExplicitlyEmptyInteractionTarget() throws {
        let data = Data(
            #"{"cursors":[],"items":[{"id":1}],"interaction":{"phase":"waiting_for_hand","reason":"no_hand","target":null}}"#.utf8
        )

        let snapshot = try XCTUnwrap(BarehandsTrackingSnapshot.decode(data))
        XCTAssertEqual(
            snapshot.interaction,
            BarehandsInteractionSnapshot(phase: .waitingForHand, reason: .noHand, target: nil)
        )
    }

    func testBarehandsTrackingSnapshotBoundsScenePayload() {
        let tooManyCursors = Data(
            #"{"cursors":[{"p":0},{"p":0},{"p":0}],"items":[]}"#.utf8
        )
        let oversized = Data(repeating: 0x20, count: 262_145)

        XCTAssertNil(BarehandsTrackingSnapshot.decode(tooManyCursors))
        XCTAssertNil(BarehandsTrackingSnapshot.decode(oversized))
    }

    func testBarehandsUndoWindowUsesServerDeadline() {
        let board = BarehandsBoardSnapshot(
            undoClearAvailable: true,
            undoExpiresAtMilliseconds: 1_776_556_812_000
        )
        let beforeExpiration = Date(timeIntervalSince1970: 1_776_556_800)
        let afterExpiration = Date(timeIntervalSince1970: 1_776_556_813)

        XCTAssertTrue(board.canUndoClear(at: beforeExpiration))
        XCTAssertEqual(board.undoSecondsRemaining(at: beforeExpiration), 12)
        XCTAssertFalse(board.canUndoClear(at: afterExpiration))
        XCTAssertNil(board.undoSecondsRemaining(at: afterExpiration))
        XCTAssertFalse(
            BarehandsBoardSnapshot(
                undoClearAvailable: false,
                undoExpiresAtMilliseconds: 1_776_556_812_000
            ).canUndoClear(at: beforeExpiration)
        )
    }

    func testBarehandsTrackingSnapshotFreshnessRejectsRetainedAndFutureState() {
        let now = Date(timeIntervalSince1970: 1_776_556_800)
        XCTAssertTrue(
            BarehandsTrackingSnapshot(
                handCount: 1,
                pinchedHandCount: 0,
                itemCount: 1,
                updatedAtMilliseconds: 1_776_556_799_000
            ).isFresh(at: now)
        )
        XCTAssertFalse(
            BarehandsTrackingSnapshot(
                handCount: 1,
                pinchedHandCount: 0,
                itemCount: 1,
                updatedAtMilliseconds: 1_776_556_797_000
            ).isFresh(at: now)
        )
        XCTAssertFalse(
            BarehandsTrackingSnapshot(
                handCount: 1,
                pinchedHandCount: 0,
                itemCount: 1,
                updatedAtMilliseconds: 1_776_556_805_000
            ).isFresh(at: now)
        )
    }

    func testBarehandsFailedPollOnlyRetainsFreshOrStartupGraceState() {
        let now = Date(timeIntervalSince1970: 1_776_556_800)
        let fresh = BarehandsTrackingSnapshot(
            handCount: 1,
            pinchedHandCount: 0,
            itemCount: 1,
            updatedAtMilliseconds: 1_776_556_799_000
        )
        let stale = BarehandsTrackingSnapshot(
            handCount: 1,
            pinchedHandCount: 0,
            itemCount: 1,
            updatedAtMilliseconds: 1_776_556_797_000
        )
        let legacy = BarehandsTrackingSnapshot(
            handCount: 1,
            pinchedHandCount: 0,
            itemCount: 1
        )

        XCTAssertTrue(fresh.remainsAuthoritativeAfterFailedPoll(at: now, legacyDeadline: nil))
        XCTAssertFalse(stale.remainsAuthoritativeAfterFailedPoll(at: now, legacyDeadline: nil))
        XCTAssertTrue(
            legacy.remainsAuthoritativeAfterFailedPoll(
                at: now,
                legacyDeadline: now.addingTimeInterval(1)
            )
        )
        XCTAssertFalse(
            legacy.remainsAuthoritativeAfterFailedPoll(
                at: now,
                legacyDeadline: now.addingTimeInterval(-1)
            )
        )
    }

    func testBarehandsTrackingSnapshotAcceptsLegacyCursorWithoutHoverTarget() {
        let data = Data(#"{"cursors":[{"x":0.2,"y":0.4,"p":0}],"items":[{"id":1}]}"#.utf8)

        XCTAssertEqual(
            BarehandsTrackingSnapshot.decode(data),
            BarehandsTrackingSnapshot(handCount: 1, pinchedHandCount: 0, itemCount: 1)
        )
    }

    func testBarehandsTrackingSnapshotRejectsNonScenePayload() {
        XCTAssertNil(BarehandsTrackingSnapshot.decode(Data(#"{"status":"ok"}"#.utf8)))
    }

    func testHQParticleConfigurationUsesLoopbackAndSafeSSHArguments() {
        let configuration = HQParticleServiceConfiguration(
            sshHost: "render-test-host",
            localPort: 4_200,
            remotePort: 3_200,
            serviceName: "hq-test.service"
        )

        XCTAssertEqual(configuration.voiceURL.absoluteString, "http://127.0.0.1:4200/voice")
        XCTAssertTrue(configuration.remoteStartArguments.contains("hq-test.service"))
        XCTAssertTrue(configuration.tunnelArguments.contains("127.0.0.1:4200:127.0.0.1:3200"))
        XCTAssertTrue(configuration.tunnelArguments.contains("ExitOnForwardFailure=yes"))
    }

    func testBarehandsConnectionLabelsExplainEveryState() {
        let states: [BarehandsConnectionState] = [
            .stopped,
            .checking,
            .starting,
            .ready,
            .missing,
            .failed("failure"),
        ]

        for state in states {
            XCTAssertFalse(state.label.isEmpty)
        }
    }

    func testBarehandsJarvisCommunicationOnlyAcceptsHeldWidgetPinch() {
        let ring = BarehandsHoverTarget(id: 1, type: "widget", title: "Friday")
        let card = BarehandsHoverTarget(id: 2, type: "card", title: "Notes")

        XCTAssertTrue(
            BarehandsJarvisCommunication.isRingHold(
                BarehandsInteractionSnapshot(phase: .pinching, reason: .releaseQuickly, target: ring)
            )
        )
        XCTAssertFalse(
            BarehandsJarvisCommunication.isRingHold(
                BarehandsInteractionSnapshot(phase: .ready, reason: .holdOKSign, target: ring)
            )
        )
        XCTAssertFalse(
            BarehandsJarvisCommunication.isRingHold(
                BarehandsInteractionSnapshot(phase: .pinching, reason: .releaseQuickly, target: card)
            )
        )
        XCTAssertEqual(BarehandsJarvisCommunication.holdDurationNanoseconds, 650_000_000)
    }

    func testBarehandsAssistantVisualStateMapsJarvisWithoutExposingUnsupportedState() {
        XCTAssertEqual(BarehandsAssistantVisualState.resolve(.idle), .init(state: "idle", mood: "green"))
        XCTAssertEqual(BarehandsAssistantVisualState.resolve(.listening), .init(state: "listening", mood: "green"))
        XCTAssertEqual(BarehandsAssistantVisualState.resolve(.thinking), .init(state: "thinking", mood: "green"))
        XCTAssertEqual(BarehandsAssistantVisualState.resolve(.speaking), .init(state: "speaking", mood: "green"))
        XCTAssertEqual(BarehandsAssistantVisualState.resolve(.error), .init(state: "idle", mood: "amber"))
    }

    func testBarehandsAssistantStateWriterPublishesFaceAndBoundedWave() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("barehands-assistant-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = BarehandsAssistantStateWriter(stateDirectoryURL: root)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        try writer.write(.resolve(.speaking), audioLevel: 4, now: now)

        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("state"), encoding: .utf8),
            "speaking"
        )
        let mood = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent("mood.json"))
            ) as? [String: Any]
        )
        XCTAssertEqual(mood["mood"] as? String, "green")
        let wave = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: root.appendingPathComponent("wave.json"))
            ) as? [String: Any]
        )
        let samples = try XCTUnwrap(wave["samples"] as? [NSNumber])
        XCTAssertEqual(samples.count, 64)
        XCTAssertTrue(samples.allSatisfy { $0.doubleValue == 1 })
    }
}
