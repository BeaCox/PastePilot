import SwiftUI

extension MenuBarView {
    var panelContent: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            historyList
            Divider()
            footer
        }
        .frame(width: preferredSize.width, height: preferredSize.height)
    }

    var stateHandlingPanel: some View {
        panelContent
        .onHover(perform: handlePanelHover)
        .onAppear {
            handleAppear()
        }
        .onDisappear {
            handleDisappear()
        }
        .onChange(of: searchText) {
            handleSearchChange()
        }
        .onChange(of: store.items.first?.id) {
            handleFirstItemChange()
        }
        .onChange(of: store.items.map(\.id)) {
            pasteStack.retain(availableIDs: Set(store.items.map(\.id)))
        }
        .onChange(of: filteredItems.count) {
            handleFilteredCountChange()
        }
        .onChange(of: selectedID) {
            handleSelectionChange()
        }
        .onChange(of: showsClearConfirmation) {
            if !showsClearConfirmation {
                previewClosesInstantly = false
            }
        }
        .sheet(isPresented: metadataEditorPresented) {
            ClipboardMetadataEditor(
                item: editingMetadataItem,
                title: $metadataTitle,
                note: $metadataNote,
                aliases: $metadataAliases,
                save: saveMetadataEdit,
                cancel: cancelMetadataEdit
            )
        }
    }

    var notificationHandlingPanel: some View {
        stateHandlingPanel
        .onMoveCommand(perform: moveSelection)
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotKeyboardCommand)) { notification in
            guard let command = notification.object as? PopoverKeyboardCommand else { return }
            performKeyboardCommand(command)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotCopyIndex)) { notification in
            copyItem(at: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotNotice)) { notification in
            guard let notice = notification.object as? PastePilotNotice else { return }
            showNotice(notice)
        }
    }

    var footer: some View {
        HStack {
            Text("%d items".localized(store.items.count))
                .foregroundStyle(.secondary)
            if pasteStack.count > 0 || pasteStack.isPasting {
                pasteStackMenu
            }
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
                Button(
                    settings.monitoringEnabled
                        ? "Pause Capture".localized
                        : "Resume Capture".localized
                ) {
                    settings.monitoringEnabled.toggle()
                }
                Button("Ignore Next Copy".localized) {
                    store.ignoreNextCopy()
                }
                if store.hasProtectedItems {
                    Button(
                        store.hasLockedProtectedItems
                            ? "Unlock Protected Items".localized
                            : "Lock Protected Items".localized
                    ) {
                        if store.hasLockedProtectedItems {
                            Task { await store.unlockProtectedHistory() }
                        } else {
                            store.lockProtectedHistory()
                        }
                    }
                }
                Divider()
                Button("Clear Unpinned".localized) {
                    beginClearUnpinnedConfirmation()
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

    var pasteStackMenu: some View {
        Menu {
            if pasteStack.isPasting {
                Text(
                    "Pasted %d of %d".localized(
                        pasteStack.completedItemCount,
                        pasteStack.count
                    )
                )
                Button("Cancel Paste Stack".localized, action: cancelPasteStack)
            } else {
                Button(
                    "Paste %d Items in Order".localized(pasteStack.count),
                    action: startPasteStack
                )
                Divider()
                Button("Clear Paste Stack".localized) {
                    pasteStack.clear()
                }
            }
        } label: {
            Label(
                pasteStack.isPasting
                    ? "Pasting %d/%d".localized(
                        pasteStack.completedItemCount,
                        pasteStack.count
                    )
                    : "%d queued".localized(pasteStack.count),
                systemImage: "square.stack.3d.up"
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Paste Stack".localized)
    }

    var searchBar: some View {
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
    var historyList: some View {
        let items = filteredItems
        if items.isEmpty {
            ContentUnavailableView(
                emptyStateTitle,
                systemImage: emptyStateSystemImage,
                description: Text(
                    emptyStateDescription
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            if shouldShowPinnedHeader(at: index, in: items) {
                                HistorySectionHeader(
                                    title: "Pinned".localized,
                                    detail: "Always on top, kept when history is cleared".localized
                                )
                            } else if shouldShowRecentHeader(at: index, in: items) {
                                HistorySectionHeader(
                                    title: "Recent".localized,
                                    detail: nil
                                )
                            }
                            CompactHistoryItem(
                                item: item,
                                image: store.thumbnail(for: item),
                                userSensitivePatterns: settings.userSensitivePatterns,
                                shortcutNumber: index < 9 ? index + 1 : nil,
                                isSelected: selectedID == item.id,
                                pasteStackPosition: pasteStack.position(of: item.id),
                                select: { selectedID = item.id },
                                hoverChanged: { hovering in
                                    handleRowHover(item, hovering: hovering)
                                },
                                editMetadata: {
                                    beginEditingMetadata(for: item)
                                },
                                copy: {
                                    if item.protectionState == .locked {
                                        Task { await store.unlockProtectedHistory() }
                                    } else {
                                        performAction(
                                            ClipboardActionFactory.copyAction(for: item)
                                        )
                                    }
                                },
                                togglePinned: {
                                    store.togglePinned(item.id)
                                },
                                toggleProtection: {
                                    Task {
                                        switch item.protectionState {
                                        case .locked:
                                            await store.unlockProtectedHistory()
                                        case .unlocked:
                                            await store.removeProtection(item.id)
                                        case nil:
                                            await store.protect(item.id)
                                        }
                                    }
                                },
                                togglePasteStack: {
                                    togglePasteStackItem(item)
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
                    Label(notice.message, systemImage: notice.systemImage)
                        .font(.caption)
                        .foregroundStyle(noticeForegroundStyle(notice.style))
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
                    anchorRect: previewedID.flatMap { historyItemFrames[$0] },
                    instantClose: previewClosesInstantly,
                    animationEnabled: settings.previewAnimationEnabled
                ) {
                    if let item = previewedItem {
                        ClipboardDetailPreview(
                            item: item,
                            image: store.image(for: item),
                            customActions: settings.customClipboardActions,
                            performAction: performAction,
                            hoverChanged: handlePreviewHover,
                            previewSnippet: store.previewSnippet
                        )
                    }
                }
            )
        }
    }

    private var emptyStateTitle: String {
        emptyState.title
    }

    private var emptyStateSystemImage: String {
        emptyState.systemImage
    }

    private var emptyStateDescription: String {
        emptyState.description
    }

    private var emptyState: MenuBarPopoverEmptyState {
        MenuBarPopoverState.emptyState(
            itemCount: store.items.count,
            isSearching: interactionState.fullTextSearch.isSearching
        )
    }

    private var metadataEditorPresented: Binding<Bool> {
        Binding(
            get: {
                editingMetadataItemID != nil
            },
            set: { isPresented in
                if !isPresented {
                    cancelMetadataEdit()
                }
            }
        )
    }

    private var editingMetadataItem: ClipboardItem? {
        guard let editingMetadataItemID else { return nil }
        return store.items.first { $0.id == editingMetadataItemID }
    }
}

private struct ClipboardMetadataEditor: View {
    let item: ClipboardItem?
    @Binding var title: String
    @Binding var note: String
    @Binding var aliases: String
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                if item?.isProtected == true {
                    Label(
                        "Titles, notes, and aliases stay visible and searchable while protected. Keep secrets in the content itself.".localized,
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                MetadataEditorField(title: "Title".localized, symbol: "textformat") {
                    TextField("Title".localized, text: $title)
                        .metadataEditorControl()
                }

                MetadataEditorField(title: "Aliases".localized, symbol: "tag") {
                    TextField("Aliases".localized, text: $aliases)
                        .metadataEditorControl()
                }

                MetadataEditorField(title: "Note".localized, symbol: "note.text") {
                    TextEditor(text: $note)
                        .font(.body)
                        .frame(minHeight: 92)
                        .scrollContentBackground(.hidden)
                        .padding(5)
                        .background(
                            Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(.quaternary, lineWidth: 0.5)
                        }
                }
            }
            .padding(14)
            .background(
                .quaternary.opacity(0.4),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
            .padding(18)

            Divider()

            HStack(spacing: 8) {
                Spacer()
                Button("Cancel".localized, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save".localized, action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
            .padding(.horizontal, 18)
            .frame(height: 52)
        }
        .frame(width: MenuBarPopoverState.preferredWidth)
    }

    private var editorHeader: some View {
        HStack(spacing: 10) {
            if let item {
                ContentKindBadge(kind: item.kind, size: 32)
            } else {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Edit Details".localized)
                    .font(.headline)

                if let item {
                    HStack(spacing: 4) {
                        Text(item.sourceAppName ?? "Unknown Source".localized)
                        Text("·")
                        Text(item.kind.localizedTitle)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }

            Spacer()

            if let item {
                Label {
                    Text(item.createdAt, style: .relative)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct MetadataEditorField<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content
        }
    }
}

private extension View {
    func metadataEditorControl() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                Color.primary.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            }
    }
}
