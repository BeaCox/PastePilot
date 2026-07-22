import Foundation

public struct PastePilotCLIApplication {
    public typealias Write = (String) -> Void

    public static let usage = """
        Usage: pastepilot [--data-dir PATH] <command> [options]

        Commands:
          search <query> [--limit N] [--json]  Search content and metadata
          read <id|index> [--json]             Read one history item
          copy <id|index>                      Copy one item to the pasteboard
          export <archive.zip> [--force]       Export a live-safe backup
          diagnostics [--json]                 Check local storage health
          help                                 Show this help

        Search supports PastePilot filters such as kind:json, app:Terminal,
        pinned:true, has:ocr, and quoted phrases. Protected content stays locked.
        """

    private let stdout: Write
    private let stderr: Write

    public init(
        stdout: @escaping Write = { print($0, terminator: "") },
        stderr: @escaping Write = { FileHandle.standardError.write(Data($0.utf8)) }
    ) {
        self.stdout = stdout
        self.stderr = stderr
    }

    @discardableResult
    public func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Int32 {
        do {
            var arguments = Array(arguments.dropFirst())
            let dataDirectoryURL = try parseDataDirectory(
                arguments: &arguments,
                environment: environment
            )
            guard let command = arguments.first else {
                stdout(Self.usage + "\n")
                return 0
            }
            arguments.removeFirst()
            let history = PastePilotCLIHistory(dataDirectoryURL: dataDirectoryURL)

            switch command {
            case "help", "--help", "-h":
                guard arguments.isEmpty else {
                    throw PastePilotCLIError.invalidArguments("help takes no arguments.")
                }
                stdout(Self.usage + "\n")
            case "search":
                try runSearch(arguments: arguments, history: history)
            case "read":
                try runRead(arguments: arguments, history: history)
            case "copy":
                try runCopy(arguments: arguments, history: history)
            case "export":
                try runExport(arguments: arguments, history: history)
            case "diagnostics":
                try runDiagnostics(arguments: arguments, history: history)
            default:
                throw PastePilotCLIError.invalidArguments("Unknown command '\(command)'.")
            }
            return 0
        } catch let error as PastePilotCLIError {
            stderr("error: \(error.localizedDescription)\n")
            return error.exitCode
        } catch {
            stderr("error: \(error.localizedDescription)\n")
            return 1
        }
    }

    private func parseDataDirectory(
        arguments: inout [String],
        environment: [String: String]
    ) throws -> URL {
        if arguments.first == "--data-dir" {
            guard arguments.count >= 2 else {
                throw PastePilotCLIError.invalidArguments("--data-dir requires a path.")
            }
            let path = arguments[1]
            arguments.removeFirst(2)
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        if let path = environment["PASTEPILOT_DATA_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return PastePilotCLIHistory.defaultDataDirectoryURL
    }

    private func runSearch(
        arguments: [String],
        history: PastePilotCLIHistory
    ) throws {
        var queryParts: [String] = []
        var limit = 20
        var json = false
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                json = true
                index += 1
            case "--limit":
                guard index + 1 < arguments.count,
                      let value = Int(arguments[index + 1]) else {
                    throw PastePilotCLIError.invalidArguments("--limit requires an integer.")
                }
                limit = value
                index += 2
            default:
                queryParts.append(arguments[index])
                index += 1
            }
        }
        let items = try history.search(queryParts.joined(separator: " "), limit: limit)
        if json {
            try writeJSON(items)
        } else {
            for item in items {
                let protectedMarker = item.isProtected ? "\tlocked" : ""
                stdout("\(item.index)\t\(item.id)\t\(item.kind)\(protectedMarker)\t\(item.preview)\n")
            }
        }
    }

    private func runRead(
        arguments: [String],
        history: PastePilotCLIHistory
    ) throws {
        let json = arguments.contains("--json")
        let selectors = arguments.filter { $0 != "--json" }
        guard selectors.count == 1, !arguments.contains(where: { $0.hasPrefix("--") && $0 != "--json" }) else {
            throw PastePilotCLIError.invalidArguments("read requires one ID or one-based index.")
        }
        let item = try history.read(selectors[0])
        if json {
            try writeJSON(item)
        } else if item.isProtected {
            throw PastePilotCLIError.protectedItem
        } else if let content = item.content {
            stdout(content + (content.hasSuffix("\n") ? "" : "\n"))
        } else if !item.filePaths.isEmpty {
            stdout(item.filePaths.joined(separator: "\n") + "\n")
        } else if let imagePath = item.imagePath {
            stdout(imagePath + "\n")
        } else {
            stdout("\n")
        }
    }

    private func runCopy(
        arguments: [String],
        history: PastePilotCLIHistory
    ) throws {
        guard arguments.count == 1 else {
            throw PastePilotCLIError.invalidArguments("copy requires one ID or one-based index.")
        }
        try history.copy(arguments[0])
        stdout("Copied \(arguments[0]).\n")
    }

    private func runExport(
        arguments: [String],
        history: PastePilotCLIHistory
    ) throws {
        let force = arguments.contains("--force")
        let paths = arguments.filter { $0 != "--force" }
        guard paths.count == 1,
              !arguments.contains(where: { $0.hasPrefix("--") && $0 != "--force" }) else {
            throw PastePilotCLIError.invalidArguments("export requires one .zip path.")
        }
        let url = URL(fileURLWithPath: paths[0])
        guard url.pathExtension.lowercased() == "zip" else {
            throw PastePilotCLIError.invalidArguments("export destination must end in .zip.")
        }
        try history.exportBackup(to: url, force: force)
        stdout("Exported \(url.standardizedFileURL.path).\n")
    }

    private func runDiagnostics(
        arguments: [String],
        history: PastePilotCLIHistory
    ) throws {
        guard arguments.isEmpty || arguments == ["--json"] else {
            throw PastePilotCLIError.invalidArguments("diagnostics accepts only --json.")
        }
        let result = try history.diagnostics()
        if arguments == ["--json"] {
            try writeJSON(result)
        } else {
            stdout("Database: \(result.database)\n")
            stdout("Schema: \(result.schemaVersion.map(String.init) ?? "unknown")\n")
            stdout("Integrity: \(result.integrityCheck)\n")
            stdout("Items: \(result.itemCount) (\(result.protectedItemCount) protected)\n")
            stdout("Assets: \(result.imageAssetCount) images, \(result.textAssetCount) text\n")
            stdout("Retained bytes: \(result.retainedBytes)\n")
        }
    }

    private func writeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        stdout(String(decoding: try encoder.encode(value), as: UTF8.self) + "\n")
    }
}

private extension PastePilotCLIError {
    var exitCode: Int32 {
        switch self {
        case .invalidArguments: 64
        case .itemNotFound, .ambiguousItem: 2
        case .protectedItem, .unsupportedCopy: 3
        case .databaseMissing, .unsafeAssetPath, .destinationExists, .archiveFailed: 1
        }
    }
}
