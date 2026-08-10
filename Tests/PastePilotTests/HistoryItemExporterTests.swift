import Foundation
import Testing
@testable import PastePilot

@Suite
struct HistoryItemExporterTests {
    @Test
    func plainTextExportReadsExternalContentAndRequiresUnlockedItems() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let textDirectory = root.appendingPathComponent("text", isDirectory: true)
        let imageDirectory = root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(
            at: textDirectory,
            withIntermediateDirectories: true
        )
        let fullContent = String(repeating: "external line\n", count: 8_000)
        try fullContent.write(
            to: textDirectory.appendingPathComponent("large.txt"),
            atomically: true,
            encoding: .utf8
        )
        let item = ClipboardItem(
            content: "external preview",
            kind: .text,
            contentFileName: "large.txt"
        )
        let source = HistoryItemExportSource(
            item: item,
            textDirectoryURL: textDirectory,
            imageDirectoryURL: imageDirectory
        )
        let destinationURL = root.appendingPathComponent("Export.txt")

        let result = try HistoryItemExporter.export(
            [source],
            as: .plainText,
            to: destinationURL
        )

        #expect(result.exportedURLs == [destinationURL])
        #expect(try String(contentsOf: destinationURL, encoding: .utf8) == fullContent)

        let lockedItem = ClipboardItem(
            content: "secret",
            kind: .text,
            protectionState: .locked
        )
        let lockedSource = HistoryItemExportSource(
            item: lockedItem,
            textDirectoryURL: textDirectory,
            imageDirectoryURL: imageDirectory
        )
        let lockedDestinationURL = root.appendingPathComponent("Locked.txt")
        #expect(throws: HistoryItemExporter.ExportError.lockedItem) {
            try HistoryItemExporter.export(
                [lockedSource],
                as: .plainText,
                to: lockedDestinationURL
            )
        }
        #expect(!FileManager.default.fileExists(atPath: lockedDestinationURL.path))
    }

    @Test
    func jsonExportIncludesUsefulMetadataWithoutInternalStorageFields() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let exportedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = root.appendingPathComponent("example.swift")
        let item = ClipboardItem(
            content: "let value = 42",
            kind: .code,
            createdAt: createdAt,
            isPinned: true,
            containsSensitiveData: true,
            sourceAppName: "Terminal",
            sourceBundleIdentifier: "com.apple.Terminal",
            imageFileName: "internal.png",
            imageWidth: 40,
            imageHeight: 20,
            imageByteCount: 512,
            imageSourceURL: "https://example.com/image.png",
            imageOriginalPath: "/tmp/original.png",
            filePaths: [fileURL.path],
            pasteboardRepresentations: [
                ClipboardPasteboardRepresentation(
                    typeIdentifier: "dev.pastepilot.private",
                    data: Data("private representation".utf8)
                )
            ],
            contentDigest: "internal-digest",
            ocrText: "recognized text",
            userTitle: "Reusable snippet",
            userNote: "Use in tests",
            tags: ["swift", "fixture"],
            protectionState: .unlocked
        )
        let source = HistoryItemExportSource(
            item: item,
            textDirectoryURL: root.appendingPathComponent("text"),
            imageDirectoryURL: root.appendingPathComponent("images")
        )
        let destinationURL = root.appendingPathComponent("Export.json")

        try HistoryItemExporter.export(
            [source],
            as: .json,
            to: destinationURL,
            exportedAt: exportedAt
        )

        let data = try Data(contentsOf: destinationURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(
            HistoryItemExporter.JSONDocument.self,
            from: data
        )
        let exportedItem = try #require(document.items.first)
        #expect(document.formatVersion == 1)
        #expect(document.exportedAt == exportedAt)
        #expect(exportedItem.id == item.id)
        #expect(exportedItem.kind == "code")
        #expect(exportedItem.content == "let value = 42")
        #expect(exportedItem.isPinned)
        #expect(exportedItem.containsSensitiveData)
        #expect(exportedItem.isProtected)
        #expect(exportedItem.filePaths == [fileURL.path])
        #expect(exportedItem.image?.width == 40)
        #expect(exportedItem.ocrText == "recognized text")
        #expect(exportedItem.title == "Reusable snippet")
        #expect(exportedItem.tags == ["swift", "fixture"])

        let json = try #require(String(data: data, encoding: .utf8))
        #expect(!json.contains("contentFileName"))
        #expect(!json.contains("imageFileName"))
        #expect(!json.contains("pasteboardRepresentations"))
        #expect(!json.contains("internal-digest"))
        #expect(!json.contains("private representation"))
    }

    @Test
    func imageExportCopiesTheCachedPNG() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let imageDirectory = root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(
            at: imageDirectory,
            withIntermediateDirectories: true
        )
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        try imageData.write(to: imageDirectory.appendingPathComponent("cached.png"))
        let item = ClipboardItem(
            content: "Image 10 × 10",
            kind: .image,
            imageFileName: "cached.png",
            imageWidth: 10,
            imageHeight: 10,
            ocrText: "text in image"
        )
        let source = HistoryItemExportSource(
            item: item,
            textDirectoryURL: root.appendingPathComponent("text"),
            imageDirectoryURL: imageDirectory
        )
        let imageDestinationURL = root.appendingPathComponent("Export.png")
        let textDestinationURL = root.appendingPathComponent("OCR.txt")

        try HistoryItemExporter.export(
            [source],
            as: .image,
            to: imageDestinationURL
        )
        try HistoryItemExporter.export(
            [source],
            as: .plainText,
            to: textDestinationURL
        )

        #expect(try Data(contentsOf: imageDestinationURL) == imageData)
        #expect(
            try String(contentsOf: textDestinationURL, encoding: .utf8)
                == "text in image"
        )
    }

    @Test
    func originalFileExportPreservesSourcesAndAvoidsNameCollisions() throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = root.appendingPathComponent("source", isDirectory: true)
        let destinationDirectory = root.appendingPathComponent(
            "destination",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: sourceDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let firstURL = sourceDirectory.appendingPathComponent("notes.txt")
        let secondURL = sourceDirectory.appendingPathComponent("config.json")
        try Data("new notes".utf8).write(to: firstURL)
        try Data(#"{"enabled":true}"#.utf8).write(to: secondURL)
        let existingURL = destinationDirectory.appendingPathComponent("notes.txt")
        try Data("existing notes".utf8).write(to: existingURL)
        let item = ClipboardItem(
            content: "notes.txt\nconfig.json",
            kind: .file,
            filePaths: [firstURL.path, secondURL.path]
        )
        let source = HistoryItemExportSource(
            item: item,
            textDirectoryURL: root.appendingPathComponent("text"),
            imageDirectoryURL: root.appendingPathComponent("images")
        )

        let result = try HistoryItemExporter.export(
            [source],
            as: .originalFiles,
            to: destinationDirectory
        )

        #expect(result.exportedURLs.map(\.lastPathComponent) == [
            "notes 2.txt",
            "config.json"
        ])
        #expect(try String(contentsOf: existingURL, encoding: .utf8) == "existing notes")
        #expect(
            try String(
                contentsOf: destinationDirectory.appendingPathComponent("notes 2.txt"),
                encoding: .utf8
            ) == "new notes"
        )
        #expect(FileManager.default.fileExists(
            atPath: destinationDirectory.appendingPathComponent("config.json").path
        ))
    }
}
