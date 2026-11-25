import Foundation

enum HTMLPlainTextExtractor {
    private static let strippedBlockRegexes: [NSRegularExpression] = [
        RegexFactory.make(#"<!--[\s\S]*?-->"#),
        RegexFactory.make(#"<script\b[^>]*>[\s\S]*?</script\s*>"#, options: [.caseInsensitive]),
        RegexFactory.make(#"<style\b[^>]*>[\s\S]*?</style\s*>"#, options: [.caseInsensitive]),
        RegexFactory.make(#"<head\b[^>]*>[\s\S]*?</head\s*>"#, options: [.caseInsensitive])
    ].compactMap(\.self)

    private static let lineBreakTagRegex = RegexFactory.make(
        #"<(?:br\s*/?|/(?:p|div|li|tr|h[1-6]|blockquote|pre)\b[^>]*)>"#,
        options: [.caseInsensitive]
    )
    private static let stripTagsRegex = RegexFactory.make(#"<[^>]+>"#)
    private static let horizontalWhitespaceRegex = RegexFactory.make(#"[ \t\u00A0]+"#)
    private static let numericEntityRegex = RegexFactory.make(#"&#(x[0-9A-Fa-f]+|[0-9]+);"#)

    private static let namedEntities: [(entity: String, replacement: String)] = [
        ("&amp;", "&"),
        ("&lt;", "<"),
        ("&gt;", ">"),
        ("&quot;", "\""),
        ("&#39;", "'"),
        ("&apos;", "'"),
        ("&nbsp;", " ")
    ]

    static func extractPlainText(from html: String) -> String {
        var text = html
        for regex in strippedBlockRegexes {
            let range = NSRange(text.startIndex..., in: text)
            text = regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }
        if let lineBreakTagRegex {
            let range = NSRange(text.startIndex..., in: text)
            text = lineBreakTagRegex.stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: "\n"
            )
        }
        if let stripTagsRegex {
            let range = NSRange(text.startIndex..., in: text)
            text = stripTagsRegex.stringByReplacingMatches(
                in: text,
                range: range,
                withTemplate: ""
            )
        }

        text = decodeHTMLEntities(in: text)
        text = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let normalizedLines = text
            .components(separatedBy: "\n")
            .map { line -> String in
                let collapsed: String
                if let horizontalWhitespaceRegex {
                    let range = NSRange(line.startIndex..., in: line)
                    collapsed = horizontalWhitespaceRegex.stringByReplacingMatches(
                        in: line,
                        range: range,
                        withTemplate: " "
                    )
                } else {
                    collapsed = line
                }
                return collapsed.trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }

        return normalizedLines
            .joined(separator: "\n")
    }

    static func decodeHTMLEntities(in value: String) -> String {
        var decoded = value
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }

        guard let numericEntityRegex else {
            return decoded
        }
        let matches = numericEntityRegex.matches(
            in: decoded,
            range: NSRange(decoded.startIndex..., in: decoded)
        ).reversed()
        for match in matches {
            guard let wholeRange = Range(match.range(at: 0), in: decoded),
                  let valueRange = Range(match.range(at: 1), in: decoded) else {
                continue
            }
            let encodedValue = String(decoded[valueRange])
            let radix = encodedValue.lowercased().hasPrefix("x") ? 16 : 10
            let digits = radix == 16 ? String(encodedValue.dropFirst()) : encodedValue
            guard let scalarValue = UInt32(digits, radix: radix),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            decoded.replaceSubrange(wholeRange, with: String(Character(scalar)))
        }
        return decoded
    }
}
