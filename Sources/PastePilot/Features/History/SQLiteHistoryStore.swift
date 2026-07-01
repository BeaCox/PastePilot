import Foundation
import GRDB

final class SQLiteHistoryStore: @unchecked Sendable {
    private enum SQLiteHistoryError: Error {
        case legacyUnrecoverable
        case searchUnavailable
    }

    private enum MetadataKey {
        static let schemaVersion = "schema_version"
        static let legacyJSONImported = "legacy_json_imported"
    }

    private struct StoredItem {
        let item: ClipboardItem
        let filePaths: [String]
        let richTextRTFBase64: String?
        let richTextHTML: String?
    }

    private let dataDirectoryURL: URL
    private let databaseURL: URL
    private let textDirectoryURL: URL

    init(
        dataDirectoryURL: URL,
        databaseURL: URL,
        textDirectoryURL: URL
    ) {
        self.dataDirectoryURL = dataDirectoryURL
        self.databaseURL = databaseURL
        self.textDirectoryURL = textDirectoryURL
    }

    func load(
        legacyLoader: () -> HistoryRepository.LegacyLoadResult?,
        legacyNormalizer: ([ClipboardItem]) -> [ClipboardItem]
    ) throws -> HistoryRepository.LoadResult {
        let dbQueue = try openDatabase()
        var importedSource: HistoryRepository.LoadSource?

        try dbQueue.write { db in
            if try metadataValue(for: MetadataKey.legacyJSONImported, db: db) == nil {
                if let legacy = legacyLoader() {
                    guard legacy.source != .unrecoverable else {
                        throw SQLiteHistoryError.legacyUnrecoverable
                    }
                    let normalizedItems = legacyNormalizer(legacy.items)
                    try save(normalizedItems, db: db)
                    try setMetadataValue(
                        legacy.source == .backup ? "backup" : "primary",
                        for: MetadataKey.legacyJSONImported,
                        db: db
                    )
                    importedSource = legacy.source
                } else {
                    try setMetadataValue(
                        "none",
                        for: MetadataKey.legacyJSONImported,
                        db: db
                    )
                }
            }
        }

        let items = try dbQueue.read { db in
            try loadItems(db: db)
        }
        let source: HistoryRepository.LoadSource
        if let importedSource {
            source = importedSource
        } else if items.isEmpty {
            source = .empty
        } else {
            source = .primary
        }
        return HistoryRepository.LoadResult(items: items, source: source)
    }

    func save(_ items: [ClipboardItem]) throws {
        let dbQueue = try openDatabase()
        try dbQueue.write { db in
            try save(items, db: db)
            try setMetadataValue(
                "primary",
                for: MetadataKey.legacyJSONImported,
                db: db
            )
        }
    }

    func matchingIDs(query: String) throws -> Set<UUID> {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let dbQueue = try openDatabase()
        return try dbQueue.read { db in
            guard try hasSearchIndex(db: db) else {
                throw SQLiteHistoryError.searchUnavailable
            }

            let sql: String
            let arguments: StatementArguments
            if query.count >= 3 {
                sql = "SELECT item_id FROM search_index WHERE body MATCH ?"
                arguments = [Self.quotedFTSQuery(query)]
            } else {
                sql = """
                    SELECT item_id FROM search_index
                    WHERE lower(body) LIKE ? ESCAPE '\\'
                    """
                arguments = [Self.likePattern(for: query.lowercased())]
            }

            let ids = try String.fetchAll(db, sql: sql, arguments: arguments)
            return Set(ids.compactMap(UUID.init(uuidString:)))
        }
    }

