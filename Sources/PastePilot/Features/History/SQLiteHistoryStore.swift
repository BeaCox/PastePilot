import Foundation
import GRDB

final class SQLiteHistoryStore: @unchecked Sendable {
    enum SQLiteHistoryError: Error {
        case legacyUnrecoverable
        case searchUnavailable
    }

    private let dataDirectoryURL: URL
    private let databaseURL: URL
    let textDirectoryURL: URL
    let protectedHistoryVault: ProtectedHistoryVault
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

        let items = try dbQueue.write { db in
            let items = try loadItems(db: db)
            if try metadataValue(for: MetadataKey.aliasRemoval, db: db) == "pending" {
                try save(items, db: db)
                try setMetadataValue(
                    "complete",
                    for: MetadataKey.aliasRemoval,
                    db: db
                )
            }
            return items
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

    func databaseQueue() throws -> DatabaseQueue {
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
}
