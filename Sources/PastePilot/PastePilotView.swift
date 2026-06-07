import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void
    let openAbout: () -> Void
    let quit: () -> Void
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
        .background(.regularMaterial)
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
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotMoveUp)) { _ in
            moveSelection(.up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotMoveDown)) { _ in
            moveSelection(.down)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotTogglePreview)) { _ in
            togglePreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotCopyIndex)) { notification in
            copyItem(at: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotTogglePinned)) { _ in
            guard let item = selectedItem else { return }
            store.togglePinned(item.id)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotDeleteItem)) { _ in
            guard let item = selectedItem else { return }
            store.delete(item.id)
            selectFirstItem()
        }
    }

    private var footer: some View {
        HStack {
            Text("%d items".localized(store.items.count))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                Text("↩ \("Copy".localized)")
                Text("␣ \("Preview".localized)")
                Text("⌘P \("Pin".localized)")
                Text("⌘⌫ \("Delete".localized)")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            Menu {
                Button("Clear Unpinned".localized) {
                    showsClearConfirmation = true
                }
                Divider()
                Button("Preferences…".localized, action: openSettings)
                    .keyboardShortcut(",", modifiers: .command)
                Button("About PastePilot".localized, action: openAbout)
                    .keyboardShortcut("a", modifiers: [.command, .option])
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
                                copy: {
                                    showNotice(
                                        ClipboardActionFactory.perform(
                                            ClipboardActionFactory.copyAction(for: item),
                                            using: store
                                        )
                                    )
                                },
                                togglePinned: {
                                    store.togglePinned(item.id)
                                },
                                delete: {
                                    store.delete(item.id)
                                    selectFirstItem()
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(.trailing, 6)
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
                StablePopover(isPresented: previewedItem != nil) {
                    if let item = previewedItem {
                        ClipboardDetailPreview(
                            item: item,
                            store: store,
                            image: store.image(for: item),
                            showNotice: { showNotice($0) },
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
        }
    }

    private func copyItem(at notification: Notification) {
        guard let number = notification.object as? Int,
              filteredItems.indices.contains(number - 1) else {
            return
        }
        let item = filteredItems[number - 1]
        showNotice(
            ClipboardActionFactory.perform(
                ClipboardActionFactory.copyAction(for: item),
                using: store
            )
        )
    }

    private func clearUnpinnedHistory() {
        store.clearUnpinned()
        closePreview()
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
        guard let action = ClipboardActionFactory.actions(for: item).first else { return }
        showNotice(ClipboardActionFactory.perform(action, using: store))
    }

    private func showNotice(_ message: String) {
        withAnimation { notice = message }
        Task {
            try? await Task.sleep(for: .seconds(1.3))
            withAnimation { notice = nil }
        }
    }
}

private struct CompactHistoryItem: View {
    let item: ClipboardItem
    let image: NSImage?
    let shortcutNumber: Int?
    let isSelected: Bool
    let select: () -> Void
    let hoverChanged: (Bool) -> Void
    let preview: () -> Void
    let copy: () -> Void
    let togglePinned: () -> Void
    let delete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            Button(action: copy) {
                HStack(spacing: 7) {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 22, height: 22)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    } else {
                        ContentKindBadge(kind: item.kind, size: 22)
                    }

                    Text(summary)
                        .font(.system(size: 13, design: item.kind == .text ? .default : .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if item.containsSensitiveData {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if !showsActions, let shortcutNumber {
                        Text("⌘\(shortcutNumber)")
                            .font(.system(size: 11, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    } else if !showsActions {
                        Text(item.createdAt, style: .relative)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary.opacity(0.8))
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.kind.localizedTitle), \(summary)")
            .accessibilityHint("Copies the original clipboard content.".localized)

            if showsActions {
                RowIconButton(
                    symbol: item.isPinned ? "pin.fill" : "pin",
                    label: item.isPinned ? "Unpin".localized : "Pin to Top".localized,
                    isActive: item.isPinned,
                    action: togglePinned
                )
                RowIconButton(
                    symbol: "trash",
                    label: "Delete".localized,
                    isDestructive: true,
                    action: delete
                )
            } else if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)
                    .accessibilityLabel("Pinned".localized)
            }
        }
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovering = hovering
            }
            if hovering { select() }
            hoverChanged(hovering)
        }
        .contextMenu {
            Button("Copy original".localized, action: copy)
            Button("Preview".localized, action: preview)
            if !item.fileURLs.isEmpty {
                Button("Quick Look".localized) {
                    _ = QuickLookService.shared.preview(item.fileURLs)
                }
                Button("Show in Finder".localized) {
                    NSWorkspace.shared.activateFileViewerSelecting(item.fileURLs)
                }
            }
            Button(item.isPinned ? "Unpin".localized : "Pin to Top".localized, action: togglePinned)
            Divider()
            Button("Delete".localized, role: .destructive, action: delete)
        }
    }

    private var summary: String {
        let content = item.containsSensitiveData
            ? ContentAnalyzer.redacted(item.content)
            : item.content
        return content.replacingOccurrences(of: "\n", with: " ")
    }

    private var showsActions: Bool {
        isHovering || isSelected
    }
}

private struct RowIconButton: View {
    let symbol: String
    let label: String
    var isActive = false
    var isDestructive = false
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foregroundColor)
        .background(
            isHovering ? Color.primary.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering in
            isHovering = hovering
        }
    }

    private var foregroundColor: Color {
        if isDestructive && isHovering {
            return .red
        }
        if isActive {
            return .accentColor
        }
        return .secondary
    }
}

