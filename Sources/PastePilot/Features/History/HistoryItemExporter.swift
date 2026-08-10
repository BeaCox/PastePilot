import Foundation

enum HistoryItemExportFormat: Equatable, Sendable {
    case plainText
    case json
    case image
    case originalFiles
}

struct HistoryItemExportSource: Sendable {
    let id: UUID
    let content: String
    let externalContentURL: URL?
    let kind: ContentKind
    let createdAt: Date
    let isPinned: Bool
    let containsSensitiveData: Bool
    let isProtected: Bool
    let sourceAppName: String?
    let sourceBundleIdentifier: String?
    let originalFileURLs: [URL]
    let imageURL: URL?
    let imageWidth: Int?
    let imageHeight: Int?
    let imageByteCount: Int?
    let imageSourceURL: String?
    let imageOriginalPath: String?
    let linkMetadata: LinkMetadata?
    let detectedBarcodes: [DetectedBarcode]?
    let ocrText: String?
    let userTitle: String?
    let userNote: String?
    let tags: [String]?
    let isLocked: Bool

    init(
        item: ClipboardItem,
        textDirectoryURL: URL,
        imageDirectoryURL: URL
    ) {
        id = item.id
        content = item.content
        externalContentURL = item.contentFileName.map {
            textDirectoryURL.appendingPathComponent($0, isDirectory: false)
        }
        kind = item.kind
        createdAt = item.createdAt
        isPinned = item.isPinned
        containsSensitiveData = item.containsSensitiveData
        isProtected = item.isProtected
        sourceAppName = item.sourceAppName
        sourceBundleIdentifier = item.sourceBundleIdentifier
        originalFileURLs = item.fileURLs
        imageURL = item.imageFileName.map {
            imageDirectoryURL.appendingPathComponent($0, isDirectory: false)
        }
        imageWidth = item.imageWidth
        imageHeight = item.imageHeight
        imageByteCount = item.imageByteCount
        imageSourceURL = item.imageSourceURL
        imageOriginalPath = item.imageOriginalPath
        linkMetadata = item.linkMetadata
        detectedBarcodes = item.detectedBarcodes
        ocrText = item.ocrText
        userTitle = item.userTitle
        userNote = item.userNote
        tags = item.tags
        isLocked = item.protectionState == .locked
    }
}

struct HistoryItemExportResult: Sendable, Equatable {
    let exportedURLs: [URL]
}

enum HistoryItemExporter {
    enum ExportError: LocalizedError, Equatable {
        case noItems
        case lockedItem
        case contentUnavailable
        case imageUnavailable
        case originalFilesUnavailable
        case singleImageRequired

        var errorDescription: String? {
            switch self {
            case .noItems:
                "No history items were selected.".localized
            case .lockedItem:
                "Unlock protected history before exporting this item.".localized
            case .contentUnavailable:
                "Content is no longer available".localized
            case .imageUnavailable:
                "Image file missing".localized
            case .originalFilesUnavailable:
                "Files are no longer available".localized
            case .singleImageRequired:
                "Export one image at a time.".localized
            }
        }
    }

    struct JSONDocument: Codable, Equatable, Sendable {
        let formatVersion: Int
        let exportedAt: Date
        let items: [JSONItem]
    }

    struct JSONItem: Codable, Equatable, Sendable {
        let id: UUID
        let kind: String
        let content: String
        let createdAt: Date
        let isPinned: Bool
        let containsSensitiveData: Bool
        let isProtected: Bool
        let sourceAppName: String?
        let sourceBundleIdentifier: String?
        let filePaths: [String]?
        let image: JSONImage?
        let linkMetadata: LinkMetadata?
        let detectedBarcodes: [DetectedBarcode]?
        let ocrText: String?
        let title: String?
        let note: String?
        let tags: [String]?
    }

    struct JSONImage: Codable, Equatable, Sendable {
        let width: Int?
        let height: Int?
        let byteCount: Int?
        let sourceURL: String?
        let originalPath: String?
    }

    static func suggestedFileName(
        for source: HistoryItemExportSource,
        format: HistoryItemExportFormat
    ) -> String? {
        guard format != .originalFiles else { return nil }
        let baseName = sanitizedFileName(
            source.userTitle ?? defaultBaseName(for: source)
        )
        let pathExtension = switch format {
        case .plainText: "txt"
        case .json: "json"
        case .image: "png"
        case .originalFiles: ""
        }
        return "\(baseName).\(pathExtension)"
    }

