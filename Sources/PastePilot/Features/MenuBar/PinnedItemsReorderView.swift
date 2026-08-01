import SwiftUI

struct PinnedItemsReorderView: View {
    let items: [ClipboardItem]
    let userSensitivePatterns: [UserSensitivePattern]
    let move: (IndexSet, Int) -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            Divider()

            List {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PinnedItemReorderRow(
                        item: item,
                        shortcutNumber: index + 1,
                        userSensitivePatterns: userSensitivePatterns
                    )
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            .frame(minHeight: 120, maxHeight: 320)

            Divider()

            HStack {
                Text("Drag rows to reorder.".localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done".localized, action: done)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.regular)
            .padding(.horizontal, 18)
            .frame(height: 52)
        }
        .frame(width: MenuBarPopoverState.preferredWidth)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "pin.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Reorder Pinned Items".localized)
                    .font(.headline)
                Text("%d pinned".localized(items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct PinnedItemReorderRow: View {
    let item: ClipboardItem
    let shortcutNumber: Int
    let userSensitivePatterns: [UserSensitivePattern]

    var body: some View {
        HStack(spacing: 10) {
            Text(shortcutNumber <= 9 ? "⌘\(shortcutNumber)" : "\(shortcutNumber)")
                .font(.system(size: 11, design: .rounded).weight(.semibold))
                .foregroundStyle(shortcutNumber <= 9 ? Color.accentColor : .secondary)
                .frame(width: 24, alignment: .center)

            ContentKindBadge(kind: item.kind, size: 20)

            Text(TextPreview.summary(for: item, userPatterns: userSensitivePatterns))
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 3)
    }
}
