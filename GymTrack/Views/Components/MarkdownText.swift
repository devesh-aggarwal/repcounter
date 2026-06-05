import SwiftUI

/// Lightweight markdown renderer for AI chat responses. Handles the common
/// block elements OpenAI emits — headings, paragraphs, bullet + numbered
/// lists, code blocks, and a custom `[chart:Exercise Name]` directive that
/// inlines an `ExerciseSparkline` for the named exercise.
///
/// Inline formatting (bold, italic, links, inline code) is delegated to
/// `AttributedString(markdown:)` which SwiftUI's `Text` renders natively.
struct MarkdownText: View {
    let markdown: String
    let exercises: [Exercise]

    private var blocks: [Block] { Self.parse(markdown) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Block model

    fileprivate enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
        case numbered(Int, String)
        case codeBlock(String)
        case chart(String)
        case divider
    }

    // MARK: Rendering

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineAttributed(text))
                .font(.system(
                    size: level == 1 ? 20 : level == 2 ? 17 : 15,
                    weight: .bold
                ))
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 2)

        case .paragraph(let text):
            Text(inlineAttributed(text))
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text(inlineAttributed(text))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

        case .numbered(let n, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(n).")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(inlineAttributed(text))
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

        case .codeBlock(let code):
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.fill)
                )
                .textSelection(.enabled)

        case .chart(let name):
            if let exercise = matchExercise(named: name) {
                ExerciseSparkline(exercise: exercise)
                    .padding(.vertical, 2)
            } else {
                // Fall back gracefully when the model names something we
                // can't find — render the directive as plain text rather
                // than swallowing it silently.
                Text("[chart:\(name)]")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

        case .divider:
            Divider().overlay(Theme.stroke)
        }
    }

    private func inlineAttributed(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private func matchExercise(named raw: String) -> Exercise? {
        let needle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return exercises.first { $0.name.lowercased() == needle }
            ?? exercises.first { $0.name.lowercased().contains(needle) }
    }

    // MARK: Parser

    fileprivate static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var inCode = false
        var codeBuffer: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph.removeAll()
        }

        for line in source.components(separatedBy: "\n") {
            // Triple-backtick code blocks toggle on/off.
            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.codeBlock(codeBuffer.joined(separator: "\n")))
                    codeBuffer.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }
            if inCode {
                codeBuffer.append(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Standalone chart directive.
            if trimmed.hasPrefix("[chart:") && trimmed.hasSuffix("]") {
                flushParagraph()
                let name = String(trimmed.dropFirst("[chart:".count).dropLast())
                blocks.append(.chart(name))
                continue
            }

            // Horizontal rule.
            if trimmed == "---" || trimmed == "***" {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            // Headings.
            if trimmed.hasPrefix("### ") {
                flushParagraph()
                blocks.append(.heading(level: 3, text: String(trimmed.dropFirst(4))))
                continue
            }
            if trimmed.hasPrefix("## ") {
                flushParagraph()
                blocks.append(.heading(level: 2, text: String(trimmed.dropFirst(3))))
                continue
            }
            if trimmed.hasPrefix("# ") {
                flushParagraph()
                blocks.append(.heading(level: 1, text: String(trimmed.dropFirst(2))))
                continue
            }

            // Bullet list.
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                flushParagraph()
                blocks.append(.bullet(String(trimmed.dropFirst(2))))
                continue
            }

            // Numbered list: 1. or 1)
            if let match = trimmed.range(of: #"^(\d{1,2})[\.\)]\s"#, options: .regularExpression) {
                flushParagraph()
                let prefix = String(trimmed[trimmed.startIndex..<match.upperBound])
                let n = Int(prefix.filter(\.isNumber)) ?? 0
                let body = String(trimmed[match.upperBound...])
                blocks.append(.numbered(n, body))
                continue
            }

            // Blank line ends the current paragraph.
            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            paragraph.append(trimmed)
        }
        flushParagraph()
        if inCode, !codeBuffer.isEmpty {
            blocks.append(.codeBlock(codeBuffer.joined(separator: "\n")))
        }
        return blocks
    }
}
