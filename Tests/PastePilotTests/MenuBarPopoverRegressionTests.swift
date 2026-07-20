import AppKit
import Foundation
import SwiftUI
import Testing
@testable import PastePilot

@MainActor
@Suite(.serialized)
struct MenuBarPopoverRegressionTests {
    @Test
    func searchKeepsPinnedAndFullTextMatchesInStableSections() {
        let pinned = ClipboardItem(
            content: "needle pinned",
            kind: .markdown,
            createdAt: Date(timeIntervalSince1970: 1),
            isPinned: true
        )
        let externalMatch = ClipboardItem(
            content: "large content prefix",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 2),
            sourceAppName: "Terminal",
            contentFileName: "large.txt"
        )
        let inlineMatch = ClipboardItem(
            content: "needle recent",
            kind: .command,
            createdAt: Date(timeIntervalSince1970: 3),
            sourceAppName: "Terminal"
        )
        let ocrMatch = ClipboardItem(
            content: "screenshot",
            kind: .image,
            createdAt: Date(timeIntervalSince1970: 4),
            imageFileName: "screen.png",
            ocrText: "needle from image"
        )
        let hidden = ClipboardItem(
            content: "unrelated",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 5)
        )
        var fullTextSearch = FullTextSearchState()
        let token = fullTextSearch.start(query: "needle")
        fullTextSearch.finish(token: token, ids: [externalMatch.id])

        let filtered = MenuBarPopoverState.filteredItems(
            from: [hidden, externalMatch, inlineMatch, ocrMatch, pinned],
            searchText: "needle",
            fullTextSearch: fullTextSearch
        )

        #expect(filtered.map(\.id) == [
            pinned.id,
            ocrMatch.id,
            inlineMatch.id,
            externalMatch.id
        ])
        #expect(MenuBarPopoverState.shouldShowPinnedHeader(at: 0, in: filtered))
        #expect(MenuBarPopoverState.shouldShowRecentHeader(at: 1, in: filtered))
        #expect(!MenuBarPopoverState.shouldShowRecentHeader(at: 2, in: filtered))
        #expect(
            MenuBarPopoverState.preferredSize(for: filtered)
                == CGSize(width: 400, height: 262)
        )

        let terminalOnly = MenuBarPopoverState.filteredItems(
            from: [hidden, externalMatch, inlineMatch, ocrMatch, pinned],
            searchText: "app:Terminal",
            fullTextSearch: FullTextSearchState()
        )
        #expect(terminalOnly.map(\.id) == [inlineMatch.id, externalMatch.id])
    }

    @Test
    func emptyStatesDistinguishWaitingSearchingAndNoResults() {
        #expect(
            MenuBarPopoverState.emptyState(itemCount: 0, isSearching: false)
                == MenuBarPopoverEmptyState(
                    title: "Waiting for content".localized,
                    systemImage: "clipboard",
                    description: "Copied content will appear here automatically.".localized
                )
        )
        #expect(
            MenuBarPopoverState.emptyState(itemCount: 3, isSearching: true)
                == MenuBarPopoverEmptyState(
                    title: "Searching…".localized,
                    systemImage: "magnifyingglass",
                    description: "Scanning large clipboard items.".localized
                )
        )
        #expect(
            MenuBarPopoverState.emptyState(itemCount: 3, isSearching: false)
                == MenuBarPopoverEmptyState(
                    title: "No search results".localized,
                    systemImage: "magnifyingglass",
                    description: "Try searching for other content or types.".localized
                )
        )
    }

    @Test
    func previewActionsAndLongContentRemainBounded() {
        let json = ClipboardItem(
            content: #"{"b":2,"a":1}"#,
            kind: .json
        )
        let actionIDs = MenuBarPopoverState.previewActions(for: json).map(\.id)

        #expect(actionIDs == ["copy", "format-json", "minify-json", "typescript"])
        #expect(actionIDs.count <= MenuBarPopoverState.previewActionLimit)

        let longContent = String(repeating: "line of content\n", count: 2_000)
        let longItem = ClipboardItem(content: longContent, kind: .text)
        let summary = TextPreview.summary(for: longItem)
        let preview = TextPreview.detailSnippet(
            for: longItem,
            revealsSensitiveContent: false,
            maxCharacters: TextPreview.initialDetailCharacterLimit
        )
        let manyLongItems = (0..<50).map { index in
            ClipboardItem(
                content: "\(index) \(longContent)",
                kind: .text,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }

        #expect(summary.count <= TextPreview.summaryCharacterLimit)
        #expect(!summary.contains("\n"))
        #expect(preview.text.count == TextPreview.initialDetailCharacterLimit)
        #expect(preview.isTruncated)
        #expect(
            MenuBarPopoverState.preferredSize(for: manyLongItems)
                == CGSize(width: 400, height: 450)
        )
    }

    @Test
    func filteringMatchesUserMetadataWithoutFullTextSearch() {
        let item = ClipboardItem(
            content: "ordinary body",
            kind: .text,
            userTitle: "Customer escalation",
            userNote: "Billing review",
            userAliases: ["vip"]
        )
        let other = ClipboardItem(content: "unrelated", kind: .text)

        #expect(
            MenuBarPopoverState.filteredItems(
                from: [item, other],
                query: ClipboardSearchQuery("billing vip"),
                fullTextIDs: []
            ).map(\.id) == [item.id]
        )
    }

    @Test
    func popoverKeyboardMonitorIgnoresTopLevelEditorsAndSheets() {
        let popoverWindow = NSWindow()
        let editorWindow = NSWindow()

        #expect(
            AppDelegate.shouldHandlePopoverKeyEvent(
                popoverIsShown: true,
                eventWindow: popoverWindow,
                popoverWindow: popoverWindow
            )
        )
        #expect(
            !AppDelegate.shouldHandlePopoverKeyEvent(
                popoverIsShown: true,
                eventWindow: editorWindow,
                popoverWindow: popoverWindow
            )
        )
        #expect(
            !AppDelegate.shouldHandlePopoverKeyEvent(
                popoverIsShown: false,
                eventWindow: popoverWindow,
                popoverWindow: popoverWindow
            )
        )

        popoverWindow.beginSheet(editorWindow)
        #expect(
            !AppDelegate.shouldHandlePopoverKeyEvent(
                popoverIsShown: true,
                eventWindow: popoverWindow,
                popoverWindow: popoverWindow
            )
        )
        popoverWindow.endSheet(editorWindow)
    }

    @Test
    func pinDeleteActionsNoticesAndRenderingStayConnected() throws {
        let defaultsName = "PastePilotPopoverTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let settings = AppSettings(defaults: defaults)

        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("PastePilotTests.\(UUID().uuidString)")
        )
        let store = ClipboardStore(
            pasteboard: pasteboard,
            settings: settings,
            dataDirectoryURL: directory,
            ocrService: StubOCRService(),
            logger: SilentPastePilotLogger()
        )
        let older = ClipboardItem(
            content: "alpha",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let newer = ClipboardItem(
            content: "beta",
            kind: .text,
            createdAt: Date(timeIntervalSince1970: 2)
        )
        store.items = [newer, older]

        let popover = makePopoverView(store: store, settings: settings)
        let renderedSize = fittingSize(for: popover.panelContent)

        #expect(abs(renderedSize.width - popover.preferredSize.width) < 1)
        #expect(abs(renderedSize.height - popover.preferredSize.height) < 1)

        store.togglePinned(older.id)
        #expect(
            MenuBarPopoverState.filteredItems(
                from: store.items,
                searchText: "",
                fullTextSearch: FullTextSearchState()
            ).map(\.id) == [older.id, newer.id]
        )

        let copyResult = ClipboardActionFactory.performResult(
            ClipboardActionFactory.copyAction(for: older),
            using: store
        )
        let notice = PastePilotNotice(copyResult.message)

        #expect(copyResult.didCopy)
        #expect(pasteboard.string(forType: .string) == "alpha")
        #expect(notice.message == "Copied: %@".localized("Copy Original".localized))
        #expect(notice.systemImage == "checkmark.circle.fill")

        store.delete(older.id)

        #expect(store.items.map(\.id) == [newer.id])
        store.flushHistoryWrites()
    }

    private func fittingSize<V: View>(for view: V) -> CGSize {
        let hostingView = NSHostingView(rootView: view)
        hostingView.layoutSubtreeIfNeeded()
        return hostingView.fittingSize
    }

    private func makePopoverView(
        store: ClipboardStore,
        settings: AppSettings
    ) -> MenuBarView {
        MenuBarView(
            store: store,
            settings: settings,
            pasteStack: PasteStackController(
                isAccessibilityGranted: { true },
                postPasteShortcut: {}
            ),
            openSettings: {},
            openAbout: {},
            checkForUpdates: {},
            quit: {},
            closePopover: {},
            pasteAfterCopying: { .pasted },
            showAccessibilityRequired: {},
            resize: { _ in }
        )
    }
}
