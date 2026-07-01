import Foundation

struct HistoryRepository: Sendable {
    enum LoadSource {
        case primary
        case backup
        case empty
        case unrecoverable
    }

    struct LoadResult {
        let items: [ClipboardItem]
        let source: LoadSource
    }

    private struct HistoryDocument: Codable {
        static let currentSchemaVersion = 1

        let schemaVersion: Int
        let items: [ClipboardItem]
    }

    struct LegacyLoadResult {
        let items: [ClipboardItem]
        let source: LoadSource
    }

    let dataDirectoryURL: URL

    private var historyURL: URL {
        dataDirectoryURL.appendingPathComponent("history.json")
    }

    private var backupURL: URL {
        dataDirectoryURL.appendingPathComponent("history.backup.json")
    }

    private var sqliteURL: URL {
        dataDirectoryURL.appendingPathComponent("history.sqlite")
    }

    private var textDirectoryURL: URL {
        dataDirectoryURL.appendingPathComponent("text", isDirectory: true)
    }

    init(dataDirectoryURL: URL) {
        self.dataDirectoryURL = dataDirectoryURL
    }

    func load() -> LoadResult {
        do {
            return try sqliteStore().load(
                legacyLoader: loadLegacyHistory,
                legacyNormalizer: normalizeLegacyItemsForSQLiteImport
            )
        } catch {
            if let legacy = loadLegacyHistory() {
                return LoadResult(items: legacy.items, source: legacy.source)
            }
            if FileManager.default.fileExists(atPath: sqliteURL.path) {
                return LoadResult(items: [], source: .unrecoverable)
            }
            return LoadResult(items: [], source: .empty)
        }
    }

    func save(_ items: [ClipboardItem]) throws {
        try sqliteStore().save(items)
    }

    func matchingIDs(query: String) -> Set<UUID>? {
        try? sqliteStore().matchingIDs(query: query)
    }

    func estimatedHistoryByteCount(for items: [ClipboardItem]) -> Int64 {
        let document = HistoryDocument(
            schemaVersion: HistoryDocument.currentSchemaVersion,
            items: items
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return Int64((try? encoder.encode(document).count) ?? 0)
    }

    func dataDirectoryByteCount() -> Int64 {
        Self.byteCount(of: dataDirectoryURL)
    }

    private func sqliteStore() -> SQLiteHistoryStore {
        SQLiteHistoryStore(
            dataDirectoryURL: dataDirectoryURL,
            databaseURL: sqliteURL,
            textDirectoryURL: textDirectoryURL
        )
    }

    private func loadLegacyHistory() -> LegacyLoadResult? {
        if let items = decodeLegacyFile(at: historyURL) {
            return LegacyLoadResult(items: items, source: .primary)
        }
        if let items = decodeLegacyFile(at: backupURL) {
            return LegacyLoadResult(items: items, source: .backup)
        }
        if FileManager.default.fileExists(atPath: historyURL.path)
            || FileManager.default.fileExists(atPath: backupURL.path) {
            return LegacyLoadResult(items: [], source: .unrecoverable)
        }
        return nil
    }

    private func decodeLegacyFile(at url: URL) -> [ClipboardItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let document = try? decoder.decode(HistoryDocument.self, from: data),
           document.schemaVersion <= HistoryDocument.currentSchemaVersion {
            return document.items
        }
        return try? decoder.decode([ClipboardItem].self, from: data)
    }

    private func normalizeLegacyItemsForSQLiteImport(
        _ items: [ClipboardItem]
    ) -> [ClipboardItem] {
        let textStore = ClipboardTextStore(directoryURL: textDirectoryURL)
        return items.map { item in
            guard item.contentFileName == nil,
                  item.kind != .file,
                  item.kind != .image,
                  item.content.utf8.count > ClipboardTextStore.externalizationByteLimit else {
                return item
            }

            let processed = ClipboardTextWriteQueue.process(
                item.content,
                id: item.id,
                textStore: textStore
            )
            guard let fileName = processed.fileName else { return item }
            return item.externalizedContent(
                fileName: fileName,
                digest: processed.digest
            )
        }
    }

    private static func byteCount(of url: URL) -> Int64 {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }
        if !isDirectory.boolValue {
            let attributes = try? fileManager.attributesOfItem(atPath: url.path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(
                forKeys: [.fileSizeKey, .isRegularFileKey]
            )
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }
}

final class HistoryWriteQueue: @unchecked Sendable {
    private let repository: HistoryRepository
    private let debounceInterval: DispatchTimeInterval
    private let queue = DispatchQueue(
        label: "PastePilot.HistoryWriteQueue",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<Void>()
    private var pendingItems: [ClipboardItem]?
    private var pendingCompletions: [@Sendable (Error?) -> Void] = []
    private var scheduledGeneration = 0

    init(
        repository: HistoryRepository,
        debounceInterval: DispatchTimeInterval = .milliseconds(150)
    ) {
        self.repository = repository
        self.debounceInterval = debounceInterval
        queue.setSpecific(key: queueKey, value: ())
    }

    func save(
        _ items: [ClipboardItem],
        completion: (@Sendable (Error?) -> Void)? = nil
    ) {
        queue.async {
            self.pendingItems = items
            if let completion {
                self.pendingCompletions.append(completion)
            }

            self.scheduledGeneration += 1
            let generation = self.scheduledGeneration
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval) {
                self.writePending(ifGeneration: generation)
            }
        }
    }

    func flush() {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            scheduledGeneration += 1
            writePending()
            return
        }

        queue.sync {
            self.scheduledGeneration += 1
            self.writePending()
        }
    }

    private func writePending(ifGeneration generation: Int? = nil) {
        if let generation, generation != scheduledGeneration { return }
        guard let items = pendingItems else { return }

        pendingItems = nil
        let completions = pendingCompletions
        pendingCompletions = []

        let saveError: Error?
        do {
            try repository.save(items)
            saveError = nil
        } catch {
            saveError = error
        }

        completions.forEach { $0(saveError) }
    }
}
