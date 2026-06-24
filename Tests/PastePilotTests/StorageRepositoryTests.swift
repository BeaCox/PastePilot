import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PastePilot

@Suite(.serialized)
struct StorageRepositoryTests {
    @Test
    func repositoryLoadsLegacyArrayAndWritesVersionedDocument() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let item = ClipboardItem(content: "legacy", kind: .text)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([item]).write(
            to: directory.appendingPathComponent("history.json")
        )

        let repository = HistoryRepository(dataDirectoryURL: directory)
        let loadedLegacyItem = try #require(repository.load().items.first)
        #expect(loadedLegacyItem.id == item.id)
        #expect(loadedLegacyItem.content == item.content)
        #expect(loadedLegacyItem.kind == item.kind)

        try repository.save([item])
        let data = try Data(
            contentsOf: directory.appendingPathComponent("history.json")
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        #expect(object["schemaVersion"] as? Int == 1)
        #expect(object["items"] as? [[String: Any]] != nil)
    }

    @Test
    func repositoryRecoversFromBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = HistoryRepository(dataDirectoryURL: directory)
        let first = ClipboardItem(content: "first", kind: .text)
        let second = ClipboardItem(content: "second", kind: .text)
        try repository.save([first])
        try repository.save([second])

        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("history.json"),
            options: .atomic
        )

        let result = repository.load()
        let recoveredItem = try #require(result.items.first)
        #expect(recoveredItem.id == first.id)
        #expect(recoveredItem.content == first.content)
        guard case .backup = result.source else {
            Issue.record("Expected backup recovery")
            return
        }
    }

    @Test
    func repositoryOverwritesExistingBackup() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let repository = HistoryRepository(dataDirectoryURL: directory)
        let first = ClipboardItem(content: "first", kind: .text)
        let second = ClipboardItem(content: "second", kind: .text)
        let third = ClipboardItem(content: "third", kind: .text)

        try repository.save([first])
        try repository.save([second])
        try repository.save([third])

        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("history.json"),
            options: .atomic
        )

        let recoveredItem = try #require(repository.load().items.first)
        #expect(recoveredItem.id == second.id)
        #expect(recoveredItem.content == second.content)
    }

    @Test
    func repositoryDistinguishesMissingAndUnrecoverableHistory() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(dataDirectoryURL: directory)

        guard case .empty = repository.load().source else {
            Issue.record("Expected an empty repository")
            return
        }

        try Data("not json".utf8).write(
            to: directory.appendingPathComponent("history.json")
        )
        guard case .unrecoverable = repository.load().source else {
            Issue.record("Expected unrecoverable history")
            return
        }
    }
}
