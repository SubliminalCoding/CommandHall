import AVFoundation
import Foundation

struct JarvisSpeechPayload: Codable, Equatable {
    var model = "kokoro"
    var input: String
    var voice = "am_michael"
    var responseFormat = "mp3"

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case voice
        case responseFormat = "response_format"
    }
}

struct HQJarvisSpeechPayload: Codable, Equatable {
    var text: String
}

enum JarvisSpeechRequest {
    static var hqEndpoint: URL {
        HQJarvisClient.defaultBaseURL.appendingPathComponent("api/voice/tts")
    }
    static let localKokoroEndpoint = URL(string: "http://127.0.0.1:8880/v1/audio/speech")!

    static func makeHQ(text: String, endpoint: URL = hqEndpoint) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(HQJarvisSpeechPayload(text: text))
        return request
    }

    static func makeLocalKokoro(
        text: String,
        endpoint: URL = localKokoroEndpoint,
        voice: String = "am_michael"
    ) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(JarvisSpeechPayload(input: text, voice: voice))
        return request
    }
}

struct JarvisSpeechClient {
    enum SpeechError: LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case emptyAudio

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "Jarvis returned an invalid response."
            case .httpStatus(let status): "Jarvis returned HTTP \(status)."
            case .emptyAudio: "Jarvis returned no audio."
            }
        }
    }

    let session: URLSession
    let hqEndpoint: URL
    let localKokoroEndpoint: URL
    let voice: String

    struct SynthesisResult {
        let audio: Data
        let provider: JarvisSpeechProvider
    }

    init(
        session: URLSession = .shared,
        hqEndpoint: URL = JarvisSpeechRequest.hqEndpoint,
        localKokoroEndpoint: URL = JarvisSpeechRequest.localKokoroEndpoint,
        voice: String = "am_michael"
    ) {
        self.session = session
        self.hqEndpoint = hqEndpoint
        self.localKokoroEndpoint = localKokoroEndpoint
        self.voice = voice
    }

    func synthesize(_ text: String) async throws -> Data {
        try await synthesizeWithProvider(text).audio
    }

    func synthesizeWithProvider(
        _ text: String,
        preference: JarvisVoiceProviderPreference = .current
    ) async throws -> SynthesisResult {
        var lastError: Error?
        for provider in Self.providerOrder(for: preference) {
            do {
                let request: URLRequest
                switch provider {
                case .hqKokoro:
                    request = try JarvisSpeechRequest.makeHQ(text: text, endpoint: hqEndpoint)
                case .kokoro:
                    request = try JarvisSpeechRequest.makeLocalKokoro(
                        text: text,
                        endpoint: localKokoroEndpoint,
                        voice: voice
                    )
                case .system:
                    throw SpeechError.invalidResponse
                }
                return SynthesisResult(audio: try await audio(for: request), provider: provider)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? SpeechError.invalidResponse
    }

    static func providerOrder(for preference: JarvisVoiceProviderPreference) -> [JarvisSpeechProvider] {
        switch preference {
        case .automatic:
            [.hqKokoro, .kokoro]
        case .kokoro:
            [.hqKokoro, .kokoro]
        }
    }

    private func audio(for request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SpeechError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else { throw SpeechError.httpStatus(http.statusCode) }
        guard !data.isEmpty else { throw SpeechError.emptyAudio }
        return data
    }
}

struct JarvisSpeechChunkBuffer: Equatable {
    private(set) var buffer = ""
    private(set) var isInsideControlBlock = false

    mutating func append(_ delta: String) -> [String] {
        guard !delta.isEmpty, !isInsideControlBlock else { return [] }
        buffer += delta
        if let controlStart = buffer.range(of: JarvisDelegationProtocol.openingTag) {
            let spokenPrefix = String(buffer[..<controlStart.lowerBound])
            buffer = spokenPrefix
            isInsideControlBlock = true
            return drain(force: true)
        }
        return drain(force: false)
    }

    mutating func finish() -> [String] {
        guard !isInsideControlBlock else {
            buffer = ""
            return []
        }
        return drain(force: true)
    }

    mutating func reset() {
        buffer = ""
        isInsideControlBlock = false
    }

    private mutating func drain(force: Bool) -> [String] {
        var chunks: [String] = []
        while let boundary = Self.boundary(in: buffer, force: force) {
            let chunk = String(buffer[..<boundary.end])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(..<boundary.end)
            buffer = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunk.isEmpty { chunks.append(chunk) }
        }
        if force {
            let trailing = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trailing.isEmpty { chunks.append(trailing) }
            buffer = ""
        }
        return chunks
    }

    private static func boundary(in text: String, force: Bool) -> (end: String.Index, kind: Character)? {
        for index in text.indices {
            let character = text[index]
            let after = text.index(after: index)
            if character == "\n" { return (after, character) }
            if ".!?".contains(character), after == text.endIndex || text[after].isWhitespace {
                return (after, character)
            }
        }

        if text.count >= 180 {
            let limit = text.index(text.startIndex, offsetBy: 180)
            var cursor = limit
            while cursor > text.startIndex {
                let previous = text.index(before: cursor)
                if text[previous].isWhitespace,
                   text.distance(from: text.startIndex, to: previous) >= 100 {
                    return (cursor, " ")
                }
                cursor = previous
            }
        }
        if force, !text.isEmpty { return (text.endIndex, " ") }
        return nil
    }
}

@MainActor
final class JarvisAnnouncer {
    var onStateChange: ((JarvisVoiceState) -> Void)?
    var onLevelChange: ((Double) -> Void)?
    var onFirstStreamingAudio: (() -> Void)?
    var onProviderChange: ((JarvisSpeechProvider) -> Void)?

    private let client: JarvisSpeechClient
    private let fallbackSynthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var synthesisTask: Task<Void, Never>?
    private struct QueuedSpeech {
        var text: String
        var synthesis: Task<JarvisSpeechClient.SynthesisResult, Error>
    }
    private var streamingQueue: [QueuedSpeech] = []
    private var streamingWorker: Task<Void, Never>?
    private var activeStreamingSynthesis: Task<JarvisSpeechClient.SynthesisResult, Error>?
    private var streamingChunkBuffer = JarvisSpeechChunkBuffer()
    private var streamingSnapshot = ""
    private var streamingIsActive = false
    private var streamingIsFinished = false
    private var streamingAudioStarted = false

    init(client: JarvisSpeechClient = JarvisSpeechClient()) {
        self.client = client
    }

    func speak(_ text: String) {
        stop()
        synthesisTask = Task { [weak self] in
            await self?.speakAndWait(text, stopsCurrentAudio: false)
        }
    }

    func speakAndWait(_ text: String, stopsCurrentAudio: Bool = true) async {
        if stopsCurrentAudio { stop() }
        guard !Task.isCancelled else { return }
        onStateChange?(.thinking)
        onLevelChange?(0)

        do {
            let result = try await client.synthesizeWithProvider(text)
            try Task.checkCancellation()
            onProviderChange?(result.provider)
            let player = try AVAudioPlayer(data: result.audio)
            player.isMeteringEnabled = true
            self.player = player
            player.prepareToPlay()
            guard player.play() else { throw JarvisSpeechClient.SpeechError.emptyAudio }
            onStateChange?(.speaking)
            while player.isPlaying, !Task.isCancelled {
                player.updateMeters()
                let power = player.averagePower(forChannel: 0)
                onLevelChange?(Self.normalizedLevel(fromDecibels: power))
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            if Task.isCancelled { player.stop() }
            self.player = nil
        } catch is CancellationError {
            player?.stop()
            player = nil
        } catch {
            guard !Task.isCancelled else { return }
            await speakWithSystemFallbackAndWait(text)
        }

        onLevelChange?(0)
        onStateChange?(.idle)
    }

    func beginStreamingSpeech() {
        stop()
        streamingIsActive = true
        streamingIsFinished = false
        streamingAudioStarted = false
        streamingSnapshot = ""
        streamingChunkBuffer.reset()
        onStateChange?(.thinking)
        onLevelChange?(0)
    }

    func receiveStreamingSnapshot(_ snapshot: String) {
        guard streamingIsActive, !streamingIsFinished else { return }
        let delta: String
        if snapshot.hasPrefix(streamingSnapshot) {
            delta = String(snapshot.dropFirst(streamingSnapshot.count))
        } else if !streamingAudioStarted {
            cancelPendingStreamingSynthesis()
            streamingChunkBuffer.reset()
            delta = snapshot
        } else {
            // The server replaced already-visible text after audio began. Do
            // not replay or contradict speech already heard; the final visible
            // response remains authoritative on screen.
            delta = ""
        }
        streamingSnapshot = snapshot
        enqueueStreamingChunks(streamingChunkBuffer.append(delta))
    }

    func finishStreamingSpeech(finalContent: String) {
        guard streamingIsActive else { return }
        if finalContent.hasPrefix(streamingSnapshot) {
            receiveStreamingSnapshot(finalContent)
        }
        enqueueStreamingChunks(streamingChunkBuffer.finish())
        streamingIsFinished = true
        if streamingQueue.isEmpty, streamingWorker == nil, player?.isPlaying != true {
            streamingIsActive = false
            onLevelChange?(0)
            onStateChange?(.idle)
        }
    }

    func stop() {
        synthesisTask?.cancel()
        synthesisTask = nil
        streamingWorker?.cancel()
        streamingWorker = nil
        activeStreamingSynthesis?.cancel()
        activeStreamingSynthesis = nil
        cancelPendingStreamingSynthesis()
        streamingChunkBuffer.reset()
        streamingSnapshot = ""
        streamingIsActive = false
        streamingIsFinished = false
        streamingAudioStarted = false
        player?.stop()
        player = nil
        fallbackSynthesizer.stopSpeaking(at: .immediate)
        onLevelChange?(0)
        onStateChange?(.idle)
    }

    private func enqueueStreamingChunks(_ chunks: [String]) {
        for chunk in chunks {
            let clean = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            let synthesis = Task { [client] in try await client.synthesizeWithProvider(clean) }
            streamingQueue.append(QueuedSpeech(text: clean, synthesis: synthesis))
        }
        startStreamingWorkerIfNeeded()
    }

    private func startStreamingWorkerIfNeeded() {
        guard streamingWorker == nil, !streamingQueue.isEmpty else { return }
        streamingWorker = Task { [weak self] in
            await self?.drainStreamingQueue()
        }
    }

    private func drainStreamingQueue() async {
        while !Task.isCancelled, !streamingQueue.isEmpty {
            let item = streamingQueue.removeFirst()
            activeStreamingSynthesis = item.synthesis
            do {
                let result = try await item.synthesis.value
                try Task.checkCancellation()
                activeStreamingSynthesis = nil
                onProviderChange?(result.provider)
                try await playAudioAndWait(result.audio)
            } catch is CancellationError {
                activeStreamingSynthesis = nil
                break
            } catch {
                activeStreamingSynthesis = nil
                guard !Task.isCancelled else { break }
                await speakWithSystemFallbackAndWait(item.text)
            }
        }

        streamingWorker = nil
        if !streamingQueue.isEmpty, streamingIsActive {
            startStreamingWorkerIfNeeded()
        } else if streamingIsFinished {
            streamingIsActive = false
            onLevelChange?(0)
            onStateChange?(.idle)
        } else if streamingIsActive {
            onLevelChange?(0)
            onStateChange?(.thinking)
        }
    }

    private func playAudioAndWait(_ audio: Data) async throws {
        let player = try AVAudioPlayer(data: audio)
        player.isMeteringEnabled = true
        self.player = player
        player.prepareToPlay()
        guard player.play() else { throw JarvisSpeechClient.SpeechError.emptyAudio }
        if !streamingAudioStarted {
            streamingAudioStarted = true
            onFirstStreamingAudio?()
        }
        onStateChange?(.speaking)
        while player.isPlaying, !Task.isCancelled {
            player.updateMeters()
            onLevelChange?(Self.normalizedLevel(fromDecibels: player.averagePower(forChannel: 0)))
            try? await Task.sleep(nanoseconds: 33_000_000)
        }
        if Task.isCancelled {
            player.stop()
            throw CancellationError()
        }
        self.player = nil
    }

    private func cancelPendingStreamingSynthesis() {
        for item in streamingQueue { item.synthesis.cancel() }
        streamingQueue.removeAll()
    }

    private func speakWithSystemFallbackAndWait(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.48
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        onProviderChange?(.system)
        onStateChange?(.speaking)
        fallbackSynthesizer.speak(utterance)
        var phase = 0.0
        while fallbackSynthesizer.isSpeaking, !Task.isCancelled {
            phase += 0.41
            onLevelChange?(0.18 + abs(sin(phase)) * 0.24)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        if Task.isCancelled { fallbackSynthesizer.stopSpeaking(at: .immediate) }
    }

    static func normalizedLevel(fromDecibels decibels: Float) -> Double {
        guard decibels.isFinite else { return 0 }
        let clamped = min(max(Double(decibels), -55), 0)
        return pow(10, clamped / 32)
    }
}
