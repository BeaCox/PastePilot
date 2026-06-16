import AppKit
import Foundation

extension ClipboardStore {
    func captureIfNeeded() {
        if Date().timeIntervalSince(lastPurgeCheck) > 60 {
            lastPurgeCheck = Date()
            purgeExpired()
        }
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        if captureFileURLsIfAvailable() {
            return
        }
        if captureImageIfAvailable() {
            return
        }
        if captureRichTextIfAvailable() {
            return
        }
        guard let content = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else {
            return
        }
        if content == ignoredContent {
            ignoredContent = nil
            return
        }
        guard items.first?.content != content else { return }

        let analysis = ContentAnalyzer.analyze(content)
        let source = sourceApplication()
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return }
        insertCaptured(duplicate: { $0.content == content }) { wasPinned in
            ClipboardItem(
                content: content,
                kind: analysis.kind,
                isPinned: wasPinned,
                containsSensitiveData: analysis.containsSensitiveData,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier
            )
        }
    }

    func captureFileURLsIfAvailable() -> Bool {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        captureFiles(
            urls: urls,
            source: sourceApplication(),
            pasteboardChangeCount: pasteboard.changeCount
        )
        return true
    }

    func captureFiles(
        urls: [URL],
        source: (name: String?, bundleIdentifier: String?),
        pasteboardChangeCount: Int?
    ) {
        let normalized = urls
            .filter(\.isFileURL)
            .map(\.standardizedFileURL)
        guard !normalized.isEmpty,
              !isIgnored(bundleIdentifier: source.bundleIdentifier) else {
            return
        }

        if normalized.count == 1,
           let url = normalized.first,
           isImageFile(url),
           captureImageFile(
               url,
               source: source,
               pasteboardChangeCount: pasteboardChangeCount
           ) {
            return
        }

        let paths = normalized.map(\.path)
        guard items.first?.filePaths != paths else { return }
        let content = normalized.map(\.lastPathComponent).joined(separator: "\n")
        insertCaptured(duplicate: { $0.filePaths == paths }) { wasPinned in
            ClipboardItem(
                content: content,
                kind: .file,
                isPinned: wasPinned,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier,
                filePaths: paths
            )
        }
    }

    func captureRichTextIfAvailable() -> Bool {
        let rtfData = pasteboard.data(forType: .rtf)
        let html = pasteboard.string(forType: .html)
        guard rtfData != nil || html != nil else { return false }

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

        let plainText = attributedString?.string
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plainText, !plainText.isEmpty else { return false }
        let source = sourceApplication()
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return true }
        let rtfBase64 = rtfData?.base64EncodedString()
        guard items.first?.content != plainText
                || items.first?.richTextRTFBase64 != rtfBase64
                || items.first?.richTextHTML != html else {
            return true
        }

        insertCaptured(
            duplicate: { $0.content == plainText && $0.kind == .richText }
        ) { wasPinned in
            ClipboardItem(
                content: plainText,
                kind: .richText,
                isPinned: wasPinned,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier,
                richTextRTFBase64: rtfBase64,
                richTextHTML: html
            )
        }
        return true
    }

    func sourceApplication() -> (name: String?, bundleIdentifier: String?) {
        let pasteboardBundleIdentifier = pasteboard.string(forType: Self.sourcePasteboardType)
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let bundleIdentifier = pasteboardBundleIdentifier
            ?? frontmostApplication?.bundleIdentifier

        if let bundleIdentifier {
            let runningName = NSRunningApplication
                .runningApplications(withBundleIdentifier: bundleIdentifier)
                .first?
                .localizedName
            let installedName = NSWorkspace.shared
                .urlForApplication(withBundleIdentifier: bundleIdentifier)
                .flatMap { Bundle(url: $0) }?
                .object(forInfoDictionaryKey: "CFBundleName") as? String
            return (runningName ?? installedName, bundleIdentifier)
        }

        return (
            frontmostApplication?.localizedName,
            frontmostApplication?.bundleIdentifier
        )
    }

    func isIgnored(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return settings.ignoredBundleIdentifierSet.contains(bundleIdentifier)
    }

    /// Removes any existing items matching `duplicate`, inserts `make` at the
    /// front (preserving a previously matching item's pinned state), then trims
    /// and persists. Returns the pinned state carried over from the duplicate.
    @discardableResult
    func insertCaptured(
        duplicate: (ClipboardItem) -> Bool,
        make: (_ wasPinned: Bool) -> ClipboardItem
    ) -> Bool {
        let wasPinned = items.first(where: duplicate)?.isPinned ?? false
        items.removeAll(where: duplicate)
        items.insert(make(wasPinned), at: 0)
        trimHistory(limit: settings.historyLimit)
        save()
        return wasPinned
    }
}
