import AppKit
import Foundation
import GRDB

public enum PastePilotCLIError: LocalizedError, Equatable {
    case invalidArguments(String)
    case databaseMissing(String)
    case itemNotFound(String)
    case ambiguousItem(String)
    case protectedItem
    case unsupportedCopy(String)
    case unsafeAssetPath
    case destinationExists(String)
    case archiveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message): message
        case .databaseMissing(let path): "PastePilot history database not found at \(path)."
        case .itemNotFound(let selector): "No history item matches '\(selector)'."
        case .ambiguousItem(let selector): "More than one history item matches '\(selector)'; use a longer ID."
        case .protectedItem:
            "Protected item content is locked. Unlock it in PastePilot; the CLI never bypasses authentication."
        case .unsupportedCopy(let kind): "Copy is not supported for this \(kind) item."
        case .unsafeAssetPath: "History contains an unsafe external asset path."
        case .destinationExists(let path): "Destination already exists: \(path). Pass --force to replace it."
        case .archiveFailed(let message): "Backup archive failed: \(message)"
        }
    }
}

public struct PastePilotCLIItem: Codable, Equatable, Sendable {
    public let index: Int
    public let id: String
    public let kind: String
    public let createdAt: Date
    public let isPinned: Bool
    public let isProtected: Bool
    public let containsSensitiveData: Bool
    public let sourceAppName: String?
    public let title: String?
    public let note: String?
    public let aliases: [String]
    public let content: String?
    public let imagePath: String?
    public let filePaths: [String]

    public var preview: String {
        let value: String
        if isProtected {
            value = title ?? "[protected]"
        } else {
            value = title ?? content ?? imagePath ?? filePaths.first ?? ""
        }
        return value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(120)
            .description
    }
}

public struct PastePilotCLIDiagnostics: Codable, Equatable, Sendable {
    public let dataDirectory: String
    public let database: String
    public let schemaVersion: Int?
    public let integrityCheck: String
    public let itemCount: Int
    public let protectedItemCount: Int
    public let imageAssetCount: Int
    public let textAssetCount: Int
    public let retainedBytes: Int64
}

public final class PastePilotCLIHistory: @unchecked Sendable {
    public let dataDirectoryURL: URL
    private let fileManager: FileManager

    public init(
        dataDirectoryURL: URL,
        fileManager: FileManager = .default
    ) {
        self.dataDirectoryURL = dataDirectoryURL.standardizedFileURL
        self.fileManager = fileManager
    }

