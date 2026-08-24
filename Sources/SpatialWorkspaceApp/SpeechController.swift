import AVFoundation
import Foundation
import Security
import Speech

private struct VoiceTranscriptionTimeoutError: Error {}

@MainActor
final class SpeechController: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var inputLevel = 0.0
    @Published private(set) var silenceProgress = 0.0
    @Published private(set) var autoStopRequested = false
    @Published private(set) var handsFreeRetryAllowed = false
    @Published private(set) var partialTranscript = ""
    @Published private(set) var transcriptConfidence: Float?

    private let transcriber: WorkspaceVoiceTranscriber
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingStartedAt: Date?
    private var meterTask: Task<Void, Never>?
    private var speechStartedAt: Date?
    private var silenceStartedAt: Date?
    private var noiseFloor = 0.025
    private let liveRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let liveCaptionEngine = AVAudioEngine()
    private var liveCaptionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var liveCaptionTask: SFSpeechRecognitionTask?
    private var liveCaptionTapInstalled = false

    init(transcriber: WorkspaceVoiceTranscriber = WorkspaceVoiceTranscriber()) {
        self.transcriber = transcriber
    }

    var isBusy: Bool { isRecording || isTranscribing }

    func start() async -> Bool {
        guard !isBusy else { return isRecording }
        errorMessage = nil
        handsFreeRetryAllowed = false
        transcript = ""
        partialTranscript = ""
        transcriptConfidence = nil

        guard await microphoneIsAuthorized() else {
            errorMessage = "Microphone access is off. Enable Spatial Workspace in System Settings › Privacy & Security › Microphone."
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spatial-voice-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                try? FileManager.default.removeItem(at: url)
                errorMessage = "The microphone could not start recording"
                return false
            }
            self.recorder = recorder
            recordingURL = url
            recordingStartedAt = Date()
            speechStartedAt = nil
            silenceStartedAt = nil
            silenceProgress = 0
            autoStopRequested = false
            noiseFloor = 0.025
            isRecording = true
            startMetering(recorder)
            await startLiveCaptioningIfAvailable()
            return true
        } catch {
            try? FileManager.default.removeItem(at: url)
            errorMessage = "The microphone could not start: \(error.localizedDescription)"
            return false
        }
    }

    func stopAndTranscribe(contextTerms: [String] = []) async -> String? {
        guard isRecording, let recorder, let recordingURL else { return nil }

        let duration = max(recorder.currentTime, Date().timeIntervalSince(recordingStartedAt ?? Date()))
        stopMetering()
        stopLiveCaptioning()
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        recordingStartedAt = nil
        isRecording = false

        defer { try? FileManager.default.removeItem(at: recordingURL) }

        guard duration >= 0.75 else {
            errorMessage = "Recording too short. Hold the microphone a little longer."
            handsFreeRetryAllowed = true
            return nil
        }

        let byteCount = (try? recordingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard byteCount >= 1_024 else {
            errorMessage = "No usable audio was recorded. Try again closer to the microphone."
            handsFreeRetryAllowed = true
            return nil
        }
        guard byteCount <= WorkspaceVoiceTranscriber.maximumAudioBytes else {
            errorMessage = "That recording is too large. Try a shorter command."
            return nil
        }

        errorMessage = nil
        isTranscribing = true
        defer { isTranscribing = false }

        let preferences = VoiceTranscriptionPreferences.load()
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let raw = try await Self.withTranscriptionTimeout(seconds: 12) {
                    try await self.transcriber.transcribe(
                        audioURL: recordingURL,
                        fallbackAPIKey: VoiceCredentialStore.apiKey(),
                        language: preferences.language,
                        prompt: preferences.prompt(including: contextTerms)
                    )
                }
                let clean = VoiceTranscriptPolicy.cleaned(raw)
                guard !clean.isEmpty else {
                    errorMessage = "No speech detected. Try again closer to the microphone."
                    handsFreeRetryAllowed = true
                    return nil
                }
                transcript = clean
                handsFreeRetryAllowed = false
                return clean
            } catch {
                lastError = error
                guard attempt < 1, WorkspaceVoiceTranscriber.shouldRetry(error) else { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }

        if let transcriptionError = lastError as? GroqVoiceTranscriber.TranscriptionError,
           case .httpStatus(let status, _) = transcriptionError, status == 401 || status == 403 {
            errorMessage = "Groq rejected the API key. Update it in Voice Transcription settings."
        } else if lastError is VoiceTranscriptionTimeoutError {
            errorMessage = "Transcription timed out. The voice channel is ready to try again."
            handsFreeRetryAllowed = true
        } else {
            let fallbackHint = VoiceCredentialStore.apiKey() == nil
                ? "; add a Groq fallback key in Voice settings"
                : ""
            errorMessage = "HQ transcription is unavailable\(fallbackHint)."
        }
        return nil
    }

    func cancel() {
        stopMetering()
        stopLiveCaptioning()
        recorder?.stop()
        recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        recordingStartedAt = nil
        speechStartedAt = nil
        silenceStartedAt = nil
        silenceProgress = 0
        autoStopRequested = false
        handsFreeRetryAllowed = false
        isRecording = false
        isTranscribing = false
    }

    private func startLiveCaptioningIfAvailable() async {
        let authorization: SFSpeechRecognizerAuthorizationStatus
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            authorization = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        case let status:
            authorization = status
        }
        guard authorization == .authorized, liveRecognizer?.isAvailable == true else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if liveRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
        }
        liveCaptionRequest = request

        let input = liveCaptionEngine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
            self?.liveCaptionRequest?.append(buffer)
        }
        liveCaptionTapInstalled = true
        liveCaptionTask = liveRecognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result else { return }
            let text = result.bestTranscription.formattedString
            let confidences = result.bestTranscription.segments.map(\.confidence).filter { $0 > 0 }
            let confidence = confidences.isEmpty
                ? nil
                : confidences.reduce(0, +) / Float(confidences.count)
            Task { @MainActor in
                self?.partialTranscript = text
                self?.transcriptConfidence = confidence
            }
        }

        do {
            liveCaptionEngine.prepare()
            try liveCaptionEngine.start()
        } catch {
            stopLiveCaptioning()
        }
    }

    private func stopLiveCaptioning() {
        liveCaptionTask?.finish()
        liveCaptionTask = nil
        liveCaptionRequest?.endAudio()
        liveCaptionRequest = nil
        if liveCaptionEngine.isRunning { liveCaptionEngine.stop() }
        if liveCaptionTapInstalled {
            liveCaptionEngine.inputNode.removeTap(onBus: 0)
            liveCaptionTapInstalled = false
        }
    }

    private static func withTranscriptionTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw VoiceTranscriptionTimeoutError()
            }
            guard let result = try await group.next() else { throw VoiceTranscriptionTimeoutError() }
            group.cancelAll()
            return result
        }
    }

    private func startMetering(_ recorder: AVAudioRecorder) {
        stopMetering()
        meterTask = Task { [weak self, weak recorder] in
            while !Task.isCancelled, let self, let recorder, recorder.isRecording {
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let clamped = min(max(Double(power), -55), 0)
                self.inputLevel = pow(10, clamped / 32)
                self.updateEndpointing(level: self.inputLevel)
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
        }
    }

    private func updateEndpointing(level: Double) {
        guard isRecording, !autoStopRequested else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(recordingStartedAt ?? now)
        let threshold = max(0.075, noiseFloor * 2.25)

        if speechStartedAt == nil {
            noiseFloor = noiseFloor * 0.94 + min(level, 0.055) * 0.06
            if level >= threshold, elapsed >= 0.65 {
                speechStartedAt = now
                silenceStartedAt = nil
            } else if elapsed >= 7 {
                autoStopRequested = true
            }
            return
        }

        if level >= max(0.065, noiseFloor * 2.1) {
            silenceStartedAt = nil
            silenceProgress = 0
            return
        }

        if silenceStartedAt == nil { silenceStartedAt = now }
        let quietFor = now.timeIntervalSince(silenceStartedAt ?? now)
        silenceProgress = min(max(quietFor / 1.35, 0), 1)
        if quietFor >= 1.35, elapsed >= 1.8 {
            autoStopRequested = true
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
        inputLevel = 0
        silenceProgress = 0
    }

    private func microphoneIsAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

struct VoiceTranscriptionPreferences: Equatable {
    static let languageKey = "voiceTranscription.language"
    static let promptKey = "voiceTranscription.prompt"
    static let defaultPrompt = "Coding workspace dictation. Common terms include Codex, Claude Code, GitHub, npm, TypeScript, Swift, macOS, API, JSON, URL, terminal, workspace, browser, and localhost."

    var language: String
    var prompt: String

    static func load(defaults: UserDefaults = .standard) -> Self {
        Self(
            language: defaults.string(forKey: languageKey) ?? "en",
            prompt: defaults.string(forKey: promptKey) ?? defaultPrompt
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(language, forKey: Self.languageKey)
        defaults.set(prompt, forKey: Self.promptKey)
    }

    func prompt(including contextTerms: [String]) -> String {
        var seen = Set<String>()
        let cleanTerms = contextTerms.compactMap { term -> String? in
            let clean = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty, clean.count <= 80 else { return nil }
            let key = clean.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return clean
        }
        let context = cleanTerms.isEmpty ? "" : "Active workspace names: \(cleanTerms.prefix(30).joined(separator: ", "))."
        return [context, prompt.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .prefix(500)
            .description
    }
}

enum VoiceCredentialStore {
    static let service = "dev.spatialworkspace.voice-transcription"
    static let account = "groq-api-key"

    static func apiKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    static func save(apiKey: String) throws {
        let clean = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw CredentialError.emptyKey }
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: Data(clean.utf8)]
        let updateStatus = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = Data(clean.utf8)
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw CredentialError.keychain(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw CredentialError.keychain(updateStatus)
        }
    }

    static func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status)
        }
    }

    enum CredentialError: LocalizedError {
        case emptyKey
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .emptyKey: "Enter an API key first."
            case .keychain(let status): "Keychain could not save the API key (\(status))."
            }
        }
    }
}

