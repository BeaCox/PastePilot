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
    let openSettings: () -> Void
    let openAbout: () -> Void
    let checkForUpdates: () -> Void
    let quit: () -> Void
    let closePopover: () -> Void
    let resize: (CGSize) -> Void
    @State var searchText = ""
    @State var selectedID: UUID?
    @State var previewedID: UUID?
    @State var notice: String?
    @State var needsScrollToSelection = false
    @State var showsClearConfirmation = false
    @State var previewTask: Task<Void, Never>?
    @State var closePreviewTask: Task<Void, Never>?
    @State var historyItemFrames: [UUID: CGRect] = [:]
    @State var previewClosesInstantly = false
    @FocusState var searchFocused: Bool

    var filteredItems: [ClipboardItem] {
        let matches = searchText.isEmpty ? store.items : store.items.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
                || $0.kind.localizedTitle.localizedCaseInsensitiveContains(searchText)
                || ($0.ocrText?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        return ClipboardHistoryOrdering.pinnedFirst(matches)
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
