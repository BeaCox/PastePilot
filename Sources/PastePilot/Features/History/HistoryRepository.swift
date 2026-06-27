import Foundation

struct HistoryRepository {
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

    let dataDirectoryURL: URL

    private var historyURL: URL {
        dataDirectoryURL.appendingPathComponent("history.json")
    }

    private var backupURL: URL {
        dataDirectoryURL.appendingPathComponent("history.backup.json")
    }

    init(dataDirectoryURL: URL) {
        self.dataDirectoryURL = dataDirectoryURL
    }

    func load() -> LoadResult {
        if let items = decodeFile(at: historyURL) {
            return LoadResult(items: items, source: .primary)
        }
        if let items = decodeFile(at: backupURL) {
            return LoadResult(items: items, source: .backup)
        }
        if FileManager.default.fileExists(atPath: historyURL.path)
            || FileManager.default.fileExists(atPath: backupURL.path) {
            return LoadResult(items: [], source: .unrecoverable)
        }
        return LoadResult(items: [], source: .empty)
    }

    func save(_ items: [ClipboardItem]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: dataDirectoryURL,
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: historyURL.path),
           decodeFile(at: historyURL) != nil {
            let currentHistory = try Data(contentsOf: historyURL)
            try currentHistory.write(to: backupURL, options: .atomic)
        }

        let document = HistoryDocument(
            schemaVersion: HistoryDocument.currentSchemaVersion,
            items: items
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: historyURL, options: .atomic)
    }

    func estimatedHistoryByteCount(for items: [ClipboardItem]) -> Int64 {
        let document = HistoryDocument(
            schemaVersion: HistoryDocument.currentSchemaVersion,
            items: items
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return Int64((try? encoder.encode(document).count) ?? 0)
    }

    func dataDirectoryByteCount() -> Int64 {
        Self.byteCount(of: dataDirectoryURL)
    }

    private func decodeFile(at url: URL) -> [ClipboardItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let document = try? decoder.decode(HistoryDocument.self, from: data),
           document.schemaVersion <= HistoryDocument.currentSchemaVersion {
            return document.items
        }
        return try? decoder.decode([ClipboardItem].self, from: data)
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

final class HistoryWriteQueue {
    private let repository: HistoryRepository
    private let debounceInterval: DispatchTimeInterval
    private let queue = DispatchQueue(
        label: "PastePilot.HistoryWriteQueue",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<Void>()
    private var pendingItems: [ClipboardItem]?
    private var pendingCompletions: [(Error?) -> Void] = []
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
        completion: ((Error?) -> Void)? = nil
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
