import SwiftUI

struct PasteStackReorderView: View {
    let items: [ClipboardItem]
    let userSensitivePatterns: [UserSensitivePattern]
    let move: (IndexSet, Int) -> Void
    let remove: (ClipboardItem) -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

            Divider()

            if items.isEmpty {
                Text("Add at least one item to the paste stack.".localized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 220)
            } else {
                List {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        PasteStackReorderRow(
                            item: item,
                            position: index + 1,
                            userSensitivePatterns: userSensitivePatterns,
                            remove: { remove(item) }
                        )
                    }
                    .onMove(perform: move)
                }
                .listStyle(.plain)
                .frame(minHeight: 120, maxHeight: 320)
            }

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
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("Reorder Paste Stack".localized)
                    .font(.headline)
                Text("%d queued".localized(items.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}

private struct PasteStackReorderRow: View {
    let item: ClipboardItem
    let position: Int
    let userSensitivePatterns: [UserSensitivePattern]
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(position)")
                .font(.system(size: 11, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)

            ContentKindBadge(kind: item.kind, size: 20)

            Text(summary)
                .font(.system(size: 12))
                .lineLimit(1)

            Spacer()

            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .accessibilityLabel("Remove from Paste Stack".localized)
        }
        .padding(.vertical, 3)
    }

    private var summary: String {
        TextPreview.summary(for: item, userPatterns: userSensitivePatterns)
    }
}
