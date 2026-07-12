import Foundation

struct UserSensitivePattern: Equatable, Sendable {
    enum MatchKind: Equatable, Sendable {
        case literal
        case regularExpression
    }

    static let regularExpressionPrefix = "regex:"

    let kind: MatchKind
    let value: String

    static func patterns(from text: String) -> [UserSensitivePattern] {
        text.components(separatedBy: .newlines).compactMap(Self.init(rawLine:))
    }

    private init?(rawLine: String) {
        let trimmedLine = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLine.isEmpty else { return nil }

        if trimmedLine.lowercased().hasPrefix(Self.regularExpressionPrefix) {
            let valueStart = trimmedLine.index(
                trimmedLine.startIndex,
                offsetBy: Self.regularExpressionPrefix.count
            )
            let value = trimmedLine[valueStart...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return nil }
            self.init(kind: .regularExpression, value: value)
        } else {
            self.init(kind: .literal, value: trimmedLine)
        }
    }

    init(kind: MatchKind, value: String) {
        self.kind = kind
        self.value = value
    }
}

enum ContentAnalysisTrait: String, CaseIterable, Hashable {
    case json
    case url
    case color
    case shellCommand
    case error
    case markdown
    case sourceCode
    case yaml
    case xml
    case sql
    case base64
    case naturalLanguage
    case email
    case uuid
    case jwt
}

struct AnalysisResult {
    let kind: ContentKind
    let containsSensitiveData: Bool
    let confidence: Double
    let reasons: [String]
    let traits: Set<ContentAnalysisTrait>
}

enum ContentAnalyzer {
    private struct DetectionCandidate {
        let kind: ContentKind
        let confidence: Double
        let priority: Int
        var reasons: [String]
        var traits: Set<ContentAnalysisTrait>
    }

    private struct TraitMatch {
        let trait: ContentAnalysisTrait
        let reason: String
    }

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

    static func analyze(
        _ rawText: String,
        userPatterns: [UserSensitivePattern] = []
    ) -> AnalysisResult {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let detection = detectContent(text)
        let containsSensitiveData = containsSensitiveData(
            text,
            userPatterns: userPatterns
        )
        var reasons = detection.reasons
        if containsSensitiveData {
            appendUnique("Sensitive content pattern matched", to: &reasons)
        }
        return AnalysisResult(
            kind: detection.kind,
            containsSensitiveData: containsSensitiveData,
            confidence: detection.confidence,
            reasons: reasons,
            traits: detection.traits
        )
    }

    private static func detectContent(_ text: String) -> DetectionCandidate {
        guard !text.isEmpty else {
            return DetectionCandidate(
                kind: .text,
                confidence: 0.05,
                priority: 0,
                reasons: ["Empty or whitespace-only content"],
                traits: []
            )
        }

        var candidates = [
            DetectionCandidate(
                kind: .text,
                confidence: 0.1,
                priority: 0,
                reasons: ["No stronger content pattern matched"],
                traits: []
            )
        ]
        [
            jsonCandidate(for: text),
            urlCandidate(for: text),
            colorCandidate(for: text),
            errorCandidate(for: text),
            commandCandidate(for: text),
            markdownCandidate(for: text),
            codeCandidate(for: text)
        ].compactMap(\.self).forEach { candidates.append($0) }

        var traits = Set(candidates.flatMap(\.traits))
        let secondaryMatches = secondaryTraitMatches(in: text)
        secondaryMatches.forEach { traits.insert($0.trait) }

        var selected = candidates.max {
            if $0.confidence == $1.confidence {
                return $0.priority < $1.priority
            }
            return $0.confidence < $1.confidence
        } ?? candidates[0]
        secondaryMatches
            .filter { !selected.traits.contains($0.trait) }
            .forEach { appendUnique($0.reason, to: &selected.reasons) }
        selected.traits = traits
        return selected
    }

