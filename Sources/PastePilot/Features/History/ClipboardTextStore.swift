import Foundation

struct ClipboardTextStore {
    static let externalizationByteLimit = 64 * 1_024

    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func content(fileName: String) -> String? {
        try? String(contentsOf: url(fileName: fileName), encoding: .utf8)
    }

    func content(fileName: String, contains query: String) -> Bool {
        guard !query.isEmpty,
              let content = content(fileName: fileName) else {
            return false
        }
        return content.localizedCaseInsensitiveContains(query)
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
