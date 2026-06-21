import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ClipboardCaptureSnapshot {
    enum Payload {
        case files([URL])
        case image(CGImage, remoteURL: String?, originalPath: String?)
        case richText(rtfData: Data?, html: String?, plainText: String)
        case text(String)
    }

    let changeCount: Int
    let sourceBundleIdentifier: String?
    let payload: Payload?
}

protocol ClipboardCapturing {
    func capture(
        pasteboard: NSPasteboard,
        changeCount: Int,
        completion: @escaping (ClipboardCaptureSnapshot?) -> Void
    )
}

final class ClipboardCaptureQueue {
    private static let sourcePasteboardType = NSPasteboard.PasteboardType(
        rawValue: "org.nspasteboard.source"
    )
    private let queue = DispatchQueue(
        label: "PastePilot.ClipboardCaptureQueue",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 1.5) {
        self.timeout = timeout
    }

    func capture(
        pasteboard: NSPasteboard,
        changeCount: Int,
        completion: @escaping (ClipboardCaptureSnapshot?) -> Void
    ) {
        let gate = CompletionGate()

        DispatchQueue.main.async { [queue] in
            let pasteboardData = Self.readPasteboardData(from: pasteboard)
            queue.async {
                let snapshot = Self.makeSnapshot(
                    pasteboardData: pasteboardData,
                    changeCount: changeCount
                )
                gate.complete { completion(snapshot) }
            }
        }

        queue.asyncAfter(deadline: .now() + timeout) {
            gate.complete { completion(nil) }
        }
    }

    private static func readPasteboardData(
        from pasteboard: NSPasteboard
    ) -> CapturedPasteboardData {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
        let types = pasteboard.types ?? []
        let imageRepresentations = Self.imageRepresentations(
            from: pasteboard,
            types: types
        )
        let urlTypes = Self.urlPasteboardTypes
        let urlStrings = urlTypes.compactMap { pasteboard.string(forType: $0) }
        let rtfData = pasteboard.data(forType: .rtf)
        let html = pasteboard.string(forType: .html)

        return CapturedPasteboardData(
            sourceBundleIdentifier: pasteboard.string(forType: sourcePasteboardType),
            fileURLs: urls,
            pasteboardURL: NSURL(from: pasteboard) as URL?,
            imageRepresentations: imageRepresentations,
            rtfData: rtfData,
            html: html,
            richTextPlainText: plainText(rtfData: rtfData, html: html),
            text: pasteboard.string(forType: .string),
            urlStrings: urlStrings
        )
    }

    private static func makeSnapshot(
        pasteboardData: CapturedPasteboardData,
        changeCount: Int
    ) -> ClipboardCaptureSnapshot {
        let payload = filePayload(from: pasteboardData)
            ?? imagePayload(from: pasteboardData)
            ?? richTextPayload(from: pasteboardData)
            ?? textPayload(from: pasteboardData)

        return ClipboardCaptureSnapshot(
            changeCount: changeCount,
            sourceBundleIdentifier: pasteboardData.sourceBundleIdentifier,
            payload: payload
        )
    }

    private static func filePayload(
        from pasteboardData: CapturedPasteboardData
    ) -> ClipboardCaptureSnapshot.Payload? {
        guard !pasteboardData.fileURLs.isEmpty else { return nil }

        let normalized = pasteboardData.fileURLs
            .filter(\.isFileURL)
            .map(\.standardizedFileURL)
        if normalized.count == 1,
           let url = normalized.first,
           let imagePayload = imageFilePayload(url) {
            return imagePayload
        }

        return .files(pasteboardData.fileURLs)
    }

