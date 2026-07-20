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
    var userAliases: [String]?
    var protectionState: ClipboardProtectionState?

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
        userAliases: [String]? = nil,
        protectionState: ClipboardProtectionState? = nil
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
        self.userAliases = Self.normalizedAliases(userAliases)
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

    var hasUserAliases: Bool {
        userAliases?.isEmpty == false
    }

    var hasUserMetadata: Bool {
        hasUserTitle || hasUserNote || hasUserAliases
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
    func preparedForProtection(content fullContent: String) -> ClipboardItem {
        ClipboardItem(
            id: id,
            content: fullContent,
            kind: kind,
            createdAt: createdAt,
            isPinned: isPinned,
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
            userAliases: userAliases,
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
            userAliases: userAliases,
            protectionState: protectionState
        )
    }
}
