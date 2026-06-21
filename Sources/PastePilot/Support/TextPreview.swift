import Foundation

enum TextPreview {
    static let summaryCharacterLimit = 240
    static let detailCharacterLimit = 20_000
    static let countScanCharacterLimit = 100_000
    static let richTextPreviewByteLimit = 120_000
    static let jsonFormattingByteLimit = 80_000

    struct Snippet: Equatable {
        let text: String
        let isTruncated: Bool
    }

    static func summary(for item: ClipboardItem) -> String {
        let snippet = clippedText(from: item.content, maxCharacters: summaryCharacterLimit)
        let visibleText = item.containsSensitiveData
            ? ContentAnalyzer.redacted(snippet.text)
            : snippet.text
        return visibleText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    static func detailSnippet(
        for item: ClipboardItem,
        revealsSensitiveContent: Bool
    ) -> Snippet {
        let snippet = clippedText(from: item.content, maxCharacters: detailCharacterLimit)
        guard item.containsSensitiveData && !revealsSensitiveContent else {
            return snippet
        }
        return Snippet(
            text: ContentAnalyzer.redacted(snippet.text),
            isTruncated: snippet.isTruncated
        )
    }

    static func clippedText(from text: String, maxCharacters: Int) -> Snippet {
        guard maxCharacters > 0 else {
            return Snippet(text: "", isTruncated: !text.isEmpty)
        }

        var index = text.startIndex
        var count = 0
        while index < text.endIndex && count < maxCharacters {
            index = text.index(after: index)
            count += 1
        }

        return Snippet(
            text: String(text[..<index]),
            isTruncated: index < text.endIndex
        )
    }

    static func shouldUsePlainTextFallback(forRichText item: ClipboardItem) -> Bool {
        guard item.kind == .richText else { return false }
        return item.content.utf8.count > richTextPreviewByteLimit
            || (item.richTextRTFBase64?.utf8.count ?? 0) > richTextPreviewByteLimit
            || (item.richTextHTML?.utf8.count ?? 0) > richTextPreviewByteLimit
    }

    static func canFormatJSON(_ text: String) -> Bool {
        text.utf8.count <= jsonFormattingByteLimit
    }

    static func characterCountDescription(for text: String) -> String {
        let count = cappedCharacterCount(for: text)
        if count.isTruncated {
            return "%d+ characters".localized(count.value)
        }
        return "%d characters".localized(count.value)
    }

    static func lineCountDescription(for text: String) -> String {
        var index = text.startIndex
        var scanned = 0
        var lines = 1

        while index < text.endIndex {
            if scanned == countScanCharacterLimit {
                return "%d+ lines".localized(lines)
            }
            if text[index].isNewline {
                lines += 1
            }
            index = text.index(after: index)
            scanned += 1
        }

        return "%d lines".localized(lines)
    }

    private static func cappedCharacterCount(for text: String) -> (
        value: Int,
        isTruncated: Bool
    ) {
        var index = text.startIndex
        var count = 0

        while index < text.endIndex {
            if count == countScanCharacterLimit {
                return (count, true)
            }
            index = text.index(after: index)
            count += 1
        }

        return (count, false)
    }
}