/// VoiceForge-style routing: use the private HQ Whisper service first, then
/// fall back to Groq only when the user has saved a key. Jarvis voice therefore
/// works on the same local transcription path as HQ without a setup ceremony.
struct WorkspaceVoiceTranscriber {
    static let maximumAudioBytes = 25 * 1_024 * 1_024

    let hq: HQVoiceTranscriber
    let groq: GroqVoiceTranscriber

    init(hq: HQVoiceTranscriber = HQVoiceTranscriber(), groq: GroqVoiceTranscriber = GroqVoiceTranscriber()) {
        self.hq = hq
        self.groq = groq
    }

    func transcribe(
        audioURL: URL,
        fallbackAPIKey: String?,
        language: String?,
        prompt: String?
    ) async throws -> String {
        do {
            return try await hq.transcribe(audioURL: audioURL)
        } catch {
            try Task.checkCancellation()
            guard let key = fallbackAPIKey else { throw error }
            return try await groq.transcribe(audioURL: audioURL, apiKey: key, language: language, prompt: prompt)
        }
    }

    static func shouldRetry(_ error: Error) -> Bool {
        HQVoiceTranscriber.shouldRetry(error) || GroqVoiceTranscriber.shouldRetry(error)
    }
}

struct HQVoiceTranscriber {
    static let endpoint = HQJarvisClient.defaultBaseURL.appendingPathComponent("api/voice/transcribe")

