import Foundation

/// The one thing the workspace needs from a Jarvis chat backend: stream a reply.
/// Both the Spark HQ client and any OpenAI-compatible endpoint conform, so the
/// backend can be swapped without touching the delegation / TTS plumbing.
protocol JarvisResponding {
    func reply(
        to history: [WorkspaceChatMessage],
        sessionID: String?,
        onUpdate: @escaping (HQJarvisUpdate) async -> Void
    ) async throws -> HQJarvisReply
}

extension HQJarvisClient: JarvisResponding {}

// MARK: - Backend selection

enum JarvisBackendKind: String, CaseIterable, Identifiable {
    case hq
    case groq
    case qwen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hq: "HQ · Jarvis"
        case .groq: "Groq"
        case .qwen: "Local Qwen"
        }
    }
}

/// Reads/writes the chosen Jarvis backend and builds the matching client. Kept as
/// plain UserDefaults so it can be read from the store and bound from `@AppStorage`
/// UI against the same keys.
enum JarvisBackend {
    static let kindKey = "jarvis.backend"
    static let groqModelKey = "jarvis.groqModel"
    static let qwenEndpointKey = "jarvis.qwenEndpoint"
    static let qwenModelKey = "jarvis.qwenModel"

    static let defaultGroqModel = "qwen/qwen3.6-27b"
    static let defaultQwenEndpoint = "http://127.0.0.1:8101/v1"
    static let defaultQwenModel = "qwen38-27b"

    static var kind: JarvisBackendKind {
        JarvisBackendKind(rawValue: UserDefaults.standard.string(forKey: kindKey) ?? "") ?? .hq
    }

    static func makeClient() -> any JarvisResponding {
        switch kind {
        case .hq:
            return HQJarvisClient()
        case .groq:
            let model = UserDefaults.standard.string(forKey: groqModelKey) ?? defaultGroqModel
            // Qwen models on Groq accept reasoning_effort to skip the <think> pass;
            // other models (gpt-oss) reject it, so only send it for qwen.
            let extra: [String: Any] = model.lowercased().contains("qwen") ? ["reasoning_effort": "none"] : [:]
            return OpenAIChatClient(
                baseURL: URL(string: "https://api.groq.com/openai/v1")!,
                model: model,
                apiKey: VoiceCredentialStore.apiKey(),
                requiresKey: true,
                label: "Groq",
                extraBody: extra
            )
        case .qwen:
            let endpoint = UserDefaults.standard.string(forKey: qwenEndpointKey) ?? defaultQwenEndpoint
            let model = UserDefaults.standard.string(forKey: qwenModelKey) ?? defaultQwenModel
            return OpenAIChatClient(
                baseURL: URL(string: endpoint) ?? URL(string: defaultQwenEndpoint)!,
                model: model,
                apiKey: nil,
                requiresKey: false,
                label: "Qwen",
                // vLLM honors this to disable Qwen3 thinking at the chat template.
                extraBody: ["chat_template_kwargs": ["enable_thinking": false]]
            )
        }
    }
}

// MARK: - OpenAI-compatible streaming client

/// Talks the OpenAI `chat/completions` streaming shape, which Groq and a local
/// vLLM server (Qwen) both speak. Maps our chat history straight through and
/// surfaces `choices[].delta.content` as incremental `HQJarvisUpdate`s so the
/// existing streaming-TTS path works unchanged.
struct OpenAIChatClient: JarvisResponding {
    let baseURL: URL
    let model: String
    let apiKey: String?
    var requiresKey: Bool = false
    var label: String = "Model"
    var session: URLSession = .shared
    var systemPrompt: String? = OpenAIChatClient.defaultJarvisSystemPrompt
    /// Extra JSON fields merged into the request (e.g. thinking-off flags).
    var extraBody: [String: Any] = [:]

    enum ClientError: LocalizedError {
        case missingKey(String)
        case invalidResponse
        case httpStatus(Int, String)
        case emptyReply

        var errorDescription: String? {
            switch self {
            case .missingKey(let name): "\(name) has no API key saved. Add one in voice settings, or switch the Jarvis backend."
            case .invalidResponse: "The model endpoint returned an invalid response."
            case .httpStatus(let code, let detail): "The model endpoint returned HTTP \(code): \(detail)"
            case .emptyReply: "The model returned an empty reply."
            }
        }
    }

    static let defaultJarvisSystemPrompt = """
    You are Jarvis, a blunt agent liaison and strategic advisor. You are answering out loud, so keep it concise and conversational: a couple of spoken sentences unless more is genuinely needed. Never invent success beyond the evidence you're given. Follow any instructions embedded in the user's briefing, including the delegation protocol markup when present.
    """

    func reply(
        to history: [WorkspaceChatMessage],
        sessionID: String?,
        onUpdate: @escaping (HQJarvisUpdate) async -> Void
    ) async throws -> HQJarvisReply {
        if requiresKey, (apiKey ?? "").isEmpty { throw ClientError.missingKey(label) }

        var messages: [[String: String]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(contentsOf: history.map { ["role": $0.role.rawValue, "content": $0.content] })

        var body: [String: Any] = [
            "model": model,
            "messages": messages,
            "stream": true,
            "temperature": 0.6,
        ]
        for (key, value) in extraBody { body[key] = value }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"), timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            var detail = ""
            for try await line in bytes.lines {
                detail += line
                if detail.count > 400 { break }
            }
            throw ClientError.httpStatus(http.statusCode, String(detail.prefix(300)))
        }

        var raw = ""
        var lastVisible = ""
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
                  let delta = chunk.choices.first?.delta.content, !delta.isEmpty else { continue }
            raw += delta
            // Never surface reasoning: publish only the answer with <think> removed.
            // While a think block is still open, `visible` simply doesn't grow.
            let visible = Self.stripThink(raw)
            if visible != lastVisible {
                let addition = String(visible.dropFirst(lastVisible.count))
                lastVisible = visible
                await onUpdate(HQJarvisUpdate(content: visible, delta: addition, replacedContent: false))
            }
        }

        let clean = Self.stripThink(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw ClientError.emptyReply }
        return HQJarvisReply(content: clean, sessionID: sessionID)
    }

    /// Remove closed `<think>…</think>` spans and any still-open trailing one.
    static func stripThink(_ input: String) -> String {
        var text = input
        while let open = text.range(of: "<think>"),
              let close = text.range(of: "</think>", range: open.upperBound ..< text.endIndex) {
            text.removeSubrange(open.lowerBound ..< close.upperBound)
        }
        if let open = text.range(of: "<think>") {
            text.removeSubrange(open.lowerBound ..< text.endIndex)
        }
        // Trim only leading whitespace so streamed spacing stays intact downstream.
        while let first = text.first, first == "\n" || first == " " || first == "\t" {
            text.removeFirst()
        }
        return text
    }
}

private struct OpenAIStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta
    }
    let choices: [Choice]
}
