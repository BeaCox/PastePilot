import SwiftUI

struct PastePilotView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings
    @State private var searchText = ""
    @State private var selection: UUID?
    @State private var selectedActionID: String?
    @State private var revealSensitive = false
    @State private var notice: String?

    private var filteredItems: [ClipboardItem] {
        guard !searchText.isEmpty else { return store.items }
        return store.items.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
                || $0.kind.localizedTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedItem: ClipboardItem? {
        let id = selection ?? filteredItems.first?.id
        return filteredItems.first { $0.id == id }
    }

    private var pinnedItems: [ClipboardItem] {
        filteredItems.filter(\.isPinned)
    }

    private var recentItems: [ClipboardItem] {
        filteredItems.filter { !$0.isPinned }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 360)
        } detail: {
            if let item = selectedItem {
                detail(for: item)
            } else {
                ContentUnavailableView(
                    searchText.isEmpty
                        ? "No clipboard content yet".localized
                        : "No search results".localized,
                    systemImage: searchText.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "Copy JSON, code, URLs, commands, or errors — PastePilot suggests the next action.".localized
                            : "Try searching by content or type.".localized
                    )
                )
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .background(.regularMaterial)
        .onAppear {
            selection = selection ?? filteredItems.first?.id
        }
        .onChange(of: searchText) {
            selection = filteredItems.first?.id
        }
        .onChange(of: selection) {
            selectedActionID = nil
            revealSensitive = false
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search clipboard history".localized, text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .padding(10)

            List(selection: $selection) {
                if !pinnedItems.isEmpty {
                    Section("Pinned".localized) {
                        historyRows(pinnedItems)
                    }
                }
                Section(!pinnedItems.isEmpty ? "Recent".localized : "") {
                    historyRows(recentItems)
                }
            }
            .listStyle(.sidebar)

            HStack {
                Label("%d items".localized(store.items.count), systemImage: "lock")
                Spacer()
                Button("Clear Unpinned".localized) {
                    store.clearUnpinned()
                    selection = store.items.first?.id
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
        }
        .navigationTitle("PastePilot")
    }

    @ViewBuilder
    private func historyRows(_ items: [ClipboardItem]) -> some View {
        ForEach(items) { item in
            HistoryRow(item: item)
                .tag(item.id)
                .contextMenu {
                    Button(item.isPinned ? "Unpin".localized : "Pin to Top".localized) {
                        store.togglePinned(item.id)
                    }
                    Divider()
                    Button("Delete".localized, role: .destructive) {
                        store.delete(item.id)
                    }
                }
        }
    }

    private func detail(for item: ClipboardItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                recognitionHeader(for: item)
                contentPreview(for: item)
                suggestedActions(for: item)
            }
            .padding(26)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if let notice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 8, y: 3)
                    .padding(.bottom, 12)
            }
        }
        .navigationTitle(item.kind.localizedTitle)
    }

    private func recognitionHeader(for item: ClipboardItem) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 23, weight: .medium))
                .foregroundStyle(item.kind == .error ? Color.red : Color.accentColor)
                .frame(width: 42, height: 42)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text("Recognized as %@".localized(item.kind.localizedTitle))
                    .font(.title2.weight(.semibold))
                Text(item.kind.explanation)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.togglePinned(item.id)
            } label: {
                Label(
                    item.isPinned ? "Unpin".localized : "Pin to Top".localized,
                    systemImage: item.isPinned ? "pin.fill" : "pin"
                )
            }
        }
    }

    private func contentPreview(for item: ClipboardItem) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                if let image = store.image(for: item) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 320)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                } else {
                    ScrollView {
                        Text(previewText(for: item))
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(minHeight: 90, maxHeight: 190)
                }

                if item.containsSensitiveData {
                    Divider()
                    HStack {
                        Label("Sensitive data detected and hidden by default".localized, systemImage: "eye.slash.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Toggle("Reveal".localized, isOn: $revealSensitive)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .font(.caption)
                }
            }
            .padding(4)
        } label: {
            Text("Clipboard Content".localized)
        }
    }

    private func suggestedActions(for item: ClipboardItem) -> some View {
        let actions = ClipboardActionFactory.actions(for: item)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Suggested Actions".localized)
                .font(.headline)
            Text("Click to copy the processed result; links will open instead.".localized)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(actions) { action in
                    ActionRow(
                        action: action,
                        isSelected: selectedActionID == action.id,
                        perform: {
                            selectedActionID = action.id
                            showNotice(ClipboardActionFactory.perform(action, using: store))
                        },
                        preview: {
                            selectedActionID = selectedActionID == action.id ? nil : action.id
                        }
                    )
                    if action.id != actions.last?.id {
                        Divider().padding(.leading, 48)
                    }
                    if selectedActionID == action.id, let preview = action.preview {
                        ResultPreview(content: preview)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 10)
                    }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator.opacity(0.55))
            }
        }
    }

    private func previewText(for item: ClipboardItem) -> String {
        item.containsSensitiveData && !revealSensitive
            ? ContentAnalyzer.redacted(item.content)
            : item.content
    }

    private func showNotice(_ message: String) {
        withAnimation { notice = message }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation { notice = nil }
        }
    }
}