    public static var defaultDataDirectoryURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("PastePilot", isDirectory: true)
    }

    public func search(_ rawQuery: String, limit: Int = 20) throws -> [PastePilotCLIItem] {
        guard (1...500).contains(limit) else {
            throw PastePilotCLIError.invalidArguments("--limit must be between 1 and 500.")
        }
        let query = CLIQuery(rawQuery)
        guard !query.isEmpty else {
            throw PastePilotCLIError.invalidArguments("search requires a query or filter.")
        }

        return try withDatabase { db in
            let rows = try loadRows(db: db)
            return try rows.enumerated().filter { _, row in
                try query.matches(row, filePaths: filePaths(for: row.id, db: db))
            }
            .prefix(limit)
            .map { offset, row in
                try item(from: row, index: offset + 1, db: db)
            }
        }
    }

    public func read(_ selector: String) throws -> PastePilotCLIItem {
        try withDatabase { db in
            let rows = try loadRows(db: db)
            let (row, index) = try selectedRow(selector, from: rows)
            return try item(from: row, index: index, db: db)
        }
    }

    public func copy(
        _ selector: String,
        to pasteboard: NSPasteboard = .general
    ) throws {
        let item = try read(selector)
        guard !item.isProtected else { throw PastePilotCLIError.protectedItem }

        if item.kind == "file", !item.filePaths.isEmpty {
            let urls = item.filePaths.map { NSURL(fileURLWithPath: $0) }
            pasteboard.clearContents()
            guard pasteboard.writeObjects(urls) else {
                throw PastePilotCLIError.unsupportedCopy(item.kind)
            }
            return
        }
        if item.kind == "image", let imagePath = item.imagePath,
           let image = NSImage(contentsOfFile: imagePath) {
            pasteboard.clearContents()
            guard pasteboard.writeObjects([image]) else {
                throw PastePilotCLIError.unsupportedCopy(item.kind)
            }
            return
        }
        if let content = item.content {
            pasteboard.clearContents()
            guard pasteboard.setString(content, forType: .string) else {
                throw PastePilotCLIError.unsupportedCopy(item.kind)
            }
            return
        }
        throw PastePilotCLIError.unsupportedCopy(item.kind)
    }

    public func diagnostics() throws -> PastePilotCLIDiagnostics {
        try withDatabase { db in
            let databaseURL = self.databaseURL
            let schemaVersion = try Int.fetchOne(
                db,
                sql: "SELECT CAST(value AS INTEGER) FROM metadata WHERE key = 'schema_version'"
            )
            let integrityCheck = try String.fetchOne(db, sql: "PRAGMA quick_check") ?? "unknown"
            let itemCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items") ?? 0
            let protectedItemCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM items WHERE is_protected = 1"
            ) ?? 0
            let images = assetSummary(in: dataDirectoryURL.appendingPathComponent("images"))
            let text = assetSummary(in: dataDirectoryURL.appendingPathComponent("text"))
            let databaseBytes = fileByteCount(databaseURL)
                + fileByteCount(URL(fileURLWithPath: databaseURL.path + "-wal"))
                + fileByteCount(URL(fileURLWithPath: databaseURL.path + "-shm"))
            return PastePilotCLIDiagnostics(
                dataDirectory: dataDirectoryURL.path,
                database: databaseURL.path,
                schemaVersion: schemaVersion,
                integrityCheck: integrityCheck,
                itemCount: itemCount,
                protectedItemCount: protectedItemCount,
                imageAssetCount: images.count,
                textAssetCount: text.count,
                retainedBytes: databaseBytes + images.bytes + text.bytes
            )
        }
    }

    public func exportBackup(to archiveURL: URL, force: Bool = false) throws {
        let archiveURL = archiveURL.standardizedFileURL
        if fileManager.fileExists(atPath: archiveURL.path) {
            guard force else { throw PastePilotCLIError.destinationExists(archiveURL.path) }
        }
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw PastePilotCLIError.databaseMissing(databaseURL.path)
        }

        let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(
            "PastePilotCLI-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fileManager.removeItem(at: temporaryDirectory) }
        let root = temporaryDirectory.appendingPathComponent("PastePilotBackup", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: root.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: root.appendingPathComponent("text", isDirectory: true),
            withIntermediateDirectories: true
        )

        try writeManifest(to: root)
        try makeDatabaseSnapshot(at: root.appendingPathComponent("history.sqlite"))
        try copyDirectoryContents(named: "images", to: root)
        try copyDirectoryContents(named: "text", to: root)
        let stagedArchiveURL = temporaryDirectory.appendingPathComponent("backup.zip")
        try runDitto(root: root, archiveURL: stagedArchiveURL)
        if fileManager.fileExists(atPath: archiveURL.path) {
            _ = try fileManager.replaceItemAt(archiveURL, withItemAt: stagedArchiveURL)
        } else {
            try fileManager.moveItem(at: stagedArchiveURL, to: archiveURL)
        }
    }

    private var databaseURL: URL {
        dataDirectoryURL.appendingPathComponent("history.sqlite")
    }

    private func withDatabase<T>(_ body: (Database) throws -> T) throws -> T {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            throw PastePilotCLIError.databaseMissing(databaseURL.path)
        }
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        return try queue.read(body)
    }

    fileprivate struct StoredRow {
        let id: String
        let content: String
        let kind: String
        let createdAt: Date
        let isPinned: Bool
        let containsSensitiveData: Bool
        let isProtected: Bool
        let sourceAppName: String?
        let sourceBundleIdentifier: String?
        let imageFileName: String?
        let contentFileName: String?
        let ocrText: String?
        let userTitle: String?
        let userNote: String?
        let userAliases: [String]
        let linkMetadataJSON: String?
        let detectedBarcodesJSON: String?
        let searchBody: String
    }

    private func loadRows(db: Database) throws -> [StoredRow] {
        let hasSearchIndex = try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'search_index')"
        ) ?? false
        let searchJoin = hasSearchIndex
            ? "LEFT JOIN search_index s ON s.item_id = i.id"
            : ""
        let searchColumn = hasSearchIndex ? "COALESCE(s.body, '')" : "''"
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT i.*, \(searchColumn) AS cli_search_body
                FROM items i \(searchJoin)
                ORDER BY i.is_pinned DESC, i.created_at DESC
                """
        )
        return rows.map { row in
            StoredRow(
                id: row["id"],
                content: row["content"],
                kind: row["kind"],
                createdAt: Date(timeIntervalSince1970: row["created_at"]),
                isPinned: (row["is_pinned"] as Int) != 0,
                containsSensitiveData: (row["contains_sensitive_data"] as Int) != 0,
                isProtected: (row["is_protected"] as Int? ?? 0) != 0,
                sourceAppName: row["source_app_name"],
                sourceBundleIdentifier: row["source_bundle_identifier"],
                imageFileName: row["image_file_name"],
                contentFileName: row["content_file_name"],
                ocrText: row["ocr_text"],
                userTitle: row["user_title"],
                userNote: row["user_note"],
                userAliases: Self.decodeAliases(row["user_aliases_json"]),
                linkMetadataJSON: row["link_metadata_json"],
                detectedBarcodesJSON: row["detected_barcodes_json"],
                searchBody: row["cli_search_body"]
            )
        }
    }

    private func selectedRow(
        _ selector: String,
        from rows: [StoredRow]
    ) throws -> (StoredRow, Int) {
        if let index = Int(selector), index > 0, index <= rows.count {
            return (rows[index - 1], index)
        }
        let matches = rows.enumerated().filter {
            $0.element.id.lowercased().hasPrefix(selector.lowercased())
        }
        guard !matches.isEmpty else { throw PastePilotCLIError.itemNotFound(selector) }
        guard matches.count == 1, let match = matches.first else {
            throw PastePilotCLIError.ambiguousItem(selector)
        }
        return (match.element, match.offset + 1)
    }

    private func item(from row: StoredRow, index: Int, db: Database) throws -> PastePilotCLIItem {
        let paths = try filePaths(for: row.id, db: db)
        return PastePilotCLIItem(
            index: index,
            id: row.id,
            kind: row.kind,
            createdAt: row.createdAt,
            isPinned: row.isPinned,
            isProtected: row.isProtected,
            containsSensitiveData: row.containsSensitiveData,
            sourceAppName: row.isProtected ? nil : row.sourceAppName,
            title: row.userTitle,
            note: row.userNote,
            aliases: row.userAliases,
            content: try effectiveContent(for: row),
            imagePath: try imagePath(for: row),
            filePaths: row.isProtected ? [] : paths
        )
    }

    private func effectiveContent(for row: StoredRow) throws -> String? {
        guard !row.isProtected else { return nil }
        if let fileName = row.contentFileName {
            return try String(contentsOf: safeAssetURL(fileName, directory: "text"), encoding: .utf8)
        }
        return row.content.isEmpty ? nil : row.content
    }

    private func imagePath(for row: StoredRow) throws -> String? {
        guard !row.isProtected, let fileName = row.imageFileName else { return nil }
        return try safeAssetURL(fileName, directory: "images").path
    }

    private func safeAssetURL(_ fileName: String, directory: String) throws -> URL {
        guard !fileName.isEmpty,
              fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              fileName != ".",
              fileName != ".." else {
            throw PastePilotCLIError.unsafeAssetPath
        }
        return dataDirectoryURL
            .appendingPathComponent(directory, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private func filePaths(for id: String, db: Database) throws -> [String] {
        try String.fetchAll(
            db,
            sql: "SELECT path FROM file_paths WHERE item_id = ? ORDER BY ordinal",
            arguments: [id]
        )
    }

    private static func decodeAliases(_ json: String?) -> [String] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func writeManifest(to root: URL) throws {
        struct Manifest: Encodable {
            let kind = "PastePilotBackup"
            let schemaVersion = 1
            let createdAt = Date()
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Manifest()).write(
            to: root.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    private func makeDatabaseSnapshot(at destinationURL: URL) throws {
        var sourceConfiguration = Configuration()
        sourceConfiguration.readonly = true
        let source = try DatabaseQueue(path: databaseURL.path, configuration: sourceConfiguration)
        let destination = try DatabaseQueue(path: destinationURL.path)
        try source.backup(to: destination)
    }

    private func copyDirectoryContents(named name: String, to root: URL) throws {
        let source = dataDirectoryURL.appendingPathComponent(name, isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else { return }
        let destination = root.appendingPathComponent(name, isDirectory: true)
        for child in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try fileManager.copyItem(
                at: child,
                to: destination.appendingPathComponent(child.lastPathComponent)
            )
        }
    }

    private func runDitto(root: URL, archiveURL: URL) throws {
        let process = Process()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", root.path, archiveURL.path]
        process.standardError = stderrPipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PastePilotCLIError.archiveFailed(error.localizedDescription)
        }
        guard process.terminationStatus == 0 else {
            let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw PastePilotCLIError.archiveFailed(message ?? "ditto exited with status \(process.terminationStatus)")
        }
    }

    private func assetSummary(in directoryURL: URL) -> (count: Int, bytes: Int64) {
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]
        ) else { return (0, 0) }
        var count = 0
        var bytes: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true {
                count += 1
                bytes += Int64(values?.fileSize ?? 0)
            }
        }
        return (count, bytes)
    }

    private func fileByteCount(_ url: URL) -> Int64 {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private struct CLIQuery {
    var terms: [String] = []
    var kinds = Set<String>()
    var apps: [String] = []
    var pinned: Bool?
    var has = Set<String>()

    init(_ rawValue: String) {
        for token in Self.tokens(from: rawValue) {
            guard let separator = token.firstIndex(of: ":"), separator > token.startIndex else {
                terms.append(token.lowercased())
                continue
            }
            let key = token[..<separator].lowercased()
            let value = token[token.index(after: separator)...].lowercased()
            guard !value.isEmpty else {
                terms.append(token.lowercased())
                continue
            }
            switch key {
            case "kind", "type": kinds.insert(value)
            case "app", "source": apps.append(value)
            case "pinned":
                switch value {
                case "true", "yes", "y", "1": pinned = true
                case "false", "no", "n", "0": pinned = false
                default: terms.append(token.lowercased())
                }
            case "has": has.insert(value)
            default: terms.append(token.lowercased())
            }
        }
    }

    var isEmpty: Bool {
        terms.isEmpty && kinds.isEmpty && apps.isEmpty && pinned == nil && has.isEmpty
    }

    func matches(_ row: PastePilotCLIHistory.StoredRow, filePaths: [String]) throws -> Bool {
        if !terms.allSatisfy({ row.searchBody.localizedCaseInsensitiveContains($0) }) { return false }
        if !kinds.isEmpty && !kinds.contains(where: { row.kind.lowercased().contains($0) }) { return false }
        if let pinned, row.isPinned != pinned { return false }
        let source = [row.sourceAppName, row.sourceBundleIdentifier]
            .compactMap { $0 }.joined(separator: " ").lowercased()
        if !apps.allSatisfy({ source.contains($0) }) { return false }
        for filter in has {
            switch filter {
            case "ocr": if row.ocrText?.isEmpty != false { return false }
            case "image": if row.kind != "image" { return false }
            case "file", "files": if filePaths.isEmpty { return false }
            case "sensitive": if !row.containsSensitiveData { return false }
            case "title": if row.userTitle?.isEmpty != false { return false }
            case "note", "notes": if row.userNote?.isEmpty != false { return false }
            case "alias", "aliases": if row.userAliases.isEmpty { return false }
            case "metadata", "link": if row.linkMetadataJSON == nil { return false }
            case "barcode", "qr": if row.detectedBarcodesJSON == nil { return false }
            default: return false
            }
        }
        return true
    }

    private static func tokens(from query: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        var escaped = false
        for character in query {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character.isWhitespace && !quoted {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
