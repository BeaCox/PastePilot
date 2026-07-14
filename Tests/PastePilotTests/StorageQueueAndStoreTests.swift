import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PastePilot

@Suite(.serialized)
struct StorageQueueAndStoreTests {
    @Test
    func imageStoreRemovesOnlyOrphanedFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageStore = ClipboardImageStore(
            directoryURL: directory.appendingPathComponent("images")
        )
        try imageStore.save(Data("keep".utf8), fileName: "keep.png")
        try imageStore.save(Data("remove".utf8), fileName: "remove.png")

        imageStore.removeOrphans(retaining: ["keep.png"])

        #expect(
            FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "keep.png")
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "remove.png")
            )
        )
    }

    @Test
    func imageProcessingQueueEncodesAndSavesPNG() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let imageStore = ClipboardImageStore(
            directoryURL: directory.appendingPathComponent("images")
        )
        let writer = ClipboardImageProcessingQueue()
        let image = try makeTestImage(width: 3, height: 2)

        let processedImage = try await withCheckedThrowingContinuation { continuation in
            writer.encodeAndSave(
                image,
                fileName: "queued.png",
                imageStore: imageStore,
                sizeLimitBytes: 1_000_000
            ) { result in
                continuation.resume(with: result)
            }
        }

        #expect(processedImage.fileName == "queued.png")
        #expect(processedImage.width == 3)
        #expect(processedImage.height == 2)
        #expect(processedImage.byteCount > 0)
        #expect(!processedImage.digest.isEmpty)
        #expect(processedImage.perceptualHash?.hasPrefix("v1-") == true)
        #expect(
            FileManager.default.fileExists(
                atPath: imageStore.path(fileName: "queued.png")
            )
        )
    }

    @Test
    func perceptualHashComparesStructureAndAverageLuminance() {
        #expect(
            ImagePerceptualHash.areSimilar(
                "v1-0000000000000000-80",
                "v1-0000000000000003-88"
            )
        )
        #expect(
            !ImagePerceptualHash.areSimilar(
                "v1-0000000000000000-20",
                "v1-0000000000000000-e0"
            )
        )
        #expect(!ImagePerceptualHash.areSimilar("invalid", nil))
    }

    @Test
    func textStoreSearchFindsMatchesAcrossReadChunks() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let textStore = ClipboardTextStore(
            directoryURL: directory.appendingPathComponent("text")
        )
        let fileName = "large.txt"
        let content = String(repeating: "a", count: 65_530)
            + "NeedleAcrossBoundary"
            + String(repeating: "z", count: 2_000)

        try textStore.save(content, fileName: fileName)

        #expect(textStore.content(fileName: fileName, contains: "needleacrossboundary"))
        #expect(!textStore.content(fileName: fileName, contains: "missing value"))
    }

    @Test
    func textStoreSearchFindsAllTermsAcrossDistantChunks() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let textStore = ClipboardTextStore(
            directoryURL: directory.appendingPathComponent("text")
        )
        let fileName = "large.txt"
        let content = "FirstNeedle\n"
            + String(repeating: "middle content\n", count: 10_000)
            + "SecondNeedle"

        try textStore.save(content, fileName: fileName)

        #expect(textStore.content(fileName: fileName, contains: "secondneedle firstneedle"))
        #expect(!textStore.content(fileName: fileName, contains: "firstneedle missing"))
    }

    @Test
    func textStoreSearchStopsWhenCancelled() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let textStore = ClipboardTextStore(
            directoryURL: directory.appendingPathComponent("text")
        )
        let fileName = "large.txt"
        let content = String(repeating: "a", count: 150_000) + "Needle"
        var cancellationChecks = 0

        try textStore.save(content, fileName: fileName)
        let found = textStore.content(fileName: fileName, contains: "needle") {
            cancellationChecks += 1
            return cancellationChecks >= 2
        }

        #expect(!found)
        #expect(cancellationChecks >= 2)
    }

    @Test
    func fullTextSearchStopsBeforeScanningMoreTargetsWhenCancelled() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let textStore = ClipboardTextStore(
            directoryURL: directory.appendingPathComponent("text")
        )
        let firstID = UUID()
        let secondID = UUID()
        try textStore.save("first file without match", fileName: "first.txt")
        try textStore.save("needle appears here", fileName: "second.txt")
        var cancellationChecks = 0

        let ids = ClipboardFullTextSearch.matchingIDs(
            query: "needle",
            targets: [
                (firstID, "first.txt"),
                (secondID, "second.txt")
            ],
            textDirectoryURL: textStore.directoryURL
        ) {
            cancellationChecks += 1
            return cancellationChecks >= 3
        }

        #expect(ids.isEmpty)
        #expect(cancellationChecks >= 3)
    }

    @Test
    func historyWriteQueuePersistsAfterFlush() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(dataDirectoryURL: directory)
        let writer = HistoryWriteQueue(repository: repository)
        let item = ClipboardItem(content: "queued", kind: .text)

        writer.save([item])
        writer.flush()

        let loadedItem = try #require(repository.load().items.first)
        #expect(loadedItem.id == item.id)
        #expect(loadedItem.content == item.content)
    }

    @Test
    func historyWriteQueueFlushWritesOnlyLatestPendingSnapshot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(dataDirectoryURL: directory)
        let writer = HistoryWriteQueue(
            repository: repository,
            debounceInterval: .seconds(60)
        )
        let first = ClipboardItem(content: "first", kind: .text)
        let second = ClipboardItem(content: "second", kind: .text)

        writer.save([first])
        writer.save([second])
        writer.flush()

        let loadedItem = try #require(repository.load().items.first)
        #expect(loadedItem.id == second.id)
        #expect(loadedItem.content == second.content)
        #expect(
            !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("history.backup.json").path
            )
        )
    }
}
