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
                    searchText.isEmpty ? "还没有剪贴板内容" : "没有搜索结果",
                    systemImage: searchText.isEmpty ? "clipboard" : "magnifyingglass",
                    description: Text(
                        searchText.isEmpty
                            ? "复制 JSON、代码、链接、命令或报错，PastePilot 会给出下一步操作。"
                            : "尝试搜索内容或类型。"
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
                TextField("搜索剪贴板历史", text: $searchText)
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
                    Section("已固定") {
                        historyRows(pinnedItems)
                    }
                }
                Section(!pinnedItems.isEmpty ? "最近项目" : "") {
                    historyRows(recentItems)
                }
            }
            .listStyle(.sidebar)

            HStack {
                Label("\(store.items.count) 条记录", systemImage: "lock")
                Spacer()
                Button("清除未固定记录") {
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
                    Button(item.isPinned ? "取消置顶" : "固定到顶部") {
                        store.togglePinned(item.id)
                    }
                    Divider()
                    Button("删除", role: .destructive) {
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
                Text("已识别为\(item.kind.localizedTitle)")
                    .font(.title2.weight(.semibold))
                Text(item.kind.explanation)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.togglePinned(item.id)
            } label: {
                Label(
                    item.isPinned ? "取消置顶" : "固定到顶部",
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
                        Label("检测到敏感信息，默认已隐藏", systemImage: "eye.slash.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Toggle("显示原文", isOn: $revealSensitive)
                            .toggleStyle(.switch)
                            .controlSize(.small)
                    }
                    .font(.caption)
                }
            }
            .padding(4)
        } label: {
            Text("剪贴板内容")
        }
    }

    private func suggestedActions(for item: ClipboardItem) -> some View {
        let actions = ClipboardActionFactory.actions(for: item)
        return VStack(alignment: .leading, spacing: 10) {
            Text("建议操作")
                .font(.headline)
            Text("点击后会将处理结果复制到剪贴板；打开链接除外。")
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
                Text("\(store.items.count) 条记录")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("管理全部记录", action: openHistory)
                    .buttonStyle(.plain)
                Menu {
                    Button("清除未固定记录") {
                        store.clearUnpinned()
                    }
                    Divider()
                    Button("偏好设置…", action: openSettings)
                        .keyboardShortcut(",", modifiers: .command)
                    Button("关于 PastePilot", action: openAbout)
                    Divider()
                    Button("退出 PastePilot", action: quit)
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
            TextField("搜索剪贴板历史", text: $searchText)
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
                store.items.isEmpty ? "等待复制内容" : "没有搜索结果",
                systemImage: store.items.isEmpty ? "clipboard" : "magnifyingglass",
                description: Text(
                    store.items.isEmpty
                        ? "复制内容后会自动出现在这里。"
                        : "尝试搜索其他内容或类型。"
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
                                    title: "已固定",
                                    detail: "始终置顶，清理历史时保留"
                                )
                            } else if shouldShowRecentHeader(at: index) {
                                HistorySectionHeader(
                                    title: "最近项目",
                                    detail: nil
                                )
                            }
                            CompactHistoryItem(
                                item: item,
                                image: store.image(for: item),
                                shortcutNumber: index < 9 ? index + 1 : nil,
                                hoverPreviewEnabled: settings.hoverPreviewEnabled,
                                isSelected: selectedID == item.id,
                                isExpanded: expandedID == item.id,
                                actions: ClipboardActionFactory.compactActions(for: item),
                                select: {
                                    selectedID = item.id
                                    withAnimation(.easeInOut(duration: 0.14)) {
                                        expandedID = expandedID == item.id ? nil : item.id
                                    }
                                },
                                perform: { action in
                                    showNotice(
                                        ClipboardActionFactory.perform(action, using: store)
                                    )
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
                                    selectFirstItem(expand: false)
                                }
                            )
                            .id(item.id)

                            if item.id != filteredItems.last?.id {
                                Divider().padding(.leading, 42)
                            }
                        }
                    }
                }
                .onChange(of: selectedID) {
                    guard let selectedID else { return }
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
    let image: NSImage?
    let shortcutNumber: Int?
    let hoverPreviewEnabled: Bool
    let isSelected: Bool
    let isExpanded: Bool
    let actions: [ClipboardAction]
    let select: () -> Void
    let perform: (ClipboardAction) -> Void
    let copy: () -> Void
    let togglePinned: () -> Void
    let delete: () -> Void
    @State private var isHovering = false
    @State private var showsDetails = false
    @State private var detailTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: select) {
                    HStack(spacing: 9) {
                        if let image {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            Image(systemName: item.kind.symbol)
                                .font(.system(size: 13))
                                .foregroundStyle(item.kind == .error ? Color.red : Color.secondary)
                                .frame(width: 20)
                        }

                        Text(summary)
                            .font(.system(.callout, design: item.kind == .text ? .default : .monospaced))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if item.containsSensitiveData {
                    Image(systemName: "eye.slash.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                if isHovering {
                    HStack(spacing: 1) {
                        RowHoverButton(
                            symbol: "doc.on.doc",
                            help: "复制原文",
                            action: copy
                        )
                        RowHoverButton(
                            symbol: item.isPinned ? "pin.slash" : "pin",
                            help: item.isPinned ? "取消置顶" : "固定到顶部",
                            action: togglePinned
                        )
                        RowHoverButton(
                            symbol: "trash",
                            help: "删除",
                            role: .destructive,
                            action: delete
                        )
                    }
                    .transition(.opacity)
                } else {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if let shortcutNumber {
                        Text("⌘\(shortcutNumber)")
                            .font(.system(.caption2, design: .rounded).weight(.medium))
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 28, alignment: .trailing)
                    } else {
                        Text(item.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .frame(minWidth: 38, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 11)
            .frame(height: 48)
            .background(
                rowBackground,
                in: RoundedRectangle(cornerRadius: 7)
            )
            .padding(.horizontal, 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.1)) {
                    isHovering = hovering
                }
                updateDetailPresentation(isHovering: hovering)
            }
            .contextMenu {
                Button("复制原文", action: copy)
                Button(item.isPinned ? "取消置顶" : "固定到顶部", action: togglePinned)
                Divider()
                Button("删除", role: .destructive, action: delete)
            }

            if isExpanded, !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions) { action in
                        InlineCommandButton(
                            title: compactTitle(for: action),
                            symbol: action.symbol,
                            help: action.detail
                        ) {
                            perform(action)
                        }
                    }
                }
                .padding(.leading, 39)
                .padding(.trailing, 12)
                .padding(.top, 3)
                .padding(.bottom, 11)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .popover(
            isPresented: $showsDetails,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .trailing
        ) {
            ClipboardDetailPreview(
                item: item,
                image: image,
                hoverChanged: updatePreviewHover
            )
        }
        .onDisappear {
            detailTask?.cancel()
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.13)
        }
        if isHovering {
            return Color.primary.opacity(0.055)
        }
        return .clear
    }

    private func compactTitle(for action: ClipboardAction) -> String {
        switch action.id {
        case "open-url": "打开"
        case "format-json": "格式化"
        case "minify-json": "压缩"
        case "typescript": "TypeScript"
        case "uppercase-color": "大写色值"
        case "quote-command", "escape": "转义"
        case "markdown-error": "代码块"
        case "shell-code-block", "extracted-shell-code-block": "代码块"
        case "extract-shell": "提取命令"
        case "camel-case": "camelCase"
        case "snake-case": "snake_case"
        case "copy-image-markdown": "Markdown"
        case "copy-image-url": "图片 URL"
        case "copy-image-path": "文件路径"
        case "copy-image-cache-path": "缓存路径"
        default: action.title
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
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    showsDetails = true
                }
            }
        } else {
            detailTask = Task {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    showsDetails = false
                }
            }
        }
    }

    private func updatePreviewHover(_ isHovering: Bool) {
        detailTask?.cancel()
        if isHovering {
            showsDetails = true
        } else {
            detailTask = Task {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    showsDetails = false
                }
            }
        }
    }
}

