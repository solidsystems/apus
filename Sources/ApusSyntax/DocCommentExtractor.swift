import SwiftSyntax

/// Extracts documentation comments from a syntax node's leading trivia.
enum DocCommentExtractor: Sendable {
    static func extract(from trivia: Trivia) -> String? {
        var lines: [String] = []

        for piece in trivia {
            switch piece {
            case .docLineComment(let text):
                // Strip leading "/// " or "///"
                let stripped = text.hasPrefix("/// ")
                    ? String(text.dropFirst(4))
                    : String(text.dropFirst(3))
                lines.append(stripped)
            case .docBlockComment(let text):
                // Strip leading "/**" and trailing "*/"
                var body = text
                if body.hasPrefix("/**") { body = String(body.dropFirst(3)) }
                if body.hasSuffix("*/") { body = String(body.dropLast(2)) }
                let blockLines = body.split(separator: "\n", omittingEmptySubsequences: false)
                    .map { line -> String in
                        var l = String(line)
                        // Strip leading whitespace and optional " * " prefix
                        l = l.trimmingCharacters(in: .whitespaces)
                        if l.hasPrefix("* ") { l = String(l.dropFirst(2)) }
                        else if l == "*" { l = "" }
                        return l
                    }
                lines.append(contentsOf: blockLines)
            default:
                continue
            }
        }

        guard !lines.isEmpty else { return nil }
        let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
