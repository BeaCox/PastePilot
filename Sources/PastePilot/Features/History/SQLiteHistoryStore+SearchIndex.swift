import Foundation
import GRDB

extension SQLiteHistoryStore {
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

    func refreshSearchIndex(
        for storedItem: StoredItem,
        db: Database
    ) throws {
        try replaceSearchIndexEntry(
            itemID: storedItem.item.id,
            body: searchBody(for: storedItem),
            db: db
        )
    }

    func replaceSearchIndexEntry(
        itemID: UUID,
        body: String,
        db: Database
    ) throws {
        guard try hasSearchIndex(db: db) else { return }
        let id = itemID.uuidString
        try db.execute(
            sql: "DELETE FROM search_index WHERE item_id = ?",
            arguments: [id]
        )
        try db.execute(
            sql: "INSERT INTO search_index (item_id, body) VALUES (?, ?)",
            arguments: [id, body]
        )
    }

    func searchBody(for storedItem: StoredItem) -> String {
        let item = storedItem.item
        if item.isProtected {
            return Self.protectedMetadataSearchBody(for: item)
        }

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
            item.tags?.joined(separator: "\n"),
            storedItem.filePaths.joined(separator: "\n")
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: "\n")
    }

    static func protectedMetadataSearchBody(for item: ClipboardItem) -> String {
        [
            item.kind.rawValue,
            item.userTitle,
            item.userNote,
            item.tags?.joined(separator: "\n"),
        ]
        .compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: "\n")
    }

    func hasSearchIndex(db: Database) throws -> Bool {
        try String.fetchOne(
            db,
            sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name = 'search_index'
                """
        ) != nil
    }

    func searchIndexItemIDs(db: Database) throws -> Set<String>? {
        guard try hasSearchIndex(db: db) else { return nil }
        let ids = try String.fetchAll(db, sql: "SELECT item_id FROM search_index")
        return Set(ids)
    }

    static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    static func fullTextQuery(for query: ClipboardSearchQuery) -> String {
        query.terms.map(quotedFTSTerm).joined(separator: " ")
    }

    static func quotedFTSTerm(_ term: String) -> String {
        "\"\(term.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func likePattern(for query: String) -> String {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }
}
