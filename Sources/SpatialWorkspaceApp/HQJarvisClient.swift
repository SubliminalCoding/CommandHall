import Foundation

struct HQJarvisMessage: Codable, Equatable {
    var role: String
    var content: String
}

struct HQJarvisChatRequest: Codable, Equatable {
    var messages: [HQJarvisMessage]
    var activePath = "/voice"
    var sessionId: String?
}

struct HQJarvisChatSlot: Codable, Equatable {
    var slotId: String
    var sessionId: String?
}

struct HQJarvisStreamEvent: Codable, Equatable {
    var type: String
    var content: String?
    var replace: Bool?
    var message: String?
}

struct HQJarvisReply: Equatable {
    var content: String
    var sessionID: String?
}

struct HQJarvisUpdate: Equatable {
    var content: String
    var delta: String
    var replacedContent: Bool
}

enum HQJarvisStream {
    static func event(from line: String) -> HQJarvisStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(HQJarvisStreamEvent.self, from: data)
    }
}

struct HQJarvisClient {
    enum ClientError: LocalizedError {
        case invalidResponse
        case httpStatus(Int, String)
        case streamError(String)
        case emptyReply

        var errorDescription: String? {
            switch self {
            case .invalidResponse: "HQ Jarvis returned an invalid response."
            case .httpStatus(let status, let detail): "HQ Jarvis returned HTTP \(status): \(detail)"
            case .streamError(let message): message
            case .emptyReply: "HQ Jarvis returned an empty reply."
            }
        }
    }

    static let baseURLKey = "jarvis.hqBaseURL"
    static let fallbackBaseURL = URL(string: "http://127.0.0.1:3200")!

    static var defaultBaseURL: URL {
        let environment = ProcessInfo.processInfo.environment["COMMANDHALL_HQ_BASE_URL"]
        let saved = UserDefaults.standard.string(forKey: baseURLKey)
        return (environment ?? saved).flatMap(URL.init(string:)) ?? fallbackBaseURL
    }

    let session: URLSession
    let baseURL: URL

    init(session: URLSession = .shared, baseURL: URL = defaultBaseURL) {
        self.session = session
        self.baseURL = baseURL
    }

    func reply(
        to history: [WorkspaceChatMessage],
        sessionID: String?,
        onUpdate: @escaping (HQJarvisUpdate) async -> Void
    ) async throws -> HQJarvisReply {
        let messages = history.map { HQJarvisMessage(role: $0.role.rawValue, content: $0.content) }
        let payload = HQJarvisChatRequest(messages: messages, sessionId: sessionID)
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"), timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (slotData, slotResponse) = try await session.data(for: request)
        guard let slotHTTP = slotResponse as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200 ..< 300).contains(slotHTTP.statusCode) else {
            throw ClientError.httpStatus(slotHTTP.statusCode, String(decoding: slotData.prefix(240), as: UTF8.self))
        }
        let slot = try JSONDecoder().decode(HQJarvisChatSlot.self, from: slotData)

        var streamRequest = URLRequest(
            url: baseURL.appendingPathComponent("api/chat/stream/\(slot.slotId)"),
            timeoutInterval: 360
        )
        streamRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, streamResponse) = try await session.bytes(for: streamRequest)
        guard let streamHTTP = streamResponse as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200 ..< 300).contains(streamHTTP.statusCode) else {
            throw ClientError.httpStatus(streamHTTP.statusCode, "stream unavailable")
        }

        var content = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = HQJarvisStream.event(from: line) else { continue }
            switch event.type {
            case "chunk":
                let delta = event.content ?? ""
                if event.replace == true {
                    content = delta
                } else {
                    content += delta
                }
                await onUpdate(
                    HQJarvisUpdate(
                        content: content,
                        delta: delta,
                        replacedContent: event.replace == true
                    )
                )
            case "error":
                throw ClientError.streamError(event.message ?? "HQ Jarvis could not answer.")
            case "done":
                let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty else { throw ClientError.emptyReply }
                return HQJarvisReply(content: clean, sessionID: slot.sessionId)
            default:
                continue
            }
        }

        let clean = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ClientError.emptyReply }
        return HQJarvisReply(content: clean, sessionID: slot.sessionId)
    }
}
