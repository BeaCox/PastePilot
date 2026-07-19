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
                                preview: {
                                    selectedID = item.id
                                    previewedID = item.id
                                },
                                performAction: performAction,
                                editMetadata: {
                                    beginEditingMetadata(for: item)
                                },
                                copy: {
                                    performAction(ClipboardActionFactory.copyAction(for: item))
                                },
                                togglePinned: {
                                    store.togglePinned(item.id)
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
}

private struct ClipboardMetadataEditor: View {
    @Binding var title: String
    @Binding var note: String
    @Binding var aliases: String
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Details".localized)
                .font(.headline)

            VStack(alignment: .leading, spacing: 5) {
                Text("Title".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Title".localized, text: $title)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Aliases".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Aliases".localized, text: $aliases)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Note".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $note)
                    .font(.body)
                    .frame(minHeight: 90)
                    .scrollContentBackground(.hidden)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Spacer()
                Button("Cancel".localized, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save".localized, action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 360)
    }
}