struct MenuBarView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings
    let openHistory: () -> Void
    let openSettings: () -> Void
    let openAbout: () -> Void
    let quit: () -> Void
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var expandedID: UUID?
    @State private var notice: String?
    @State private var needsScrollToSelection = false
    @FocusState private var searchFocused: Bool

    private var filteredItems: [ClipboardItem] {
        let matches = searchText.isEmpty ? store.items : store.items.filter {
            $0.content.localizedCaseInsensitiveContains(searchText)
                || $0.kind.localizedTitle.localizedCaseInsensitiveContains(searchText)
        }
        return ClipboardHistoryOrdering.pinnedFirst(matches)
    }

    private var selectedItem: ClipboardItem? {
        guard let selectedID else { return filteredItems.first }
        return filteredItems.first { $0.id == selectedID } ?? filteredItems.first
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            historyList

            Divider()

            HStack {
                Text("%d items".localized(store.items.count))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Manage All".localized, action: openHistory)
                    .buttonStyle(.plain)
                Menu {
                    Button("Clear Unpinned".localized) {
                        store.clearUnpinned()
                    }
                    Divider()
                    Button("Preferences…".localized, action: openSettings)
                        .keyboardShortcut(",", modifiers: .command)
                    Button("About PastePilot".localized, action: openAbout)
                    Divider()
                    Button("Quit PastePilot".localized, action: quit)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .frame(height: 38)
        }
        .frame(width: 400, height: 450)
        .background(.regularMaterial)
        .onAppear {
            selectFirstItem(expand: true)
            searchFocused = true
        }
        .onChange(of: searchText) {
            selectFirstItem(expand: false)
        }
        .onChange(of: store.items.first?.id) {
            guard searchText.isEmpty else { return }
            selectFirstItem(expand: true)
        }
        .onMoveCommand(perform: moveSelection)
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotMoveUp)) { _ in
            moveSelection(.up)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotMoveDown)) { _ in
            moveSelection(.down)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pastePilotCopyIndex)) { notification in
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
        .onExitCommand {
            if !searchText.isEmpty {
                searchText = ""
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search clipboard history".localized, text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
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
                                store: store,
                                image: store.image(for: item),
                                shortcutNumber: index < 9 ? index + 1 : nil,
                                hoverPreviewEnabled: settings.hoverPreviewEnabled,
                                isSelected: selectedID == item.id,
                                select: { selectedID = item.id },
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
                                    selectFirstItem(expand: false)
                                },
                                showNotice: { showNotice($0) }
                            )
                            .id(item.id)
                        }
                    }
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
        }
    }

    private func selectFirstItem(expand: Bool) {
        selectedID = filteredItems.first?.id
        expandedID = expand ? filteredItems.first?.id : nil
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
        expandedID = selectedID
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
    let store: ClipboardStore
    let image: NSImage?
    let shortcutNumber: Int?
    let hoverPreviewEnabled: Bool
    let isSelected: Bool
    let select: () -> Void
    let copy: () -> Void
    let togglePinned: () -> Void
    let delete: () -> Void
    let showNotice: (String) -> Void
    @State private var showsDetails = false
    @State private var detailTask: Task<Void, Never>?

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 7) {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Circle()
                        .fill(item.kind.accentColor)
                        .frame(width: 6, height: 6)
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

                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }

                if let shortcutNumber {
                    Text("⌘\(shortcutNumber)")
                        .font(.system(size: 11, design: .rounded).weight(.medium))
                        .foregroundStyle(.tertiary)
                } else {
                    Text(item.createdAt, style: .relative)
                        .font(.system(size: 11))
                        .foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in
            if hovering { select() }
            updateDetailPresentation(isHovering: hovering)
        }
        .contextMenu {
            Button("Copy original".localized, action: copy)
            Button(item.isPinned ? "Unpin".localized : "Pin to Top".localized, action: togglePinned)
            Divider()
            Button("Delete".localized, role: .destructive, action: delete)
        }
        .popover(
            isPresented: $showsDetails,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            ClipboardDetailPreview(
                item: item,
                store: store,
                image: image,
                hoverChanged: updatePreviewHover,
                togglePinned: togglePinned,
                delete: delete,
                showNotice: showNotice
            )
        }
        .onDisappear {
            detailTask?.cancel()
        }
    }

    private var summary: String {
        let content = item.containsSensitiveData
            ? ContentAnalyzer.redacted(item.content)
            : item.content
        return content.replacingOccurrences(of: "\n", with: " ")
    }

    private func updateDetailPresentation(isHovering: Bool) {
        detailTask?.cancel()
        guard hoverPreviewEnabled else {
            showsDetails = false
            return
        }
        if isHovering {
            detailTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await MainActor.run { showsDetails = true }
            }
        } else {
            detailTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await MainActor.run { showsDetails = false }
            }
        }
    }

    private func updatePreviewHover(_ isHovering: Bool) {
        detailTask?.cancel()
        if isHovering {
            showsDetails = true
        } else {
            detailTask = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                await MainActor.run { showsDetails = false }
            }
        }
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
                    .foregroundStyle(.quaternary)
            }
            Spacer()
        }
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

