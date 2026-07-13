import Foundation
import SwiftUI

enum ContentKind: String, Codable, CaseIterable {
    case file
    case richText
    case image
    case json
    case url
    case color
    case command
    case error
    case markdown
    case code
    case text

    var symbol: String {
        switch self {
        case .file: "doc.on.doc"
        case .richText: "textformat"
        case .image: "photo"
        case .json: "curlybraces"
        case .url: "link"
        case .color: "paintpalette"
        case .command: "terminal"
        case .error: "exclamationmark.triangle"
        case .markdown: "text.badge.checkmark"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .text: "doc.text"
        }
    }

    var accentColor: Color {
        switch self {
        case .file: .cyan
        case .richText: .mint
        case .image: .purple
        case .json: .blue
        case .url: .green
        case .color: .pink
        case .command: .orange
        case .error: .red
        case .markdown: .teal
        case .code: .indigo
        case .text: .secondary.opacity(0.5)
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let kind: ContentKind
    let createdAt: Date
    var isPinned: Bool
    let containsSensitiveData: Bool
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
    let imageFileName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageByteCount: Int?
    let imageDigest: String?
    let imageSourceURL: String?
    let imageOriginalPath: String?
    let filePaths: [String]?
    let richTextRTFBase64: String?
    let richTextHTML: String?
    let pasteboardRepresentations: [ClipboardPasteboardRepresentation]?
    let contentFileName: String?
    let contentDigest: String?
    let contentCharacterCount: Int?
    let contentLineCount: Int?
    let contentByteCount: Int?
    var ocrText: String?
    var userTitle: String?
    var userNote: String?
    var userAliases: [String]?

    init(
        id: UUID = UUID(),
        content: String,
        kind: ContentKind,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        containsSensitiveData: Bool = false,
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        imageByteCount: Int? = nil,
        imageDigest: String? = nil,
        imageSourceURL: String? = nil,
        imageOriginalPath: String? = nil,
        filePaths: [String]? = nil,
        richTextRTFBase64: String? = nil,
        richTextHTML: String? = nil,
        pasteboardRepresentations: [ClipboardPasteboardRepresentation]? = nil,
        contentFileName: String? = nil,
        contentDigest: String? = nil,
        contentCharacterCount: Int? = nil,
        contentLineCount: Int? = nil,
        contentByteCount: Int? = nil,
        ocrText: String? = nil,
        userTitle: String? = nil,
        userNote: String? = nil,
        userAliases: [String]? = nil
    ) {
        self.id = id
        self.content = content
        self.kind = kind
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.containsSensitiveData = containsSensitiveData
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageByteCount = imageByteCount
        self.imageDigest = imageDigest
        self.imageSourceURL = imageSourceURL
        self.imageOriginalPath = imageOriginalPath
        self.filePaths = filePaths
        self.richTextRTFBase64 = richTextRTFBase64
        self.richTextHTML = richTextHTML
        self.pasteboardRepresentations = pasteboardRepresentations?.isEmpty == true
            ? nil
            : pasteboardRepresentations
        self.contentFileName = contentFileName
        self.contentDigest = contentDigest
        self.contentCharacterCount = contentCharacterCount
        self.contentLineCount = contentLineCount
        self.contentByteCount = contentByteCount
        self.ocrText = ocrText
        self.userTitle = Self.normalizedMetadataText(userTitle)
        self.userNote = Self.normalizedMetadataText(userNote)
        self.userAliases = Self.normalizedAliases(userAliases)
    }

    var isImage: Bool {
        kind == .image && imageFileName != nil
    }

    var fileURLs: [URL] {
        (filePaths ?? []).map { URL(fileURLWithPath: $0) }
    }

    var hasRichText: Bool {
        richTextRTFBase64 != nil || richTextHTML != nil
    }

    var hasPasteboardRepresentations: Bool {
        pasteboardRepresentations?.isEmpty == false
    }

    var hasExternalContent: Bool {
        contentFileName != nil
    }

    var hasUserTitle: Bool {
        userTitle?.isEmpty == false
    }

    var hasUserNote: Bool {
        userNote?.isEmpty == false
    }

    var hasUserAliases: Bool {
        userAliases?.isEmpty == false
    }

    var hasUserMetadata: Bool {
        hasUserTitle || hasUserNote || hasUserAliases
    }

    mutating func updateUserMetadata(
        title: String?,
        note: String?,
        aliases: [String]?
    ) {
        userTitle = Self.normalizedMetadataText(title)
        userNote = Self.normalizedMetadataText(note)
        userAliases = Self.normalizedAliases(aliases)
    }

    mutating func inheritUserMetadata(from item: ClipboardItem?) {
        guard let item else { return }
        userTitle = item.userTitle
        userNote = item.userNote
        userAliases = item.userAliases
    }

    private static func normalizedMetadataText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedAliases(_ aliases: [String]?) -> [String]? {
        guard let aliases else { return nil }
        var seen = Set<String>()
        let normalized = aliases.compactMap { alias -> String? in
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
        return normalized.isEmpty ? nil : normalized
    }
}

enum ClipboardHistoryOrdering {
    static func newestFirst(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted { $0.createdAt > $1.createdAt }
    }

    static func pinnedFirst(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let chronological = newestFirst(items)
        return chronological.filter(\.isPinned)
            + chronological.filter { !$0.isPinned }
    }
}

extension ClipboardItem {
    func externalizedContent(fileName: String, digest: String? = nil) -> ClipboardItem {
        ClipboardItem(
            id: id,
            content: TextPreview.clippedText(
                from: content,
                maxCharacters: TextPreview.initialDetailCharacterLimit
            ).text,
            kind: kind,
            createdAt: createdAt,
            isPinned: isPinned,
            containsSensitiveData: containsSensitiveData,
            sourceAppName: sourceAppName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            imageFileName: imageFileName,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageByteCount: imageByteCount,
            imageDigest: imageDigest,
            imageSourceURL: imageSourceURL,
            imageOriginalPath: imageOriginalPath,
            filePaths: filePaths,
            richTextRTFBase64: richTextRTFBase64,
            richTextHTML: richTextHTML,
            pasteboardRepresentations: pasteboardRepresentations,
            contentFileName: fileName,
            contentDigest: digest ?? contentDigest ?? ContentDigest.sha256Hex(for: content),
            contentCharacterCount: content.count,
            contentLineCount: content.reduce(1) { count, character in
                character.isNewline ? count + 1 : count
            },
            contentByteCount: content.utf8.count,
            ocrText: ocrText,
            userTitle: userTitle,
            userNote: userNote,
            userAliases: userAliases
        )
    }
}
