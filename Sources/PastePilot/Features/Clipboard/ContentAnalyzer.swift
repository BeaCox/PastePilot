import Foundation

struct AnalysisResult {
    let kind: ContentKind
    let containsSensitiveData: Bool
}

enum ContentAnalyzer {
    private struct SensitivePattern {
        let regex: NSRegularExpression
        let replacementTemplate: String
    }

    private static let redactionToken = "••••••••"
    private static let sensitiveAssignmentKeyPattern =
        #"(?i)\b("#
            + #"api[_-]?key|access[_-]?token|auth[_-]?token|"#
            + #"client[_-]?secret|password|passwd|"#
            + #"aws[_-]?secret[_-]?access[_-]?key|secret[_-]?access[_-]?key"#
            + #")\b"#

    private static let sensitivePatterns: [SensitivePattern] = [
        makeSensitivePattern(
            sensitiveAssignmentKeyPattern + #"(\s*[:=]\s*)"[^"]*""#,
            replacementTemplate: "$1$2\"\(redactionToken)\""
        ),
        makeSensitivePattern(
            sensitiveAssignmentKeyPattern + #"(\s*[:=]\s*)'[^']*'"#,
            replacementTemplate: "$1$2'\(redactionToken)'"
        ),
        makeSensitivePattern(
            sensitiveAssignmentKeyPattern + #"(\s*[:=]\s*)[^\s"',;}]+"#,
            replacementTemplate: "$1$2\(redactionToken)"
        ),
        makeSensitivePattern(
            #"(?i)\b(Bearer\s+)[A-Za-z0-9._~+/-]+=*\b"#,
            replacementTemplate: "$1\(redactionToken)"
        ),
        makeSensitivePattern(
            #"\bsk-[A-Za-z0-9_-]{16,}\b"#,
            replacementTemplate: redactionToken
        ),
        makeSensitivePattern(
            #"\bgh[opsur]_[A-Za-z0-9]{20,}\b"#,
            replacementTemplate: redactionToken
        ),
        makeSensitivePattern(
            #"\bgithub_pat_[A-Za-z0-9_]{20,}\b"#,
            replacementTemplate: redactionToken
        ),
        makeSensitivePattern(
            #"\bxox[abprs]-[A-Za-z0-9-]{20,}\b"#,
            replacementTemplate: redactionToken
        ),
        makeSensitivePattern(
            #"\b(?:A3T[A-Z0-9]|AKIA|ASIA)[A-Z0-9]{16}\b"#,
            replacementTemplate: redactionToken
        ),
        makeSensitivePattern(
            #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            replacementTemplate: redactionToken
        ),
        makeSensitivePattern(
            #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\s\S]*?-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            replacementTemplate: redactionToken
        ),
        makeSensitivePattern(
            #"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"#,
            replacementTemplate: redactionToken
        )
    ].compactMap(\.self)

    private static let supportedURLSchemes: Set<String> = [
        "http", "https", "file", "mailto"
    ]

    static func analyze(_ rawText: String) -> AnalysisResult {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        return AnalysisResult(
            kind: detectKind(text),
            containsSensitiveData: containsSensitiveData(text)
        )
    }

    private static func detectKind(_ text: String) -> ContentKind {
        if isJSON(text) { return .json }
        if isSupportedURL(text) { return .url }
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
        return sensitivePatterns.contains {
            $0.regex.firstMatch(in: text, range: range) != nil
        }
    }

    static func redacted(_ text: String) -> String {
        sensitivePatterns.reduce(text) { result, pattern in
            let range = NSRange(result.startIndex..., in: result)
            return pattern.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: pattern.replacementTemplate
            )
        }
    }

    private static func makeSensitivePattern(
        _ pattern: String,
        replacementTemplate: String
    ) -> SensitivePattern? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        return SensitivePattern(
            regex: regex,
            replacementTemplate: replacementTemplate
        )
    }

    private static func isJSON(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] || object is [Any] else {
            return false
        }
        return true
    }

    private static func isSupportedURL(_ text: String) -> Bool {
        guard !text.contains(where: \.isWhitespace),
              let scheme = URL(string: text)?.scheme?.lowercased(),
              supportedURLSchemes.contains(scheme) else {
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
