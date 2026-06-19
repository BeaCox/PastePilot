import AppKit
import Foundation
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

        queue.async {
            let snapshot = Self.makeSnapshot(
                pasteboard: pasteboard,
                changeCount: changeCount
            )
            gate.complete { completion(snapshot) }
        }

        queue.asyncAfter(deadline: .now() + timeout) {
            gate.complete { completion(nil) }
        }
    }

    private static func makeSnapshot(
        pasteboard: NSPasteboard,
        changeCount: Int
    ) -> ClipboardCaptureSnapshot {
        let sourceBundleIdentifier = pasteboard.string(
            forType: sourcePasteboardType
        )
        let payload = filePayload(from: pasteboard)
            ?? imagePayload(from: pasteboard)
            ?? richTextPayload(from: pasteboard)
            ?? textPayload(from: pasteboard)

        return ClipboardCaptureSnapshot(
            changeCount: changeCount,
            sourceBundleIdentifier: sourceBundleIdentifier,
            payload: payload
        )
    }

    private static func filePayload(
        from pasteboard: NSPasteboard
    ) -> ClipboardCaptureSnapshot.Payload? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return nil }

        let normalized = urls
            .filter(\.isFileURL)
            .map(\.standardizedFileURL)
        if normalized.count == 1,
           let url = normalized.first,
           let imagePayload = imageFilePayload(url) {
            return imagePayload
        }

        return .files(urls)
    }

    private static func imagePayload(
        from pasteboard: NSPasteboard
    ) -> ClipboardCaptureSnapshot.Payload? {
        let origin = imageOriginMetadata(from: pasteboard)

        if let image = NSImage(pasteboard: pasteboard),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return .image(
                cgImage,
                remoteURL: origin.remoteURL,
                originalPath: origin.localPath
            )
        }

        guard let url = NSURL(from: pasteboard) as URL?,
              url.isFileURL,
              let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image),
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return .image(cgImage, remoteURL: origin.remoteURL, originalPath: url.path)
    }

    private static func imageFilePayload(
        _ url: URL
    ) -> ClipboardCaptureSnapshot.Payload? {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image),
              let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return .image(cgImage, remoteURL: nil, originalPath: url.path)
    }

    private static func richTextPayload(
        from pasteboard: NSPasteboard
    ) -> ClipboardCaptureSnapshot.Payload? {
        let rtfData = pasteboard.data(forType: .rtf)
        let html = pasteboard.string(forType: .html)
        guard rtfData != nil || html != nil else { return nil }

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

        guard let plainText = attributedString?.string
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !plainText.isEmpty else {
            return nil
        }
        return .richText(rtfData: rtfData, html: html, plainText: plainText)
    }

    private static func textPayload(
        from pasteboard: NSPasteboard
    ) -> ClipboardCaptureSnapshot.Payload? {
        guard let content = pasteboard.string(forType: .string),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return .text(content)
    }

    private static func imageOriginMetadata(
        from pasteboard: NSPasteboard
    ) -> (remoteURL: String?, localPath: String?) {
        let localURL = NSURL(from: pasteboard) as URL?
        let localPath: String?
        if let localURL,
           localURL.isFileURL,
           let type = UTType(filenameExtension: localURL.pathExtension),
           type.conforms(to: .image) {
            localPath = localURL.path
        } else {
            localPath = nil
        }

        if let html = pasteboard.string(forType: .html),
           let source = imageSourceFromHTML(html) {
            return (source, localPath)
        }

        let urlTypes = [
            NSPasteboard.PasteboardType.URL,
            NSPasteboard.PasteboardType(rawValue: "public.url"),
            NSPasteboard.PasteboardType(rawValue: "WebURLsWithTitlesPboardType")
        ]
        for type in urlTypes {
            guard let value = pasteboard.string(forType: type),
                  let url = URL(string: value),
                  ["http", "https"].contains(url.scheme?.lowercased()) else {
                continue
            }
            return (url.absoluteString, localPath)
        }

        return (nil, localPath)
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