    @discardableResult
    static func export(
        _ sources: [HistoryItemExportSource],
        as format: HistoryItemExportFormat,
        to destinationURL: URL,
        exportedAt: Date = Date(),
        fileManager: FileManager = .default
    ) throws -> HistoryItemExportResult {
        guard !sources.isEmpty else { throw ExportError.noItems }
        guard !sources.contains(where: \.isLocked) else {
            throw ExportError.lockedItem
        }

        switch format {
        case .plainText:
            let values = try sources.map {
                try plainText(for: $0, fileManager: fileManager)
            }
            let text = values.joined(separator: "\n\n---\n\n")
            try text.write(
                to: destinationURL,
                atomically: true,
                encoding: .utf8
            )
            return HistoryItemExportResult(exportedURLs: [destinationURL])
        case .json:
            let document = try jsonDocument(
                for: sources,
                exportedAt: exportedAt,
                fileManager: fileManager
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(document).write(to: destinationURL, options: [.atomic])
            return HistoryItemExportResult(exportedURLs: [destinationURL])
        case .image:
            guard sources.count == 1, let source = sources.first else {
                throw ExportError.singleImageRequired
            }
            guard let imageURL = source.imageURL,
                  fileManager.fileExists(atPath: imageURL.path) else {
                throw ExportError.imageUnavailable
            }
            let data = try Data(contentsOf: imageURL, options: [.mappedIfSafe])
            try data.write(to: destinationURL, options: [.atomic])
            return HistoryItemExportResult(exportedURLs: [destinationURL])
        case .originalFiles:
            return try exportOriginalFiles(
                from: sources,
                to: destinationURL,
                fileManager: fileManager
            )
        }
    }

    private static func plainText(
        for source: HistoryItemExportSource,
        fileManager: FileManager
    ) throws -> String {
        if source.kind == .file, !source.originalFileURLs.isEmpty {
            return source.originalFileURLs.map(\.path).joined(separator: "\n")
        }
        if source.kind == .image,
           let ocrText = source.ocrText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !ocrText.isEmpty {
            return ocrText
        }
        return try resolvedContent(for: source, fileManager: fileManager)
    }

    private static func jsonDocument(
        for sources: [HistoryItemExportSource],
        exportedAt: Date,
        fileManager: FileManager
    ) throws -> JSONDocument {
        let items = try sources.map { source in
            let image = source.imageURL == nil ? nil : JSONImage(
                width: source.imageWidth,
                height: source.imageHeight,
                byteCount: source.imageByteCount,
                sourceURL: source.imageSourceURL,
                originalPath: source.imageOriginalPath
            )
            return JSONItem(
                id: source.id,
                kind: source.kind.rawValue,
                content: try resolvedContent(for: source, fileManager: fileManager),
                createdAt: source.createdAt,
                isPinned: source.isPinned,
                containsSensitiveData: source.containsSensitiveData,
                isProtected: source.isProtected,
                sourceAppName: source.sourceAppName,
                sourceBundleIdentifier: source.sourceBundleIdentifier,
                filePaths: source.originalFileURLs.isEmpty
                    ? nil
                    : source.originalFileURLs.map(\.path),
                image: image,
                linkMetadata: source.linkMetadata,
                detectedBarcodes: source.detectedBarcodes,
                ocrText: source.ocrText,
                title: source.userTitle,
                note: source.userNote,
                tags: source.tags
            )
        }
        return JSONDocument(formatVersion: 1, exportedAt: exportedAt, items: items)
    }

    private static func resolvedContent(
        for source: HistoryItemExportSource,
        fileManager: FileManager
    ) throws -> String {
        guard let externalContentURL = source.externalContentURL else {
            return source.content
        }
        guard fileManager.fileExists(atPath: externalContentURL.path),
              let content = try? String(contentsOf: externalContentURL, encoding: .utf8) else {
            throw ExportError.contentUnavailable
        }
        return content
    }

    private static func exportOriginalFiles(
        from sources: [HistoryItemExportSource],
        to directoryURL: URL,
        fileManager: FileManager
    ) throws -> HistoryItemExportResult {
        let sourceURLs = sources.flatMap(\.originalFileURLs)
        guard !sourceURLs.isEmpty,
              sourceURLs.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            throw ExportError.originalFilesUnavailable
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var copiedURLs: [URL] = []
        do {
            for sourceURL in sourceURLs {
                let destinationURL = availableDestinationURL(
                    for: sourceURL,
                    in: directoryURL,
                    fileManager: fileManager
                )
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                copiedURLs.append(destinationURL)
            }
        } catch {
            for copiedURL in copiedURLs {
                try? fileManager.removeItem(at: copiedURL)
            }
            throw error
        }
        return HistoryItemExportResult(exportedURLs: copiedURLs)
    }

    private static func availableDestinationURL(
        for sourceURL: URL,
        in directoryURL: URL,
        fileManager: FileManager
    ) -> URL {
        let preferredURL = directoryURL.appendingPathComponent(
            sourceURL.lastPathComponent,
            isDirectory: sourceURL.hasDirectoryPath
        )
        guard fileManager.fileExists(atPath: preferredURL.path) else {
            return preferredURL
        }

        let pathExtension = sourceURL.pathExtension
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var copyNumber = 2
        while true {
            let fileName = pathExtension.isEmpty
                ? "\(baseName) \(copyNumber)"
                : "\(baseName) \(copyNumber).\(pathExtension)"
            let candidate = directoryURL.appendingPathComponent(
                fileName,
                isDirectory: sourceURL.hasDirectoryPath
            )
            if !fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            copyNumber += 1
        }
    }

    private static func defaultBaseName(for source: HistoryItemExportSource) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "PastePilot \(source.kind.localizedTitle) \(formatter.string(from: source.createdAt))"
    }

    private static func sanitizedFileName(_ value: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.controlCharacters)
        let components = value.components(separatedBy: invalidCharacters)
        let normalized = components
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
                CharacterSet(charactersIn: ".")
            ))
        let clipped = String(normalized.prefix(80))
        return clipped.isEmpty ? "PastePilot Item".localized : clipped
    }
}