    private func openDatabase() throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: dataDirectoryURL,
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let dbQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
            try migrate(db)
        }
        return dbQueue
    }

    private func migrate(_ db: Database) throws {
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS items (
                id TEXT PRIMARY KEY NOT NULL,
                fingerprint TEXT NOT NULL,
                content TEXT NOT NULL,
                kind TEXT NOT NULL,
                created_at REAL NOT NULL,
                is_pinned INTEGER NOT NULL,
                contains_sensitive_data INTEGER NOT NULL,
                source_app_name TEXT,
                source_bundle_identifier TEXT,
                image_file_name TEXT,
                image_width INTEGER,
                image_height INTEGER,
                image_byte_count INTEGER,
                image_digest TEXT,
                image_source_url TEXT,
                image_original_path TEXT,
                content_file_name TEXT,
                content_digest TEXT,
                content_character_count INTEGER,
                content_line_count INTEGER,
                content_byte_count INTEGER,
                ocr_text TEXT
            )
            """)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS rich_text (
                item_id TEXT PRIMARY KEY NOT NULL
                    REFERENCES items(id) ON DELETE CASCADE,
                rtf_base64 TEXT,
                html TEXT
            )
            """)
        try db.execute(sql: """
            CREATE TABLE IF NOT EXISTS file_paths (
                item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                ordinal INTEGER NOT NULL,
                path TEXT NOT NULL,
                PRIMARY KEY (item_id, ordinal)
            )
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS items_created_at_idx
            ON items(created_at DESC)
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS items_pinned_created_idx
            ON items(is_pinned DESC, created_at DESC)
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS items_kind_idx
            ON items(kind)
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS items_content_digest_idx
            ON items(content_digest)
            """)
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS items_image_digest_idx
            ON items(image_digest)
            """)
        do {
            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS search_index
                USING fts5(item_id UNINDEXED, body, tokenize='trigram')
                """)
        } catch {
            try db.execute(sql: "DROP TABLE IF EXISTS search_index")
        }
        try setMetadataValue(
            "1",
            for: MetadataKey.schemaVersion,
            db: db
        )
    }

    private func loadItems(db: Database) throws -> [ClipboardItem] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM items ORDER BY created_at DESC"
        )
        return try rows.compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let kindRaw: String = row["kind"]
            let kind = ContentKind(rawValue: kindRaw) ?? .text
            let filePaths = try String.fetchAll(
                db,
                sql: """
                    SELECT path FROM file_paths
                    WHERE item_id = ?
                    ORDER BY ordinal
                    """,
                arguments: [id.uuidString]
            )
            let richText = try Row.fetchOne(
                db,
                sql: """
                    SELECT rtf_base64, html FROM rich_text
                    WHERE item_id = ?
                    """,
                arguments: [id.uuidString]
            )

            return ClipboardItem(
                id: id,
                content: row["content"],
                kind: kind,
                createdAt: Date(timeIntervalSince1970: row["created_at"]),
                isPinned: (row["is_pinned"] as Int) != 0,
                containsSensitiveData: (row["contains_sensitive_data"] as Int) != 0,
                sourceAppName: row["source_app_name"],
                sourceBundleIdentifier: row["source_bundle_identifier"],
                imageFileName: row["image_file_name"],
                imageWidth: row["image_width"],
                imageHeight: row["image_height"],
                imageByteCount: row["image_byte_count"],
                imageDigest: row["image_digest"],
                imageSourceURL: row["image_source_url"],
                imageOriginalPath: row["image_original_path"],
                filePaths: filePaths.isEmpty ? nil : filePaths,
                richTextRTFBase64: richText?["rtf_base64"],
                richTextHTML: richText?["html"],
                contentFileName: row["content_file_name"],
                contentDigest: row["content_digest"],
                contentCharacterCount: row["content_character_count"],
                contentLineCount: row["content_line_count"],
                contentByteCount: row["content_byte_count"],
                ocrText: row["ocr_text"]
            )
        }
    }

    private func save(_ items: [ClipboardItem], db: Database) throws {
        let storedItems = items.map { item in
            StoredItem(
                item: item,
                filePaths: item.filePaths ?? [],
                richTextRTFBase64: item.richTextRTFBase64,
                richTextHTML: item.richTextHTML
            )
        }
        let existingFingerprints = try Dictionary(
            uniqueKeysWithValues: Row.fetchAll(
                db,
                sql: "SELECT id, fingerprint FROM items"
            ).map { row in
                (row["id"] as String, row["fingerprint"] as String)
            }
        )
        let snapshotIDs = Set(storedItems.map { $0.item.id.uuidString })
        try deleteStaleItems(
            retaining: snapshotIDs,
            existingIDs: Set(existingFingerprints.keys),
            db: db
        )

        for storedItem in storedItems {
            let item = storedItem.item
            let fingerprint = Self.fingerprint(for: storedItem)
            guard existingFingerprints[item.id.uuidString] != fingerprint else {
                continue
            }
            try upsert(storedItem, fingerprint: fingerprint, db: db)
            try refreshChildren(for: storedItem, db: db)
            try refreshSearchIndex(for: storedItem, db: db)
        }
    }

    private func deleteStaleItems(
        retaining snapshotIDs: Set<String>,
        existingIDs: Set<String>,
        db: Database
    ) throws {
        let staleIDs = existingIDs.subtracting(snapshotIDs)
        guard !staleIDs.isEmpty else { return }
        let placeholders = Self.placeholders(count: staleIDs.count)
        let arguments = StatementArguments(Array(staleIDs))
        if try hasSearchIndex(db: db) {
            try db.execute(
                sql: "DELETE FROM search_index WHERE item_id IN (\(placeholders))",
                arguments: arguments
            )
        }
        try db.execute(
            sql: "DELETE FROM items WHERE id IN (\(placeholders))",
            arguments: arguments
        )
    }

    private func upsert(
        _ storedItem: StoredItem,
        fingerprint: String,
        db: Database
    ) throws {
        let item = storedItem.item
        try db.execute(
            sql: """
                INSERT INTO items (
                    id, fingerprint, content, kind, created_at, is_pinned,
                    contains_sensitive_data, source_app_name,
                    source_bundle_identifier, image_file_name, image_width,
                    image_height, image_byte_count, image_digest,
                    image_source_url, image_original_path, content_file_name,
                    content_digest, content_character_count,
                    content_line_count, content_byte_count, ocr_text
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    fingerprint = excluded.fingerprint,
                    content = excluded.content,
                    kind = excluded.kind,
                    created_at = excluded.created_at,
                    is_pinned = excluded.is_pinned,
                    contains_sensitive_data = excluded.contains_sensitive_data,
                    source_app_name = excluded.source_app_name,
                    source_bundle_identifier = excluded.source_bundle_identifier,
                    image_file_name = excluded.image_file_name,
                    image_width = excluded.image_width,
                    image_height = excluded.image_height,
                    image_byte_count = excluded.image_byte_count,
                    image_digest = excluded.image_digest,
                    image_source_url = excluded.image_source_url,
                    image_original_path = excluded.image_original_path,
                    content_file_name = excluded.content_file_name,
                    content_digest = excluded.content_digest,
                    content_character_count = excluded.content_character_count,
                    content_line_count = excluded.content_line_count,
                    content_byte_count = excluded.content_byte_count,
                    ocr_text = excluded.ocr_text
                """,
            arguments: [
                item.id.uuidString,
                fingerprint,
                item.content,
                item.kind.rawValue,
                item.createdAt.timeIntervalSince1970,
                item.isPinned ? 1 : 0,
                item.containsSensitiveData ? 1 : 0,
                item.sourceAppName,
                item.sourceBundleIdentifier,
                item.imageFileName,
                item.imageWidth,
                item.imageHeight,
                item.imageByteCount,
                item.imageDigest,
                item.imageSourceURL,
                item.imageOriginalPath,
                item.contentFileName,
                item.contentDigest,
                item.contentCharacterCount,
                item.contentLineCount,
                item.contentByteCount,
                item.ocrText
            ]
        )
    }

    private func refreshChildren(
        for storedItem: StoredItem,
        db: Database
    ) throws {
        let id = storedItem.item.id.uuidString
        try db.execute(
            sql: "DELETE FROM rich_text WHERE item_id = ?",
            arguments: [id]
        )
        if storedItem.richTextRTFBase64 != nil || storedItem.richTextHTML != nil {
            try db.execute(
                sql: """
                    INSERT INTO rich_text (item_id, rtf_base64, html)
                    VALUES (?, ?, ?)
                    """,
                arguments: [
                    id,
                    storedItem.richTextRTFBase64,
                    storedItem.richTextHTML
                ]
            )
        }

        try db.execute(
            sql: "DELETE FROM file_paths WHERE item_id = ?",
            arguments: [id]
        )
        for (index, path) in storedItem.filePaths.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO file_paths (item_id, ordinal, path)
                    VALUES (?, ?, ?)
                    """,
                arguments: [id, index, path]
            )
        }
    }

    private func refreshSearchIndex(
        for storedItem: StoredItem,
        db: Database
    ) throws {
        guard try hasSearchIndex(db: db) else { return }
        let id = storedItem.item.id.uuidString
        try db.execute(
            sql: "DELETE FROM search_index WHERE item_id = ?",
            arguments: [id]
        )
        try db.execute(
            sql: "INSERT INTO search_index (item_id, body) VALUES (?, ?)",
            arguments: [id, searchBody(for: storedItem)]
        )
    }

    private func searchBody(for storedItem: StoredItem) -> String {
        let item = storedItem.item
        let primaryContent: String
        if let fileName = item.contentFileName,
           let externalContent = try? String(
            contentsOf: textDirectoryURL.appendingPathComponent(fileName),
            encoding: .utf8
           ) {
            primaryContent = externalContent
        } else {
            primaryContent = item.content
        }

        return [
            primaryContent,
            item.kind.rawValue,
            item.ocrText,
            storedItem.filePaths.joined(separator: "\n")
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: "\n")
    }

    private func metadataValue(
        for key: String,
        db: Database
    ) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT value FROM metadata WHERE key = ?",
            arguments: [key]
        )
    }

    private func setMetadataValue(
        _ value: String,
        for key: String,
        db: Database
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO metadata (key, value)
                VALUES (?, ?)
                ON CONFLICT(key) DO UPDATE SET value = excluded.value
                """,
            arguments: [key, value]
        )
    }

    private func hasSearchIndex(db: Database) throws -> Bool {
        try String.fetchOne(
            db,
            sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name = 'search_index'
                """
        ) != nil
    }

    private static func fingerprint(for storedItem: StoredItem) -> String {
        let item = storedItem.item
        var parts: [String] = []
        parts.reserveCapacity(24)
        parts.append(item.id.uuidString)
        parts.append(item.content)
        parts.append(item.kind.rawValue)
        parts.append(String(item.createdAt.timeIntervalSince1970))
        parts.append(item.isPinned ? "1" : "0")
        parts.append(item.containsSensitiveData ? "1" : "0")
        parts.append(item.sourceAppName ?? "")
        parts.append(item.sourceBundleIdentifier ?? "")
        parts.append(item.imageFileName ?? "")
        parts.append(item.imageWidth.map(String.init) ?? "")
        parts.append(item.imageHeight.map(String.init) ?? "")
        parts.append(item.imageByteCount.map(String.init) ?? "")
        parts.append(item.imageDigest ?? "")
        parts.append(item.imageSourceURL ?? "")
        parts.append(item.imageOriginalPath ?? "")
        parts.append(storedItem.filePaths.joined(separator: "\u{1F}"))
        parts.append(storedItem.richTextRTFBase64 ?? "")
        parts.append(storedItem.richTextHTML ?? "")
        parts.append(item.contentFileName ?? "")
        parts.append(item.contentDigest ?? "")
        parts.append(item.contentCharacterCount.map(String.init) ?? "")
        parts.append(item.contentLineCount.map(String.init) ?? "")
        parts.append(item.contentByteCount.map(String.init) ?? "")
        parts.append(item.ocrText ?? "")
        return ContentDigest.sha256Hex(for: parts.joined(separator: "\u{1E}"))
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func quotedFTSQuery(_ query: String) -> String {
        "\"\(query.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func likePattern(for query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }
}
