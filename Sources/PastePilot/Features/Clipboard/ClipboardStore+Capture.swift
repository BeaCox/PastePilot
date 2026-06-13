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
        let wasPinned = items.first { $0.content == content }?.isPinned ?? false
        items.removeAll { $0.content == content }
        items.insert(
            ClipboardItem(
                content: content,
                kind: analysis.kind,
                isPinned: wasPinned,
                containsSensitiveData: analysis.containsSensitiveData,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier
            ),
            at: 0
        )
        trimHistory(limit: settings.historyLimit)
        save()
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
        let previous = items.first { $0.filePaths == paths }
        items.removeAll { $0.filePaths == paths }
        let content = normalized.map(\.lastPathComponent).joined(separator: "\n")
        items.insert(
            ClipboardItem(
                content: content,
                kind: .file,
                isPinned: previous?.isPinned ?? false,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier,
                filePaths: paths
            ),
            at: 0
        )
        trimHistory(limit: settings.historyLimit)
        save()
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

        let previous = items.first {
            $0.content == plainText && $0.kind == .richText
        }
        items.removeAll {
            $0.content == plainText && $0.kind == .richText
        }
        items.insert(
            ClipboardItem(
                content: plainText,
                kind: .richText,
                isPinned: previous?.isPinned ?? false,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier,
                richTextRTFBase64: rtfBase64,
                richTextHTML: html
            ),
            at: 0
        )
        trimHistory(limit: settings.historyLimit)
        save()
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
}
