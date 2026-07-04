import AppKit
import Foundation
import GRDB
import Testing
import UniformTypeIdentifiers
@testable import PastePilot

@Suite(.serialized)
struct StorageRepositoryTests {
    @Test
    func repositoryImportsLegacyArrayAndKeepsLegacyFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = ClipboardItem(content: "legacy", kind: .text)
        try writeLegacyArray([item], to: directory.appendingPathComponent("history.json"))

        let repository = HistoryRepository(dataDirectoryURL: directory)
        let loadedLegacyItem = try #require(repository.load().items.first)
        #expect(loadedLegacyItem.id == item.id)
        #expect(loadedLegacyItem.content == item.content)
        #expect(loadedLegacyItem.kind == item.kind)
        #expect(
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("history.sqlite").path
            )
        )

        try repository.save([ClipboardItem(content: "sqlite only", kind: .text)])
        let legacyItems = try readLegacyArray(from: directory.appendingPathComponent("history.json"))
        #expect(legacyItems.map(\.id) == [item.id])
    }

    @Test
    func repositoryImportsVersionedDocumentAndSearchesExternalizedLegacyText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let originalContent = "legacy-large-needle\n" + String(
            repeating: "externalized legacy text\n",
            count: ClipboardTextStore.externalizationByteLimit / 8
        )
        let item = ClipboardItem(content: originalContent, kind: .text)
        try writeVersionedDocument(
            [item],
            to: directory.appendingPathComponent("history.json")
        )

        let repository = HistoryRepository(dataDirectoryURL: directory)
        let loadedItem = try #require(repository.load().items.first)
        let fileName = try #require(loadedItem.contentFileName)

        #expect(loadedItem.id == item.id)
        #expect(loadedItem.content.count == TextPreview.initialDetailCharacterLimit)
        #expect(
            FileManager.default.fileExists(
                atPath: directory
                    .appendingPathComponent("text", isDirectory: true)
                    .appendingPathComponent(fileName)
                    .path
            )
        )
        #expect(try repository.matchingIDs(query: "legacy-large-needle") == Set([item.id]))
    }

    @Test
    func repositoryRecoversFromBackupWhenPrimaryLegacyJSONIsCorrupt() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backupItem = ClipboardItem(content: "backup", kind: .text)
        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("history.json"),
            options: .atomic
        )
        try writeVersionedDocument(
            [backupItem],
            to: directory.appendingPathComponent("history.backup.json")
        )

        let result = HistoryRepository(dataDirectoryURL: directory).load()
        let recoveredItem = try #require(result.items.first)
        #expect(recoveredItem.id == backupItem.id)
        #expect(recoveredItem.content == backupItem.content)
        guard case .backup = result.source else {
            Issue.record("Expected backup recovery")
            return
        }
    }

    @Test
    func repositoryMigrationIsIdempotent() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(content: "single import", kind: .text)
        try writeVersionedDocument(
            [item],
            to: directory.appendingPathComponent("history.json")
        )
        let repository = HistoryRepository(dataDirectoryURL: directory)

        #expect(repository.load().items.map(\.id) == [item.id])
        #expect(repository.load().items.map(\.id) == [item.id])
    }

    @Test
    func repositorySaveLoadRoundTripsClipboardItemFields() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(
            content: "Round trip",
            kind: .richText,
            createdAt: Date(timeIntervalSince1970: 1_725_000_000),
            isPinned: true,
            containsSensitiveData: true,
            sourceAppName: "Source App",
            sourceBundleIdentifier: "com.example.Source",
            imageFileName: "image.png",
            imageWidth: 12,
            imageHeight: 34,
            imageByteCount: 56,
            imageDigest: String(repeating: "a", count: 64),
            imageSourceURL: "https://example.com/image.png",
            imageOriginalPath: "/tmp/image.png",
            filePaths: ["/tmp/one.txt", "/tmp/two.txt"],
            richTextRTFBase64: Data("{\\rtf1 Round trip}".utf8).base64EncodedString(),
            richTextHTML: "<strong>Round trip</strong>",
            contentFileName: nil,
            contentDigest: String(repeating: "b", count: 64),
            contentCharacterCount: 10,
            contentLineCount: 1,
            contentByteCount: 10,
            ocrText: "recognized text"
        )
        let repository = HistoryRepository(dataDirectoryURL: directory)

        try repository.save([item])

        let loadedItem = try #require(repository.load().items.first)
        #expect(loadedItem == item)
    }

    @Test
    func repositoryDiffDeletesStaleRowsAndSearchIndexEntries() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stale = ClipboardItem(
            content: "stale searchable needle",
            kind: .richText,
            filePaths: ["/tmp/stale.txt"],
            richTextHTML: "<em>stale searchable needle</em>"
        )
        let retained = ClipboardItem(content: "retained", kind: .text)
        let repository = HistoryRepository(dataDirectoryURL: directory)

        try repository.save([stale, retained])
        try repository.save([retained])

        let loadedIDs = Set(repository.load().items.map(\.id))
        #expect(loadedIDs == Set([retained.id]))
        #expect(try repository.matchingIDs(query: "stale searchable needle").isEmpty)
    }

    @Test
    func repositoryRebuildsMissingSearchIndexForUnchangedItems() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(
            content: "rehydrated searchable needle",
            kind: .text
        )
        do {
            let repository = HistoryRepository(dataDirectoryURL: directory)
            try repository.save([item])
        }
        try dropSearchIndex(in: directory)

        let repository = HistoryRepository(dataDirectoryURL: directory)
        #expect(try repository.matchingIDs(query: "rehydrated searchable needle").isEmpty)

        try repository.save([item])

        #expect(
            try repository.matchingIDs(query: "rehydrated searchable needle") == Set([item.id])
        )
    }

    @Test
    func repositorySearchThrowsWhenSQLiteStoreCannotOpen() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not sqlite".utf8).write(
            to: directory.appendingPathComponent("history.sqlite")
        )
        let repository = HistoryRepository(dataDirectoryURL: directory)

        var didThrow = false
        do {
            _ = try repository.matchingIDs(query: "needle")
        } catch {
            didThrow = true
        }

        #expect(didThrow)
    }

    @Test
    func repositoryDistinguishesMissingAndUnrecoverableLegacyHistory() throws {
        let emptyDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: emptyDirectory) }
        let emptyRepository = HistoryRepository(dataDirectoryURL: emptyDirectory)

        guard case .empty = emptyRepository.load().source else {
            Issue.record("Expected an empty repository")
            return
        }

        let corruptDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: corruptDirectory) }
        try Data("not json".utf8).write(
            to: corruptDirectory.appendingPathComponent("history.json")
        )
        guard case .unrecoverable = HistoryRepository(dataDirectoryURL: corruptDirectory).load().source else {
            Issue.record("Expected unrecoverable history")
            return
        }
    }

    private func writeLegacyArray(_ items: [ClipboardItem], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(items).write(to: url, options: .atomic)
    }

    private func readLegacyArray(from url: URL) throws -> [ClipboardItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ClipboardItem].self, from: Data(contentsOf: url))
    }

    private func writeVersionedDocument(_ items: [ClipboardItem], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let document: [String: Any] = [
            "schemaVersion": 1,
            "items": try JSONSerialization.jsonObject(with: encoder.encode(items))
        ]
        let data = try JSONSerialization.data(
            withJSONObject: document,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private func dropSearchIndex(in directory: URL) throws {
        let dbQueue = try DatabaseQueue(
            path: directory.appendingPathComponent("history.sqlite").path
        )
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "DROP TABLE IF EXISTS search_index")
        }
    }
}
