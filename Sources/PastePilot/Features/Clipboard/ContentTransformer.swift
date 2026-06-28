import Foundation

enum ContentTransformer {
    static func formatJSON(_ text: String) -> String? {
        transformJSON(text, options: [.prettyPrinted, .sortedKeys])
    }

    static func minifyJSON(_ text: String) -> String? {
        transformJSON(text, options: [.sortedKeys])
    }

    static func jsonToTypeScript(_ text: String, rootName: String = "Root") -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return TypeScriptDeclarationGenerator.declaration(
            name: rootName,
            value: object
        )
    }

    static func toCamelCase(_ text: String) -> String {
        let words = splitWords(text)
        guard let first = words.first else { return text }
        return first.lowercased() + words.dropFirst().map(\.capitalizedFirst).joined()
    }

    static func toSnakeCase(_ text: String) -> String {
        splitWords(text).map { $0.lowercased() }.joined(separator: "_")
    }

    static func escapeString(_ text: String) -> String {
        var escaped = text
        escaped = escaped.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\t", with: "\\t")
        return escaped
    }

    static func shellCodeBlock(_ text: String) -> String {
        ShellCommandParser.codeBlock(for: text)
    }

    static func markdownCodeBlock(_ text: String, language: String? = nil) -> String {
        let body = text.trimmingCharacters(in: .newlines)
        var fence = "```"
        while body.contains(fence) {
            fence.append("`")
        }
        let languageTag = language ?? ""
        return "\(fence)\(languageTag)\n\(body)\n\(fence)"
    }

    static func imageMarkdown(reference: String, altText: String = "image") -> String {
        let escapedAltText = altText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        let escapedReference = reference.replacingOccurrences(of: ">", with: "%3E")
        return "![\(escapedAltText)](<\(escapedReference)>)"
    }

    static func extractShellCommands(_ text: String) -> String? {
        ShellCommandParser.extractCommands(from: text)
    }

    private static func transformJSON(_ text: String, options: JSONSerialization.WritingOptions) -> String? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let output = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }
        return String(data: output, encoding: .utf8)
    }

    private static func splitWords(_ text: String) -> [String] {
        let separated = text.replacingOccurrences(
            of: #"([a-z0-9])([A-Z])"#,
            with: "$1 $2",
            options: .regularExpression
        )
        return separated
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func promptedCommand(from line: String) -> String? {
        ShellCommandParser.promptedCommand(from: line)
    }

    static func isBareShellCommand(_ line: String) -> Bool {
        ShellCommandParser.isBareCommand(line)
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst().lowercased()
    }
}
