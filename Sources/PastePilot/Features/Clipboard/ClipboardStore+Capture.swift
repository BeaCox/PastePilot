import AppKit
import Foundation

extension ClipboardStore {
    func captureIfNeeded() {
        if Date().timeIntervalSince(lastPurgeCheck) > 60 {
            lastPurgeCheck = Date()
            purgeExpired()
        }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        pasteboardCaptureQueue.capture(
            pasteboard: pasteboard,
            changeCount: changeCount
        ) { [weak self] snapshot in
            Task { @MainActor in
                guard let self, let snapshot else { return }
                self.applyCaptureSnapshot(snapshot)
            }
        }
    }

    func applyCaptureSnapshot(_ snapshot: ClipboardCaptureSnapshot) {
        guard pasteboard.changeCount == snapshot.changeCount else { return }
        let source = sourceApplication(
            pasteboardBundleIdentifier: snapshot.sourceBundleIdentifier
        )

        switch snapshot.payload {
        case .files(let urls):
            captureFiles(
                urls: urls,
                source: source,
                pasteboardChangeCount: snapshot.changeCount
            )
        case .image(let cgImage, let remoteURL, let originalPath):
            _ = saveImage(
                cgImage,
                source: source,
                remoteURL: remoteURL,
                originalPath: originalPath,
                pasteboardChangeCount: snapshot.changeCount
            )
        case .richText(let rtfData, let html, let plainText):
            _ = captureRichText(
                rtfData: rtfData,
                html: html,
                plainText: plainText,
                source: source
            )
        case .text(let content):
            captureText(content, source: source)
        case .none:
            return
        }
    }

    func captureText(
        _ content: String,
        source: (name: String?, bundleIdentifier: String?)
    ) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return
        }
        if content == ignoredContent {
            ignoredContent = nil
            return
        }
        guard items.first?.content != content else { return }

        let analysis = ContentAnalyzer.analyze(trimmedContent)
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

    func captureRichText(
        rtfData: Data?,
        html: String?,
        plainText: String,
        source: (name: String?, bundleIdentifier: String?)
    ) -> Bool {
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
        sourceApplication(
            pasteboardBundleIdentifier: pasteboard.string(forType: Self.sourcePasteboardType)
        )
    }

    func sourceApplication(
        pasteboardBundleIdentifier: String?
    ) -> (name: String?, bundleIdentifier: String?) {
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
