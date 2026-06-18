import AppKit
import SwiftUI

struct ClipboardDetailPreview: View {
    let item: ClipboardItem
    let image: NSImage?
    let performAction: (ClipboardAction) -> Void
    let hoverChanged: (Bool) -> Void
    @State private var revealsSensitiveContent = false

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
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 12)

            actionButtons
        }
        .padding(16)
        .frame(width: 340, alignment: .topLeading)
        .onHover(perform: hoverChanged)
        .onChange(of: item.id) {
            revealsSensitiveContent = false
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        let actions = Array(keyboardActions.prefix(9))
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

    private var keyboardActions: [ClipboardAction] {
        ClipboardActionFactory.keyboardActions(for: item)
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
        if item.containsSensitiveData && !revealsSensitiveContent {
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
    private static let stringRegex = RegexFactory.make(#""(?:\\.|[^"\\])*""#)
    private static let keyRegex = RegexFactory.make(#""(?:\\.|[^"\\])*"(?=\s*:)"#)
    private static let boolNullRegex = RegexFactory.make(#"\b(?:true|false|null)\b"#)
    private static let numberRegex = RegexFactory.make(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#)

    static func highlight(_ source: String) -> AttributedString {
        var result = AttributedString(source)
        result.foregroundColor = .primary
        let fullRange = NSRange(source.startIndex..., in: source)
        apply(stringRegex, color: .green, to: &result, source: source, range: fullRange)
        apply(keyRegex, color: .blue, to: &result, source: source, range: fullRange)
        apply(boolNullRegex, color: .purple, to: &result, source: source, range: fullRange)
        apply(numberRegex, color: .orange, to: &result, source: source, range: fullRange)
        return result
    }

    private static func apply(
        _ regex: NSRegularExpression?,
        color: Color,
        to result: inout AttributedString,
        source: String,
        range: NSRange
    ) {
        guard let regex else { return }
        for match in regex.matches(in: source, range: range) {
            guard let sourceRange = Range(match.range, in: source),
                  let lower = AttributedString.Index(sourceRange.lowerBound, within: result),
                  let upper = AttributedString.Index(sourceRange.upperBound, within: result) else {
                continue
            }
            result[lower..<upper].foregroundColor = color
        }
    }
}
