import Foundation
import GRDB

extension SQLiteHistoryStore {
    func migrate(_ db: Database) throws {
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
                pinned_order INTEGER,
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
                is_protected INTEGER NOT NULL DEFAULT 0,
                protected_payload BLOB,
                protected_metadata_version INTEGER NOT NULL DEFAULT 0
            )
            """)
        try ensureColumn(
            "pinned_order",
            definition: "pinned_order INTEGER",
            in: "items",
            db: db
        )
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
        try ensureColumn(
            "protected_metadata_version",
            definition: "protected_metadata_version INTEGER NOT NULL DEFAULT 0",
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
            CREATE TABLE IF NOT EXISTS item_tags (
                item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                ordinal INTEGER NOT NULL,
                normalized_name TEXT NOT NULL,
                PRIMARY KEY (item_id, normalized_name)
            )
            """)
        if try hasColumn("user_aliases_json", in: "items", db: db) {
            try migrateLegacyAliasesToTags(db: db)
            try db.execute(sql: "UPDATE items SET fingerprint = ''")
            try db.execute(sql: "ALTER TABLE items DROP COLUMN user_aliases_json")
            try setMetadataValue("pending", for: MetadataKey.aliasRemoval, db: db)
        }
        try db.execute(sql: """
            CREATE INDEX IF NOT EXISTS item_tags_name_idx
            ON item_tags(normalized_name)
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
            CREATE INDEX IF NOT EXISTS items_pinned_order_idx
            ON items(is_pinned DESC, pinned_order, created_at DESC)
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
            "10",
            for: MetadataKey.schemaVersion,
            db: db
        )
    }

    func migrateLegacyAliasesToTags(db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT id, user_aliases_json FROM items
                WHERE user_aliases_json IS NOT NULL
                """
        )
        for row in rows {
            let itemID: String = row["id"]
            let aliasesJSON: String? = row["user_aliases_json"]
            guard let aliases: [String] = Self.decodedJSON(from: aliasesJSON),
                  let migratedTags = ClipboardItem.normalizedTags(aliases) else {
                continue
            }
            var existingTags = Set(
                try String.fetchAll(
                    db,
                    sql: "SELECT normalized_name FROM item_tags WHERE item_id = ?",
                    arguments: [itemID]
                )
            )
            var nextOrdinal = try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(MAX(ordinal) + 1, 0) FROM item_tags
                    WHERE item_id = ?
                    """,
                arguments: [itemID]
            ) ?? 0
            for tag in migratedTags where existingTags.insert(tag).inserted {
                try db.execute(
                    sql: """
                        INSERT INTO item_tags (item_id, ordinal, normalized_name)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [itemID, nextOrdinal, tag]
                )
                nextOrdinal += 1
            }
        }
    }

    private func ensureColumn(
        _ column: String,
        definition: String,
        in table: String,
        db: Database
    ) throws {
        guard try !hasColumn(column, in: table, db: db) else { return }
        try db.execute(sql: "ALTER TABLE \(table) ADD COLUMN \(definition)")
    }

    private func hasColumn(
        _ column: String,
        in table: String,
        db: Database
    ) throws -> Bool {
        try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))").contains { row in
            row["name"] as String == column
        }
    }
}
