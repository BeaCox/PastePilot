import Foundation

struct ClipboardTextStore {
    static let externalizationByteLimit = 64 * 1_024
    private static let searchChunkByteLimit = 64 * 1_024

    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func content(fileName: String) -> String? {
        try? String(contentsOf: url(fileName: fileName), encoding: .utf8)
    }

    func content(
        fileName: String,
        contains query: String,
        isCancelled: () -> Bool = { false }
    ) -> Bool {
        guard !query.isEmpty,
              !isCancelled(),
              let handle = try? FileHandle(forReadingFrom: url(fileName: fileName)) else {
            return false
        }
        defer { try? handle.close() }

        let overlapByteLimit = max(query.utf8.count * 4, 16)
        var overlap = Data()

        while true {
            guard !isCancelled() else { return false }
            let chunk = handle.readData(ofLength: Self.searchChunkByteLimit)
            guard !chunk.isEmpty else { return false }

            var searchableData = Data()
            searchableData.reserveCapacity(overlap.count + chunk.count)
            searchableData.append(overlap)
            searchableData.append(chunk)

            let searchableText = String(decoding: searchableData, as: UTF8.self)
            if searchableText.localizedCaseInsensitiveContains(query) {
                return true
            }

            if searchableData.count > overlapByteLimit {
                overlap = searchableData.suffix(overlapByteLimit)
            } else {
                overlap = searchableData
            }
        }
    }

    func prefix(fileName: String, maxCharacters: Int) -> String? {
        guard maxCharacters > 0 else { return "" }
        let url = url(fileName: fileName)
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let byteLimit = maxCharacters * 4 + 4
        let data = handle.readData(ofLength: byteLimit)
        let decoded = String(decoding: data, as: UTF8.self)
        return TextPreview.clippedText(
            from: decoded,
            maxCharacters: maxCharacters
        ).text
    }

    func save(_ content: String, fileName: String) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try content.write(
            to: url(fileName: fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(fileName: fileName))
    }

    func removeOrphans(retaining fileNames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        for file in files where !fileNames.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func url(fileName: String) -> URL {
        directoryURL.appendingPathComponent(fileName)
    }
}

enum ClipboardFullTextSearch {
    static func matchingIDs(
        query: String,
        targets: [(id: UUID, fileName: String)],
        textDirectoryURL: URL,
        isCancelled: () -> Bool = { false }
    ) -> Set<UUID> {
        guard !query.isEmpty, !targets.isEmpty else { return [] }
        let textStore = ClipboardTextStore(directoryURL: textDirectoryURL)
        var ids = Set<UUID>()

        for target in targets {
            guard !isCancelled() else { return ids }
            if textStore.content(
                fileName: target.fileName,
                contains: query,
                isCancelled: isCancelled
            ) {
                ids.insert(target.id)
            }
        }

        return ids
    }
}

struct ProcessedClipboardText {
    let content: String
    let fileName: String?
    let characterCount: Int
    let lineCount: Int
    let byteCount: Int
    let digest: String
    let externalizationFailed: Bool
}

final class ClipboardTextWriteQueue {
    private let queue = DispatchQueue(
        label: "PastePilot.TextWriteQueue",
        qos: .userInitiated
    )

    func processAndSave(
        _ content: String,
        id: UUID,
        textStore: ClipboardTextStore,
        completion: @escaping (ProcessedClipboardText) -> Void
    ) {
        queue.async {
            completion(Self.process(content, id: id, textStore: textStore))
        }
    }

    static func process(
        _ content: String,
        id: UUID,
        textStore: ClipboardTextStore
    ) -> ProcessedClipboardText {
        let characterCount = content.count
        let lineCount = content.reduce(1) { count, character in
            character.isNewline ? count + 1 : count
        }
        let byteCount = content.utf8.count
        let digest = ContentDigest.sha256Hex(for: content)
        guard byteCount > ClipboardTextStore.externalizationByteLimit else {
            return ProcessedClipboardText(
                content: content,
                fileName: nil,
                characterCount: characterCount,
                lineCount: lineCount,
                byteCount: byteCount,
                digest: digest,
                externalizationFailed: false
            )
        }

        let fileName = "\(id.uuidString).txt"
        do {
            try textStore.save(content, fileName: fileName)
            return ProcessedClipboardText(
                content: TextPreview.clippedText(
                    from: content,
                    maxCharacters: TextPreview.initialDetailCharacterLimit
                ).text,
                fileName: fileName,
                characterCount: characterCount,
                lineCount: lineCount,
                byteCount: byteCount,
                digest: digest,
                externalizationFailed: false
            )
        } catch {
            NSLog("PastePilot failed to externalize text content: \(error)")
            return ProcessedClipboardText(
                content: content,
                fileName: nil,
                characterCount: characterCount,
                lineCount: lineCount,
                byteCount: byteCount,
                digest: digest,
                externalizationFailed: true
            )
        }
    }
}
