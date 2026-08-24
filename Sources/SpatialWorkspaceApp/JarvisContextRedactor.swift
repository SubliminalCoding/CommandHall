import Foundation

enum JarvisContextRedactor {
    private static let patterns: [(NSRegularExpression, String)] = [
        (
            try! NSRegularExpression(pattern: #"(?i)\b(?:sk-(?:proj-)?|gsk_|xox[baprs]-|gh[pousr]_|AKIA)[A-Za-z0-9_\-]{8,}"#),
            "[REDACTED CREDENTIAL]"
        ),
        (
            try! NSRegularExpression(pattern: #"(?i)(authorization\s*:\s*bearer\s+)[^\s]+"#),
            "$1[REDACTED]"
        ),
        (
            try! NSRegularExpression(pattern: #"(?i)\b([A-Z][A-Z0-9_]{2,}(?:API_KEY|TOKEN|SECRET|PASSWORD)\s*=\s*)[^\s]+"#),
            "$1[REDACTED]"
        ),
        (
            try! NSRegularExpression(pattern: #"(?i)((?:--api-key|--token|--secret|--password)(?:=|\s+))[^\s]+"#),
            "$1[REDACTED]"
        ),
    ]

    static func redact(_ value: String, limit: Int) -> String {
        var redacted = value
        for (pattern, template) in patterns {
            let range = NSRange(redacted.startIndex ..< redacted.endIndex, in: redacted)
            redacted = pattern.stringByReplacingMatches(
                in: redacted,
                range: range,
                withTemplate: template
            )
        }
        guard redacted.count > limit else { return redacted }
        return String(redacted.prefix(max(0, limit - 1))) + "…"
    }

    static func singleLine(_ value: String, limit: Int) -> String {
        let collapsed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return redact(collapsed, limit: limit)
    }
}
