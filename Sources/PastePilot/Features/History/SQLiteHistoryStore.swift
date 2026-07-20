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
        let pasteboardRepresentations: [ClipboardPasteboardRepresentation]
        let protectedPayload: Data?
    }

    private let dataDirectoryURL: URL
    private let databaseURL: URL
    private let textDirectoryURL: URL
    private let protectedHistoryVault: ProtectedHistoryVault
    private let dbQueueLock = NSLock()
    private var cachedDBQueue: DatabaseQueue?

    init(
        dataDirectoryURL: URL,
        databaseURL: URL,
        textDirectoryURL: URL,
        protectedHistoryVault: ProtectedHistoryVault
    ) {
        self.dataDirectoryURL = dataDirectoryURL
        self.databaseURL = databaseURL
        self.textDirectoryURL = textDirectoryURL
        self.protectedHistoryVault = protectedHistoryVault
    }

    func load(
        legacyLoader: () -> HistoryRepository.LegacyLoadResult?,
        legacyNormalizer: ([ClipboardItem]) -> [ClipboardItem]
    ) throws -> HistoryRepository.LoadResult {
        let dbQueue = try databaseQueue()
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
        let dbQueue = try databaseQueue()
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
        let searchQuery = ClipboardSearchQuery(query)
        guard searchQuery.hasSearchTerms else { return [] }
        let dbQueue = try databaseQueue()
        return try dbQueue.read { db in
            guard try hasSearchIndex(db: db) else {
                throw SQLiteHistoryError.searchUnavailable
            }

            let sql: String
            let arguments: StatementArguments
            if searchQuery.canUseTrigramFullTextSearch {
                sql = "SELECT item_id FROM search_index WHERE body MATCH ?"
                arguments = [Self.fullTextQuery(for: searchQuery)]
            } else {
                let clauses = Array(
                    repeating: "lower(body) LIKE ? ESCAPE '\\'",
                    count: searchQuery.terms.count
                ).joined(separator: " AND ")
                sql = """
                    SELECT item_id FROM search_index
                    WHERE \(clauses)
                    """
                arguments = StatementArguments(
                    searchQuery.terms.map { Self.likePattern(for: $0.lowercased()) }
                )
            }

            let ids = try String.fetchAll(db, sql: sql, arguments: arguments)
            return Set(ids.compactMap(UUID.init(uuidString:)))
        }
    }

    func closeDatabase() throws {
        dbQueueLock.lock()
        let dbQueue = cachedDBQueue
        cachedDBQueue = nil
        dbQueueLock.unlock()

        guard let dbQueue else { return }
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    func securelyCompactDatabase() throws {
        let dbQueue = try databaseQueue()
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            try db.execute(sql: "VACUUM")
        }
    }

    private func databaseQueue() throws -> DatabaseQueue {
        dbQueueLock.lock()
        defer { dbQueueLock.unlock() }
        if let cachedDBQueue {
            return cachedDBQueue
        }
        let dbQueue = try openDatabase()
        cachedDBQueue = dbQueue
        return dbQueue
    }

    private func openDatabase() throws -> DatabaseQueue {
        try FileManager.default.createDirectory(
            at: dataDirectoryURL,
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA secure_delete = ON")
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
                image_perceptual_hash TEXT,
                image_source_url TEXT,
                image_original_path TEXT,
                link_metadata_json TEXT,
                detected_barcodes_json TEXT,
                content_file_name TEXT,
                content_digest TEXT,
                content_character_count INTEGER,
                content_line_count INTEGER,
                content_byte_count INTEGER,
                ocr_text TEXT,
                user_title TEXT,
                user_note TEXT,
                user_aliases_json TEXT,
                is_protected INTEGER NOT NULL DEFAULT 0,
                protected_payload BLOB
            )
            """)
        try ensureColumn(
            "image_perceptual_hash",
            definition: "image_perceptual_hash TEXT",
            in: "items",
            db: db
        )
        try ensureColumn(
            "link_metadata_json",
            definition: "link_metadata_json TEXT",
            in: "items",
            db: db
        )
        try ensureColumn(
            "detected_barcodes_json",
            definition: "detected_barcodes_json TEXT",
            in: "items",
            db: db
        )
        try ensureColumn(
            "user_title",
            definition: "user_title TEXT",
            in: "items",
            db: db
        )
        try ensureColumn(
            "user_note",
            definition: "user_note TEXT",
            in: "items",
            db: db
        )
        try ensureColumn(
            "user_aliases_json",
            definition: "user_aliases_json TEXT",
            in: "items",
            db: db
        )
        try ensureColumn(
            "is_protected",
            definition: "is_protected INTEGER NOT NULL DEFAULT 0",
            in: "items",
            db: db
        )
        try ensureColumn(
            "protected_payload",
            definition: "protected_payload BLOB",
            in: "items",
            db: db
        )
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
            CREATE TABLE IF NOT EXISTS pasteboard_representations (
                item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                item_index INTEGER NOT NULL,
                ordinal INTEGER NOT NULL,
                type_identifier TEXT NOT NULL,
                data BLOB NOT NULL,
                PRIMARY KEY (item_id, item_index, ordinal)
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
            "6",
            for: MetadataKey.schemaVersion,
            db: db
        )
    }

    private func loadItems(db: Database) throws -> [ClipboardItem] {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM items ORDER BY is_pinned DESC, created_at DESC"
        )
        return try rows.compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            let kindRaw: String = row["kind"]
            let kind = ContentKind(rawValue: kindRaw) ?? .text
            let isProtected = (row["is_protected"] as Int? ?? 0) != 0
            if isProtected {
                if let encryptedPayload: Data = row["protected_payload"],
                   let plaintext = try? protectedHistoryVault.decrypt(encryptedPayload),
                   var item = try? JSONDecoder().decode(ClipboardItem.self, from: plaintext) {
                    item.protectionState = .unlocked
                    item.isPinned = (row["is_pinned"] as Int) != 0
                    return item
                }
                return ClipboardItem(
                    id: id,
                    content: "Protected item".localized,
                    kind: kind,
                    createdAt: Date(timeIntervalSince1970: row["created_at"]),
                    isPinned: (row["is_pinned"] as Int) != 0,
                    containsSensitiveData: true,
                    protectionState: .locked
                )
            }
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
            let pasteboardRepresentations = try Row.fetchAll(
                db,
                sql: """
                    SELECT item_index, type_identifier, data
                    FROM pasteboard_representations
                    WHERE item_id = ?
                    ORDER BY item_index, ordinal
                    """,
                arguments: [id.uuidString]
            ).map { representationRow in
                ClipboardPasteboardRepresentation(
                    itemIndex: representationRow["item_index"],
                    typeIdentifier: representationRow["type_identifier"],
                    data: representationRow["data"]
                )
            }

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
                imagePerceptualHash: row["image_perceptual_hash"],
                imageSourceURL: row["image_source_url"],
                imageOriginalPath: row["image_original_path"],
                linkMetadata: Self.decodedJSON(from: row["link_metadata_json"]),
                detectedBarcodes: Self.decodedJSON(
                    from: row["detected_barcodes_json"]
                ),
                filePaths: filePaths.isEmpty ? nil : filePaths,
                richTextRTFBase64: richText?["rtf_base64"],
                richTextHTML: richText?["html"],
                pasteboardRepresentations: pasteboardRepresentations.isEmpty
                    ? nil
                    : pasteboardRepresentations,
                contentFileName: row["content_file_name"],
                contentDigest: row["content_digest"],
                contentCharacterCount: row["content_character_count"],
                contentLineCount: row["content_line_count"],
                contentByteCount: row["content_byte_count"],
                ocrText: row["ocr_text"],
                userTitle: row["user_title"],
                userNote: row["user_note"],
                userAliases: Self.decodedAliases(from: row["user_aliases_json"])
            )
        }
    }

    private func save(_ items: [ClipboardItem], db: Database) throws {
        let storedItems = try items.map { item in
            let protectedPayload: Data?
            if item.protectionState == .unlocked {
                protectedPayload = try protectedHistoryVault.encrypt(
                    JSONEncoder().encode(item)
                )
            } else {
                protectedPayload = nil
            }
            return StoredItem(
                item: item,
                filePaths: item.isProtected ? [] : item.filePaths ?? [],
                richTextRTFBase64: item.isProtected ? nil : item.richTextRTFBase64,
                richTextHTML: item.isProtected ? nil : item.richTextHTML,
                pasteboardRepresentations: item.isProtected
                    ? []
                    : item.pasteboardRepresentations ?? [],
                protectedPayload: protectedPayload
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
        let indexedIDs = try searchIndexItemIDs(db: db)
        let snapshotIDs = Set(storedItems.map { $0.item.id.uuidString })
        try deleteStaleItems(
            retaining: snapshotIDs,
            existingIDs: Set(existingFingerprints.keys),
            db: db
        )

        for storedItem in storedItems {
            let item = storedItem.item
            let itemID = item.id.uuidString
            if item.protectionState == .locked {
                try db.execute(
                    sql: "UPDATE items SET is_pinned = ?, created_at = ? WHERE id = ?",
                    arguments: [
                        item.isPinned ? 1 : 0,
                        item.createdAt.timeIntervalSince1970,
                        itemID,
                    ]
                )
                if try hasSearchIndex(db: db) {
                    try db.execute(
                        sql: "DELETE FROM search_index WHERE item_id = ?",
                        arguments: [itemID]
                    )
                }
                continue
            }
            let fingerprint = Self.fingerprint(for: storedItem)
            let needsItemRefresh = existingFingerprints[itemID] != fingerprint
            let needsSearchRefresh = indexedIDs.map { !$0.contains(itemID) } ?? false
            guard needsItemRefresh || needsSearchRefresh else {
                continue
            }
            if needsItemRefresh {
                try upsert(storedItem, fingerprint: fingerprint, db: db)
                try refreshChildren(for: storedItem, db: db)
            }
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
        let protected = item.isProtected
        try db.execute(
            sql: """
                INSERT INTO items (
                    id, fingerprint, content, kind, created_at, is_pinned,
                    contains_sensitive_data, source_app_name,
                    source_bundle_identifier, image_file_name, image_width,
                    image_height, image_byte_count, image_digest,
                    image_perceptual_hash,
                    image_source_url, image_original_path, link_metadata_json,
                    detected_barcodes_json, content_file_name,
                    content_digest, content_character_count,
                    content_line_count, content_byte_count, ocr_text,
                    user_title, user_note, user_aliases_json,
                    is_protected, protected_payload
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                    image_perceptual_hash = excluded.image_perceptual_hash,
                    image_source_url = excluded.image_source_url,
                    image_original_path = excluded.image_original_path,
                    link_metadata_json = excluded.link_metadata_json,
                    detected_barcodes_json = excluded.detected_barcodes_json,
                    content_file_name = excluded.content_file_name,
                    content_digest = excluded.content_digest,
                    content_character_count = excluded.content_character_count,
                    content_line_count = excluded.content_line_count,
                    content_byte_count = excluded.content_byte_count,
                    ocr_text = excluded.ocr_text,
                    user_title = excluded.user_title,
                    user_note = excluded.user_note,
                    user_aliases_json = excluded.user_aliases_json,
                    is_protected = excluded.is_protected,
                    protected_payload = excluded.protected_payload
                """,
            arguments: [
                item.id.uuidString,
                fingerprint,
                protected ? "" : item.content,
                item.kind.rawValue,
                item.createdAt.timeIntervalSince1970,
                item.isPinned ? 1 : 0,
                protected ? 1 : (item.containsSensitiveData ? 1 : 0),
                protected ? nil : item.sourceAppName,
                protected ? nil : item.sourceBundleIdentifier,
                protected ? nil : item.imageFileName,
                protected ? nil : item.imageWidth,
                protected ? nil : item.imageHeight,
                protected ? nil : item.imageByteCount,
                protected ? nil : item.imageDigest,
                protected ? nil : item.imagePerceptualHash,
                protected ? nil : item.imageSourceURL,
                protected ? nil : item.imageOriginalPath,
                protected ? nil : Self.encodedJSON(item.linkMetadata),
                protected ? nil : Self.encodedJSON(item.detectedBarcodes),
                protected ? nil : item.contentFileName,
                protected ? nil : item.contentDigest,
                protected ? nil : item.contentCharacterCount,
                protected ? nil : item.contentLineCount,
                protected ? nil : item.contentByteCount,
                protected ? nil : item.ocrText,
                protected ? nil : item.userTitle,
                protected ? nil : item.userNote,
                protected ? nil : Self.encodedAliases(item.userAliases),
                protected ? 1 : 0,
                storedItem.protectedPayload
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

        try db.execute(
            sql: "DELETE FROM pasteboard_representations WHERE item_id = ?",
            arguments: [id]
        )
        for (index, representation) in storedItem.pasteboardRepresentations.enumerated() {
            try db.execute(
                sql: """
                    INSERT INTO pasteboard_representations (
                        item_id, item_index, ordinal, type_identifier, data
                    )
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    id,
                    representation.itemIndex,
                    index,
                    representation.typeIdentifier,
                    representation.data
                ]
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
        guard !storedItem.item.isProtected else { return }
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
            item.sourceAppName,
            item.sourceBundleIdentifier,
            item.ocrText,
            item.linkMetadata?.title,
            item.linkMetadata?.summary,
            item.linkMetadata?.siteName,
            item.detectedBarcodes?.map(\.payload).joined(separator: "\n"),
            item.userTitle,
            item.userNote,
            item.userAliases?.joined(separator: "\n"),
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

    private func ensureColumn(
        _ column: String,
        definition: String,
        in table: String,
        db: Database
    ) throws {
        let columns = try Set(
            Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").map { row in
                row["name"] as String
            }
        )
        guard !columns.contains(column) else { return }
        try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN \(definition)")
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

    private func searchIndexItemIDs(db: Database) throws -> Set<String>? {
        guard try hasSearchIndex(db: db) else { return nil }
        let ids = try String.fetchAll(db, sql: "SELECT item_id FROM search_index")
        return Set(ids)
    }

    private static func fingerprint(for storedItem: StoredItem) -> String {
        let item = storedItem.item
        if item.isProtected {
            let encryptedDigest = storedItem.protectedPayload.map {
                ContentDigest.sha256Hex(for: $0)
            } ?? "locked"
            return ContentDigest.sha256Hex(
                for: [
                    item.id.uuidString,
                    item.kind.rawValue,
                    item.isPinned ? "1" : "0",
                    encryptedDigest,
                ].joined(separator: "\u{1E}")
            )
        }
        var parts: [String] = []
        parts.reserveCapacity(24 + storedItem.pasteboardRepresentations.count * 3)
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
        parts.append(item.imagePerceptualHash ?? "")
        parts.append(item.imageSourceURL ?? "")
        parts.append(item.imageOriginalPath ?? "")
        parts.append(Self.encodedJSON(item.linkMetadata) ?? "")
        parts.append(Self.encodedJSON(item.detectedBarcodes) ?? "")
        parts.append(storedItem.filePaths.joined(separator: "\u{1F}"))
        parts.append(storedItem.richTextRTFBase64 ?? "")
        parts.append(storedItem.richTextHTML ?? "")
        for representation in storedItem.pasteboardRepresentations {
            parts.append(String(representation.itemIndex))
            parts.append(representation.typeIdentifier)
            parts.append(ContentDigest.sha256Hex(for: representation.data))
        }
        parts.append(item.contentFileName ?? "")
        parts.append(item.contentDigest ?? "")
        parts.append(item.contentCharacterCount.map(String.init) ?? "")
        parts.append(item.contentLineCount.map(String.init) ?? "")
        parts.append(item.contentByteCount.map(String.init) ?? "")
        parts.append(item.ocrText ?? "")
        parts.append(item.userTitle ?? "")
        parts.append(item.userNote ?? "")
        parts.append(item.userAliases?.joined(separator: "\u{1F}") ?? "")
        return ContentDigest.sha256Hex(for: parts.joined(separator: "\u{1E}"))
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func fullTextQuery(for query: ClipboardSearchQuery) -> String {
        query.terms.map(quotedFTSTerm).joined(separator: " ")
    }

    private static func quotedFTSTerm(_ term: String) -> String {
        "\"\(term.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func likePattern(for query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    private static func decodedAliases(from json: String?) -> [String]? {
        guard let json,
              let data = json.data(using: .utf8),
              let aliases = try? JSONDecoder().decode([String].self, from: data),
              !aliases.isEmpty else {
            return nil
        }
        return aliases
    }

    private static func encodedAliases(_ aliases: [String]?) -> String? {
        guard let aliases,
              !aliases.isEmpty,
              let data = try? JSONEncoder().encode(aliases) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func decodedJSON<Value: Decodable>(from json: String?) -> Value? {
        guard let json,
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private static func encodedJSON<Value: Encodable>(_ value: Value?) -> String? {
        guard let value,
              let data = try? JSONEncoder().encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
