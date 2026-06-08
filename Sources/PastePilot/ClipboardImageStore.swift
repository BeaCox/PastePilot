import AppKit
import Foundation

struct ClipboardImageStore {
    let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func image(fileName: String) -> NSImage? {
        NSImage(contentsOf: url(fileName: fileName))
    }

    func path(fileName: String) -> String {
        url(fileName: fileName).path
    }

    func save(_ data: Data, fileName: String) throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: url(fileName: fileName), options: .atomic)
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