private struct HistorySectionHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private struct ClipboardDetailPreview: View {
    let item: ClipboardItem
    let image: NSImage?
    let hoverChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                sourceIcon
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.sourceAppName ?? "未知来源")
                        .font(.headline)
                    Text(item.sourceBundleIdentifier ?? item.kind.localizedTitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Label(item.kind.localizedTitle, systemImage: item.kind.symbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 300)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            } else {
                ScrollView {
                    Text(previewContent)
                        .font(.system(.callout, design: previewFontDesign))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(minHeight: 70, maxHeight: 220)
            }

            Divider()

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
                    Text("\(item.content.count) 字符")
                    Text("·")
                    Text("\(lineCount) 行")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if item.containsSensitiveData {
                Label("敏感内容已隐藏", systemImage: "eye.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if item.isImage, item.imageSourceURL != nil || item.imageOriginalPath != nil {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    if let sourceURL = item.imageSourceURL {
                        Label(sourceURL, systemImage: "link")
                            .lineLimit(2)
                    }
                    if let originalPath = item.imageOriginalPath {
                        Label(originalPath, systemImage: "folder")
                            .lineLimit(2)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(width: 360)
        .onHover(perform: hoverChanged)
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
            return "未知尺寸"
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

private struct InlineCommandButton: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 15)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(isHovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, minHeight: 29)
            .background(
                isHovering ? Color.primary.opacity(0.075) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.08)) {
                isHovering = hovering
            }
        }
        .help(help)
    }
}

private struct RowHoverButton: View {
    let symbol: String
    let help: String
    var role: ButtonRole?
    let action: () -> Void

    init(
        symbol: String,
        help: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.help = help
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 23, height: 23)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : Color.secondary)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        .help(help)
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
                Button(isSelected ? "收起预览" : "预览", action: preview)
                    .buttonStyle(.borderless)
            }
            if action.id == "copy" {
                Button("复制", action: perform)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button(action.id == "open-url" ? "打开" : "复制", action: perform)
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
            Text("处理结果预览")
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