    let session: URLSession
    let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL = Self.endpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    func transcribe(audioURL: URL) async throws -> String {
        let audio = try Data(contentsOf: audioURL, options: .mappedIfSafe)
        guard audio.count <= WorkspaceVoiceTranscriber.maximumAudioBytes else {
            throw TranscriptionError.audioTooLarge
        }
        let boundary = "SpatialHQVoice-\(UUID().uuidString)"
        let body = Self.multipartBody(
            boundary: boundary,
            audio: audio,
            filename: audioURL.lastPathComponent
        )
        var request = URLRequest(url: endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw TranscriptionError.httpStatus(http.statusCode, String(decoding: data.prefix(240), as: UTF8.self))
        }
        return try JSONDecoder().decode(Response.self, from: data).text
    }

    static func multipartBody(boundary: String, audio: Data, filename: String) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        let safeName = filename
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    static func shouldRetry(_ error: Error) -> Bool {
        if let urlError = error as? URLError { return urlError.code != .cancelled }
        if case TranscriptionError.httpStatus(let status, _) = error {
            return status == 408 || status == 409 || status == 429 || status >= 500
        }
        return false
    }

    private struct Response: Decodable { let text: String }

    enum TranscriptionError: LocalizedError {
        case audioTooLarge
        case invalidResponse
        case httpStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .audioTooLarge: "The recording exceeds the 25 MB upload limit."
            case .invalidResponse: "HQ transcription returned an invalid response."
            case .httpStatus(let status, let detail): "HQ transcription returned HTTP \(status): \(detail)"
            }
        }
    }
}

