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

    static func promptedCommand(from line: String) -> String? {
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

    static func isBareShellCommand(_ line: String) -> Bool {
        guard !line.isEmpty, line.count < 2_000 else { return false }
        let commands = [
            "git", "npm", "npx", "pnpm", "yarn", "bun", "node", "deno",
            "swift", "swiftc", "xcodebuild", "xcrun", "xcode-select",
            "cargo", "rustc", "rustup", "go", "python", "python3",
            "pip", "pip3", "uv", "ruby", "gem", "bundle",
            "java", "javac", "mvn", "gradle", "dotnet",
            "docker", "docker-compose", "podman",
            "kubectl", "helm", "terraform", "ansible", "vagrant",
            "aws", "gcloud", "az",
            "curl", "wget", "httpie",
            "brew", "apt", "apt-get", "dnf", "yum", "apk", "pacman", "snap",
            "make", "cmake", "ninja",
            "sudo", "env", "which", "whereis", "command",
            "cd", "ls", "mkdir", "rm", "cp", "mv", "touch", "ln",
            "ssh", "scp", "rsync",
            "cat", "sed", "awk", "grep", "rg", "find", "fd",
            "head", "tail", "less", "more", "wc", "sort", "uniq",
            "diff", "xargs", "tee",
            "chmod", "chown", "chgrp",
            "tar", "zip", "unzip", "gzip", "gunzip",
            "export", "source", "eval", "set", "unset",
            "echo", "printf",
            "kill", "killall", "pkill",
            "open", "xdg-open", "pbcopy", "pbpaste",
            "man", "nvm", "rbenv", "pyenv", "volta", "corepack",
            "ng", "vue", "vite", "next", "nuxt", "remix",
            "jest", "vitest", "pytest", "mocha",
            "eslint", "prettier", "tsc",
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
                let fieldType = typeScriptType(dictionary[key] ?? NSNull(), depth: depth + 1)
                return "\(indent)  \(safeTypeScriptKey(key)): \(fieldType);"
            }.joined(separator: "\n")
            return "interface \(name) {\n\(fields)\n\(indent)}"
        }
        return "type \(name) = \(typeScriptType(value, depth: depth));"
    }

    private static func typeScriptType(_ value: Any, depth: Int) -> String {
        if value is NSNull { return "null" }
        if value is String { return "string" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID()
                ? "boolean"
                : "number"
        }
        if let array = value as? [Any] {
            return typeScriptArrayType(array, depth: depth)
        }
        if let dictionary = value as? [String: Any] {
            return typeScriptObjectType(dictionary, depth: depth)
        }
        return "unknown"
    }

    private static func typeScriptArrayType(_ array: [Any], depth: Int) -> String {
        guard !array.isEmpty else { return "unknown[]" }

        let elementTypes = typeScriptTypes(for: array, depth: depth)
        let elementType = joinedTypeUnion(elementTypes)
        if elementTypes.count > 1 {
            return "(\(elementType))[]"
        }
        return "\(elementType)[]"
    }

    private static func typeScriptType(for values: [Any], depth: Int) -> String {
        joinedTypeUnion(typeScriptTypes(for: values, depth: depth))
    }

    private static func typeScriptTypes(for values: [Any], depth: Int) -> [String] {
        let hasNull = values.contains { $0 is NSNull }
        let nonNullValues = values.filter { !($0 is NSNull) }
        var types: [String] = []

        let dictionaries = nonNullValues.compactMap { $0 as? [String: Any] }
        if !dictionaries.isEmpty, dictionaries.count == nonNullValues.count {
            types.append(typeScriptObjectType(dictionaries, depth: depth))
        } else {
            types.append(contentsOf: nonNullValues.map { typeScriptType($0, depth: depth) })
        }

        if hasNull {
            types.append("null")
        }

        return uniqueTypeList(types)
    }

    private static func typeScriptObjectType(_ dictionary: [String: Any], depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let fields = dictionary.keys.sorted().map { key in
            "\(indent)  \(safeTypeScriptKey(key)): \(typeScriptType(dictionary[key] ?? NSNull(), depth: depth + 1));"
        }.joined(separator: "\n")
        return "{\n\(fields)\n\(indent)}"
    }

    private static func typeScriptObjectType(_ dictionaries: [[String: Any]], depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let fields = Set(dictionaries.flatMap(\.keys)).sorted().map { key in
            let values = dictionaries.compactMap { $0[key] }
            let marker = values.count < dictionaries.count ? "?" : ""
            return "\(indent)  \(safeTypeScriptKey(key))\(marker): \(typeScriptType(for: values, depth: depth + 1));"
        }.joined(separator: "\n")
        return "{\n\(fields)\n\(indent)}"
    }

    private static func joinedTypeUnion(_ types: [String]) -> String {
        let uniqueTypes = uniqueTypeList(types)
        guard !uniqueTypes.isEmpty else { return "unknown" }
        return uniqueTypes.joined(separator: " | ")
    }

    private static func uniqueTypeList(_ types: [String]) -> [String] {
        types.reduce(into: [String]()) { result, type in
            if !result.contains(type) {
                result.append(type)
            }
        }
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
