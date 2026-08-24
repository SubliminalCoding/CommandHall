import Foundation

struct DecodedAgentStreamEvent {
    var displayText: String?
    var sessionID: String?
    var evidenceText: String?
    var activityText: String?
}

enum AgentStreamDecoder {
    static func displayText(from line: String) -> String? {
        decode(line).displayText
    }

    static func decode(_ line: String) -> DecodedAgentStreamEvent {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return DecodedAgentStreamEvent() }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return DecodedAgentStreamEvent(displayText: trimmed, evidenceText: trimmed, activityText: trimmed)
        }

        let sessionID = (object["thread_id"] as? String) ?? (object["session_id"] as? String)
        let evidenceText = evidenceStrings(in: object).joined(separator: "\n")
        let activityText = activityText(in: object, sessionID: sessionID)

        if let item = object["item"] as? [String: Any],
           item["type"] as? String == "agent_message",
           let text = item["text"] as? String {
            return DecodedAgentStreamEvent(displayText: text, sessionID: sessionID, evidenceText: evidenceText, activityText: activityText)
        }

        if object["type"] as? String == "assistant",
           let message = object["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let text = content.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
            return DecodedAgentStreamEvent(displayText: text.isEmpty ? nil : text, sessionID: sessionID, evidenceText: evidenceText, activityText: activityText)
        }

        if object["type"] as? String == "result" {
            return DecodedAgentStreamEvent(sessionID: sessionID, evidenceText: evidenceText, activityText: activityText)
        }

        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return DecodedAgentStreamEvent(displayText: "Error: \(message)", sessionID: sessionID, evidenceText: evidenceText, activityText: activityText)
        }
        if let message = object["message"] as? String,
           (object["type"] as? String)?.contains("error") == true {
            return DecodedAgentStreamEvent(displayText: "Error: \(message)", sessionID: sessionID, evidenceText: evidenceText, activityText: activityText)
        }
        return DecodedAgentStreamEvent(
            sessionID: sessionID,
            evidenceText: evidenceText.isEmpty ? nil : evidenceText,
            activityText: activityText
        )
    }

    private static func activityText(in object: [String: Any], sessionID: String?) -> String? {
        let type = object["type"] as? String ?? "event"

        if let item = object["item"] as? [String: Any] {
            return codexActivity(type: type, item: item)
        }

        if type == "assistant",
           let message = object["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let entries = content.compactMap(claudeAssistantActivity)
            return entries.isEmpty ? nil : entries.joined(separator: "\n")
        }

        if type == "user",
           let message = object["message"] as? [String: Any],
           let content = message["content"] as? [[String: Any]] {
            let results = content.compactMap(claudeToolResultActivity)
            return results.isEmpty ? nil : results.joined(separator: "\n")
        }

        switch type {
        case "thread.started":
            return sessionID.map { "[Codex session \($0)]" } ?? "[Codex session started]"
        case "turn.started":
            return "[turn started]"
        case "turn.completed":
            return "[turn complete]"
        case "system":
            if object["subtype"] as? String == "init" {
                return sessionID.map { "[Claude session \($0)]" } ?? "[Claude session ready]"
            }
        case "result":
            let failed = (object["is_error"] as? Bool) == true
            return failed ? "[run failed]" : "[run complete]"
        default:
            break
        }

        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return "error: \(message)"
        }
        if let message = object["message"] as? String, type.contains("error") {
            return "error: \(message)"
        }
        return nil
    }

    private static func codexActivity(type: String, item: [String: Any]) -> String? {
        let itemType = item["type"] as? String ?? "item"
        switch itemType {
        case "agent_message":
            guard let text = item["text"] as? String, !text.isEmpty else { return nil }
            return "assistant\n\(text)"
        case "reasoning":
            guard let text = item["text"] as? String, !text.isEmpty else { return nil }
            return "thinking\n\(text)"
        case "command_execution":
            if type == "item.started", let command = item["command"] as? String {
                return "$ \(command)"
            }
            if type == "item.completed" {
                var parts: [String] = []
                if let output = item["aggregated_output"] as? String,
                   !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(output.trimmingCharacters(in: .newlines))
                }
                if let exitCode = item["exit_code"] as? Int {
                    parts.append("[exit \(exitCode)]")
                } else if let status = item["status"] as? String {
                    parts.append("[\(status)]")
                }
                return parts.isEmpty ? nil : parts.joined(separator: "\n")
            }
        case "file_change":
            let changes = item["changes"] as? [[String: Any]] ?? []
            let lines = changes.compactMap { change -> String? in
                guard let path = change["path"] as? String else { return nil }
                let kind = change["kind"] as? String ?? "updated"
                return "◆ \(kind.capitalized) \(path)"
            }
            return lines.isEmpty ? "◆ File changes \(item["status"] as? String ?? "updated")" : lines.joined(separator: "\n")
        case "mcp_tool_call":
            let server = item["server"] as? String
            let tool = item["tool"] as? String ?? item["name"] as? String ?? "tool"
            let target = [server, tool].compactMap { $0 }.joined(separator: ".")
            if type == "item.started" {
                let arguments = compactDescription(item["arguments"])
                return arguments.map { "◆ \(target)\n\($0)" } ?? "◆ \(target)"
            }
            if type == "item.completed", let result = compactDescription(item["result"]) {
                return result
            }
        case "web_search":
            if let query = item["query"] as? String { return "◆ Search \(query)" }
        default:
            if type == "item.started" { return "◆ \(itemType.replacingOccurrences(of: "_", with: " "))" }
        }
        return nil
    }

    private static func claudeAssistantActivity(_ block: [String: Any]) -> String? {
        switch block["type"] as? String {
        case "text":
            guard let text = block["text"] as? String, !text.isEmpty else { return nil }
            return "assistant\n\(text)"
        case "tool_use":
            let name = block["name"] as? String ?? "Tool"
            let input = block["input"] as? [String: Any] ?? [:]
            if name.caseInsensitiveCompare("Bash") == .orderedSame,
               let command = input["command"] as? String {
                return "$ \(command)"
            }
            let path = (input["file_path"] as? String) ?? (input["path"] as? String)
            var heading = "◆ \(name)"
            if let path { heading += " \(path)" }
            if let detail = claudeToolDetail(name: name, input: input), !detail.isEmpty {
                return heading + "\n" + detail
            }
            return heading
        default:
            return nil
        }
    }

    private static func claudeToolDetail(name: String, input: [String: Any]) -> String? {
        let lowered = name.lowercased()
        if lowered == "write", let content = input["content"] as? String { return content }
        if lowered == "edit" {
            let old = input["old_string"] as? String
            let new = input["new_string"] as? String
            if old != nil || new != nil {
                return [old.map { "- \($0)" }, new.map { "+ \($0)" }].compactMap { $0 }.joined(separator: "\n")
            }
        }
        var detail = input
        detail.removeValue(forKey: "file_path")
        detail.removeValue(forKey: "path")
        return compactDescription(detail)
    }

    private static func claudeToolResultActivity(_ block: [String: Any]) -> String? {
        guard block["type"] as? String == "tool_result" else { return nil }
        let prefix = (block["is_error"] as? Bool) == true ? "error\n" : ""
        guard let content = compactDescription(block["content"]), !content.isEmpty else {
            return prefix.isEmpty ? nil : prefix.trimmingCharacters(in: .newlines)
        }
        return prefix + content
    }

    private static func compactDescription(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            return String(string.prefix(12_000))
        }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else {
            return String(String(describing: value).prefix(12_000))
        }
        return String(String(decoding: data, as: UTF8.self).prefix(12_000))
    }

    private static func evidenceStrings(in value: Any) -> [String] {
        switch value {
        case let string as String:
            guard string.contains("/") || string.contains("http://") || string.contains("https://") || string.contains("localhost") else { return [] }
            return [String(string.prefix(4_000))]
        case let dictionary as [String: Any]:
            return dictionary.values.flatMap { evidenceStrings(in: $0) }
        case let array as [Any]:
            return array.flatMap { evidenceStrings(in: $0) }
        default:
            return []
        }
    }
}
