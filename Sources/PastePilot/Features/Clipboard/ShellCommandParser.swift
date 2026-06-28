import Foundation

enum ShellCommandParser {
    private enum FenceKind {
        case shell
        case console
    }

    private enum Quote {
        case single
        case double
    }

    private static let commandExecutables: Set<String> = [
        "git", "gh", "npm", "npx", "pnpm", "yarn", "bun", "node", "deno",
        "bunx", "uvx",
        "swift", "swiftc", "xcodebuild", "xcrun", "xcode-select",
        "cargo", "rustc", "rustup", "go", "python", "python3",
        "pip", "pip3", "pipx", "uv", "poetry", "ruff", "black", "mypy",
        "ruby", "gem", "bundle", "rails",
        "php", "composer",
        "java", "javac", "mvn", "gradle", "dotnet",
        "mvnw", "gradlew",
        "docker", "docker-compose", "podman",
        "kubectl", "helm", "terraform", "pulumi", "ansible", "vagrant",
        "nix", "nix-shell", "nix-env",
        "aws", "gcloud", "az", "fly", "vercel", "netlify", "wrangler",
        "curl", "wget", "httpie",
        "brew", "apt", "apt-get", "dnf", "yum", "apk", "pacman", "snap",
        "make", "cmake", "ninja",
        "sudo", "env", "which", "whereis", "command",
        "cd", "ls", "mkdir", "rm", "cp", "mv", "touch", "ln",
        "ssh", "scp", "rsync",
        "cat", "sed", "awk", "grep", "rg", "find", "fd",
        "head", "tail", "less", "more", "wc", "sort", "uniq",
        "jq", "yq", "psql", "mysql", "sqlite3", "redis-cli", "mongosh",
        "diff", "xargs", "tee",
        "chmod", "chown", "chgrp",
        "tar", "zip", "unzip", "gzip", "gunzip",
        "export", "source", "eval", "set", "unset",
        "echo", "printf",
        "kill", "killall", "pkill",
        "open", "xdg-open", "pbcopy", "pbpaste",
        "man", "nvm", "rbenv", "pyenv", "volta", "corepack", "asdf", "mise",
        "ng", "vue", "vite", "next", "nuxt", "remix",
        "jest", "vitest", "pytest", "mocha",
        "eslint", "prettier", "tsc",
    ]

    private static let fenceLanguages: [String: FenceKind] = [
        "sh": .shell,
        "shell": .shell,
        "bash": .shell,
        "zsh": .shell,
        "console": .console,
        "terminal": .console,
        "shell-session": .console,
        "shellsession": .console,
        "bash-session": .console,
        "zsh-session": .console,
    ]

    private static let environmentAssignmentRegex =
        #"^[A-Za-z_][A-Za-z0-9_]*(?:\+)?=.*$"#

    private static let promptRegexes: [NSRegularExpression] = [
        #"^\s*(?:\$|%|❯|➜)\s+(.+)$"#,
        #"^\s*[A-Za-z0-9._-]+@[A-Za-z0-9._-]+(?::[^$#]+)?[$#]\s+(.+)$"#,
        #"^\s*\([^)]*\)\s*(?:\$|%|❯|➜)\s+(.+)$"#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    static func codeBlock(for text: String) -> String {
        let commands = extractCommands(from: text)
        let body = commands ?? stripPrompt(from: text)
        return "```sh\n\(body.trimmingCharacters(in: .whitespacesAndNewlines))\n```"
    }

    static func extractCommands(from text: String) -> String? {
        let lines = text.components(separatedBy: .newlines)
        var commands: [String] = []
        var currentCommand: String?
        var isInsideFence = false
        var fenceKind: FenceKind?

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
                if isInsideFence {
                    isInsideFence = false
                    fenceKind = nil
                } else {
                    isInsideFence = true
                    fenceKind = parsedFenceKind(from: line)
                }
                continue
            }

