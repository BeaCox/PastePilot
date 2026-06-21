import SwiftUI

struct CompactHistoryItem: View {
    let item: ClipboardItem
    let image: NSImage?
    let shortcutNumber: Int?
    let isSelected: Bool
    let select: () -> Void
    let hoverChanged: (Bool) -> Void
    let preview: () -> Void
    let performAction: (ClipboardAction) -> Void
    let copy: () -> Void
    let togglePinned: () -> Void
    let delete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            Button(action: copy) {
                HStack(spacing: 7) {
                    if item.containsSensitiveData {
                        SensitiveContentBadge(size: 22)
                    } else if let image {
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
                    performAction(
                        ClipboardAction(
                            id: "quick-look",
                            title: "Quick Look".localized,
                            detail: "Preview using the macOS system viewer".localized,
                            symbol: "eye",
                            effect: .quickLook(item.fileURLs)
                        )
                    )
                }
                Button("Show in Finder".localized) {
                    performAction(
                        ClipboardAction(
                            id: "reveal-files",
                            title: "Show in Finder".localized,
                            detail: "Reveal the original file location".localized,
                            symbol: "folder",
                            effect: .revealFiles(item.fileURLs)
                        )
                    )
                }
            }
            Button(item.isPinned ? "Unpin".localized : "Pin to Top".localized, action: togglePinned)
            Divider()
            Button("Delete".localized, role: .destructive, action: delete)
        }
    }

    private var summary: String {
        TextPreview.summary(for: item)
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

struct HistorySectionHeader: View {
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

struct SensitiveContentBadge: View {
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: "eye.slash.fill")
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(.orange)
            .frame(width: size, height: size)
            .background(
                Color.orange.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.24)
            )
            .accessibilityLabel("Sensitive content hidden".localized)
    }
}

struct ContentKindBadge: View {
    let kind: ContentKind
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: kind.symbol)
            .font(.system(size: size * 0.46, weight: .medium))
            .foregroundStyle(kind.accentColor)
            .frame(width: size, height: size)
            .background(
                kind.accentColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.24)
            )
            .accessibilityHidden(true)
    }
}
