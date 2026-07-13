import CoreGraphics
import Foundation

struct MenuBarPopoverEmptyState: Equatable {
    let title: String
    let systemImage: String
    let description: String
}

enum MenuBarPopoverState {
    static let preferredWidth: CGFloat = 400
    static let emptyHeight: CGFloat = 250
    static let minimumHeight: CGFloat = 190
    static let maximumHeight: CGFloat = 450
    static let heightBase: CGFloat = 82
    static let sectionHeaderHeight: CGFloat = 22
    static let rowHeight: CGFloat = 34
    static let previewActionLimit = 9

    static func filteredItems(
        from items: [ClipboardItem],
        searchText: String,
        fullTextSearch: FullTextSearchState
    ) -> [ClipboardItem] {
        let query = ClipboardSearchQuery(searchText)
        let fullTextIDs = fullTextSearch.matchingIDs(for: query.searchText)
        return filteredItems(
            from: items,
            query: query,
            fullTextIDs: fullTextIDs
        )
    }

    static func filteredItems(
        from items: [ClipboardItem],
        query: ClipboardSearchQuery,
        fullTextIDs: Set<UUID>
    ) -> [ClipboardItem] {
        let matches = query.isEmpty ? items : items.filter {
            guard query.matchesFilters($0) else { return false }
            guard query.hasSearchTerms else { return true }
            return shortSearchMatches($0, query: query) || fullTextIDs.contains($0.id)
        }
        return ClipboardHistoryOrdering.pinnedFirst(matches)
    }

    static func shortSearchMatches(
        _ item: ClipboardItem,
        query: ClipboardSearchQuery
    ) -> Bool {
        let userMetadata = [
            item.userTitle,
            item.userNote,
            item.userAliases?.joined(separator: " ")
        ]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        return query.matches(item.content)
            || query.matches(item.kind.localizedTitle)
            || query.matches(item.ocrText)
            || query.matches(userMetadata)
    }

    static func selectedItem(
        in filteredItems: [ClipboardItem],
        selectedID: UUID?
    ) -> ClipboardItem? {
        guard let selectedID else { return filteredItems.first }
        return filteredItems.first { $0.id == selectedID } ?? filteredItems.first
    }

    static func previewedItem(
        in items: [ClipboardItem],
        previewedID: UUID?
    ) -> ClipboardItem? {
        guard let previewedID else { return nil }
        return items.first { $0.id == previewedID }
    }

    static func preferredSize(for filteredItems: [ClipboardItem]) -> CGSize {
        CGSize(
            width: preferredWidth,
            height: preferredHeight(for: filteredItems)
        )
    }

    static func preferredHeight(for filteredItems: [ClipboardItem]) -> CGFloat {
        guard !filteredItems.isEmpty else { return emptyHeight }
        let sectionCount = (filteredItems.contains(where: \.isPinned) ? 1 : 0)
            + (filteredItems.contains(where: { !$0.isPinned }) ? 1 : 0)
        let unclampedHeight = heightBase
            + CGFloat(sectionCount) * sectionHeaderHeight
            + CGFloat(filteredItems.count) * rowHeight
        return min(maximumHeight, max(minimumHeight, unclampedHeight))
    }

    static func shouldShowPinnedHeader(
        at index: Int,
        in items: [ClipboardItem]
    ) -> Bool {
        index == 0 && items.first?.isPinned == true
    }

    static func shouldShowRecentHeader(
        at index: Int,
        in items: [ClipboardItem]
    ) -> Bool {
        guard index < items.count,
              !items[index].isPinned else {
            return false
        }
        return index == 0 || items[index - 1].isPinned
    }

    static func emptyState(
        itemCount: Int,
        isSearching: Bool
    ) -> MenuBarPopoverEmptyState {
        if itemCount == 0 {
            return MenuBarPopoverEmptyState(
                title: "Waiting for content".localized,
                systemImage: "clipboard",
                description: "Copied content will appear here automatically.".localized
            )
        }
        if isSearching {
            return MenuBarPopoverEmptyState(
                title: "Searching…".localized,
                systemImage: "magnifyingglass",
                description: "Scanning large clipboard items.".localized
            )
        }
        return MenuBarPopoverEmptyState(
            title: "No search results".localized,
            systemImage: "magnifyingglass",
            description: "Try searching for other content or types.".localized
        )
    }

    static func previewActions(for item: ClipboardItem) -> [ClipboardAction] {
        Array(
            ClipboardActionFactory.keyboardActions(for: item)
                .prefix(previewActionLimit)
        )
    }
}
