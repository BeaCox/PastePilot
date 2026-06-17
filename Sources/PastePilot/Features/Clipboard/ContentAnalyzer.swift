import Foundation

struct AnalysisResult {
    let kind: ContentKind
    let containsSensitiveData: Bool
}

enum ContentAnalyzer {
    private static let sensitivePatterns = [
        #"(?i)\b(api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|passwd)\b\s*[:=]\s*["']?[^\s"',;}]+"#,
        #"\bsk-[A-Za-z0-9_-]{16,}\b"#,
        #"\bgh[opsu]_[A-Za-z0-9]{20,}\b"#,
        #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#
    ]

    private static let sensitiveRegexes: [NSRegularExpression] = sensitivePatterns.compactMap {
        try? NSRegularExpression(pattern: $0)
    }

    static func analyze(_ rawText: String) -> AnalysisResult {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return AnalysisResult(
            kind: detectKind(text),
            containsSensitiveData: containsSensitiveData(text)
        )
    }

    private static func detectKind(_ text: String) -> ContentKind {
        if isJSON(text) { return .json }
        if URL(string: text).flatMap({ $0.scheme }) != nil, !text.contains(where: \.isWhitespace) {
            return .url
        }
        if text.range(of: #"^(#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|rgba?\([^)]+\)|hsla?\([^)]+\))$"#, options: .regularExpression) != nil {
            return .color
        }
        if looksLikeError(text) { return .error }
        if looksLikeCommand(text) { return .command }
        if looksLikeMarkdown(text) { return .markdown }
        if looksLikeCode(text) { return .code }
        return .text
    }

    static func containsSensitiveData(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return sensitiveRegexes.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    static func redacted(_ text: String) -> String {
        sensitiveRegexes.reduce(text) { result, regex in
            let range = NSRange(result.startIndex..., in: result)
            return regex.stringByReplacingMatches(in: result, range: range, withTemplate: "••••••••")
        }
    }

    private static func isJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] || object is [Any] else {
            return false
        }
        return true
    }

    private static func looksLikeError(_ text: String) -> Bool {
        let markers = [
            "error:", "fatal:", "exception", "traceback", "stack trace",
            "uncaught", "segmentation fault", "command not found", "permission denied"
        ]
        let lowercased = text.lowercased()
        return markers.contains(where: lowercased.contains)
            || text.range(of: #"\b[A-Z][A-Za-z]+Error\b"#, options: .regularExpression) != nil
    }

    private static func looksLikeCommand(_ text: String) -> Bool {
        if text.contains("\n") {
            return ContentTransformer.extractShellCommands(text) != nil
        }
        guard text.count < 500 else { return false }
        return ContentTransformer.promptedCommand(from: text) != nil
            || ContentTransformer.isBareShellCommand(text)
    }

    private static func looksLikeMarkdown(_ text: String) -> Bool {
        text.range(of: #"(?m)^(#{1,6}\s|[-*]\s|\d+\.\s|>\s|```)"#, options: .regularExpression) != nil
            || text.range(of: #"\[[^\]]+\]\([^)]+\)"#, options: .regularExpression) != nil
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let markers = ["func ", "function ", "const ", "let ", "var ", "class ", "struct ", "import ", "=>", "();", " {"]
        let score = markers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        return score >= 2 || (text.contains("\n") && text.contains("{") && text.contains("}"))
    }
}
