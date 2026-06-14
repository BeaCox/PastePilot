import SwiftUI

/// Reports the natural content height of each settings page, keyed by page id,
/// so the window can size itself to exactly fit the selected page.
struct SettingsHeightKey: PreferenceKey {
    static var defaultValue: [AnyHashable: CGFloat] = [:]

    static func reduce(
        value: inout [AnyHashable: CGFloat],
        nextValue: () -> [AnyHashable: CGFloat]
    ) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

struct SettingsPane<Content: View>: View {
    let id: AnyHashable
    @ViewBuilder let content: Content

    init(id: AnyHashable, @ViewBuilder content: () -> Content) {
        self.id = id
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: SettingsHeightKey.self,
                        value: [id: proxy.size.height]
                    )
                }
            )
        }
    }
}

struct SettingsGroup<Content: View>: View {
    var title: String?
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let title {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 0.5)
            )
        }
    }
}

struct SettingsRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(title)
                .frame(width: 170, alignment: .leading)
            Spacer()
            content
        }
        .frame(minHeight: 30)
    }
}

struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
