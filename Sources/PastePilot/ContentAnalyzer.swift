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

    static func analyze(_ rawText: String) -> AnalysisResult {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sensitive = sensitivePatterns.contains { text.range(of: $0, options: .regularExpression) != nil }

        if isJSON(text) {
            return AnalysisResult(kind: .json, containsSensitiveData: sensitive)
        }
        if URL(string: text).flatMap({ $0.scheme }) != nil, !text.contains(where: \.isWhitespace) {
            return AnalysisResult(kind: .url, containsSensitiveData: sensitive)
        }
        if text.range(of: #"^(#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|rgba?\([^)]+\)|hsla?\([^)]+\))$"#, options: .regularExpression) != nil {
            return AnalysisResult(kind: .color, containsSensitiveData: sensitive)
        }
        if looksLikeError(text) {
            return AnalysisResult(kind: .error, containsSensitiveData: sensitive)
        }
        if looksLikeCommand(text) {
            return AnalysisResult(kind: .command, containsSensitiveData: sensitive)
        }
        if looksLikeMarkdown(text) {
            return AnalysisResult(kind: .markdown, containsSensitiveData: sensitive)
        }
        if looksLikeCode(text) {
            return AnalysisResult(kind: .code, containsSensitiveData: sensitive)
        }
        return AnalysisResult(kind: .text, containsSensitiveData: sensitive)
    }

    static func redacted(_ text: String) -> String {
        sensitivePatterns.reduce(text) { result, pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
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
        let prefixes = [
            "$ ", "git ", "npm ", "pnpm ", "yarn ", "bun ", "swift ",
            "cargo ", "go ", "docker ", "kubectl ", "curl ", "brew ",
            "cd ", "ls ", "mkdir ", "rm ", "cp ", "mv ", "ssh "
        ]
        return prefixes.contains(where: text.hasPrefix)
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
