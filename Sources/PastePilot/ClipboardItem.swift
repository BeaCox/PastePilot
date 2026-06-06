import Foundation
import SwiftUI

enum ContentKind: String, Codable, CaseIterable {
    case image
    case json
    case url
    case color
    case command
    case error
    case markdown
    case code
    case text

    var title: String {
        switch self {
        case .image: "Image"
        case .json: "JSON"
        case .url: "URL"
        case .color: "Color"
        case .command: "Command"
        case .error: "Error"
        case .markdown: "Markdown"
        case .code: "Code"
        case .text: "Text"
        }
    }

    var symbol: String {
        switch self {
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
        imageOriginalPath: String? = nil
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
    }

    var isImage: Bool {
        kind == .image && imageFileName != nil
    }
}

enum ClipboardHistoryOrdering {
    static func pinnedFirst(_ items: [ClipboardItem]) -> [ClipboardItem] {
        let chronological = items.sorted { $0.createdAt > $1.createdAt }
        return chronological.filter(\.isPinned)
            + chronological.filter { !$0.isPinned }
    }
}
