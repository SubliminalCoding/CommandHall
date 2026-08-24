import Foundation

struct JarvisDelegation: Codable, Equatable {
    var agent: String
    var task: String
}

struct JarvisDelegationPayload: Codable, Equatable {
    var version: Int
    var delegations: [JarvisDelegation]
}

struct JarvisParsedResponse: Equatable {
    var visibleContent: String
    var delegations: [JarvisDelegation]
    var controlError: String?
}

struct JarvisDelegationCandidate: Equatable {
    var name: String
    var provider: String
    var isAvailable: Bool
}

struct JarvisDelegationDispatch: Equatable {
    var delegation: JarvisDelegation
    var nodeID: UUID?
    var launched: Bool
    var detail: String
}

enum JarvisDelegationProtocol {
    static let openingTag = "<spatial_delegations>"
    static let closingTag = "</spatial_delegations>"
    static let maximumDelegations = 6
    static let maximumTaskLength = 4_000

    static func instructions(candidates: [JarvisDelegationCandidate]) -> String {
        let roster = candidates.map {
            "- \($0.name) | \($0.provider) | \($0.isAvailable ? "available" : "busy")"
        }.joined(separator: "\n")
        return """
        SPATIAL DELEGATION CONTRACT
        You can assign execution work to the coding agents below. This is a real side effect in Matt's current workspace.

        \(roster.isEmpty ? "- No coding agents are open." : roster)

        Rules:
        1. Delegate only when Matt asks for work to be performed. Never delegate a status question, explanation, brainstorm, or casual conversation.
        2. Select only an available agent and copy its name exactly. Never invent or rename an agent.
        3. Give each agent a complete, self-contained task with the desired outcome and verification expectations.
        4. Say naturally which agent or agents you are putting on the work.
        5. After the spoken response, append exactly one control block using this schema:
        <spatial_delegations>
        {"version":1,"delegations":[{"agent":"Exact agent name","task":"Complete task"}]}
        </spatial_delegations>
        6. Omit the control block when no delegation is warranted. Never mention the control block to Matt.
        """
    }

    static func parse(_ content: String) -> JarvisParsedResponse {
        guard let opening = content.range(of: openingTag) else {
            return JarvisParsedResponse(
                visibleContent: content.trimmingCharacters(in: .whitespacesAndNewlines),
                delegations: [],
                controlError: nil
            )
        }

        let visiblePrefix = content[..<opening.lowerBound]
        guard let closing = content.range(of: closingTag, range: opening.upperBound ..< content.endIndex) else {
            return JarvisParsedResponse(
                visibleContent: String(visiblePrefix).trimmingCharacters(in: .whitespacesAndNewlines),
                delegations: [],
                controlError: "Jarvis returned an incomplete delegation block. Nothing was assigned."
            )
        }

        let json = String(content[opening.upperBound ..< closing.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleSuffix = content[closing.upperBound...]
        let visible = (String(visiblePrefix) + String(visibleSuffix))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let payload = try JSONDecoder().decode(JarvisDelegationPayload.self, from: Data(json.utf8))
            guard payload.version == 1 else {
                return JarvisParsedResponse(visibleContent: visible, delegations: [], controlError: "Jarvis used an unsupported delegation version. Nothing was assigned.")
            }
            guard payload.delegations.count <= maximumDelegations else {
                return JarvisParsedResponse(visibleContent: visible, delegations: [], controlError: "Jarvis requested too many assignments at once. Nothing was assigned.")
            }

            var seenAgents = Set<String>()
            var validated: [JarvisDelegation] = []
            for delegation in payload.delegations {
                let agent = delegation.agent.trimmingCharacters(in: .whitespacesAndNewlines)
                let task = delegation.task.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = agent.lowercased()
                guard !agent.isEmpty, agent.count <= 80,
                      !task.isEmpty, task.count <= maximumTaskLength,
                      seenAgents.insert(key).inserted else {
                    return JarvisParsedResponse(visibleContent: visible, delegations: [], controlError: "Jarvis returned an invalid or duplicate assignment. Nothing was assigned.")
                }
                validated.append(JarvisDelegation(agent: agent, task: task))
            }
            return JarvisParsedResponse(visibleContent: visible, delegations: validated, controlError: nil)
        } catch {
            return JarvisParsedResponse(visibleContent: visible, delegations: [], controlError: "Jarvis returned malformed delegation data. Nothing was assigned.")
        }
    }

    static func requestAuthorizesDelegation(_ request: String) -> Bool {
        let normalized = request
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return false }

        let informationalPrefixes = [
            "what is", "what are", "what did", "why", "how does", "how do",
            "tell me about", "explain", "summarize", "give me a status", "what s the status",
        ]
        if informationalPrefixes.contains(where: normalized.hasPrefix) { return false }

        let executionSignals = [
            "delegate", "assign", "get someone", "get nova", "get marshall", "get skye",
            "put someone", "have someone", "take care of", "work on", "i want",
            "please build", "please fix", "please make", "please create", "please implement",
            "build ", "fix ", "make ", "create ", "implement ", "add ", "update ",
            "run ", "test ", "audit ", "review ",
        ]
        return executionSignals.contains { normalized.contains($0) }
    }

