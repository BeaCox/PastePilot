import AppKit
import SwiftUI

struct ClipboardDetailPreview: View {
    let item: ClipboardItem
    let image: NSImage?
    let performAction: (ClipboardAction) -> Void
    let hoverChanged: (Bool) -> Void
    let previewSnippet: (ClipboardItem, Int, Bool) -> TextPreview.Snippet
    @State private var revealsSensitiveContent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClipboardPreviewHeader(item: item)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if item.kind == .file {
                        FileListPreview(urls: item.fileURLs)
                            .frame(minHeight: 60, maxHeight: 220)
                    } else if item.kind == .richText,
                              !TextPreview.shouldUsePlainTextFallback(forRichText: item) {
                        RichTextPreview(item: item)
                            .frame(minHeight: 80, maxHeight: 180)
                    } else if let image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, minHeight: 100, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        PlainTextPreview(
                            item: item,
                            revealsSensitiveContent: revealsSensitiveContent,
                            previewSnippet: previewSnippet
                        )
                        .frame(minHeight: 50, maxHeight: 160)
                    }
                }

                ClipboardPreviewMetadata(
                    item: item,
                    revealsSensitiveContent: $revealsSensitiveContent
                )
            }
            .padding(10)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .padding(.bottom, 12)

            ClipboardPreviewActionList(
                actions: MenuBarPopoverState.previewActions(for: item),
                performAction: performAction
            )
        }
        .padding(16)
        .frame(width: 340, alignment: .topLeading)
        .onHover(perform: hoverChanged)
        .onChange(of: item.id) {
            revealsSensitiveContent = false
        }
    }

}

private struct PlainTextPreview: View {
    let item: ClipboardItem
    let revealsSensitiveContent: Bool
    let previewSnippet: (ClipboardItem, Int, Bool) -> TextPreview.Snippet
    @State private var visibleCharacterLimit = TextPreview.initialDetailCharacterLimit

    var body: some View {
        let preview = renderedPreview
        VStack(alignment: .leading, spacing: 6) {
            TextKitPreview(
                content: preview.content,
                fontDesign: previewFontDesign
            )

            if preview.isTruncated {
                loadingControls
            }
        }
        .onChange(of: item.id) {
            resetVisibleLimit()
        }
        .onChange(of: revealsSensitiveContent) {
            resetVisibleLimit()
        }
    }

    private var canLoadMore: Bool {
        visibleCharacterLimit < TextPreview.maxInteractiveDetailCharacterLimit
    }

    private var loadingStatus: String {
        if canLoadMore {
            return "Showing first %d characters".localized(visibleCharacterLimit)
        }
        return "Preview limited to first %d characters".localized(visibleCharacterLimit)
    }

    private var loadingSystemImage: String {
        canLoadMore ? "text.append" : "scissors"
    }

    private var loadingControls: some View {
        HStack(spacing: 8) {
            Label(loadingStatus, systemImage: loadingSystemImage)
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Spacer()

            if canLoadMore {
                Button("Show More".localized) {
                    loadMore()
                }
                .buttonStyle(.link)
                .font(.caption2)
            }
        }
    }

    private var renderedPreview: (content: AttributedString, isTruncated: Bool) {
        if item.kind == .json,
           !item.hasExternalContent,
           (!item.containsSensitiveData || revealsSensitiveContent),
           TextPreview.canFormatJSON(item.content),
           let formatted = ContentTransformer.formatJSON(item.content) {
            let snippet = TextPreview.clippedText(
                from: formatted,
                maxCharacters: visibleCharacterLimit
            )
            return (JSONSyntaxHighlighter.highlight(snippet.text), snippet.isTruncated)
        }

        let snippet = previewSnippet(item, visibleCharacterLimit, revealsSensitiveContent)
        return (AttributedString(snippet.text), snippet.isTruncated)
    }

    private var previewFontDesign: Font.Design {
        item.kind == .text || item.kind == .markdown || item.kind == .richText
            ? .default
            : .monospaced
    }

