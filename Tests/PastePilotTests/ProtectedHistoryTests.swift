import AppKit
import Foundation
import GRDB
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

private actor ControlledProtectedHistoryAuthenticator: ProtectedHistoryAuthenticating {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var authenticationCount = 0

    func authenticate() async throws {
        authenticationCount += 1
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitUntilAuthenticationStarts() async {
        while authenticationCount == 0 {
            await Task.yield()
        }
    }

    func succeed() {
        let pendingContinuations = continuations
        continuations.removeAll(keepingCapacity: false)
        pendingContinuations.forEach { $0.resume() }
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
    func lockedItemsDoNotExposeClipboardActions() {
        let item = ClipboardItem(
            content: "Protected item",
            kind: .text,
            protectionState: .locked
        )

        #expect(ClipboardActionFactory.actions(for: item).isEmpty)
        #expect(ClipboardActionFactory.keyboardActions(for: item).isEmpty)
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
        #expect(locked.userTitle == original.userTitle)
        #expect(locked.userNote == original.userNote)
        #expect(locked.userAliases == original.userAliases)
        #expect(
            try repository.matchingIDs(query: "production token") == [original.id]
        )
        #expect(try repository.matchingIDs(query: "protected-secret-417").isEmpty)

        locked.isPinned = true
        locked.updateUserMetadata(
            title: "Rotated production token",
            note: "Visible organizational note",
            aliases: ["rotated", "prod"]
        )
        try repository.save([locked])

        try vault.unlock(timeout: 60)
        let restored = try #require(repository.load().items.first)
        #expect(restored.id == original.id)
        #expect(restored.content == original.content)
        #expect(restored.richTextHTML == original.richTextHTML)
        #expect(restored.userTitle == "Rotated production token")
        #expect(restored.userNote == "Visible organizational note")
        #expect(restored.userAliases == ["rotated", "prod"])
        #expect(restored.isPinned)
        #expect(restored.protectionState == .unlocked)
    }

    @Test
    func legacyEncryptedMetadataMigratesWithoutLossOnFirstUnlock() throws {
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
            content: "legacy-protected-secret-2257",
            kind: .text,
            userTitle: "Legacy production key",
            userNote: "Migrated visible note",
            userAliases: ["legacy", "production"]
        ).preparedForProtection(content: "legacy-protected-secret-2257")
        try repository.save([original])

        let database = try DatabaseQueue(
            path: directory.appendingPathComponent("history.sqlite").path
        )
        try database.write { db in
            try db.execute(
                sql: """
                    UPDATE items SET
                        user_title = NULL, user_note = NULL,
                        user_aliases_json = NULL, protected_metadata_version = 0
                    WHERE id = ?
                    """,
                arguments: [original.id.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM search_index WHERE item_id = ?",
                arguments: [original.id.uuidString]
            )
        }

        let migrated = try #require(repository.load().items.first)
        #expect(migrated.userTitle == original.userTitle)
        #expect(migrated.userNote == original.userNote)
        #expect(migrated.userAliases == original.userAliases)
        #expect(
            try repository.matchingIDs(query: "legacy production") == [original.id]
        )

        vault.lockVault()
        let locked = try #require(repository.load().items.first)
        #expect(locked.protectionState == .locked)
        #expect(locked.userTitle == original.userTitle)
        #expect(locked.userNote == original.userNote)
        #expect(locked.userAliases == original.userAliases)
    }

    @Test
    func clearingVisibleMetadataWhileLockedDoesNotRestoreEncryptedCopies() throws {
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
            content: "clear-metadata-secret-7742",
            kind: .text,
            userTitle: "Temporary title",
            userNote: "Temporary note",
            userAliases: ["temporary"]
        ).preparedForProtection(content: "clear-metadata-secret-7742")
        try repository.save([original])

        vault.lockVault()
        var locked = try #require(repository.load().items.first)
        locked.updateUserMetadata(title: nil, note: nil, aliases: nil)
        try repository.save([locked])

        try vault.unlock(timeout: 60)
        let restored = try #require(repository.load().items.first)
        #expect(restored.content == original.content)
        #expect(restored.userTitle == nil)
        #expect(restored.userNote == nil)
        #expect(restored.userAliases == nil)
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
            userNote: "Visible migration label"
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

    @Test
    func lockedSummaryUsesVisibleMetadataWithoutExposingContent() {
        let titled = ClipboardItem(
            content: "Protected item",
            kind: .text,
            userTitle: "Production credential",
            userNote: "Used by deployment",
            protectionState: .locked
        )
        let noted = ClipboardItem(
            content: "Protected item",
            kind: .text,
            userNote: "Finance recovery code",
            protectionState: .locked
        )
        let unlabeled = ClipboardItem(
            content: "Protected item",
            kind: .text,
            protectionState: .locked
        )

        #expect(TextPreview.summary(for: titled) == "Production credential")
        #expect(TextPreview.summary(for: noted) == "Finance recovery code")
        #expect(TextPreview.summary(for: unlabeled) == "Protected item".localized)
    }

    @Test
    func unlockedProtectedSensitiveContentDoesNotRequireSeparateReveal() {
        let content = "api-token=protected-secret-417"
        let item = ClipboardItem(
            content: content,
            kind: .text,
            containsSensitiveData: true,
            protectionState: .unlocked
        )

        #expect(!item.requiresSensitiveContentReveal)
        #expect(
            TextPreview.detailSnippet(
                for: item,
                revealsSensitiveContent: false
            ).text == content
        )
    }

    @Test @MainActor
    func concurrentUnlockRequestsShareOneAuthentication() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suiteName = "PastePilotTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let authenticator = ControlledProtectedHistoryAuthenticator()
        let noticePoster = CapturingNoticePoster()
        let vault = ProtectedHistoryVault(
            keyStore: FixedProtectedHistoryKeyStore()
        )
        let store = ClipboardStore(
            pasteboard: NSPasteboard(name: .init("ProtectedHistoryUnlockTests")),
            settings: AppSettings(defaults: defaults),
            dataDirectoryURL: directory,
            protectedHistoryVault: vault,
            protectedHistoryAuthenticator: authenticator,
            noticePoster: noticePoster,
            logger: SilentPastePilotLogger()
        )

        let firstRequest = Task { await store.unlockProtectedHistory() }
        await authenticator.waitUntilAuthenticationStarts()
        let secondRequest = Task { await store.unlockProtectedHistory() }
        await Task.yield()
        await authenticator.succeed()

        #expect(await firstRequest.value)
        #expect(await secondRequest.value)
        #expect(await store.unlockProtectedHistory())
        let authenticationCount = await authenticator.authenticationCount
        #expect(authenticationCount == 1)
        #expect(
            noticePoster.notices.filter {
                $0.message == "Protected history unlocked".localized
            }.count == 1
        )
    }

    @Test @MainActor
    func movingItemToProtectedStorageLocksItImmediately() async throws {
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
            pasteboard: NSPasteboard(name: .init("ProtectedHistoryImmediateLockTests")),
            settings: AppSettings(defaults: defaults),
            dataDirectoryURL: directory,
            protectedHistoryVault: vault,
            logger: SilentPastePilotLogger()
        )
        let item = ClipboardItem(
            content: "credential-value-9081",
            kind: .text,
            userTitle: "Deployment credential",
            userNote: "Visible label"
        )
        store.items = [item]

        #expect(await store.protect(item.id))
        #expect(!vault.isUnlocked)
        let locked = try #require(store.items.first)
        #expect(locked.protectionState == .locked)
        #expect(locked.content == "Protected item".localized)
        #expect(locked.userTitle == "Deployment credential")
        #expect(locked.userNote == "Visible label")
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
