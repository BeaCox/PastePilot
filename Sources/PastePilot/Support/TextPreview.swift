import Foundation

enum TextPreview {
    static let summaryCharacterLimit = 240
    static let initialDetailCharacterLimit = 8_000
    static let detailLoadStep = 8_000
    static let maxInteractiveDetailCharacterLimit = 40_000
    static let detailCharacterLimit = initialDetailCharacterLimit
    static let countScanCharacterLimit = 100_000
    static let richTextPreviewByteLimit = 48_000
    static let jsonFormattingByteLimit = 32_000

    struct Snippet: Equatable {
        let text: String
        let isTruncated: Bool
    }

    static func summary(
        for item: ClipboardItem,
        userPatterns: [UserSensitivePattern] = []
    ) -> String {
        let snippet = clippedText(from: item.content, maxCharacters: summaryCharacterLimit)
        let visibleText = item.containsSensitiveData
            ? ContentAnalyzer.redacted(snippet.text, userPatterns: userPatterns)
            : snippet.text
        return visibleText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    static func detailSnippet(
        for item: ClipboardItem,
        revealsSensitiveContent: Bool,
        maxCharacters: Int = detailCharacterLimit,
        userPatterns: [UserSensitivePattern] = []
    ) -> Snippet {
        let snippet = clippedText(from: item.content, maxCharacters: maxCharacters)
        let isTruncated = snippet.isTruncated
            || (item.contentCharacterCount ?? snippet.text.count) > snippet.text.count
        guard item.containsSensitiveData && !revealsSensitiveContent else {
            return Snippet(text: snippet.text, isTruncated: isTruncated)
        }
        return Snippet(
            text: ContentAnalyzer.redacted(
                snippet.text,
                userPatterns: userPatterns
            ),
            isTruncated: isTruncated
        )
    }

    static func nextDetailCharacterLimit(after currentLimit: Int) -> Int {
        min(currentLimit + detailLoadStep, maxInteractiveDetailCharacterLimit)
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

    static func characterCountDescription(for item: ClipboardItem) -> String {
        if let count = item.contentCharacterCount {
            return "%d characters".localized(count)
        }
        return characterCountDescription(for: item.content)
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

    static func lineCountDescription(for item: ClipboardItem) -> String {
        if let count = item.contentLineCount {
            return "%d lines".localized(count)
        }
        return lineCountDescription(for: item.content)
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
