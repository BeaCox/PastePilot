import SwiftUI

struct CompactHistoryItem: View {
    let item: ClipboardItem
    let image: NSImage?
    let userSensitivePatterns: [UserSensitivePattern]
    let shortcutNumber: Int?
    let isSelected: Bool
    let pasteStackPosition: Int?
    let select: () -> Void
    let hoverChanged: (Bool) -> Void
    let editMetadata: () -> Void
    let copy: () -> Void
    let togglePinned: () -> Void
    let toggleProtection: () -> Void
    let togglePasteStack: () -> Void
    let delete: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            Button(action: copy) {
                HStack(spacing: 7) {
                    if item.isProtected {
                        ProtectedContentBadge(isLocked: !item.isProtectedContentAvailable)
                    } else if item.containsSensitiveData {
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

                    if let pasteStackPosition {
                        Text("#\(pasteStackPosition)")
                            .font(.system(size: 10, design: .rounded).weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                            .accessibilityLabel(
                                "Paste stack position %d".localized(pasteStackPosition)
                            )
                    } else if !showsActions, let shortcutNumber {
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
            .accessibilityHint(
                item.protectionState == .locked
                    ? "Unlocks protected content.".localized
                    : "Copies the original clipboard content.".localized
            )

            if showsActions {
                RowIconButton(
                    symbol: pasteStackPosition == nil
                        ? "square.stack.3d.up"
                        : "square.stack.3d.up.fill",
                    label: pasteStackPosition == nil
                        ? "Add to Paste Stack".localized
                        : "Remove from Paste Stack".localized,
                    isActive: pasteStackPosition != nil,
                    action: togglePasteStack
                )
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
            Button("Edit Details…".localized, action: editMetadata)
            if item.kind != .image && item.kind != .file {
                Button(protectionActionTitle, action: toggleProtection)
            }
        }
    }

    private var summary: String {
        return TextPreview.summary(
            for: item,
            userPatterns: userSensitivePatterns
        )
    }

    private var protectionActionTitle: String {
        switch item.protectionState {
        case .locked:
            "Unlock Protected Items".localized
        case .unlocked:
            "Remove Protection".localized
        case nil:
            "Move to Protected Storage".localized
        }
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

struct ProtectedContentBadge: View {
    let isLocked: Bool
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: size * 0.43, weight: .medium))
            .foregroundStyle(.blue)
            .frame(width: size, height: size)
            .background(
                Color.blue.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size * 0.24)
            )
            .accessibilityLabel(
                isLocked ? "Protected item locked".localized : "Protected item unlocked".localized
            )
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
