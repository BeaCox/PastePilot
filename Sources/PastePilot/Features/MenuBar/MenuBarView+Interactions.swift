import SwiftUI

extension MenuBarView {
    func selectFirstItem() {
        selectedID = filteredItems.first?.id
    }

    func handleAppear() {
        previewClosesInstantly = false
        selectFirstItem()
        searchFocused = true
        resize(preferredSize)
    }

    func handlePanelHover(_ hovering: Bool) {
        closePreviewTask?.cancel()
        guard !hovering, previewedItem != nil else { return }
        closePreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewTask?.cancel()
                previewedID = nil
            }
        }
    }

    func handleSearchChange() {
        selectFirstItem()
        resize(preferredSize)
    }

    func handleFirstItemChange() {
        guard searchText.isEmpty else { return }
        selectFirstItem()
        resize(preferredSize)
    }

    func handleFilteredCountChange() {
        if let previewedID,
           !store.items.contains(where: { $0.id == previewedID }) {
            closePreview()
        }
        resize(preferredSize)
    }

    func handleSelectionChange() {
        if previewedItem != nil {
            previewedID = selectedID
        }
    }

    func handleExitCommand() {
        if previewedItem != nil {
            closePreview()
        } else if !searchText.isEmpty {
            searchText = ""
        } else {
            closePopover()
        }
    }

    func copyItem(at notification: Notification) {
        guard let number = notification.object as? Int,
              filteredItems.indices.contains(number - 1) else {
            return
        }
        let item = filteredItems[number - 1]
        performAction(ClipboardActionFactory.copyAction(for: item))
    }

    func clearUnpinnedHistory() {
        store.clearUnpinned()
        closePreview()
        selectFirstItem()
    }

    func performKeyboardCommand(_ command: PopoverKeyboardCommand) {
        switch command {
        case .moveUp:
            moveSelection(.up)
        case .moveDown:
            moveSelection(.down)
        case .copySelected:
            guard let item = selectedItem else { return }
            performPrimaryAction(for: item)
        case .togglePreview:
            togglePreview()
        case .togglePinned:
            toggleSelectedPinned()
        case .deleteSelected:
            deleteSelectedItem()
        case .focusSearch:
            searchFocused = true
        case .clearSearch:
            searchText = ""
            searchFocused = true
        case .clearUnpinned:
            showsClearConfirmation = true
        case let .performAction(index):
            performAction(at: index)
        case .close:
            handleExitCommand()
        case .dismissAll:
            previewClosesInstantly = true
            closePreview()
            closePopover()
        }
    }

    func toggleSelectedPinned() {
        guard let item = selectedItem else { return }
        store.togglePinned(item.id)
    }

    func deleteSelectedItem() {
        guard let item = selectedItem else { return }
        store.delete(item.id)
        selectFirstItem()
    }

    func shouldShowPinnedHeader(at index: Int) -> Bool {
        index == 0
            && filteredItems.first?.isPinned == true
    }

    func shouldShowRecentHeader(at index: Int) -> Bool {
        guard index < filteredItems.count,
              !filteredItems[index].isPinned else {
            return false
        }
        return index == 0 || filteredItems[index - 1].isPinned
    }

    func moveSelection(_ direction: MoveCommandDirection) {
        guard direction == .up || direction == .down, !filteredItems.isEmpty else { return }
        let currentIndex = selectedID.flatMap { id in
            filteredItems.firstIndex { $0.id == id }
        } ?? 0
        let nextIndex: Int
        if direction == .up {
            nextIndex = max(0, currentIndex - 1)
        } else {
            nextIndex = min(filteredItems.count - 1, currentIndex + 1)
        }
        needsScrollToSelection = true
        selectedID = filteredItems[nextIndex].id
    }

    func handleRowHover(_ item: ClipboardItem, hovering: Bool) {
        previewTask?.cancel()
        guard hovering else {
            schedulePreviewClose()
            return
        }
        closePreviewTask?.cancel()
        selectedID = item.id
        guard settings.hoverPreviewEnabled else { return }
        if previewedItem != nil {
            previewedID = item.id
            return
        }
        previewTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewedID = item.id
            }
        }
    }

    func handlePreviewHover(_ hovering: Bool) {
        closePreviewTask?.cancel()
        if !hovering {
            schedulePreviewClose()
        }
    }

    func schedulePreviewClose() {
        closePreviewTask?.cancel()
        guard previewedItem != nil else { return }
        closePreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewedID = nil
            }
        }
    }

    func togglePreview() {
        if previewedItem != nil {
            closePreview()
        } else {
            previewedID = selectedItem?.id
        }
    }

    func closePreview() {
        previewTask?.cancel()
        previewedID = nil
    }

    func performPrimaryAction(for item: ClipboardItem) {
        let action = ClipboardActionFactory.copyAction(for: item)
        performAction(action)
    }

    func performAction(at oneBasedIndex: Int) {
        guard let item = selectedItem else { return }
        let actions = keyboardActions(for: item)
        guard actions.indices.contains(oneBasedIndex - 1) else { return }
        let action = actions[oneBasedIndex - 1]
        performAction(action)
    }

    func performAction(_ action: ClipboardAction) {
        let message = ClipboardActionFactory.perform(action, using: store)
        applyPasteCloseBehavior(forcePreviewClose: action.closesInlinePreview)
        showNotice(message)
    }

    func applyPasteCloseBehavior(forcePreviewClose: Bool) {
        switch PasteCloseBehavior(rawValue: settings.pasteCloseBehavior) ?? .closePreview {
        case .closePanel:
            // Dismiss the preview instantly (no fade) this runloop, then close
            // the panel on the next one. Closing the panel while the preview
            // child popover is still up makes AppKit animate the preview out as
            // a separate, sequential step.
            previewClosesInstantly = true
            closePreview()
            let closePopover = closePopover
            DispatchQueue.main.async(execute: closePopover)
        case .closePreview:
            closePreview()
        case .keepOpen:
            if forcePreviewClose {
                closePreview()
            }
        }
    }

    func keyboardActions(for item: ClipboardItem) -> [ClipboardAction] {
        ClipboardActionFactory.keyboardActions(for: item)
    }

    func showNotice(_ message: String) {
        noticeTask?.cancel()
        withAnimation { notice = message }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(1.3))
            guard !Task.isCancelled else { return }
            withAnimation { notice = nil }
        }
    }
}
