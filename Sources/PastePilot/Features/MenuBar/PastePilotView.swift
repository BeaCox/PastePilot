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
        MenuBarPopoverState.filteredItems(
            from: store.items,
            searchText: searchText,
            fullTextSearch: interactionState.fullTextSearch
        )
    }

    func shortSearchMatches(_ item: ClipboardItem, query: ClipboardSearchQuery) -> Bool {
        MenuBarPopoverState.shortSearchMatches(item, query: query)
    }

    var selectedItem: ClipboardItem? {
        MenuBarPopoverState.selectedItem(
            in: filteredItems,
            selectedID: selectedID
        )
    }

    var previewedItem: ClipboardItem? {
        MenuBarPopoverState.previewedItem(
            in: store.items,
            previewedID: previewedID
        )
    }

    var listPreferredHeight: CGFloat {
        MenuBarPopoverState.preferredHeight(for: filteredItems)
    }

    var preferredSize: CGSize {
        MenuBarPopoverState.preferredSize(for: filteredItems)
    }

    var body: some View {
        notificationHandlingPanel
            .onExitCommand(perform: handleExitCommand)
    }

}
