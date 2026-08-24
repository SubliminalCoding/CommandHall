import SwiftUI

/// Typographic treatment for terminal-style text. A terminal needs one
/// fixed-width family so columns stay aligned, so every kind shares the same
/// face (Menlo — more characterful than the system SF Mono default) and is
/// distinguished by weight and color instead of by swapping families.
enum TerminalLineKind {
    case command   // an echoed prompt / command line
    case error     // errors, failures, tracebacks
    case warning   // warnings, deprecations
    case success   // completions, passing checks
    case output    // ordinary stdout
}

enum TerminalTypography {
    /// Installed on every modern macOS; falls back to the system monospace if
    /// somehow absent because `Font.custom` degrades gracefully.
    static let fontName = "Menlo"

    static func font(size: CGFloat, kind: TerminalLineKind) -> Font {
        let base = Font.custom(fontName, fixedSize: size)
        switch kind {
        case .command: return base.weight(.bold)
        case .error, .success: return base.weight(.medium)
        case .warning, .output: return base
        }
    }

    static func color(_ kind: TerminalLineKind) -> Color {
        switch kind {
        case .command: return Color(red: 0.60, green: 0.95, blue: 0.80)   // bright teal — stands out
        case .error:   return Color(red: 1.00, green: 0.47, blue: 0.45)   // red
        case .warning: return Color(red: 1.00, green: 0.80, blue: 0.42)   // amber
        case .success: return Color(red: 0.53, green: 0.92, blue: 0.60)   // green
        case .output:  return Color(red: 0.79, green: 0.90, blue: 0.83)   // soft green-white (the prior default)
        }
    }

    /// Conservative, high-precision line classification. Anything unmatched
    /// stays ordinary output, so normal text is never mis-tinted.
    static func classify(_ line: String) -> TerminalLineKind {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .output }

        for marker in ["❯", "➜", "$ ", "% "] where trimmed.hasPrefix(marker) {
            return .command
        }

        let lower = trimmed.lowercased()
        let errorTokens = ["error", "fatal:", "command not found", "permission denied",
                           "traceback (most recent call last)", "no such file or directory",
                           "segmentation fault", "panic:", "✗", "✘"]
        if errorTokens.contains(where: lower.contains) { return .error }

        let warningTokens = ["warning", "deprecated", "⚠"]
        if warningTokens.contains(where: lower.contains) { return .warning }

        let successTokens = ["build complete", "compiled successfully", "tests passed",
                             "success", "✓", "✔", " passed", "up to date"]
        if successTokens.contains(where: lower.contains) { return .success }

        return .output
    }

    /// Render a raw transcript into a per-line styled `AttributedString`.
    static func attributed(_ raw: String, size: CGFloat) -> AttributedString {
        var result = AttributedString()
        let lines = raw.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let kind = classify(line)
            var piece = AttributedString(line)
            piece.font = font(size: size, kind: kind)
            piece.foregroundColor = color(kind)
            result.append(piece)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }
}
