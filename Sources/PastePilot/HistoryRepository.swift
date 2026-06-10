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
}

final class HistoryWriteQueue {
    private let repository: HistoryRepository
    private let queue = DispatchQueue(
        label: "PastePilot.HistoryWriteQueue",
        qos: .utility
    )
    private let queueKey = DispatchSpecificKey<Void>()

    init(repository: HistoryRepository) {
        self.repository = repository
        queue.setSpecific(key: queueKey, value: ())
    }

    func save(
        _ items: [ClipboardItem],
        completion: ((Error?) -> Void)? = nil
    ) {
        queue.async { [repository] in
            do {
                try repository.save(items)
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }

    func flush() {
        guard DispatchQueue.getSpecific(key: queueKey) == nil else { return }
        queue.sync {}
    }
}
