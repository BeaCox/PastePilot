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
        return typeScriptDeclaration(name: rootName, value: object, depth: 0)
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
        let commands = extractShellCommands(text)
        let body = commands ?? stripShellPrompt(from: text)
        return "```sh\n\(body.trimmingCharacters(in: .whitespacesAndNewlines))\n```"
    }

    static func imageMarkdown(reference: String, altText: String = "image") -> String {
        let escapedAltText = altText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "]", with: "\\]")
        let escapedReference = reference.replacingOccurrences(of: ">", with: "%3E")
        return "![\(escapedAltText)](<\(escapedReference)>)"
    }

    static func extractShellCommands(_ text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var commands: [String] = []
        var currentCommand: String?
        var shellFenceLanguage: String?

        func appendCurrentCommand() {
            guard let command = currentCommand?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !command.isEmpty,
                  !commands.contains(command) else {
                currentCommand = nil
                return
            }
            commands.append(command)
            currentCommand = nil
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                appendCurrentCommand()
                if shellFenceLanguage == nil {
                    let language = String(line.dropFirst(3)).lowercased()
                    shellFenceLanguage = ["sh", "shell", "bash", "zsh", "console"]
                        .contains(language) ? language : ""
                } else {
                    shellFenceLanguage = nil
                }
                continue
            }

            if let language = shellFenceLanguage {
                guard !language.isEmpty, !line.isEmpty, !line.hasPrefix("#") else { continue }
                let command = stripShellPrompt(from: line)
                if currentCommand != nil {
                    currentCommand? += "\n\(stripContinuationPrompt(from: command))"
                } else {
                    currentCommand = command
                }
                if !line.hasSuffix("\\") {
                    appendCurrentCommand()
                }
                continue
            }

            if let prompted = promptedCommand(from: line) {
                appendCurrentCommand()
                currentCommand = prompted
                if !line.hasSuffix("\\") {
                    appendCurrentCommand()
                }
                continue
            }

            if currentCommand != nil {
                let continuation = stripContinuationPrompt(from: line)
                currentCommand? += "\n\(continuation)"
                if !line.hasSuffix("\\") {
                    appendCurrentCommand()
                }
                continue
            }

            if isBareShellCommand(line) {
                currentCommand = line
                if !line.hasSuffix("\\") {
                    appendCurrentCommand()
                }
            }
        }

        appendCurrentCommand()
        guard !commands.isEmpty else { return nil }
        return commands.joined(separator: "\n")
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

    private static func promptedCommand(from line: String) -> String? {
        let patterns = [
            #"^\s*(?:\$|%|❯|➜)\s+(.+)$"#,
            #"^\s*[A-Za-z0-9._-]+@[A-Za-z0-9._-]+(?::[^$#]+)?[$#]\s+(.+)$"#,
            #"^\s*\([^)]*\)\s*(?:\$|%|❯|➜)\s+(.+)$"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: line,
                    range: NSRange(line.startIndex..., in: line)
                  ),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: line) else {
                continue
            }
            return String(line[range])
        }
        return nil
    }

    private static func stripShellPrompt(from text: String) -> String {
        promptedCommand(from: text) ?? text
    }

    private static func stripContinuationPrompt(from line: String) -> String {
        line.replacingOccurrences(
            of: #"^\s*(?:>|\.{3})\s?"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func isBareShellCommand(_ line: String) -> Bool {
        guard !line.isEmpty, line.count < 2_000 else { return false }
        let commands = [
            "git", "npm", "npx", "pnpm", "yarn", "bun", "node", "deno",
            "swift", "xcodebuild", "cargo", "rustc", "go", "python", "python3",
            "pip", "pip3", "ruby", "bundle", "docker", "docker-compose",
            "kubectl", "helm", "curl", "wget", "brew", "make", "cmake",
            "cd", "ls", "mkdir", "rm", "cp", "mv", "ssh", "scp", "rsync",
            "cat", "sed", "awk", "grep", "rg", "find", "chmod", "chown",
            "export", "source", "echo", "printf"
        ]
        guard let first = line.split(whereSeparator: \.isWhitespace).first else {
            return false
        }
        let executable = first.split(separator: "/").last.map(String.init) ?? String(first)
        return commands.contains(executable)
    }

    private static func typeScriptDeclaration(name: String, value: Any, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        if let dictionary = value as? [String: Any] {
            let fields = dictionary.keys.sorted().map { key in
                let fieldType = typeScriptType(dictionary[key] as Any, depth: depth + 1)
                return "\(indent)  \(safeTypeScriptKey(key)): \(fieldType);"
            }.joined(separator: "\n")
            return "interface \(name) {\n\(fields)\n\(indent)}"
        }
        return "type \(name) = \(typeScriptType(value, depth: depth));"
    }

    private static func typeScriptType(_ value: Any, depth: Int) -> String {
        if value is NSNull { return "null" }
        if value is String { return "string" }
        if value is Bool { return "boolean" }
        if value is NSNumber { return "number" }
        if let array = value as? [Any] {
            guard let first = array.first else { return "unknown[]" }
            return "\(typeScriptType(first, depth: depth))[]"
        }
        if let dictionary = value as? [String: Any] {
            let indent = String(repeating: "  ", count: depth)
            let fields = dictionary.keys.sorted().map { key in
                "\(indent)  \(safeTypeScriptKey(key)): \(typeScriptType(dictionary[key] as Any, depth: depth + 1));"
            }.joined(separator: "\n")
            return "{\n\(fields)\n\(indent)}"
        }
        return "unknown"
    }

    private static func safeTypeScriptKey(_ key: String) -> String {
        key.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#, options: .regularExpression) != nil
            ? key
            : "\"\(key.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst().lowercased()
    }
}