    private static func imagePayload(
        from pasteboardData: CapturedPasteboardData
    ) -> ClipboardCaptureSnapshot.Payload? {
        let origin = imageOriginMetadata(from: pasteboardData)

        if let cgImage = pasteboardData.imageRepresentations.lazy
            .compactMap(cgImage)
            .first {
            return .image(
                cgImage,
                remoteURL: origin.remoteURL,
                originalPath: origin.localPath
            )
        }

        guard let url = pasteboardData.pasteboardURL,
              url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image),
              let cgImage = cgImage(contentsOf: url) else {
            return nil
        }
        return .image(cgImage, remoteURL: origin.remoteURL, originalPath: url.path)
    }

    private static func imageFilePayload(
        _ url: URL
    ) -> ClipboardCaptureSnapshot.Payload? {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image),
              let cgImage = cgImage(contentsOf: url) else {
            return nil
        }
        return .image(cgImage, remoteURL: nil, originalPath: url.path)
    }

    private static func richTextPayload(
        from pasteboardData: CapturedPasteboardData
    ) -> ClipboardCaptureSnapshot.Payload? {
        let rtfData = pasteboardData.rtfData
        let html = pasteboardData.html
        guard rtfData != nil || html != nil else { return nil }

        guard let plainText = pasteboardData.richTextPlainText,
              !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return .richText(rtfData: rtfData, html: html, plainText: plainText)
    }

    private static func plainText(rtfData: Data?, html: String?) -> String? {
        let attributedString: NSAttributedString?
        if let rtfData {
            attributedString = try? NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        } else if let html,
                  let data = html.data(using: .utf8) {
            attributedString = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            )
        } else {
            attributedString = nil
        }
        return attributedString?.string
    }

    private static func textPayload(
        from pasteboardData: CapturedPasteboardData
    ) -> ClipboardCaptureSnapshot.Payload? {
        guard let content = pasteboardData.text,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return .text(content)
    }

    private static func imageOriginMetadata(
        from pasteboardData: CapturedPasteboardData
    ) -> (remoteURL: String?, localPath: String?) {
        let localURL = pasteboardData.pasteboardURL
        let localPath: String?
        if let localURL,
           localURL.isFileURL,
           let type = UTType(filenameExtension: localURL.pathExtension),
           type.conforms(to: .image) {
            localPath = localURL.path
        } else {
            localPath = nil
        }

        if let html = pasteboardData.html,
           let source = imageSourceFromHTML(html) {
            return (source, localPath)
        }

        for value in pasteboardData.urlStrings {
            guard let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased()) else {
                continue
            }
            return (url.absoluteString, localPath)
        }

        return (nil, localPath)
    }

    private static func cgImage(
        from representation: ImageRepresentation
    ) -> CGImage? {
        let options = [
            kCGImageSourceTypeIdentifierHint: representation.typeIdentifier
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithData(
            representation.data as CFData,
            options
        ) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func imageRepresentations(
        from pasteboard: NSPasteboard,
        types: [NSPasteboard.PasteboardType]
    ) -> [ImageRepresentation] {
        let orderedTypes = preferredImagePasteboardTypes
            .filter(types.contains)
            + types.filter { type in
                !preferredImagePasteboardTypes.contains(type)
                    && UTType(type.rawValue)?.conforms(to: .image) == true
            }

        return orderedTypes.compactMap { type in
            guard let data = pasteboard.data(forType: type),
                  let uniformType = UTType(type.rawValue),
                  uniformType.conforms(to: .image) else {
                return nil
            }
            return ImageRepresentation(
                data: data,
                typeIdentifier: uniformType.identifier
            )
        }
    }

    private static func cgImage(contentsOf url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static let urlPasteboardTypes = [
        NSPasteboard.PasteboardType.URL,
        NSPasteboard.PasteboardType(rawValue: "public.url"),
        NSPasteboard.PasteboardType(rawValue: "WebURLsWithTitlesPboardType")
    ]

    private static let preferredImagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff
    ]

    private struct CapturedPasteboardData {
        let sourceBundleIdentifier: String?
        let fileURLs: [URL]
        let pasteboardURL: URL?
        let imageRepresentations: [ImageRepresentation]
        let rtfData: Data?
        let html: String?
        let richTextPlainText: String?
        let text: String?
        let urlStrings: [String]
    }

    private struct ImageRepresentation {
        let data: Data
        let typeIdentifier: String
    }

    private static let imgSrcRegex = RegexFactory.make(
        #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#,
        options: [.caseInsensitive]
    )

    private static func imageSourceFromHTML(_ html: String) -> String? {
        guard let imgSrcRegex,
              let match = imgSrcRegex.firstMatch(
            in: html,
            range: NSRange(html.startIndex..., in: html)
        ),
        match.numberOfRanges > 1,
        let range = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let rawValue = String(html[range])
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
        guard let url = URL(string: rawValue),
              ["http", "https"].contains(url.scheme?.lowercased()) else {
            return nil
        }
        return url.absoluteString
    }
}

extension ClipboardCaptureQueue: ClipboardCapturing {}

private final class CompletionGate {
    private let lock = NSLock()
    private var didComplete = false

    func complete(_ body: () -> Void) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        lock.unlock()
        body()
    }
}