    private func loadMore() {
        visibleCharacterLimit = TextPreview.nextDetailCharacterLimit(
            after: visibleCharacterLimit
        )
    }

    private func resetVisibleLimit() {
        visibleCharacterLimit = TextPreview.initialDetailCharacterLimit
    }
}

private struct TextKitPreview: NSViewRepresentable {
    let content: AttributedString
    let fontDesign: Font.Design

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.allowsUndo = false
        textView.usesFindPanel = false
        textView.layoutManager?.allowsNonContiguousLayout = true

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let attributedString = NSMutableAttributedString(content)
        attributedString.addAttributes(
            [.font: font],
            range: NSRange(location: 0, length: attributedString.length)
        )

        if textView.string != attributedString.string {
            textView.textStorage?.setAttributedString(attributedString)
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
        textView.font = font
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: ()) {
        clearTextView(in: scrollView)
    }

    private static func clearTextView(in scrollView: NSScrollView) {
        if let textView = scrollView.documentView as? NSTextView {
            textView.textStorage?.setAttributedString(NSAttributedString())
        }
        scrollView.documentView = nil
    }

    private var font: NSFont {
        switch fontDesign {
        case .monospaced:
            return .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        default:
            return .systemFont(ofSize: NSFont.smallSystemFontSize)
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
        textView.textStorage?.setAttributedString(
            PreviewRenderCache.shared.richTextPreview(for: item)
        )
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: ()) {
        if let textView = scrollView.documentView as? NSTextView {
            textView.textStorage?.setAttributedString(NSAttributedString())
        }
        scrollView.documentView = nil
    }

    static func attributedString(for item: ClipboardItem) -> NSAttributedString {
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

final class PreviewRenderCache: @unchecked Sendable {
    static let shared = PreviewRenderCache()

    private let applicationIcons = NSCache<NSString, NSImage>()
    private let richTextPreviews = NSCache<NSString, NSAttributedString>()

    private init() {
        applicationIcons.countLimit = 64
        richTextPreviews.countLimit = 128
    }

    func applicationIcon(forBundleIdentifier bundleIdentifier: String) -> NSImage? {
        let key = bundleIdentifier as NSString
        if let icon = applicationIcons.object(forKey: key) {
            return icon
        }
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: bundleIdentifier
        ) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
        applicationIcons.setObject(icon, forKey: key)
        return icon
    }

    @MainActor
    func richTextPreview(for item: ClipboardItem) -> NSAttributedString {
        let key = item.id.uuidString as NSString
        if let preview = richTextPreviews.object(forKey: key) {
            return preview
        }
        let preview = RichTextPreview.attributedString(for: item)
        richTextPreviews.setObject(preview, forKey: key)
        return preview
    }
}

private enum JSONSyntaxHighlighter {
    private static let stringRegex = RegexFactory.make(#""(?:\\.|[^"\\])*""#)
    private static let keyRegex = RegexFactory.make(#""(?:\\.|[^"\\])*"(?=\s*:)"#)
    private static let boolNullRegex = RegexFactory.make(#"\b(?:true|false|null)\b"#)
    private static let numberRegex = RegexFactory.make(#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#)

    static func highlight(_ source: String) -> AttributedString {
        let result = NSMutableAttributedString(
            string: source,
            attributes: [.foregroundColor: NSColor.labelColor]
        )
        let fullRange = NSRange(source.startIndex..., in: source)
        apply(stringRegex, color: .systemGreen, to: result, source: source, range: fullRange)
        apply(keyRegex, color: .systemBlue, to: result, source: source, range: fullRange)
        apply(boolNullRegex, color: .systemPurple, to: result, source: source, range: fullRange)
        apply(numberRegex, color: .systemOrange, to: result, source: source, range: fullRange)
        return AttributedString(result)
    }

    private static func apply(
        _ regex: NSRegularExpression?,
        color: NSColor,
        to result: NSMutableAttributedString,
        source: String,
        range: NSRange
    ) {
        guard let regex else { return }
        for match in regex.matches(in: source, range: range) {
            result.addAttribute(.foregroundColor, value: color, range: match.range)
        }
    }
}
