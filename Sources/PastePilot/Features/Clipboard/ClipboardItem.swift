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

enum ClipboardProtectionState: String, Codable {
    case unlocked
    case locked
}

struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    let content: String
    let kind: ContentKind
    let createdAt: Date
    var isPinned: Bool
    var pinnedOrder: Int?
    var containsSensitiveData: Bool
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
    let imageFileName: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageByteCount: Int?
    let imageDigest: String?
    let imagePerceptualHash: String?
    let imageSourceURL: String?
    let imageOriginalPath: String?
    var linkMetadata: LinkMetadata?
    var detectedBarcodes: [DetectedBarcode]?
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
    var tags: [String]?
    var protectionState: ClipboardProtectionState?

    init(
        id: UUID = UUID(),
        content: String,
        kind: ContentKind,
        createdAt: Date = Date(),
        isPinned: Bool = false,
        pinnedOrder: Int? = nil,
        containsSensitiveData: Bool = false,
        sourceAppName: String? = nil,
        sourceBundleIdentifier: String? = nil,
        imageFileName: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        imageByteCount: Int? = nil,
        imageDigest: String? = nil,
        imagePerceptualHash: String? = nil,
        imageSourceURL: String? = nil,
        imageOriginalPath: String? = nil,
        linkMetadata: LinkMetadata? = nil,
        detectedBarcodes: [DetectedBarcode]? = nil,
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
        tags: [String]? = nil,
        protectionState: ClipboardProtectionState? = nil
    ) {
        self.id = id
        self.content = content
        self.kind = kind
        self.createdAt = createdAt
        self.isPinned = isPinned
        self.pinnedOrder = isPinned ? pinnedOrder : nil
        self.containsSensitiveData = containsSensitiveData
        self.sourceAppName = sourceAppName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.imageFileName = imageFileName
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageByteCount = imageByteCount
        self.imageDigest = imageDigest
        self.imagePerceptualHash = imagePerceptualHash
        self.imageSourceURL = imageSourceURL
        self.imageOriginalPath = imageOriginalPath
        self.linkMetadata = linkMetadata
        self.detectedBarcodes = detectedBarcodes?.isEmpty == true ? nil : detectedBarcodes
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
        self.tags = Self.normalizedTags(tags)
        self.protectionState = protectionState
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

    var hasTags: Bool {
        tags?.isEmpty == false
    }

    var hasUserMetadata: Bool {
        hasUserTitle || hasUserNote
    }

    var hasVisibleMetadata: Bool {
        hasUserMetadata || hasTags
    }

    var hasDetectedBarcodes: Bool {
        detectedBarcodes?.isEmpty == false
    }

    var isProtected: Bool {
        protectionState != nil
    }

    var isProtectedContentAvailable: Bool {
        protectionState == .unlocked
    }

    var requiresSensitiveContentReveal: Bool {
        containsSensitiveData && !isProtected
    }

    mutating func updateUserMetadata(
        title: String?,
        note: String?,
        tags: [String]?
    ) {
        userTitle = Self.normalizedMetadataText(title)
        userNote = Self.normalizedMetadataText(note)
        self.tags = Self.normalizedTags(tags)
    }

    mutating func inheritUserMetadata(from item: ClipboardItem?) {
        guard let item else { return }
        userTitle = item.userTitle
        userNote = item.userNote
        tags = item.tags
    }

    mutating func inheritEnrichment(from item: ClipboardItem?) {
        guard let item else { return }
        linkMetadata = item.linkMetadata
        detectedBarcodes = item.detectedBarcodes
    }

    private static func normalizedMetadataText(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedTags(_ tags: [String]?) -> [String]? {
        guard let tags else { return nil }
        var seen = Set<String>()
        let normalized = tags.compactMap { tag -> String? in
            let value = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !value.isEmpty, seen.insert(value).inserted else { return nil }
            return value
        }
        return normalized.isEmpty ? nil : normalized
    }
}

enum ClipboardHistoryOrdering {
    static func newestFirst(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted(by: isNewer)
    }

    static func pinnedFirst(_ items: [ClipboardItem]) -> [ClipboardItem] {
        pinnedItems(items) + newestFirst(items.filter { !$0.isPinned })
    }

    static func pinnedItems(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.filter(\.isPinned).sorted { lhs, rhs in
            switch (lhs.pinnedOrder, rhs.pinnedOrder) {
            case let (lhsOrder?, rhsOrder?) where lhsOrder != rhsOrder:
                return lhsOrder < rhsOrder
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return isNewer(lhs, rhs)
            }
        }
    }

    private static func isNewer(_ lhs: ClipboardItem, _ rhs: ClipboardItem) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

extension ClipboardItem {
    func preparedForProtection(content fullContent: String) -> ClipboardItem {
        ClipboardItem(
            id: id,
            content: fullContent,
            kind: kind,
            createdAt: createdAt,
            isPinned: isPinned,
            pinnedOrder: pinnedOrder,
            containsSensitiveData: containsSensitiveData,
            sourceAppName: sourceAppName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            imageFileName: nil,
            imageWidth: nil,
            imageHeight: nil,
            imageByteCount: nil,
            imageDigest: nil,
            imagePerceptualHash: nil,
            imageSourceURL: imageSourceURL,
            imageOriginalPath: nil,
            linkMetadata: linkMetadata,
            detectedBarcodes: detectedBarcodes,
            filePaths: nil,
            richTextRTFBase64: richTextRTFBase64,
            richTextHTML: richTextHTML,
            pasteboardRepresentations: pasteboardRepresentations,
            contentDigest: contentDigest ?? ContentDigest.sha256Hex(for: fullContent),
            contentCharacterCount: contentCharacterCount ?? fullContent.count,
            contentLineCount: contentLineCount,
            contentByteCount: contentByteCount ?? fullContent.utf8.count,
            ocrText: ocrText,
            userTitle: userTitle,
            userNote: userNote,
            tags: tags,
            protectionState: .unlocked
        )
    }

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
            pinnedOrder: pinnedOrder,
            containsSensitiveData: containsSensitiveData,
            sourceAppName: sourceAppName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            imageFileName: imageFileName,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            imageByteCount: imageByteCount,
            imageDigest: imageDigest,
            imagePerceptualHash: imagePerceptualHash,
            imageSourceURL: imageSourceURL,
            imageOriginalPath: imageOriginalPath,
            linkMetadata: linkMetadata,
            detectedBarcodes: detectedBarcodes,
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
            tags: tags,
            protectionState: protectionState
        )
    }
}
