import AppKit
import Foundation
import Testing
@testable import PastePilot

// Run this suite on its own with:
// make test SWIFT_TEST_PARALLEL_FLAGS='--no-parallel --filter HistoryPerformanceTests'
@Suite(.serialized)
struct HistoryPerformanceTests {
    @Test
    func startupLoadsMaximumSupportedHistoryFixture() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(dataDirectoryURL: directory)
        let items = HistoryPerformanceFixture.items(
            count: HistoryPerformanceFixture.maximumHistoryLimit
        )
        try repository.save(items)

        let loadedItems = measurePerformanceScenario("startup-load") {
            HistoryRepository(dataDirectoryURL: directory).load().items
        }

        #expect(loadedItems.count == HistoryPerformanceFixture.maximumHistoryLimit)
        #expect(Set(loadedItems.map(\.id)) == Set(items.map(\.id)))
    }

    @Test
    func filteredSearchUsesMaximumSupportedHistoryFixture() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = HistoryRepository(dataDirectoryURL: directory)
        let items = HistoryPerformanceFixture.items(
            count: HistoryPerformanceFixture.maximumHistoryLimit
        )
        try repository.save(items)
        let query = ClipboardSearchQuery(
            "search-needle kind:code tag:backend has:note app:terminal"
        )

        let filteredItems = try measurePerformanceScenario("filtered-search") {
            let fullTextIDs = try repository.matchingIDs(query: query.searchText)
            return MenuBarPopoverState.filteredItems(
                from: items,
                query: query,
                fullTextIDs: fullTextIDs
            )
        }

        let expectedIDs = Set(
            items.filter { item in
                item.kind == .code
                    && item.tags == ["backend"]
                    && item.userNote != nil
                    && item.sourceAppName == "Terminal"
            }.map(\.id)
        )
        #expect(Set(filteredItems.map(\.id)) == expectedIDs)
    }

    @Test
    func externalizedTextSearchUsesMaximumSupportedHistoryFixture() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let items = try HistoryPerformanceFixture.externalizedTextItems(
            count: HistoryPerformanceFixture.maximumHistoryLimit,
            dataDirectoryURL: directory
        )
        let repository = HistoryRepository(dataDirectoryURL: directory)
        try repository.save(items)

        let matchingIDs = try measurePerformanceScenario("external-text-search") {
            try repository.matchingIDs(query: "external-needle-0490")
        }

        #expect(matchingIDs == Set([items[490].id]))
    }

    @Test
    @MainActor
    func cleanupCoversEverySupportedHistoryLimit() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaultsName = "PastePilotPerformanceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        defaults.removePersistentDomain(forName: defaultsName)
        let store = ClipboardStore(
            pasteboard: NSPasteboard(
                name: NSPasteboard.Name("PastePilotPerformanceTests.\(UUID().uuidString)")
            ),
            settings: AppSettings(defaults: defaults),
            dataDirectoryURL: directory,
            ocrService: StubOCRService(),
            logger: SilentPastePilotLogger()
        )

        for limit in AppSettings.supportedHistoryLimits {
            let fixtureItems = HistoryPerformanceFixture.items(
                count: limit + HistoryPerformanceFixture.cleanupOverflow,
                pinsEvery: 100
            )
            let pinnedIDs = Set(fixtureItems.filter(\.isPinned).map(\.id))
            store.items = fixtureItems

            measurePerformanceScenario("cleanup-limit-\(limit)") {
                store.trimHistory(limit: limit)
            }

            #expect(store.items.filter { !$0.isPinned }.count == limit)
            #expect(Set(store.items.filter(\.isPinned).map(\.id)) == pinnedIDs)
        }
    }
}

private enum HistoryPerformanceFixture {
    static let maximumHistoryLimit = AppSettings.supportedHistoryLimits.max() ?? 500
    static let cleanupOverflow = 125

    static func items(count: Int, pinsEvery: Int? = nil) -> [ClipboardItem] {
        (0..<count).map { index in
            let isPinned = pinsEvery.map { index.isMultiple(of: $0) } ?? false
            return ClipboardItem(
                content: "fixture search-needle item \(index)",
                kind: index.isMultiple(of: 2) ? .code : .text,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                isPinned: isPinned,
                sourceAppName: index.isMultiple(of: 10) ? "Terminal" : "Editor",
                sourceBundleIdentifier: index.isMultiple(of: 10)
                    ? "com.apple.Terminal"
                    : "com.example.Editor",
                userNote: index.isMultiple(of: 4) ? "representative note" : nil,
                tags: index.isMultiple(of: 5) ? ["backend"] : ["general"]
            )
        }
    }

    static func externalizedTextItems(
        count: Int,
        dataDirectoryURL: URL
    ) throws -> [ClipboardItem] {
        let textStore = ClipboardTextStore(
            directoryURL: dataDirectoryURL.appendingPathComponent(
                "text",
                isDirectory: true
            )
        )
        return try (0..<count).map { index in
            let content = "external fixture external-needle-\(String(format: "%04d", index))"
            let id = UUID()
            let fileName = "\(id.uuidString).txt"
            try textStore.save(content, fileName: fileName)
            return ClipboardItem(
                id: id,
                content: "",
                kind: .text,
                createdAt: Date(timeIntervalSince1970: TimeInterval(index)),
                contentFileName: fileName,
                contentDigest: ContentDigest.sha256Hex(for: content),
                contentCharacterCount: content.count,
                contentLineCount: 1,
                contentByteCount: content.utf8.count
            )
        }
    }
}

@discardableResult
private func measurePerformanceScenario<Result>(
    _ name: String,
    operation: () throws -> Result
) rethrows -> Result {
    let clock = ContinuousClock()
    let start = clock.now
    let result = try operation()
    let duration = start.duration(to: clock.now)
    print("PastePilot performance fixture [\(name)]: \(duration)")
    return result
}