struct GroqVoiceTranscriber {
    static let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    static let maximumAudioBytes = 25 * 1_024 * 1_024

    let session: URLSession
    let endpoint: URL

    init(session: URLSession = .shared, endpoint: URL = Self.endpoint) {
        self.session = session
        self.endpoint = endpoint
    }

    func transcribe(audioURL: URL, apiKey: String, language: String?, prompt: String?) async throws -> String {
        let audio = try Data(contentsOf: audioURL, options: .mappedIfSafe)
        guard audio.count <= Self.maximumAudioBytes else { throw TranscriptionError.audioTooLarge }
        let boundary = "SpatialVoice-\(UUID().uuidString)"
        let body = Self.multipartBody(
            boundary: boundary,
            audio: audio,
            filename: audioURL.lastPathComponent,
            language: language,
            prompt: prompt
        )
        var request = URLRequest(url: endpoint, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TranscriptionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data)
            throw TranscriptionError.httpStatus(http.statusCode, envelope?.error.message)
        }
        let decoded = try JSONDecoder().decode(VerboseResponse.self, from: data)
        return decoded.text
    }

    static func multipartBody(
        boundary: String,
        audio: Data,
        filename: String,
        language: String?,
        prompt: String?
    ) -> Data {
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(sanitizedFilename(filename))\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
        body.append(audio)
        append("\r\n")
        field("model", "whisper-large-v3-turbo")
        field("response_format", "verbose_json")
        if let language = normalized(language), language != "auto" { field("language", language) }
        if let prompt = normalized(prompt) { field("prompt", prompt) }
        append("--\(boundary)--\r\n")
        return body
    }

    static func shouldRetry(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        if case TranscriptionError.httpStatus(let status, _) = error {
            return status == 408 || status == 409 || status == 429 || status >= 500
        }
        return false
    }

    private static func normalized(_ value: String?) -> String? {
        let clean = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return clean.isEmpty ? nil : clean
    }

    private static func sanitizedFilename(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "_").replacingOccurrences(of: "\r", with: "_").replacingOccurrences(of: "\n", with: "_")
    }

    private struct VerboseResponse: Decodable { let text: String }
    private struct APIErrorEnvelope: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail
    }

    enum TranscriptionError: LocalizedError {
        case audioTooLarge
        case invalidResponse
        case httpStatus(Int, String?)

        var errorDescription: String? {
            switch self {
            case .audioTooLarge: "The recording exceeds Groq's 25 MB upload limit."
            case .invalidResponse: "The transcription service returned an invalid response."
            case .httpStatus(let status, let message): message ?? "The transcription service returned HTTP \(status)."
            }
        }
    }
}

enum VoiceTranscriptPolicy {
    private static let wholeClipArtifacts: Set<String> = [
        "you", "thank you", "thanks", "thanks for watching", "thank you for watching",
        "please subscribe", "subscribe", "like and subscribe", "see you next time", "the end",
        "music", "music playing", "applause", "silence", "background noise",
    ]

    static func cleaned(_ transcript: String) -> String {
        let clean = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "" }
        let normalized = normalize(clean)
        guard !normalized.isEmpty,
              !wholeClipArtifacts.contains(normalized),
              !isRepetitionLoop(normalized) else { return "" }
        return clean
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func isRepetitionLoop(_ text: String) -> Bool {
        let words = text.split(separator: " ").map(String.init)
        guard words.count >= 3 else { return false }
        for unitLength in 1...min(4, words.count / 3) where words.count.isMultiple(of: unitLength) {
            let unit = Array(words.prefix(unitLength))
            if stride(from: 0, to: words.count, by: unitLength).allSatisfy({ start in
                Array(words[start..<start + unitLength]) == unit
            }) { return true }
        }
        return false
    }
}

enum VoiceCommandPolicy {
    static func isSleepCommand(_ transcript: String) -> Bool {
        let normalized = transcript
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return normalized.hasSuffix("go to sleep")
    }
}
