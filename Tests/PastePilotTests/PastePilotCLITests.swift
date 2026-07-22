import AppKit
import Foundation
import GRDB
import PastePilotCLIKit
import Testing
@testable import PastePilot

@Suite(.serialized)
struct PastePilotCLITests {
    @Test
    func searchSupportsFiltersQuotedPhrasesAndStableHistoryIndexes() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let older = ClipboardItem(
            content: "release notes for version one",
            kind: .json,
            createdAt: Date(timeIntervalSince1970: 100),
            isPinned: true,
            sourceAppName: "Terminal",
            sourceBundleIdentifier: "com.apple.Terminal",
            userTitle: "Deploy payload",
            userAliases: ["shipping"]
        )
        let newer = ClipboardItem(
            content: "unrelated text",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try HistoryRepository(dataDirectoryURL: directory).save([newer, older])

        let history = PastePilotCLIHistory(dataDirectoryURL: directory)
        let matches = try history.search(
            "\"release notes\" kind:json app:Terminal pinned:true has:alias"
        )

        #expect(matches.count == 1)
        #expect(matches.first?.id == older.id.uuidString)
        #expect(matches.first?.index == 1)
        #expect(matches.first?.content == older.content)
        #expect(matches.first?.aliases == ["shipping"])
        #expect(try history.read(older.id.uuidString.prefix(8).description).id == older.id.uuidString)
    }

    @Test
    func readLoadsExternalTextAndCopyWritesToRequestedPasteboard() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let textDirectory = directory.appendingPathComponent("text", isDirectory: true)
        try FileManager.default.createDirectory(at: textDirectory, withIntermediateDirectories: true)
        let fileName = "external.txt"
        let content = "external CLI content"
        try Data(content.utf8).write(to: textDirectory.appendingPathComponent(fileName))
        let item = ClipboardItem(
            content: "preview",
            kind: .text,
            contentFileName: fileName,
            contentDigest: ContentDigest.sha256Hex(for: content)
        )
        try HistoryRepository(dataDirectoryURL: directory).save([item])

        let history = PastePilotCLIHistory(dataDirectoryURL: directory)
        #expect(try history.read("1").content == content)

        let pasteboard = NSPasteboard(name: .init("PastePilotCLITests-\(UUID().uuidString)"))
        try history.copy("1", to: pasteboard)
        #expect(pasteboard.string(forType: .string) == content)
    }

    @Test
    func failedCopyDoesNotClearExistingPasteboardContents() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(
            content: "",
            kind: .image,
            imageFileName: "missing.png"
        )
        try HistoryRepository(dataDirectoryURL: directory).save([item])
        let pasteboard = NSPasteboard(name: .init("PastePilotCLIFailedCopyTest"))
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)

        #expect(throws: PastePilotCLIError.unsupportedCopy("image")) {
            try PastePilotCLIHistory(dataDirectoryURL: directory).copy("1", to: pasteboard)
        }
        #expect(pasteboard.string(forType: .string) == "keep me")
    }

    @Test
    func protectedRowsExposeOnlyVisibleMetadata() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(
            content: "must not escape",
            kind: .text,
            sourceAppName: "Secrets",
            userTitle: "Visible label",
            userNote: "Visible note",
            userAliases: ["visible alias"]
        )
        let repository = HistoryRepository(dataDirectoryURL: directory)
        try repository.save([item])
        let databaseURL = directory.appendingPathComponent("history.sqlite")
        try DatabaseQueue(path: databaseURL.path).write { db in
            try db.execute(
                sql: """
                    UPDATE items SET content = '', source_app_name = NULL,
                        source_bundle_identifier = NULL, is_protected = 1
                    WHERE id = ?
                    """,
                arguments: [item.id.uuidString]
            )
            try db.execute(
                sql: "UPDATE search_index SET body = ? WHERE item_id = ?",
                arguments: ["text\nVisible label\nVisible note\nvisible alias", item.id.uuidString]
            )
        }

        let history = PastePilotCLIHistory(dataDirectoryURL: directory)
        let result = try history.read("1")
        #expect(result.isProtected)
        #expect(result.title == "Visible label")
        #expect(result.note == "Visible note")
        #expect(result.aliases == ["visible alias"])
        #expect(result.content == nil)
        #expect(result.sourceAppName == nil)
        #expect(result.filePaths.isEmpty)
        #expect(throws: PastePilotCLIError.protectedItem) {
            try history.copy("1", to: NSPasteboard(name: .init("PastePilotCLIProtectedTest")))
        }
        #expect(try history.search("visible alias").count == 1)
        #expect(try history.search("must not escape").isEmpty)
    }

    @Test
    func diagnosticsAndLiveBackupUseConsistentDatabaseSnapshot() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let item = ClipboardItem(content: "backup from CLI", kind: .text)
        try HistoryRepository(dataDirectoryURL: directory).save([item])
        let imageDirectory = directory.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true)
        try Data([0, 1, 2]).write(to: imageDirectory.appendingPathComponent("asset.png"))

        let history = PastePilotCLIHistory(dataDirectoryURL: directory)
        let diagnostics = try history.diagnostics()
        #expect(diagnostics.integrityCheck == "ok")
        #expect(diagnostics.itemCount == 1)
        #expect(diagnostics.imageAssetCount == 1)
        #expect(diagnostics.retainedBytes > 3)

        let archiveURL = directory.deletingLastPathComponent()
            .appendingPathComponent("PastePilotCLI-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: archiveURL) }
        try history.exportBackup(to: archiveURL)
        #expect(FileManager.default.fileExists(atPath: archiveURL.path))
        #expect(throws: PastePilotCLIError.destinationExists(archiveURL.path)) {
            try history.exportBackup(to: archiveURL)
        }
        try history.exportBackup(to: archiveURL, force: true)

        let extraction = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: extraction) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archiveURL.path, extraction.path]
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)

        let manifestURL = extraction.appendingPathComponent("manifest.json")
        let snapshotURL = extraction.appendingPathComponent("history.sqlite")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        let snapshotCount = try DatabaseQueue(path: snapshotURL.path).read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM items")
        }
        #expect(snapshotCount == 1)
    }

    @Test
    func applicationReportsUsageErrorsAndEmitsJSON() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try HistoryRepository(dataDirectoryURL: directory).save([
            ClipboardItem(content: "CLI JSON", kind: .text)
        ])
        var output = ""
        var errors = ""
        let application = PastePilotCLIApplication(
            stdout: { output += $0 },
            stderr: { errors += $0 }
        )

        #expect(application.run(arguments: ["pastepilot", "--data-dir", directory.path, "diagnostics", "--json"]) == 0)
        #expect(output.contains("\"itemCount\" : 1"))
        #expect(errors.isEmpty)

        output = ""
        #expect(application.run(arguments: ["pastepilot", "unknown"]) == 64)
        #expect(errors.contains("Unknown command"))
    }
}
