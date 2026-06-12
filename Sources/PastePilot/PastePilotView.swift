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
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var previewedID: UUID?
    @State private var notice: String?
    @State private var needsScrollToSelection = false
    @State private var showsClearConfirmation = false
    @State private var previewTask: Task<Void, Never>?
    @State private var closePreviewTask: Task<Void, Never>?
    @State private var isFileDropTargeted = false
    @State private var historyItemFrames: [UUID: CGRect] = [:]
    @FocusState private var searchFocused: Bool

    private var filteredItems: [ClipboardItem] {
        let matches = searchText.isEmpty ? store.items : store.items.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
                || $0.kind.localizedTitle.localizedCaseInsensitiveContains(searchText)
                || ($0.ocrText?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        return ClipboardHistoryOrdering.pinnedFirst(matches)
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedID else { return filteredItems.first }
        return filteredItems.first { $0.id == selectedID } ?? filteredItems.first
    }

    private var previewedItem: ClipboardItem? {
        guard let previewedID else { return nil }
        return store.items.first { $0.id == previewedID }
    }

    private var listPreferredHeight: CGFloat {
        guard !filteredItems.isEmpty else { return 250 }
        let sectionCount = (filteredItems.contains(where: \.isPinned) ? 1 : 0)
            + (filteredItems.contains(where: { !$0.isPinned }) ? 1 : 0)
        return min(450, max(190, 82 + CGFloat(sectionCount * 22) + CGFloat(filteredItems.count * 34)))
    }

    private var preferredSize: CGSize {
        CGSize(width: 400, height: listPreferredHeight)
    }

    var body: some View {
        notificationHandlingPanel
            .onExitCommand(perform: handleExitCommand)
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            historyList
            Divider()
            footer
        }
        .frame(width: preferredSize.width, height: preferredSize.height)
    }

    private var dropHandlingPanel: some View {
        panelContent
        .dropDestination(for: URL.self) { urls, _ in
            store.importFiles(urls)
            return !urls.isEmpty
        } isTargeted: { targeted in
            withAnimation(.easeOut(duration: 0.12)) {
                isFileDropTargeted = targeted
            }
        }
        .overlay {
            FileDropOverlay(isTargeted: isFileDropTargeted)
        }
    }

    private var stateHandlingPanel: some View {
        dropHandlingPanel
        .onHover(perform: handlePanelHover)
        .onAppear {
            handleAppear()
        }
        .onChange(of: searchText) {
            handleSearchChange()
        }
        .onChange(of: store.items.first?.id) {
            handleFirstItemChange()
        }
        .onChange(of: filteredItems.count) {
            handleFilteredCountChange()
        }
        .onChange(of: selectedID) {
            handleSelectionChange()
        }
    }

    private var notificationHandlingPanel: some View {
        stateHandlingPanel
        .onMoveCommand(perform: moveSelection)
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotKeyboardCommand)) { notification in
            guard let command = notification.object as? PopoverKeyboardCommand else { return }
            performKeyboardCommand(command)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotCopyIndex)) { notification in
            copyItem(at: notification)
        }
    }

    private var footer: some View {
        HStack {
            Text("%d items".localized(store.items.count))
                .foregroundStyle(.secondary)
            Spacer()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text("↩ \("Copy".localized)")
                    Text("␣ \("Preview".localized)")
                    Text("⌥1-9 \("Actions".localized)")
                    Text("⌘P \("Pin".localized)")
                    Text("⌘F \("Search".localized)")
                }
                HStack(spacing: 6) {
                    Text("↩ \("Copy".localized)")
                    Text("␣ \("Preview".localized)")
                    Text("⌥1-9 \("Actions".localized)")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Menu {
                Button("Clear Unpinned".localized) {
                    showsClearConfirmation = true
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                Divider()
                Button("Preferences…".localized, action: openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Button("About PastePilot".localized, action: openAbout)
                    .keyboardShortcut("a", modifiers: [.command, .option])
                Button("Check for Updates…".localized, action: checkForUpdates)
                Divider()
                Button("Quit PastePilot".localized, action: quit)
                    .keyboardShortcut("q", modifiers: .command)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("More Options".localized)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .confirmationDialog(
            "Clear Unpinned History?".localized,
            isPresented: $showsClearConfirmation
        ) {
            Button("Clear Unpinned".localized, role: .destructive) {
                clearUnpinnedHistory()
            }
        } message: {
            Text("Pinned items will be kept. This action cannot be undone.".localized)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history".localized, text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search clipboard history".localized)
                .onSubmit {
                    guard let item = selectedItem else { return }
                    performPrimaryAction(for: item)
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel("Clear Search".localized)
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
    }

    @ViewBuilder
    private var historyList: some View {
        if filteredItems.isEmpty {
            ContentUnavailableView(
                store.items.isEmpty
                    ? "Waiting for content".localized
                    : "No search results".localized,
                systemImage: store.items.isEmpty ? "clipboard" : "magnifyingglass",
                description: Text(
                    store.items.isEmpty
                        ? "Copied content will appear here automatically.".localized
                        : "Try searching for other content or types.".localized
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                            if shouldShowPinnedHeader(at: index) {
                                HistorySectionHeader(
                                    title: "Pinned".localized,
                                    detail: "Always on top, kept when history is cleared".localized
                                )
                            } else if shouldShowRecentHeader(at: index) {
                                HistorySectionHeader(
                                    title: "Recent".localized,
                                    detail: nil
                                )
                            }
                            CompactHistoryItem(
                                item: item,
                                image: store.image(for: item),
                                shortcutNumber: index < 9 ? index + 1 : nil,
                                isSelected: selectedID == item.id,
                                select: { selectedID = item.id },
                                hoverChanged: { hovering in
                                    handleRowHover(item, hovering: hovering)
                                },
                                preview: {
                                    selectedID = item.id
                                    previewedID = item.id
                                },
                                performAction: performAction,
                                copy: {
                                    performAction(ClipboardActionFactory.copyAction(for: item))
                                },
                                togglePinned: {
                                    store.togglePinned(item.id)
                                },
                                delete: {
                                    store.delete(item.id)
                                    selectFirstItem()
                                }
                            )
                            .background {
                                GeometryReader { geometry in
                                    Color.clear.preference(
                                        key: HistoryItemFramePreferenceKey.self,
                                        value: [
                                            item.id: geometry.frame(
                                                in: .named(HistoryListCoordinateSpace.name)
                                            )
                                        ]
                                    )
                                }
                            }
                            .id(item.id)
                        }
                    }
                    .padding(.trailing, 6)
                }
                .coordinateSpace(name: HistoryListCoordinateSpace.name)
                .onPreferenceChange(HistoryItemFramePreferenceKey.self) {
                    historyItemFrames = $0
                }
                .onChange(of: selectedID) {
                    guard needsScrollToSelection, let selectedID else { return }
                    needsScrollToSelection = false
                    withAnimation {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 6, y: 2)
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(
                StablePopover(
                    isPresented: previewedItem != nil,
                    anchorRect: previewedID.flatMap { historyItemFrames[$0] }
                ) {
                    if let item = previewedItem {
                        ClipboardDetailPreview(
                            item: item,
                            image: store.image(for: item),
                            performAction: performAction,
                            hoverChanged: handlePreviewHover
                        )
                    }
                }
            )
        }
    }

    private func selectFirstItem() {
        selectedID = filteredItems.first?.id
    }

    private func handleAppear() {
        selectFirstItem()
        searchFocused = true
        resize(preferredSize)
    }

    private func handlePanelHover(_ hovering: Bool) {
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

    private func handleSearchChange() {
        selectFirstItem()
        resize(preferredSize)
    }

    private func handleFirstItemChange() {
        guard searchText.isEmpty else { return }
        selectFirstItem()
        resize(preferredSize)
    }

    private func handleFilteredCountChange() {
        if let previewedID,
           !store.items.contains(where: { $0.id == previewedID }) {
            closePreview()
        }
        resize(preferredSize)
    }

    private func handleSelectionChange() {
        if previewedItem != nil {
            previewedID = selectedID
        }
    }

    private func handleExitCommand() {
        if previewedItem != nil {
            closePreview()
        } else if !searchText.isEmpty {
            searchText = ""
        } else {
            closePopover()
        }
    }

    private func copyItem(at notification: Notification) {
        guard let number = notification.object as? Int,
              filteredItems.indices.contains(number - 1) else {
            return
        }
        let item = filteredItems[number - 1]
        performAction(ClipboardActionFactory.copyAction(for: item))
    }

    private func clearUnpinnedHistory() {
        store.clearUnpinned()
        closePreview()
        selectFirstItem()
    }

    private func performKeyboardCommand(_ command: PopoverKeyboardCommand) {
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
        }
    }

    private func toggleSelectedPinned() {
        guard let item = selectedItem else { return }
        store.togglePinned(item.id)
    }

    private func deleteSelectedItem() {
        guard let item = selectedItem else { return }
        store.delete(item.id)
        selectFirstItem()
    }

    private func shouldShowPinnedHeader(at index: Int) -> Bool {
        index == 0
            && filteredItems.first?.isPinned == true
    }

    private func shouldShowRecentHeader(at index: Int) -> Bool {
        guard index < filteredItems.count,
              !filteredItems[index].isPinned else {
            return false
        }
        return index == 0 || filteredItems[index - 1].isPinned
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
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

    private func handleRowHover(_ item: ClipboardItem, hovering: Bool) {
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

    private func handlePreviewHover(_ hovering: Bool) {
        closePreviewTask?.cancel()
        if !hovering {
            schedulePreviewClose()
        }
    }

    private func schedulePreviewClose() {
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

    private func togglePreview() {
        if previewedItem != nil {
            closePreview()
        } else {
            previewedID = selectedItem?.id
        }
    }

    private func closePreview() {
        previewTask?.cancel()
        previewedID = nil
    }

    private func performPrimaryAction(for item: ClipboardItem) {
        let action = ClipboardActionFactory.copyAction(for: item)
        performAction(action)
    }

    private func performAction(at oneBasedIndex: Int) {
        guard let item = selectedItem else { return }
        let actions = keyboardActions(for: item)
        guard actions.indices.contains(oneBasedIndex - 1) else { return }
        let action = actions[oneBasedIndex - 1]
        performAction(action)
    }

    private func performAction(_ action: ClipboardAction) {
        if action.closesInlinePreview {
            closePreview()
        }
        showNotice(ClipboardActionFactory.perform(action, using: store))
    }

    private func keyboardActions(for item: ClipboardItem) -> [ClipboardAction] {
        let copyAction = ClipboardActionFactory.copyAction(for: item)
        return [copyAction] + ClipboardActionFactory.actions(for: item).filter {
            $0.id != copyAction.id
        }
    }

    private func showNotice(_ message: String) {
        withAnimation { notice = message }
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation { notice = nil }
        }
    }
}
