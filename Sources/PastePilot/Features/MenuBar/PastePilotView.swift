import SwiftUI

enum PopoverKeyboardCommand {
    case moveUp
    case moveDown
    case copySelected
    case togglePreview
    case togglePinned
    case deleteSelected
    case focusSearch
    case clearSearch
    case clearUnpinned
    case performAction(Int)
    case close
    case dismissAll
}

struct MenuBarView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings
    let openSettings: @MainActor () -> Void
    let openAbout: @MainActor () -> Void
    let checkForUpdates: @MainActor () -> Void
    let quit: @MainActor () -> Void
    let closePopover: @MainActor () -> Void
    let pasteAfterCopying: @MainActor () -> PasteShortcutService.Result
    let showAccessibilityRequired: @MainActor () -> Void
    let resize: @MainActor (CGSize) -> Void
    @State var searchText = ""
    @State var selectedID: UUID?
    @State var previewedID: UUID?
    @State var notice: PastePilotNotice?
    @State var needsScrollToSelection = false
    @State var showsClearConfirmation = false
    @State var interactionState = MenuBarInteractionState()
    @State var historyItemFrames: [UUID: CGRect] = [:]
    @State var previewClosesInstantly = false
    @FocusState var searchFocused: Bool

    var filteredItems: [ClipboardItem] {
        let query = ClipboardSearchQuery(searchText)
        let fullTextIDs = interactionState.fullTextSearch.matchingIDs(
            for: query.searchText
        )
        let matches = query.isEmpty ? store.items : store.items.filter {
            guard query.matchesFilters($0) else { return false }
            guard query.hasSearchTerms else { return true }
            return shortSearchMatches($0, query: query) || fullTextIDs.contains($0.id)
        }
        return ClipboardHistoryOrdering.pinnedFirst(matches)
    }

    func shortSearchMatches(_ item: ClipboardItem, query: ClipboardSearchQuery) -> Bool {
        query.matches(item.content)
            || query.matches(item.kind.localizedTitle)
            || query.matches(item.ocrText)
    }

    var selectedItem: ClipboardItem? {
        guard let selectedID else { return filteredItems.first }
        return filteredItems.first { $0.id == selectedID } ?? filteredItems.first
    }

    var previewedItem: ClipboardItem? {
        guard let previewedID else { return nil }
        return store.items.first { $0.id == previewedID }
    }

    var listPreferredHeight: CGFloat {
        guard !filteredItems.isEmpty else { return 250 }
        let sectionCount = (filteredItems.contains(where: \.isPinned) ? 1 : 0)
            + (filteredItems.contains(where: { !$0.isPinned }) ? 1 : 0)
        return min(450, max(190, 82 + CGFloat(sectionCount * 22) + CGFloat(filteredItems.count * 34)))
    }

    var preferredSize: CGSize {
        CGSize(width: 400, height: listPreferredHeight)
    }

    var body: some View {
        notificationHandlingPanel
            .onExitCommand(perform: handleExitCommand)
    }

}