private struct ClipboardDetailPreview: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let image: NSImage?
    let hoverChanged: (Bool) -> Void
    let togglePinned: () -> Void
    let delete: () -> Void
    let showNotice: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                sourceIcon
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.sourceAppName ?? "Unknown Source".localized)
                        .font(.callout.weight(.medium))
                    Text(item.sourceBundleIdentifier ?? item.kind.localizedTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Label(item.kind.localizedTitle, systemImage: item.kind.symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 240)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            } else {
                ScrollView {
                    Text(previewContent)
                        .font(.system(.caption, design: previewFontDesign))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(minHeight: 50, maxHeight: 160)
            }

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
            }

            Divider()

            actionButtons
        }
        .padding(14)
        .frame(width: 340)
        .onHover(perform: hoverChanged)
    }

    @ViewBuilder
    private var actionButtons: some View {
        let actions = ClipboardActionFactory.actions(for: item)
        VStack(spacing: 4) {
            ForEach(actions) { action in
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PreviewActionButtonStyle())
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 8) {
                Button {
                    togglePinned()
                } label: {
                    Label(
                        item.isPinned ? "Unpin".localized : "Pin to Top".localized,
                        systemImage: item.isPinned ? "pin.slash" : "pin"
                    )
                    .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button(role: .destructive) {
                    delete()
                } label: {
                    Label("Delete".localized, systemImage: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red.opacity(0.7))
            }
            .padding(.horizontal, 4)
        }
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

    private var previewContent: String {
        item.containsSensitiveData
            ? ContentAnalyzer.redacted(item.content)
            : item.content
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

private struct HistoryRow: View {
    let item: ClipboardItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(item.kind == .error ? .red : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(item.kind.localizedTitle)
                        .font(.callout.weight(.medium))
                    if item.containsSensitiveData {
                        Image(systemName: "eye.slash.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.tint)
                    }
                }
                Text(item.containsSensitiveData ? ContentAnalyzer.redacted(item.content) : item.content)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ActionRow: View {
    let action: ClipboardAction
    let isSelected: Bool
    let perform: () -> Void
    let preview: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: action.symbol)
                .font(.system(size: 16))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .fontWeight(.medium)
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if action.preview != nil {
                Button(isSelected ? "Hide Preview".localized : "Preview".localized, action: preview)
                    .buttonStyle(.borderless)
            }
            if action.id == "copy" {
                Button("Copy".localized, action: perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button(action.id == "open-url" ? "Open".localized : "Copy".localized, action: perform)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(12)
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