    static func containsSensitiveData(
        _ text: String,
        userPatterns: [UserSensitivePattern] = []
    ) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return allSensitivePatterns(userPatterns: userPatterns).contains {
            $0.regex.firstMatch(in: text, range: range) != nil
        }
    }

    static func redacted(
        _ text: String,
        userPatterns: [UserSensitivePattern] = []
    ) -> String {
        allSensitivePatterns(userPatterns: userPatterns).reduce(text) { result, pattern in
            let range = NSRange(result.startIndex..., in: result)
            return pattern.regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: pattern.replacementTemplate
            )
        }
    }

    private static func allSensitivePatterns(
        userPatterns: [UserSensitivePattern]
    ) -> [SensitivePattern] {
        guard !userPatterns.isEmpty else { return sensitivePatterns }
        return sensitivePatterns + userPatterns.compactMap(makeSensitivePattern)
    }

    private static func makeSensitivePattern(
        _ userPattern: UserSensitivePattern
    ) -> SensitivePattern? {
        switch userPattern.kind {
        case .literal:
            makeSensitivePattern(
                NSRegularExpression.escapedPattern(for: userPattern.value),
                replacementTemplate: redactionToken,
                options: .caseInsensitive
            )
        case .regularExpression:
            makeSensitivePattern(
                userPattern.value,
                replacementTemplate: redactionToken
            )
        }
    }

    private static func makeSensitivePattern(
        _ pattern: String,
        replacementTemplate: String,
        options: NSRegularExpression.Options = []
    ) -> SensitivePattern? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: options
        ) else {
            return nil
        }
        return SensitivePattern(
            regex: regex,
            replacementTemplate: replacementTemplate
        )
    }

    private static func jsonCandidate(for text: String) -> DetectionCandidate? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              object is [String: Any] || object is [Any] else {
            return nil
        }
        return DetectionCandidate(
            kind: .json,
            confidence: 0.98,
            priority: 100,
            reasons: ["Parsed as JSON object or array"],
            traits: [.json]
        )
    }

    private static func urlCandidate(for text: String) -> DetectionCandidate? {
        guard !text.contains(where: \.isWhitespace),
              let scheme = URL(string: text)?.scheme?.lowercased(),
              supportedURLSchemes.contains(scheme) else {
            return nil
        }
        return DetectionCandidate(
            kind: .url,
            confidence: 0.93,
            priority: 90,
            reasons: ["Supported URL scheme \"\(scheme)\" matched"],
            traits: [.url]
        )
    }

    private static func colorCandidate(for text: String) -> DetectionCandidate? {
        guard matches(
            #"^(#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|rgba?\([^)]+\)|hsla?\([^)]+\))$"#,
            in: text
        ) else {
            return nil
        }
        return DetectionCandidate(
            kind: .color,
            confidence: 0.9,
            priority: 80,
            reasons: ["CSS color literal matched"],
            traits: [.color]
        )
    }

    private static func errorCandidate(for text: String) -> DetectionCandidate? {
        let markers = [
            "error:", "fatal:", "exception", "traceback", "stack trace",
            "uncaught", "segmentation fault", "command not found", "permission denied"
        ]
        let lowercased = text.lowercased()
        if let marker = markers.first(where: lowercased.contains) {
            return DetectionCandidate(
                kind: .error,
                confidence: 0.86,
                priority: 70,
                reasons: ["Error marker \"\(marker)\" matched"],
                traits: [.error]
            )
        }
        guard matches(#"\b[A-Z][A-Za-z]+Error\b"#, in: text) else {
            return nil
        }
        return DetectionCandidate(
            kind: .error,
            confidence: 0.88,
            priority: 70,
            reasons: ["Exception or error type name matched"],
            traits: [.error]
        )
    }

    private static func commandCandidate(for text: String) -> DetectionCandidate? {
        if text.contains("\n") {
            guard let extracted = ContentTransformer.extractShellCommands(text) else {
                return nil
            }
            let confidence = extracted.trimmingCharacters(in: .whitespacesAndNewlines)
                == text.trimmingCharacters(in: .whitespacesAndNewlines)
                ? 0.84
                : 0.88
            return DetectionCandidate(
                kind: .command,
                confidence: confidence,
                priority: 60,
                reasons: ["Shell commands extracted from text"],
                traits: [.shellCommand]
            )
        }
        guard text.count < 500 else { return nil }
        if ContentTransformer.promptedCommand(from: text) != nil {
            return DetectionCandidate(
                kind: .command,
                confidence: 0.9,
                priority: 60,
                reasons: ["Shell prompt command matched"],
                traits: [.shellCommand]
            )
        }
        guard ContentTransformer.isBareShellCommand(text) else { return nil }
        return DetectionCandidate(
            kind: .command,
            confidence: 0.84,
            priority: 60,
            reasons: ["Known shell executable matched"],
            traits: [.shellCommand]
        )
    }

    private static func markdownCandidate(for text: String) -> DetectionCandidate? {
        let blockSyntaxMatched = matches(
            #"(?m)^(#{1,6}\s|[-*]\s|\d+\.\s|>\s|```)"#,
            in: text
        )
        let linkSyntaxMatched = matches(#"\[[^\]]+\]\([^)]+\)"#, in: text)
        guard blockSyntaxMatched || linkSyntaxMatched else { return nil }
        return DetectionCandidate(
            kind: .markdown,
            confidence: blockSyntaxMatched ? 0.76 : 0.7,
            priority: 50,
            reasons: [
                blockSyntaxMatched
                    ? "Markdown block syntax matched"
                    : "Markdown link syntax matched"
            ],
            traits: [.markdown]
        )
    }

    private static func codeCandidate(for text: String) -> DetectionCandidate? {
        var traits: Set<ContentAnalysisTrait> = []
        var reasons: [String] = []
        var confidence = 0.0

        if looksLikeXML(text) {
            traits.insert(.xml)
            appendUnique("XML-like tags matched", to: &reasons)
            confidence = max(confidence, 0.82)
        }
        if looksLikeSQL(text) {
            traits.insert(.sql)
            appendUnique("SQL statement keywords matched", to: &reasons)
            confidence = max(confidence, 0.8)
        }
        if looksLikeYAML(text) {
            traits.insert(.yaml)
            appendUnique("YAML-style key/value lines matched", to: &reasons)
            confidence = max(confidence, 0.68)
        }
        if looksLikeSourceCode(text) {
            traits.insert(.sourceCode)
            appendUnique("Source code syntax markers matched", to: &reasons)
            confidence = max(confidence, 0.72)
        }

        guard confidence > 0 else { return nil }
        if traits.subtracting([.yaml, .xml, .sql]).isEmpty {
            traits.insert(.sourceCode)
        }
        return DetectionCandidate(
            kind: .code,
            confidence: confidence,
            priority: 40,
            reasons: reasons,
            traits: traits
        )
    }

    private static func secondaryTraitMatches(in text: String) -> [TraitMatch] {
        var traitMatches: [TraitMatch] = []
        if looksLikeYAML(text) {
            traitMatches.append(TraitMatch(
                trait: .yaml,
                reason: "YAML-style key/value lines matched"
            ))
        }
        if looksLikeXML(text) {
            traitMatches.append(TraitMatch(
                trait: .xml,
                reason: "XML-like tags matched"
            ))
        }
        if looksLikeSQL(text) {
            traitMatches.append(TraitMatch(
                trait: .sql,
                reason: "SQL statement keywords matched"
            ))
        }
        if looksLikeBase64(text) {
            traitMatches.append(TraitMatch(
                trait: .base64,
                reason: "Base64 payload shape matched"
            ))
        }
        if looksLikeNaturalLanguage(text) {
            traitMatches.append(TraitMatch(
                trait: .naturalLanguage,
                reason: "Natural language sentence structure matched"
            ))
        }
        if matches(
            #"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            in: text,
            options: [.caseInsensitive]
        ) {
            traitMatches.append(TraitMatch(
                trait: .email,
                reason: "Email address pattern matched"
            ))
        }
        if matches(
            #"\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b"#,
            in: text,
            options: [.caseInsensitive]
        ) {
            traitMatches.append(TraitMatch(
                trait: .uuid,
                reason: "UUID pattern matched"
            ))
        }
        if matches(
            #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#,
            in: text
        ) {
            traitMatches.append(TraitMatch(
                trait: .jwt,
                reason: "JWT token shape matched"
            ))
        }
        return traitMatches
    }

    private static func looksLikeSourceCode(_ text: String) -> Bool {
        let markers = ["func ", "function ", "const ", "let ", "var ", "class ", "struct ", "import ", "=>", "();", " {"]
        let score = markers.reduce(0) { $0 + (text.contains($1) ? 1 : 0) }
        return score >= 2 || (text.contains("\n") && text.contains("{") && text.contains("}"))
    }

    private static func looksLikeYAML(_ text: String) -> Bool {
        guard text.contains("\n") else { return false }
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard lines.count >= 2 else { return false }
        let keyValueCount = lines.filter {
            matches(#"^[A-Za-z0-9_.-]+\s*:\s+.+$"#, in: $0)
        }.count
        return keyValueCount >= 2
    }

    private static func looksLikeXML(_ text: String) -> Bool {
        matches(#"^\s*<\?xml\b[\s\S]*\?>[\s\S]*<[/A-Za-z]"#, in: text)
            || matches(
                #"^\s*<([A-Za-z_][A-Za-z0-9_.:-]*)\b[^>]*>[\s\S]*</\1>\s*$"#,
                in: text
            )
    }

    private static func looksLikeSQL(_ text: String) -> Bool {
        matches(
            #"(?is)^\s*(SELECT|WITH|INSERT\s+INTO|UPDATE|DELETE\s+FROM|CREATE\s+TABLE|ALTER\s+TABLE)\b[\s\S]*(\bFROM\b|\bSET\b|\bVALUES\b|\bTABLE\b|;)"#,
            in: text
        )
    }

    private static func looksLikeBase64(_ text: String) -> Bool {
        let trimCharacters = CharacterSet(
            charactersIn: #""'`,.;:()[]{}<>"#
        )
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .contains { rawToken in
                let token = rawToken.trimmingCharacters(in: trimCharacters)
                guard token.count >= 16,
                      token.count % 4 == 0,
                      token.contains("=") || token.contains("+") || token.contains("/"),
                      matches(#"^[A-Za-z0-9+/]+={0,2}$"#, in: token),
                      Data(base64Encoded: token) != nil else {
                    return false
                }
                return true
            }
    }

    private static func looksLikeNaturalLanguage(_ text: String) -> Bool {
        let words = text
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 2 }
        guard words.count >= 5 else { return false }

        let lowercased = " \(text.lowercased()) "
        let commonWords = [
            " the ", " and ", " or ", " to ", " for ", " with ", " about ",
            " this ", " that ", " is ", " are "
        ]
        return commonWords.contains(where: lowercased.contains)
            || matches(#"[.!?]\s*$"#, in: text)
    }

    private static func matches(
        _ pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) -> Bool {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: options
        ) else {
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }

    private static func appendUnique(_ reason: String, to reasons: inout [String]) {
        guard !reasons.contains(reason) else { return }
        reasons.append(reason)
    }
}
