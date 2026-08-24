import SwiftUI

/// Renders an agent's Brief reply as scannable, structured text instead of a
/// dense wall. The agent tends to write one sentence per line with almost no
/// blank lines, so this:
///  1. gives every sentence its own line with breathing room,
///  2. dims step-by-step narration ("Let me…") and brightens outcomes,
///  3. renders real markdown tables,
///  4. turns labelled status lead-ins ("Confirmed:", "Fixed:") into callouts,
///  5. promotes bold-only / `#` lines to headings,
/// while keeping `**bold**`, `*italic*`, inline `code`, bullets and ``` fences.
struct AgentBriefText: View {
    let content: String
    var accent: Color = .cyan
    /// Comfortable reading measure — on a wide pane the text sits in a centered
    /// column instead of stretching edge-to-edge.
    var columnWidth: CGFloat = 760

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
                    .padding(.top, topGap(for: block))
            }
        }
        .frame(maxWidth: columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .textSelection(.enabled)
    }

    private func topGap(for block: Block) -> CGFloat {
        if block.kind == .heading { return block.newGroup ? 12 : 8 }
        return block.newGroup ? 9 : 0
    }

    // MARK: Rendering

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block.kind {
        case .heading:
            Text(inline(block.text))
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.96))
                .frame(maxWidth: .infinity, alignment: .leading)

        case .paragraph:
            Text(inline(block.text))
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.88))
                .lineSpacing(3.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case .narration:
            // step-by-step process talk, pushed to the background
            Text(inline(block.text))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet:
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(accent.opacity(0.85))
                Text(inline(block.text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineSpacing(3.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, 4)

        case .callout:
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: block.callout.symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(block.callout.color)
                    .padding(.top, 1)
                Text(inline(block.text))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(3.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(block.callout.color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(block.callout.color.opacity(0.28)))

        case .code:
            Text(block.text)
                .font(.custom(TerminalTypography.fontName, fixedSize: 11.5))
                .foregroundStyle(Color(red: 0.79, green: 0.90, blue: 0.83))
                .lineSpacing(2.5)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(10)
                .background(Color.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.06)))

        case .table:
            tableView(block)
        }
    }

    private func tableView(_ block: Block) -> some View {
        let rows = block.tableRows
        let columns = rows.map(\.count).max() ?? 0
        return Grid(alignment: .topLeading, horizontalSpacing: 18, verticalSpacing: 7) {
            if block.tableHasHeader, let header = rows.first {
                GridRow {
                    ForEach(0..<columns, id: \.self) { c in
                        Text(inline(c < header.count ? header[c] : ""))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Divider().opacity(0.25)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if !(block.tableHasHeader && index == 0) {
                    GridRow {
                        ForEach(0..<columns, id: \.self) { c in
                            Text(inline(c < row.count ? row[c] : ""))
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.84))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.07)))
    }

    private func inline(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: string, options: options) {
            return parsed
        }
        return AttributedString(string)
    }

    // MARK: Model

    enum BlockKind { case heading, paragraph, narration, bullet, callout, code, table }

    enum CalloutKind {
        case done, info, warning
        var symbol: String {
            switch self {
            case .done: "checkmark.circle.fill"
            case .info: "info.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }
        var color: Color {
            switch self {
            case .done: Color(red: 0.53, green: 0.92, blue: 0.60)
            case .info: Color(red: 0.45, green: 0.80, blue: 0.95)
            case .warning: Color(red: 1.00, green: 0.72, blue: 0.38)
            }
        }
    }

    struct Block {
        let kind: BlockKind
        let text: String
        var newGroup = false                 // preceded by a blank line
        var callout: CalloutKind = .info
        var tableRows: [[String]] = []
        var tableHasHeader = false
    }

    private var blocks: [Block] { AgentBriefText.parse(content) }

    // MARK: Parsing

    private static let doneWords: Set<String> = [
        "confirmed", "fixed", "deployed", "done", "shipped", "verified", "complete",
        "completed", "resolved", "success", "created", "added", "merged", "passed", "working",
    ]
    private static let warnWords: Set<String> = [
        "warning", "failed", "error", "blocked", "caution", "heads-up", "gotcha",
    ]
    private static let infoWords: Set<String> = [
        "note", "fyi", "caveat", "important", "tip", "context",
    ]
    private static let narrationPrefixes: [String] = [
        "let me", "let's", "i'll", "i'm ", "i am ", "i need to", "i want to", "i should",
        "now let me", "now i'll", "next, ", "checking", "let me check", "let me see",
        "let me find", "let me verify", "let me read", "let me look", "one more",
    ]

    private static func parse(_ content: String) -> [Block] {
        var blocks: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var pendingBreak = false
        var index = 0

        func push(_ block: Block) {
            var block = block
            if pendingBreak { block.newGroup = true; pendingBreak = false }
            blocks.append(block)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                index += 1
                var code: [String] = []
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index]); index += 1
                }
                index += 1
                push(Block(kind: .code, text: code.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty { pendingBreak = true; index += 1; continue }

            // markdown table: a pipe row followed by a |---| separator
            if looksLikeTableRow(trimmed), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                var rows = [parseTableRow(trimmed)]
                index += 2
                while index < lines.count, looksLikeTableRow(lines[index].trimmingCharacters(in: .whitespaces)) {
                    rows.append(parseTableRow(lines[index].trimmingCharacters(in: .whitespaces)))
                    index += 1
                }
                var block = Block(kind: .table, text: "")
                block.tableRows = rows
                block.tableHasHeader = true
                push(block)
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                push(Block(kind: .bullet, text: String(trimmed.dropFirst(2))))
                index += 1; continue
            }

            if trimmed.hasPrefix("#") {
                let heading = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                push(Block(kind: .heading, text: heading))
                index += 1; continue
            }

            if trimmed.hasPrefix("**"), trimmed.hasSuffix("**"), trimmed.count > 4 {
                let inner = trimmed.dropFirst(2).dropLast(2)
                if !inner.contains("**") {
                    push(Block(kind: .heading, text: String(inner)))
                    index += 1; continue
                }
            }

            if let kind = calloutKind(trimmed) {
                var block = Block(kind: .callout, text: trimmed)
                block.callout = kind
                push(block)
                index += 1; continue
            }

            push(Block(kind: isNarration(trimmed) ? .narration : .paragraph, text: trimmed))
            index += 1
        }

        return blocks
    }

    /// A labelled status lead-in like "Confirmed:", "**Fixed:**", "Warning:".
    static func calloutKind(_ raw: String) -> CalloutKind? {
        let cleaned = raw.replacingOccurrences(of: "*", with: "")
        guard let colon = cleaned.firstIndex(of: ":") else { return nil }
        let label = cleaned[cleaned.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        guard !label.isEmpty, label.count <= 30 else { return nil }
        let firstWord = label.split(separator: " ").first.map(String.init) ?? label
        if doneWords.contains(firstWord) || doneWords.contains(label) { return .done }
        if warnWords.contains(firstWord) || warnWords.contains(label) { return .warning }
        if infoWords.contains(firstWord) || infoWords.contains(label) { return .info }
        return nil
    }

    static func isNarration(_ line: String) -> Bool {
        let lower = line.replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespaces).lowercased()
        return narrationPrefixes.contains { lower.hasPrefix($0) }
    }

    private static func looksLikeTableRow(_ line: String) -> Bool {
        line.filter { $0 == "|" }.count >= 2
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("|") && trimmed.contains("-")
            && trimmed.allSatisfy { "|-: ".contains($0) }
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Test hook: the sequence of block kinds parsed from `content`.
    static func blockKinds(_ content: String) -> [String] {
        parse(content).map { block in
            switch block.kind {
            case .heading: "heading"
            case .paragraph: "paragraph"
            case .narration: "narration"
            case .bullet: "bullet"
            case .callout: "callout"
            case .code: "code"
            case .table: "table"
            }
        }
    }
}
