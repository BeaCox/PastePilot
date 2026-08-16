import GRDB

extension SQLiteHistoryStore {
    enum MetadataKey {
        static let schemaVersion = "schema_version"
        static let legacyJSONImported = "legacy_json_imported"
        static let aliasRemoval = "alias_removal"
    }

    func metadataValue(
        for key: String,
        db: Database
    ) throws -> String? {
        try String.fetchOne(
            db,
            sql: "SELECT value FROM metadata WHERE key = ?",
            arguments: [key]
        )
    }

    func setMetadataValue(
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
}
