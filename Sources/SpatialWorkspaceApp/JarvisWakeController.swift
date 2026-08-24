import AVFoundation
import Foundation
import Speech

/// Always-on "Jarvis" wake word for the Jarvis screen. Uses on-device
/// `SFSpeechRecognizer` (no API quota, no network) to listen continuously; when
/// it hears the wake word it captures the rest of the spoken phrase and, after a
/// short pause, hands the command to `onCommand`. Per the ClawVoice rule, the
/// wake word captures the FULL phrase — "Jarvis, what's the build status?"
/// delivers "what's the build status?", it doesn't just wake and wait.
@MainActor
final class JarvisWakeController: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var statusText = "Wake word off"
    @Published private(set) var lastHeard = ""
    @Published private(set) var authorizationDenied = false

    /// Called on the main actor with the captured command (wake word stripped).
    var onCommand: ((String) -> Void)?
    /// Fires as soon as the wake phrase is recognized. The host uses this to
    /// stop Jarvis playback before capturing an interruption.
    var onWake: (() -> Void)?
    var onWakeCancelled: (() -> Void)?

    private let wakeWords = ["jarvis", "hey jarvis", "ok jarvis", "hey, jarvis"]
    private let silenceToFinalize: TimeInterval = 1.4
    private let emptyWakeTimeout: TimeInterval = 4.0

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var endpointTimer: Timer?

    private var enabled = false
    private var suppressed = false
    private var interruptionMode = false
    // Barge-in must be DELIBERATE, or Jarvis gets cut off too easily: ignore
    // interrupts in the opening moments after Jarvis starts speaking, and require
    // the wake phrase to persist across the recognizer's partials rather than
    // firing on a single fleeting mis-hear.
    private var interruptionModeSince: Date?
    private var interruptCandidateSince: Date?
    private let interruptGrace: TimeInterval = 0.6
    private let interruptConfirmDelay: TimeInterval = 0.35

    // Per-turn capture state.
    private var awake = false
    private var wokeAt = Date()
    private var command = ""
    private var lastChange = Date()

    // MARK: - Public control

    func setEnabled(_ on: Bool) {
        if on {
            let shouldStart = !enabled || (!suppressed && !isListening)
            enabled = true
            guard shouldStart else { return }
            Task { await authorizeAndStart() }
        } else {
            guard enabled || isListening else {
                statusText = "Wake word off"
                return
            }
            enabled = false
            teardown()
            statusText = "Wake word off"
        }
    }

    func setInterruptionMode(_ value: Bool) {
        if value && !interruptionMode { interruptionModeSince = Date() }
        interruptionMode = value
        if !value { interruptCandidateSince = nil }
    }

    /// Silence the wake word while Jarvis is speaking or a manual recording is
    /// active, so the mic doesn't capture Jarvis's own voice or fight the recorder.
    func setSuppressed(_ value: Bool) {
        guard value != suppressed else { return }
        suppressed = value
        guard enabled else { return }
        if value {
            stopEngine()
            resetTurn()
            statusText = "Paused"
        } else {
            startEngine()
        }
    }

    // MARK: - Authorization + start

    private func authorizeAndStart() async {
        guard recognizer?.isAvailable == true else {
            statusText = "Speech recognition unavailable"
            return
        }
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard enabled else { return }
        switch status {
        case .authorized:
            authorizationDenied = false
            if !suppressed { startEngine() }
        default:
            authorizationDenied = true
            statusText = "Speech access denied — enable it in System Settings ▸ Privacy"
        }
    }

    // MARK: - Engine lifecycle

    private func startEngine() {
        guard enabled, !suppressed, !audioEngine.isRunning else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = audioEngine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        if !tapInstalled {
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            tapInstalled = true
        }

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error)
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            resetTurn()
            statusText = "Listening for “Jarvis”"
            startEndpointTimer()
        } catch {
            statusText = "Microphone unavailable"
            isListening = false
        }
    }

    private func stopEngine() {
        endpointTimer?.invalidate()
        endpointTimer = nil
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        if audioEngine.isRunning { audioEngine.pause() }
        isListening = false
    }

    private func teardown() {
        stopEngine()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
        resetTurn()
    }

    /// Recreate the recognition request/task to clear the accumulated transcript
    /// so the next "Jarvis" isn't matched against stale words. The audio tap stays
    /// installed and simply feeds the new request.
    private func restartRecognition() {
        task?.cancel()
        task = nil
        request?.endAudio()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request
        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                self?.handle(result: result, error: error)
            }
        }
        resetTurn()
    }

    // MARK: - Recognition handling

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            let transcript = result.bestTranscription.formattedString
            lastHeard = transcript
            ingest(transcript: transcript.lowercased())
        }
        if error != nil || (result?.isFinal ?? false) {
            // The task ended (error, or Apple's per-utterance limit). If we were
            // mid-command, finalize it; then start a fresh recognition pass.
            if awake, !command.isEmpty {
                dispatchCommand()
            } else if awake {
                onWakeCancelled?()
            }
            if enabled, !suppressed { restartRecognition() }
        }
    }

    private func ingest(transcript: String) {
        guard !transcript.isEmpty else { return }

        if !awake {
            guard let range = wakeRange(in: transcript) else {
                interruptCandidateSince = nil
                return
            }
            // While Jarvis is speaking, only barge in on a deliberate, sustained
            // wake phrase — past the opening grace window and held long enough
            // that a momentary mis-hear can't cut Jarvis off.
            if interruptionMode, !interruptionConfirmed() { return }
            awake = true
            onWake?()
            wokeAt = Date()
            lastChange = Date()
            command = String(transcript[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            statusText = "Yes? Listening…"
        } else {
            // Everything after the most recent wake word is the command.
            let tail: String
            if let range = wakeRange(in: transcript) {
                tail = String(transcript[range.upperBound...])
            } else {
                tail = transcript
            }
            let trimmed = tail.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed != command {
                command = trimmed
                lastChange = Date()
            }
        }
    }

    /// A barge-in counts only once the wake phrase has survived the opening
    /// grace window and been present across at least `interruptConfirmDelay`.
    private func interruptionConfirmed() -> Bool {
        let now = Date()
        if let since = interruptionModeSince, now.timeIntervalSince(since) < interruptGrace {
            return false                       // too soon after Jarvis started speaking
        }
        if interruptCandidateSince == nil {
            interruptCandidateSince = now      // first sighting — wait for it to persist
            return false
        }
        return now.timeIntervalSince(interruptCandidateSince!) >= interruptConfirmDelay
    }

    private func wakeRange(in transcript: String) -> Range<String.Index>? {
        // Prefer the last occurrence so re-triggers use the freshest command.
        var best: Range<String.Index>?
        let activeWakeWords = interruptionMode ? ["hey jarvis", "ok jarvis", "hey, jarvis"] : wakeWords
        for word in activeWakeWords {
            var searchStart = transcript.startIndex
            while let found = transcript.range(of: word, range: searchStart ..< transcript.endIndex) {
                if best == nil || found.lowerBound > best!.lowerBound { best = found }
                searchStart = found.upperBound
            }
        }
        return best
    }

    // MARK: - Endpointing

    private func startEndpointTimer() {
        endpointTimer?.invalidate()
        endpointTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkEndpoint() }
        }
    }

    private func checkEndpoint() {
        guard awake else { return }
        let now = Date()
        if !command.isEmpty, now.timeIntervalSince(lastChange) >= silenceToFinalize {
            dispatchCommand()
            restartRecognition()
        } else if command.isEmpty, now.timeIntervalSince(wokeAt) >= emptyWakeTimeout {
            // Heard "Jarvis" but no command followed — reset and keep listening.
            resetTurn()
            statusText = "Listening for “Jarvis”"
            onWakeCancelled?()
        }
    }

    private func dispatchCommand() {
        let phrase = command.trimmingCharacters(in: .whitespacesAndNewlines)
        resetTurn()
        guard phrase.count >= 2 else {
            statusText = "Listening for “Jarvis”"
            onWakeCancelled?()
            return
        }
        statusText = "Sent: “\(phrase.prefix(48))”"
        onCommand?(phrase)
    }

    private func resetTurn() {
        awake = false
        command = ""
        wokeAt = Date()
        lastChange = Date()
        interruptCandidateSince = nil
    }
}
