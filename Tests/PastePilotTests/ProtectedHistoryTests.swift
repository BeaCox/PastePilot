import AppKit
import Foundation
import Testing
@testable import PastePilot

private struct FixedProtectedHistoryKeyStore: ProtectedHistoryKeyStoring {
    let key: Data

    init(byte: UInt8 = 0xA7) {
        key = Data(repeating: byte, count: 32)
    }

    func loadOrCreateKey() throws -> Data {
        key
    }
}

@Suite
struct ProtectedHistoryTests {
    @Test
    func vaultEncryptsAndRequiresUnlock() throws {
        let vault = ProtectedHistoryVault(
            keyStore: FixedProtectedHistoryKeyStore()
        )
        let plaintext = Data("private clipboard value".utf8)

        #expect(throws: ProtectedHistoryError.self) {
            try vault.encrypt(plaintext)
        }

        try vault.unlock(timeout: 60)
        let ciphertext = try vault.encrypt(plaintext)
        #expect(ciphertext != plaintext)
        #expect(try vault.decrypt(ciphertext) == plaintext)

        vault.lockVault()
        #expect(throws: ProtectedHistoryError.self) {
            try vault.decrypt(ciphertext)
        }
    }

    @Test
    func lockedItemsDoNotExposeClipboardActionsOrPreview() {
        let item = ClipboardItem(
            content: "Protected item",
            kind: .text,
            protectionState: .locked
        )

        #expect(ClipboardActionFactory.actions(for: item).isEmpty)
        #expect(ClipboardActionFactory.keyboardActions(for: item).isEmpty)
        #expect(!MenuBarPopoverState.shouldShowContextPreview(for: item))
        if case let .copyItem(id) = ClipboardActionFactory.copyAction(for: item).effect {
            #expect(id == item.id)
        } else {
            Issue.record("Locked item copy must route through the guarded item path")
        }
    }

    @Test
    func repositoryReturnsPlaceholderWhileLockedAndRestoresPayloadAfterUnlock() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ProtectedHistoryVault(
            keyStore: FixedProtectedHistoryKeyStore()
        )
        try vault.unlock(timeout: 60)
        let repository = HistoryRepository(
            dataDirectoryURL: directory,
            protectedHistoryVault: vault
        )
        let original = ClipboardItem(
            content: "api-token=protected-secret-417",
            kind: .json,
            containsSensitiveData: true,
            richTextHTML: "<b>protected-secret-417</b>",
            userTitle: "Production token",
            userNote: "Do not expose",
            userAliases: ["prod"]
        ).preparedForProtection(content: "api-token=protected-secret-417")

        try repository.save([original])
        #expect(try repository.matchingIDs(query: "protected-secret-417").isEmpty)

        vault.lockVault()
        var locked = try #require(repository.load().items.first)
        #expect(locked.id == original.id)
        #expect(locked.protectionState == .locked)
        #expect(locked.content == "Protected item".localized)
        #expect(locked.userTitle == nil)

        locked.isPinned = true
        try repository.save([locked])

        try vault.unlock(timeout: 60)
        let restored = try #require(repository.load().items.first)
        #expect(restored.id == original.id)
        #expect(restored.content == original.content)
        #expect(restored.richTextHTML == original.richTextHTML)
        #expect(restored.userTitle == original.userTitle)
        #expect(restored.userNote == original.userNote)
        #expect(restored.userAliases == original.userAliases)
        #expect(restored.isPinned)
        #expect(restored.protectionState == .unlocked)
    }

    @Test
    func plaintextItemCanBeMigratedWithoutLeavingSearchableDatabaseText() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = ProtectedHistoryVault(
            keyStore: FixedProtectedHistoryKeyStore()
        )
        try vault.unlock(timeout: 60)
        let repository = HistoryRepository(
            dataDirectoryURL: directory,
            protectedHistoryVault: vault
        )
        let secret = "migration-secret-8D1C2A91"
        let plaintext = ClipboardItem(
            content: secret,
            kind: .richText,
            richTextHTML: "<strong>\(secret)</strong>",
            pasteboardRepresentations: [
                ClipboardPasteboardRepresentation(
                    itemIndex: 0,
                    typeIdentifier: "public.utf8-plain-text",
                    data: Data(secret.utf8)
                )
            ],
            userNote: secret
        )

        try repository.save([plaintext])
        #expect(try repository.matchingIDs(query: secret) == [plaintext.id])

        try repository.save([
            plaintext.preparedForProtection(content: secret)
        ])
        try repository.securelyCompactDatabase()
        #expect(try repository.matchingIDs(query: secret).isEmpty)

        let secretData = Data(secret.utf8)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        for file in files where file.lastPathComponent.hasPrefix("history.sqlite") {
            let data = try Data(contentsOf: file)
            #expect(data.range(of: secretData) == nil)
        }
    }

    @Test @MainActor
    func unlockedProtectedLargeTextIsNeverExternalizedToPlaintextFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let vault = ProtectedHistoryVault(
            keyStore: FixedProtectedHistoryKeyStore()
        )
        try vault.unlock(timeout: 60)
        let store = ClipboardStore(
            pasteboard: NSPasteboard(name: .init("ProtectedHistoryTests")),
            settings: AppSettings(defaults: defaults),
            dataDirectoryURL: directory,
            protectedHistoryVault: vault,
            logger: SilentPastePilotLogger()
        )
        let content = String(
            repeating: "s",
            count: ClipboardTextStore.externalizationByteLimit + 1
        )
        store.items = [
            ClipboardItem(content: content, kind: .text)
                .preparedForProtection(content: content)
        ]

        #expect(!store.externalizeLoadedLargeTextContent())
        #expect(store.items.first?.contentFileName == nil)
        #expect(
            (try? FileManager.default.contentsOfDirectory(
                at: store.textStore.directoryURL,
                includingPropertiesForKeys: nil
            ))?.isEmpty != false
        )
    }
}