private struct HistorySectionHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(.caption2, weight: .medium))
                .textCase(.uppercase)
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

private struct ClipboardDetailPreview: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let image: NSImage?
    let showNotice: (String) -> Void
    let hoverChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                sourceIcon
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.sourceAppName ?? "Unknown Source".localized)
                        .font(.callout.weight(.medium))
                    Text(item.sourceBundleIdentifier ?? "")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 4) {
                    ContentKindBadge(kind: item.kind, size: 16)
                    Text(item.kind.localizedTitle)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            }
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if item.kind == .file {
                        FileListPreview(urls: item.fileURLs)
                            .frame(minHeight: 60, maxHeight: 220)
                    } else if item.kind == .richText {
                        RichTextPreview(item: item)
                            .frame(minHeight: 80, maxHeight: 180)
                    } else if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        ScrollView {
                            Text(previewContent)
                                .font(.system(.caption, design: previewFontDesign))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .frame(minHeight: 50, maxHeight: 160)
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                HStack {
                    Label {
                        Text(item.createdAt, format: .dateTime.year().month().day().hour().minute())
                    } icon: {
                        Image(systemName: "clock")
                    }
                    Spacer()
                    if item.isImage {
                        Text(imageDimensions)
                        Text("·")
                        Text(byteCount)
                    } else {
                        Text("%d characters".localized(item.content.count))
                        Text("·")
                        Text("%d lines".localized(lineCount))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                if item.containsSensitiveData {
                    Label("Sensitive content hidden".localized, systemImage: "eye.slash.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.top, 6)
                }

                if item.isImage, item.imageSourceURL != nil || item.imageOriginalPath != nil {
                    VStack(alignment: .leading, spacing: 3) {
                        if let sourceURL = item.imageSourceURL {
                            Label(sourceURL, systemImage: "link")
                                .lineLimit(1)
                        }
                        if let originalPath = item.imageOriginalPath {
                            Label(originalPath, systemImage: "folder")
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 6)
                }

                if let ocrText = item.ocrText, !ocrText.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Recognized Text".localized, systemImage: "text.viewfinder")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(ocrText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 12)

            actionButtons
        }
        .padding(16)
        .frame(width: 340, alignment: .topLeading)
        .onHover(perform: hoverChanged)
    }

    @ViewBuilder
    private var actionButtons: some View {
        let actions = [ClipboardActionFactory.copyAction(for: item)]
            + ClipboardActionFactory.compactActions(for: item)
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    showNotice(ClipboardActionFactory.perform(action, using: store))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(action.title)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PreviewActionButtonStyle())
                if index < actions.count - 1 {
                    Divider().padding(.leading, 34)
                }
            }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var sourceIcon: some View {
        if let icon = applicationIcon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app.dashed")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
        }
    }

    private var applicationIcon: NSImage? {
        guard let bundleIdentifier = item.sourceBundleIdentifier,
              let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: bundleIdentifier
              ) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: applicationURL.path)
    }

    private var previewContent: AttributedString {
        if item.containsSensitiveData {
            return AttributedString(ContentAnalyzer.redacted(item.content))
        }
        if item.kind == .json,
           let formatted = ContentTransformer.formatJSON(item.content) {
            return JSONSyntaxHighlighter.highlight(formatted)
        }
        return AttributedString(item.content)
    }

    private var previewFontDesign: Font.Design {
        item.kind == .text || item.kind == .markdown ? .default : .monospaced
    }

    private var lineCount: Int {
        item.content.components(separatedBy: .newlines).count
    }

    private var imageDimensions: String {
        guard let width = item.imageWidth, let height = item.imageHeight else {
            return "Unknown size".localized
        }
        return "\(width) × \(height)"
    }

    private var byteCount: String {
        ByteCountFormatter.string(
            fromByteCount: Int64(item.imageByteCount ?? 0),
            countStyle: .file
        )
    }
}

