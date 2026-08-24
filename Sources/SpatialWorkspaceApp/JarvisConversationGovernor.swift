import AVFoundation
import Foundation

struct JarvisConversationSnapshot: Equatable {
    var state: JarvisVoiceState
    var detail: String
    var enteredAt: Date
    var lastFailure: String?

    static let ready = JarvisConversationSnapshot(
        state: .idle,
        detail: "Voice channel ready",
        enteredAt: Date(),
        lastFailure: nil
    )
}

enum JarvisConversationPolicy {
    static func timeout(for state: JarvisVoiceState) -> TimeInterval? {
        switch state {
        case .idle, .error:
            nil
        case .listening:
            120
        case .transcribing:
            25
        case .thinking:
            75
        case .speaking:
            180
        case .recovering:
            1.5
        }
    }

    static func defaultDetail(for state: JarvisVoiceState) -> String {
        switch state {
        case .idle: "Voice channel ready"
        case .listening: "Listening for your request"
        case .transcribing: "Turning speech into a request"
        case .thinking: "Waiting for Jarvis"
        case .speaking: "Response audio playing"
        case .recovering: "Restoring the voice channel"
        case .error: "Voice channel needs attention"
        }
    }
}

enum JarvisVoiceProviderPreference: String, CaseIterable, Identifiable {
    static let defaultsKey = "jarvisVoiceProviderPreference"

    case automatic
    case kokoro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .kokoro: "Kokoro"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "HQ voice first, then the local fallback"
        case .kokoro: "Kokoro on Spark first, with local and system fallbacks"
        }
    }

    static var current: Self {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let value = Self(rawValue: raw) else { return .kokoro }
        return value
    }
}

enum JarvisSpeechProvider: String, Equatable {
    case hqKokoro
    case kokoro
    case system

    var label: String {
        switch self {
        case .hqKokoro: "Kokoro · HQ"
        case .kokoro: "Kokoro · Local fallback"
        case .system: "macOS System Voice"
        }
    }
}

enum JarvisVoiceHealthState: String, Equatable {
    case ready
    case fallback
    case unavailable

    var label: String {
        switch self {
        case .ready: "Ready"
        case .fallback: "Fallback"
        case .unavailable: "Unavailable"
        }
    }
}

struct JarvisVoiceHealthCheck: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let state: JarvisVoiceHealthState
}

struct JarvisVoiceHealthReport: Equatable {
    let checkedAt: Date
    let checks: [JarvisVoiceHealthCheck]

    var isReady: Bool { checks.allSatisfy { $0.state != .unavailable } }
    var unavailableCount: Int { checks.count(where: { $0.state == .unavailable }) }

    var summary: String {
        if unavailableCount == 0 { return "Voice pipeline ready" }
        if unavailableCount == 1 { return "1 voice check needs attention" }
        return "\(unavailableCount) voice checks need attention"
    }
}

struct JarvisVoiceDoctor {
    let session: URLSession
    let hqURL: URL
    let kokoroURL: URL

    init(
        session: URLSession = .shared,
        hqURL: URL = HQJarvisClient.defaultBaseURL,
        kokoroURL: URL = HQJarvisClient.defaultBaseURL.appendingPathComponent("api/voice/health")
    ) {
        self.session = session
        self.hqURL = hqURL
        self.kokoroURL = kokoroURL
    }

    func run() async -> JarvisVoiceHealthReport {
        async let hqReachable = probe(hqURL)
        async let kokoroReachable = probeKokoro(kokoroURL)
        let microphone = Self.microphoneCheck()
        let systemVoice = AVSpeechSynthesisVoice(language: "en-US") != nil
        let hq = await hqReachable
        let kokoro = await kokoroReachable

        return JarvisVoiceHealthReport(
            checkedAt: Date(),
            checks: [
                microphone,
                JarvisVoiceHealthCheck(
                    id: "hq",
                    title: "HQ services",
                    detail: hq ? "Jarvis and transcription are reachable" : "HQ did not answer the health probe",
                    state: hq ? .ready : .unavailable
                ),
                JarvisVoiceHealthCheck(
                    id: "kokoro",
                    title: "Kokoro on Spark",
                    detail: kokoro ? "The selected voice service is running behind HQ" : "Kokoro is offline; system voice remains available",
                    state: kokoro ? .ready : .unavailable
                ),
                JarvisVoiceHealthCheck(
                    id: "system",
                    title: "System voice",
                    detail: systemVoice ? "Emergency speech fallback is available" : "No English system voice is installed",
                    state: systemVoice ? .ready : .unavailable
                ),
            ]
        )
    }

    private func probe(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200 ..< 500).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func probeKokoro(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            return (try? JSONDecoder().decode(KokoroHealth.self, from: data).ok) == true
        } catch {
            return false
        }
    }

    private struct KokoroHealth: Decodable { let ok: Bool }

    private static func microphoneCheck() -> JarvisVoiceHealthCheck {
        let authorization = AVCaptureDevice.authorizationStatus(for: .audio)
        let hasInput = AVCaptureDevice.default(for: .audio) != nil
        if authorization == .denied || authorization == .restricted {
            return JarvisVoiceHealthCheck(
                id: "microphone",
                title: "Microphone",
                detail: "Permission is off in System Settings",
                state: .unavailable
            )
        }
        if !hasInput {
            return JarvisVoiceHealthCheck(
                id: "microphone",
                title: "Microphone",
                detail: "No audio input device is available",
                state: .unavailable
            )
        }
        return JarvisVoiceHealthCheck(
            id: "microphone",
            title: "Microphone",
            detail: authorization == .authorized ? "Input device and permission are ready" : "Input device found; permission will be requested",
            state: authorization == .authorized ? .ready : .fallback
        )
    }
}
