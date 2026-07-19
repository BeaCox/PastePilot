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

    func handleDisappear() {
        interactionState.reset()
        previewedID = nil
        notice = nil
        historyItemFrames.removeAll(keepingCapacity: false)
    }

    func handlePanelHover(_ hovering: Bool) {
        interactionState.closePreviewTask?.cancel()
        guard !hovering, previewedItem != nil else { return }
        interactionState.closePreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                interactionState.previewTask?.cancel()
                previewedID = nil
            }
        }
    }

    func handleSearchChange() {
        scheduleFullTextSearch()
        selectFirstItem()
        resize(preferredSize)
    }

    func scheduleFullTextSearch() {
        interactionState.fullTextSearchTask?.cancel()
        let searchQuery = ClipboardSearchQuery(searchText)
        let query = searchQuery.searchText
        let targets = store.externalContentSearchTargets()
        guard searchQuery.hasSearchTerms else {
            interactionState.fullTextSearch.clear(completedQuery: query)
            return
        }
        let textDirectoryURL = store.textStore.directoryURL
        let historyRepository = store.historyRepository
        let logger = store.logger
        let searchToken = interactionState.fullTextSearch.start(query: query)

        interactionState.fullTextSearchTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else {
                await MainActor.run {
                    interactionState.fullTextSearch.cancel(token: searchToken)
                }
                return
            }
            let searchTask = Task.detached(priority: .userInitiated) {
                do {
                    let ids = try historyRepository.matchingIDs(query: query)
                    return ids
                } catch {
                    logger.log(
                        "PastePilot SQLite history search failed; falling back to text scan: \(error)"
                    )
                }
                guard !targets.isEmpty else { return [] }
                return ClipboardFullTextSearch.matchingIDs(
                    query: query,
                    targets: targets,
                    textDirectoryURL: textDirectoryURL,
                    isCancelled: { Task.isCancelled }
                )
            }
            let ids = await withTaskCancellationHandler {
                await searchTask.value
            } onCancel: {
                searchTask.cancel()
            }
            guard !Task.isCancelled else {
                await MainActor.run {
                    interactionState.fullTextSearch.cancel(token: searchToken)
                }
                return
            }
            await MainActor.run {
                interactionState.fullTextSearch.finish(token: searchToken, ids: ids)
                selectFirstItem()
                resize(preferredSize)
            }
        }
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
        PastePilotAppIntents.setSelectedItemID(selectedID)
        if previewedItem != nil {
            previewedID = selectedID
        }
    }

    func handleExitCommand() {
        if previewedItem != nil {
            closePreview()
        } else if !searchText.isEmpty {
            searchText = ""
            interactionState.fullTextSearch.clear()
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
        pasteStack.retain(availableIDs: Set(store.items.map(\.id)))
        closePreview()
        selectFirstItem()
    }

    func togglePasteStackItem(_ item: ClipboardItem) {
        let wasQueued = pasteStack.contains(item.id)
        let isQueued = pasteStack.toggle(item.id)
        if !wasQueued, !isQueued {
            showNotice(PastePilotNotice(
                "Paste stack can contain up to %d items.".localized(
                    PasteStackController.maximumItemCount
                ),
                style: .warning
            ))
        }
    }

    func startPasteStack() {
        let itemsByID = Dictionary(uniqueKeysWithValues: store.items.map { ($0.id, $0) })
        let queuedItems = pasteStack.itemIDs.compactMap { itemsByID[$0] }
        pasteStack.retain(availableIDs: Set(itemsByID.keys))

        let result = pasteStack.start(
            items: queuedItems,
            separator: settings.resolvedPasteStackSeparator,
            copyItem: { store.copyOriginalItem($0) },
            copySeparator: { store.copy($0) }
        )
        switch result {
        case .started:
            previewClosesInstantly = true
            closePreview()
            closePopover()
        case .accessibilityRequired:
            showAccessibilityRequired()
            showNotice(PastePilotNotice(
                "Paste stack needs Accessibility permission.".localized,
                style: .warning
            ))
        case .empty:
            showNotice(PastePilotNotice(
                "Add at least one item to the paste stack.".localized,
                style: .warning
            ))
        case .alreadyPasting:
            break
        }
    }

    func cancelPasteStack() {
        pasteStack.cancel()
        showNotice(PastePilotNotice("Paste stack cancelled".localized))
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
            interactionState.fullTextSearch.clear()
            searchFocused = true
        case .clearUnpinned:
            beginClearUnpinnedConfirmation()
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

    func beginEditingMetadata(for item: ClipboardItem) {
        selectedID = item.id
        metadataTitle = item.userTitle ?? ""
        metadataNote = item.userNote ?? ""
        metadataAliases = (item.userAliases ?? []).joined(separator: ", ")
        prepareForTopLevelPresentation()
        editingMetadataItemID = item.id
    }

    func saveMetadataEdit() {
        guard let id = editingMetadataItemID else { return }
        store.updateUserMetadata(
            for: id,
            title: metadataTitle,
            note: metadataNote,
            aliases: parsedMetadataAliases
        )
        editingMetadataItemID = nil
        previewClosesInstantly = false
    }

    func cancelMetadataEdit() {
        editingMetadataItemID = nil
        previewClosesInstantly = false
    }

    func beginClearUnpinnedConfirmation() {
        prepareForTopLevelPresentation()
        showsClearConfirmation = true
    }

    func prepareForTopLevelPresentation() {
        previewClosesInstantly = true
        closePreview()
    }

    private var parsedMetadataAliases: [String] {
        metadataAliases
            .split { character in
                character == "," || character == "\n"
            }
            .map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    func shouldShowPinnedHeader(at index: Int) -> Bool {
        shouldShowPinnedHeader(at: index, in: filteredItems)
    }

    func shouldShowPinnedHeader(at index: Int, in items: [ClipboardItem]) -> Bool {
        MenuBarPopoverState.shouldShowPinnedHeader(at: index, in: items)
    }

    func shouldShowRecentHeader(at index: Int) -> Bool {
        shouldShowRecentHeader(at: index, in: filteredItems)
    }

    func shouldShowRecentHeader(at index: Int, in items: [ClipboardItem]) -> Bool {
        MenuBarPopoverState.shouldShowRecentHeader(at: index, in: items)
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
        interactionState.previewTask?.cancel()
        guard hovering else {
            schedulePreviewClose()
            return
        }
        interactionState.closePreviewTask?.cancel()
        selectedID = item.id
        guard settings.hoverPreviewEnabled else { return }
        if previewedItem != nil {
            previewedID = item.id
            return
        }
        interactionState.previewTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                previewedID = item.id
            }
        }
    }

    func handlePreviewHover(_ hovering: Bool) {
        interactionState.closePreviewTask?.cancel()
        if !hovering {
            schedulePreviewClose()
        }
    }

    func schedulePreviewClose() {
        interactionState.closePreviewTask?.cancel()
        guard previewedItem != nil else { return }
        interactionState.closePreviewTask = Task {
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
        interactionState.previewTask?.cancel()
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
        let result = ClipboardActionFactory.performResult(action, using: store)
        if settings.pasteAfterCopying, result.didCopy {
            pasteCopiedContent()
        } else {
            applyPasteCloseBehavior(forcePreviewClose: action.closesInlinePreview)
        }
        showNotice(PastePilotNotice(result.message))
    }

    func pasteCopiedContent() {
        previewClosesInstantly = true
        closePreview()
        closePopover()
        switch pasteAfterCopying() {
        case .pasted:
            break
        case .accessibilityRequired:
            showAccessibilityRequired()
            showNotice(PastePilotNotice(
                "Auto paste needs Accessibility permission.".localized,
                style: .warning
            ))
        }
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
            Task { @MainActor in closePopover() }
        case .closePreview:
            closePreview()
        case .keepOpen:
            if forcePreviewClose {
                closePreview()
            }
        }
    }

    func keyboardActions(for item: ClipboardItem) -> [ClipboardAction] {
        ClipboardActionFactory.keyboardActions(
            for: item,
            customActions: settings.customClipboardActions
        )
    }

    func showNotice(_ notice: PastePilotNotice) {
        interactionState.noticeTask?.cancel()
        withAnimation { self.notice = notice }
        interactionState.noticeTask = Task {
            try? await Task.sleep(for: notice.style == .success ? .seconds(1.3) : .seconds(2.4))
            guard !Task.isCancelled else { return }
            withAnimation { self.notice = nil }
        }
    }

    func noticeForegroundStyle(_ style: PastePilotNotice.Style) -> Color {
        switch style {
        case .success:
            .primary
        case .warning:
            .orange
        case .error:
            .red
        }
    }
}
