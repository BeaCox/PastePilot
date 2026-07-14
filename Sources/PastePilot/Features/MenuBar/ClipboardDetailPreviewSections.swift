import AppKit
import SwiftUI

struct ClipboardPreviewHeader: View {
    let item: ClipboardItem

    var body: some View {
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
        guard let bundleIdentifier = item.sourceBundleIdentifier else {
            return nil
        }
        return PreviewRenderCache.shared.applicationIcon(
            forBundleIdentifier: bundleIdentifier
        )
    }
}

struct ClipboardPreviewMetadata: View {
    let item: ClipboardItem
    @Binding var revealsSensitiveContent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
                .padding(.vertical, 8)

            if item.hasUserMetadata {
                UserMetadataPreview(item: item)
                    .padding(.bottom, 8)
            }

            if let linkMetadata = item.linkMetadata {
                LinkMetadataPreview(metadata: linkMetadata)
                    .padding(.bottom, 8)
            }

            if let barcodes = item.detectedBarcodes, !barcodes.isEmpty {
                BarcodeMetadataPreview(
                    barcodes: barcodes,
                    hidesContent: item.containsSensitiveData && !revealsSensitiveContent
                )
                    .padding(.bottom, 8)
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
                    Text(TextPreview.characterCountDescription(for: item))
                    Text("·")
                    Text(TextPreview.lineCountDescription(for: item))
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            if item.containsSensitiveData {
                HStack {
                    Label(
                        revealsSensitiveContent
                            ? "Sensitive content revealed".localized
                            : "Sensitive content hidden".localized,
                        systemImage: revealsSensitiveContent
                            ? "eye.fill"
                            : "eye.slash.fill"
                    )
                    Spacer()
                    Button(
                        revealsSensitiveContent
                            ? "Hide".localized
                            : "Reveal".localized
                    ) {
                        revealsSensitiveContent.toggle()
                    }
                    .buttonStyle(.link)
                }
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
        }
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

private struct LinkMetadataPreview: View {
    let metadata: LinkMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title = metadata.title {
                Label(title, systemImage: "link")
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            if let siteName = metadata.siteName {
                Text(siteName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let summary = metadata.summary {
                Text(summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .textSelection(.enabled)
    }
}

private struct BarcodeMetadataPreview: View {
    let barcodes: [DetectedBarcode]
    let hidesContent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Detected Codes".localized, systemImage: "barcode.viewfinder")
                .font(.caption.weight(.medium))
            ForEach(barcodes, id: \.self) { barcode in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(barcode.symbology)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                    Text(hidesContent ? "Sensitive content hidden".localized : barcode.payload)
                        .font(.caption2)
                        .lineLimit(2)
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct UserMetadataPreview: View {
    let item: ClipboardItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title = item.userTitle {
                Label(title, systemImage: "textformat")
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
            }
            if let note = item.userNote {
                Label(note, systemImage: "note.text")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if let aliases = item.userAliases,
               !aliases.isEmpty {
                Label(aliases.joined(separator: ", "), systemImage: "tag")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .textSelection(.enabled)
    }
}

struct ClipboardPreviewActionList: View {
    let actions: [ClipboardAction]
    let performAction: (ClipboardAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                Button {
                    performAction(action)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: action.symbol)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        Text(action.title)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Spacer()
                        Text("⌥\(index + 1)")
                            .font(.system(size: 11, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
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
}

private struct PreviewActionButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(
                isHovering || configuration.isPressed
                    ? Color.primary
                    : Color.primary.opacity(0.8)
            )
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