    static func fallbackDelegations(
        userRequest: String,
        visibleResponse: String,
        candidates: [JarvisDelegationCandidate]
    ) -> [JarvisDelegation] {
        guard requestAuthorizesDelegation(userRequest) else { return [] }
        let response = visibleResponse.lowercased()
        let refusalSignals = [
            "not on it", "can't assign", "cannot assign", "won't assign",
            "unable to assign", "no agent is available", "nobody is available",
        ]
        guard !refusalSignals.contains(where: response.contains) else { return [] }

        let commitmentSignals = [
            "on it", "i'm having", "i am having", "i'll have", "i will have",
            "i'm putting", "i am putting", "i'll put", "i will put",
            "i'm assigning", "i am assigning", "i'll assign", "i will assign",
            "i'm sending", "i am sending", "i'll send", "i will send",
            "i'll get", "i will get", "delegating to", "assigned to",
        ]
        guard commitmentSignals.contains(where: response.contains) else { return [] }

        let available = candidates.filter(\.isAvailable)
        var selected = available.filter { containsExactName($0.name, in: visibleResponse) }
        if selected.isEmpty {
            let requested = available.filter { containsExactName($0.name, in: userRequest) }
            if requested.count == 1 { selected = requested }
        }

        return selected.prefix(maximumDelegations).map {
            JarvisDelegation(agent: $0.name, task: userRequest.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    static func resolvedDelegations(
        proposed: [JarvisDelegation],
        userRequest: String,
        visibleResponse: String,
        candidates: [JarvisDelegationCandidate]
    ) -> [JarvisDelegation] {
        guard requestAuthorizesDelegation(userRequest) else { return [] }
        let available = candidates.filter(\.isAvailable)
        if !proposed.isEmpty {
            let canonical = proposed.compactMap { delegation -> JarvisDelegation? in
                guard let candidate = available.first(where: {
                    $0.name.compare(delegation.agent, options: [.caseInsensitive]) == .orderedSame
                }) else { return nil }
                return JarvisDelegation(agent: candidate.name, task: delegation.task)
            }
            if canonical.count == proposed.count { return canonical }
        }

        let naturalFallback = fallbackDelegations(
            userRequest: userRequest,
            visibleResponse: visibleResponse,
            candidates: available
        )
        if !naturalFallback.isEmpty { return naturalFallback }

        guard !proposed.isEmpty else { return [] }
        let explicitlyRequested = available.filter { containsExactName($0.name, in: userRequest) }
        guard explicitlyRequested.count == 1, let candidate = explicitlyRequested.first else { return [] }
        return [
            JarvisDelegation(
                agent: candidate.name,
                task: userRequest.trimmingCharacters(in: .whitespacesAndNewlines)
            ),
        ]
    }

    private static func containsExactName(_ name: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(
            pattern: "(?i)(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])"
        ) else { return false }
        let range = NSRange(text.startIndex ..< text.endIndex, in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }
}