private struct PreviewActionButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isHovering || configuration.isPressed ? Color.primary : Color.primary.opacity(0.8))
            .background(
                isHovering || configuration.isPressed
                    ? Color.primary.opacity(0.08)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.08)) {
                    isHovering = hovering
                }
            }
    }
}

private struct ContentKindBadge: View {
    let kind: ContentKind
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(kind.accentColor)
            .frame(width: size, height: size)
            .background(kind.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.24))
            .accessibilityHidden(true)
    }
}

private struct FileDropOverlay: View {
    let isTargeted: Bool

    var body: some View {
        if isTargeted {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 2, dash: [7, 5])
                    )
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop files to add them to PastePilot".localized)
                        .font(.headline)
                }
            }
            .padding(8)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }
}

private struct FileListPreview: View {
    let urls: [URL]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(urls, id: \.path) { url in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.lastPathComponent)
                                .lineLimit(1)
                            Text(fileDetail(for: url))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    if url != urls.last {
                        Divider().padding(.leading, 48)
                    }
                }
            }
        }
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fileDetail(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .fileSizeKey,
            .contentTypeKey
        ])
        if values?.isDirectory == true {
            return "Folder".localized
        }
        let type = values?.contentType?.localizedDescription
            ?? url.pathExtension.uppercased()
        guard let size = values?.fileSize else { return type }
        let formattedSize = ByteCountFormatter.string(
            fromByteCount: Int64(size),
            countStyle: .file
        )
        return "\(type) · \(formattedSize)"
    }
}

private struct RichTextPreview: NSViewRepresentable {
    let item: ClipboardItem

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedString)
    }

    private var attributedString: NSAttributedString {
        if let base64 = item.richTextRTFBase64,
           let data = Data(base64Encoded: base64),
           let value = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return value
        }
        if let html = item.richTextHTML,
           let data = html.data(using: .utf8),
           let value = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.html],
               documentAttributes: nil
           ) {
            return value
        }
        return NSAttributedString(string: item.content)
    }
}

private enum JSONSyntaxHighlighter {
    static func highlight(_ source: String) -> AttributedString {
        var result = AttributedString(source)
        result.foregroundColor = .primary
        apply(#""(?:\\.|[^"\\])*""#, color: .green, to: &result, source: source)
        apply(#""(?:\\.|[^"\\])*"(?=\s*:)"#, color: .blue, to: &result, source: source)
        apply(#"\b(?:true|false|null)\b"#, color: .purple, to: &result, source: source)
        apply(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, color: .orange, to: &result, source: source)
        return result
    }

    private static func apply(
        _ pattern: String,
        color: Color,
        to result: inout AttributedString,
        source: String
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let fullRange = NSRange(source.startIndex..., in: source)
        for match in regex.matches(in: source, range: fullRange) {
            guard let sourceRange = Range(match.range, in: source),
                  let lower = AttributedString.Index(sourceRange.lowerBound, within: result),
                  let upper = AttributedString.Index(sourceRange.upperBound, within: result) else {
                continue
            }
            result[lower..<upper].foregroundColor = color
        }
    }
}

private struct StablePopover<Content: View>: NSViewRepresentable {
    let isPresented: Bool
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let coordinator = context.coordinator
        if isPresented {
            if coordinator.popover == nil {
                let popover = NSPopover()
                popover.behavior = .applicationDefined
                popover.animates = true
                coordinator.popover = popover
            }
            if let hosting = coordinator.hosting {
                hosting.rootView = content()
            } else {
                let hosting = NSHostingController(rootView: content())
                coordinator.hosting = hosting
                coordinator.popover?.contentViewController = hosting
            }
            if !(coordinator.popover?.isShown ?? false), nsView.window != nil {
                coordinator.popover?.show(
                    relativeTo: nsView.bounds, of: nsView, preferredEdge: .maxX
                )
            }
        } else {
            coordinator.popover?.close()
            coordinator.popover = nil
            coordinator.hosting = nil
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.popover?.close()
        coordinator.popover = nil
        coordinator.hosting = nil
    }

    class Coordinator {
        var popover: NSPopover?
        var hosting: NSHostingController<Content>?
    }
}

private struct ResultPreview: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Result Preview".localized)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 130)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
    }
}