            if isInsideFence {
                guard let fenceKind, !line.isEmpty, !line.hasPrefix("#") else {
                    continue
                }

                if fenceKind == .shell {
                    let command = stripPrompt(from: line)
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

                if currentCommand != nil {
                    currentCommand? += "\n\(stripContinuationPrompt(from: line))"
                    if !line.hasSuffix("\\") {
                        appendCurrentCommand()
                    }
                } else if let prompted = promptedCommand(from: line) {
                    currentCommand = prompted
                    if !line.hasSuffix("\\") {
                        appendCurrentCommand()
                    }
                } else if isBareCommand(line) {
                    currentCommand = line
                    if !line.hasSuffix("\\") {
                        appendCurrentCommand()
                    }
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

            if isBareCommand(line) {
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

    static func promptedCommand(from line: String) -> String? {
        let nsRange = NSRange(line.startIndex..., in: line)
        for regex in promptRegexes {
            guard let match = regex.firstMatch(in: line, range: nsRange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: line) else {
                continue
            }
            return String(line[range])
        }
        return nil
    }

    static func isBareCommand(_ line: String) -> Bool {
        guard !line.isEmpty, line.count < 2_000 else { return false }
        return executableCandidates(in: line).contains {
            commandExecutables.contains($0)
        }
    }

    private static func stripPrompt(from text: String) -> String {
        promptedCommand(from: text) ?? text
    }

    private static func stripContinuationPrompt(from line: String) -> String {
        line.replacingOccurrences(
            of: #"^\s*(?:>|\.{3})\s?"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func parsedFenceKind(from fenceLine: String) -> FenceKind? {
        let infoString = String(fenceLine.dropFirst(3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let language = infoString.split(whereSeparator: \.isWhitespace).first else {
            return nil
        }
        return fenceLanguages[String(language)]
    }

    private static func executableCandidates(in line: String) -> [String] {
        executableCandidates(in: tokens(in: line), startingAt: 0)
    }

    private static func executableCandidates(
        in tokens: [String],
        startingAt startIndex: Int
    ) -> [String] {
        guard let executableIndex = firstExecutableIndex(
            in: tokens,
            startingAt: startIndex
        ) else {
            return []
        }

        let executable = executableName(from: tokens[executableIndex])
        guard !executable.isEmpty else { return [] }

        let nestedCandidates: [String]
        switch executable {
        case "sudo":
            nestedCandidates = sudoCommandStartIndex(
                in: tokens,
                after: executableIndex
            ).map {
                executableCandidates(in: tokens, startingAt: $0)
            } ?? []
        case "env":
            nestedCandidates = envCommandStartIndex(
                in: tokens,
                after: executableIndex
            ).map {
                executableCandidates(in: tokens, startingAt: $0)
            } ?? []
        case "command":
            nestedCandidates = commandBuiltinStartIndex(
                in: tokens,
                after: executableIndex
            ).map {
                executableCandidates(in: tokens, startingAt: $0)
            } ?? []
        default:
            nestedCandidates = []
        }

        return uniqueList(nestedCandidates + [executable])
    }

    private static func firstExecutableIndex(
        in tokens: [String],
        startingAt startIndex: Int
    ) -> Int? {
        guard !tokens.isEmpty else { return nil }

        var index = startIndex
        while index < tokens.endIndex, isEnvironmentAssignment(tokens[index]) {
            index = tokens.index(after: index)
        }
        return index < tokens.endIndex ? index : nil
    }

    private static func sudoCommandStartIndex(
        in tokens: [String],
        after sudoIndex: Int
    ) -> Int? {
        var index = tokens.index(after: sudoIndex)
        while index < tokens.endIndex {
            let token = tokens[index]
            if token == "--" {
                return tokens.index(after: index)
            }
            if isEnvironmentAssignment(token) {
                index = tokens.index(after: index)
                continue
            }
            if token.hasPrefix("-") {
                index = tokens.index(after: index)
                if sudoOptionConsumesNextArgument(token), index < tokens.endIndex {
                    index = tokens.index(after: index)
                }
                continue
            }
            return index
        }
        return nil
    }

    private static func envCommandStartIndex(
        in tokens: [String],
        after envIndex: Int
    ) -> Int? {
        var index = tokens.index(after: envIndex)
        while index < tokens.endIndex {
            let token = tokens[index]
            if token == "--" {
                return tokens.index(after: index)
            }
            if isEnvironmentAssignment(token) {
                index = tokens.index(after: index)
                continue
            }
            if token.hasPrefix("-") {
                index = tokens.index(after: index)
                if envOptionConsumesNextArgument(token), index < tokens.endIndex {
                    index = tokens.index(after: index)
                }
                continue
            }
            return index
        }
        return nil
    }

    private static func commandBuiltinStartIndex(
        in tokens: [String],
        after commandIndex: Int
    ) -> Int? {
        var index = tokens.index(after: commandIndex)
        while index < tokens.endIndex {
            let token = tokens[index]
            if token == "--" {
                return tokens.index(after: index)
            }
            if token.hasPrefix("-") {
                index = tokens.index(after: index)
                continue
            }
            return index
        }
        return nil
    }

    private static func sudoOptionConsumesNextArgument(_ token: String) -> Bool {
        guard !token.contains("=") else { return false }
        return [
            "-C", "--close-from",
            "-g", "--group",
            "-h", "--host",
            "-p", "--prompt",
            "-r", "--role",
            "-T", "--command-timeout",
            "-t", "--type",
            "-U", "--other-user",
            "-u", "--user",
        ].contains(token)
    }

    private static func envOptionConsumesNextArgument(_ token: String) -> Bool {
        guard !token.contains("=") else { return false }
        return ["-u", "--unset", "-C", "--chdir", "-S", "--split-string"]
            .contains(token)
    }

    private static func executableName(from token: String) -> String {
        token.split(separator: "/").last.map(String.init) ?? token
    }

    private static func tokens(in line: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var quote: Quote?
        var isEscaping = false
        var isBuildingToken = false

        func appendToken() {
            tokens.append(token)
            token = ""
            isBuildingToken = false
        }

        for character in line {
            if isEscaping {
                token.append(character)
                isEscaping = false
                continue
            }

            switch quote {
            case .single:
                if character == "'" {
                    quote = nil
                } else {
                    token.append(character)
                }
            case .double:
                if character == "\"" {
                    quote = nil
                } else if character == "\\" {
                    isEscaping = true
                } else {
                    token.append(character)
                }
            case nil:
                if character.isWhitespace {
                    if isBuildingToken {
                        appendToken()
                    }
                } else if character == "'" {
                    quote = .single
                    isBuildingToken = true
                } else if character == "\"" {
                    quote = .double
                    isBuildingToken = true
                } else if character == "\\" {
                    isEscaping = true
                    isBuildingToken = true
                } else {
                    token.append(character)
                    isBuildingToken = true
                }
            }
        }

        if isEscaping {
            token.append("\\")
        }
        if isBuildingToken {
            appendToken()
        }
        return tokens
    }

    private static func isEnvironmentAssignment(_ token: String) -> Bool {
        token.range(
            of: environmentAssignmentRegex,
            options: .regularExpression
        ) != nil
    }

    private static func uniqueList(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }
}
