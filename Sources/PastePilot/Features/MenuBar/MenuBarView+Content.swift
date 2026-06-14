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
    }

    var footer: some View {
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
                    anchorRect: previewedID.flatMap { historyItemFrames[$0] },
                    instantClose: previewClosesInstantly,
                    animationEnabled: settings.previewAnimationEnabled
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
}
