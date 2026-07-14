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
    func repositoryAddsUserMetadataColumnsToExistingSQLiteStore() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let dbQueue = try DatabaseQueue(
            path: directory.appendingPathComponent("history.sqlite").path
        )
        try dbQueue.write { db in
            try db.execute(sql: """
                CREATE TABLE items (
                    id TEXT PRIMARY KEY NOT NULL,
                    fingerprint TEXT NOT NULL,
                    content TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    is_pinned INTEGER NOT NULL,
                    contains_sensitive_data INTEGER NOT NULL,
                    source_app_name TEXT,
                    source_bundle_identifier TEXT,
                    image_file_name TEXT,
                    image_width INTEGER,
                    image_height INTEGER,
                    image_byte_count INTEGER,
                    image_digest TEXT,
                    image_source_url TEXT,
                    image_original_path TEXT,
                    content_file_name TEXT,
                    content_digest TEXT,
                    content_character_count INTEGER,
                    content_line_count INTEGER,
                    content_byte_count INTEGER,
                    ocr_text TEXT
                )
                """)
            try db.execute(
                sql: """
                    INSERT INTO items (
                        id, fingerprint, content, kind, created_at, is_pinned,
                        contains_sensitive_data, source_app_name,
                        source_bundle_identifier, image_file_name, image_width,
                        image_height, image_byte_count, image_digest,
                        image_source_url, image_original_path, content_file_name,
                        content_digest, content_character_count,
                        content_line_count, content_byte_count, ocr_text
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    id.uuidString,
                    "legacy-fingerprint",
                    "legacy sqlite row",
                    "text",
                    1.0,
                    0,
                    0,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil
                ]
            )
        }
        let repository = HistoryRepository(dataDirectoryURL: directory)

        let loadedItem = try #require(repository.load().items.first)
        #expect(loadedItem.id == id)
        #expect(loadedItem.userTitle == nil)
        #expect(loadedItem.imagePerceptualHash == nil)

        let updatedItem = ClipboardItem(
            id: loadedItem.id,
            content: loadedItem.content,
            kind: loadedItem.kind,
            createdAt: loadedItem.createdAt,
            userTitle: "Migrated title",
            userNote: "Migrated note",
            userAliases: ["legacy"]
        )
        try repository.save([updatedItem])

        let reloadedItem = try #require(repository.load().items.first)
        #expect(reloadedItem.userTitle == "Migrated title")
        #expect(reloadedItem.userNote == "Migrated note")
        #expect(reloadedItem.userAliases == ["legacy"])
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
            imagePerceptualHash: "v1-0123456789abcdef-80",
            imageSourceURL: "https://example.com/image.png",
            imageOriginalPath: "/tmp/image.png",
            filePaths: ["/tmp/one.txt", "/tmp/two.txt"],
            richTextRTFBase64: Data("{\\rtf1 Round trip}".utf8).base64EncodedString(),
            richTextHTML: "<strong>Round trip</strong>",
            pasteboardRepresentations: [
                ClipboardPasteboardRepresentation(
                    itemIndex: 0,
                    typeIdentifier: "public.utf8-plain-text",
                    data: Data("Round trip".utf8)
                ),
                ClipboardPasteboardRepresentation(
                    itemIndex: 1,
                    typeIdentifier: "com.example.PastePilot.custom",
                    data: Data([0x1, 0x2, 0x3])
                )
            ],
            contentFileName: nil,
            contentDigest: String(repeating: "b", count: 64),
            contentCharacterCount: 10,
            contentLineCount: 1,
            contentByteCount: 10,
            ocrText: "recognized text",
            userTitle: "Deploy snippet",
            userNote: "Use after staging checks",
            userAliases: ["release", "ship it"]
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
    func repositorySearchMatchesAllTermsAcrossIndexedFields() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let contentItem = ClipboardItem(
            content: "alpha release note",
            kind: .text
        )
        let imageItem = ClipboardItem(
            content: "screenshot",
            kind: .image,
            ocrText: "invoice total paid"
        )
        let fileItem = ClipboardItem(
            content: "Project files",
            kind: .file,
            filePaths: ["/tmp/PastePilot/Search Notes.txt"]
        )
        let appItem = ClipboardItem(
            content: "shell output",
            kind: .text,
            sourceAppName: "Terminal",
            sourceBundleIdentifier: "com.apple.Terminal"
        )
        let metadataItem = ClipboardItem(
            content: "plain body",
            kind: .text,
            userTitle: "Customer escalation",
            userNote: "Needs billing review",
            userAliases: ["vip", "renewal"]
        )
        let repository = HistoryRepository(dataDirectoryURL: directory)

        try repository.save([contentItem, imageItem, fileItem, appItem, metadataItem])

        #expect(try repository.matchingIDs(query: "note alpha") == Set([contentItem.id]))
        #expect(try repository.matchingIDs(query: "invoice paid") == Set([imageItem.id]))
        #expect(try repository.matchingIDs(query: "pastepilot notes") == Set([fileItem.id]))
        #expect(try repository.matchingIDs(query: "apple terminal") == Set([appItem.id]))
        #expect(try repository.matchingIDs(query: "customer billing") == Set([metadataItem.id]))
        #expect(try repository.matchingIDs(query: "vip renewal") == Set([metadataItem.id]))
    }

    @Test
    func repositorySearchUsesLikeFallbackForShortTerms() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(content: "go ui fix", kind: .text)
        let repository = HistoryRepository(dataDirectoryURL: directory)

        try repository.save([item])

        #expect(try repository.matchingIDs(query: "go ui") == Set([item.id]))
        #expect(try repository.matchingIDs(query: "go zz").isEmpty)
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
    func repositoryBackupExportsAndRestoresSQLiteImagesAndText() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        let restoredDirectory = root.appendingPathComponent("restored", isDirectory: true)
        let preRestoreDirectory = root.appendingPathComponent("pre-restore", isDirectory: true)
        try FileManager.default.createDirectory(
            at: sourceDirectory.appendingPathComponent("images", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory.appendingPathComponent("text", isDirectory: true),
            withIntermediateDirectories: true
        )

        let imageFileName = "image.png"
        let textFileName = "external.txt"
        let imageData = Data([0x89, 0x50, 0x4e, 0x47])
        let externalText = "full external text"
        try imageData.write(
            to: sourceDirectory
                .appendingPathComponent("images", isDirectory: true)
                .appendingPathComponent(imageFileName)
        )
        try externalText.write(
            to: sourceDirectory
                .appendingPathComponent("text", isDirectory: true)
                .appendingPathComponent(textFileName),
            atomically: true,
            encoding: .utf8
        )
        let item = ClipboardItem(
            content: "preview",
            kind: .image,
            imageFileName: imageFileName,
            contentFileName: textFileName
        )
        let sourceRepository = HistoryRepository(dataDirectoryURL: sourceDirectory)
        try sourceRepository.save([item])

        let archiveURL = root.appendingPathComponent("pastepilot-backup.zip")
        let exportResult = try sourceRepository.exportBackup(to: archiveURL)
        #expect(FileManager.default.fileExists(atPath: exportResult.archiveURL.path))

        let restoredRepository = HistoryRepository(dataDirectoryURL: restoredDirectory)
        let restoreResult = try restoredRepository.restoreBackup(
            from: archiveURL,
            preRestoreBackupDirectoryURL: preRestoreDirectory
        )

        let restoredItem = try #require(restoredRepository.load().items.first)
        #expect(restoredItem.id == item.id)
        #expect(
            try Data(
                contentsOf: restoredDirectory
                    .appendingPathComponent("images", isDirectory: true)
                    .appendingPathComponent(imageFileName)
            ) == imageData
        )
        #expect(
            try String(
                contentsOf: restoredDirectory
                    .appendingPathComponent("text", isDirectory: true)
                    .appendingPathComponent(textFileName),
                encoding: .utf8
            ) == externalText
        )
        #expect(
            FileManager.default.fileExists(
                atPath: restoreResult.preRestoreBackupURL.path
            )
        )
    }

    @Test
    func repositoryRestoreRejectsInvalidBackupBeforeReplacingData() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("target", isDirectory: true)
        let repository = HistoryRepository(dataDirectoryURL: directory)
        let existingItem = ClipboardItem(content: "existing", kind: .text)
        try repository.save([existingItem])

        let invalidRoot = root.appendingPathComponent("invalid-root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: invalidRoot,
            withIntermediateDirectories: true
        )
        try Data(
            """
            {
              "kind": "PastePilotBackup",
              "schemaVersion": 1,
              "createdAt": "2026-01-01T00:00:00Z"
            }
            """.utf8
        ).write(to: invalidRoot.appendingPathComponent("manifest.json"))
        let invalidArchive = root.appendingPathComponent("invalid.zip")
        try zipDirectory(invalidRoot, to: invalidArchive)

        var didThrow = false
        do {
            _ = try repository.restoreBackup(from: invalidArchive)
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        #expect(repository.load().items.map(\.id) == [existingItem.id])
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

    private func zipDirectory(_ directory: URL, to archiveURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-c",
            "-k",
            "--norsrc",
            directory.path,
            archiveURL.path
        ]
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "PastePilotTests.ZipDirectory",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: output.map {
                        "ditto failed: \($0)"
                    } ?? "ditto exited with \(process.terminationStatus)"
                ]
            )
        }
    }
}
