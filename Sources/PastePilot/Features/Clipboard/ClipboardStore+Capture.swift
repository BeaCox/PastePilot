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
        guard pendingCaptureChangeCount != changeCount else { return }
        pendingCaptureChangeCount = changeCount

        pasteboardCaptureQueue.capture(
            pasteboard: pasteboard,
            changeCount: changeCount
        ) { [weak self] snapshot in
            Task { @MainActor in
                guard let self else { return }
                if self.pendingCaptureChangeCount == changeCount {
                    self.pendingCaptureChangeCount = nil
                }
                guard let snapshot else { return }
                self.applyCaptureSnapshot(snapshot)
            }
        }
    }

    func applyCaptureSnapshot(_ snapshot: ClipboardCaptureSnapshot) {
        guard pasteboard.changeCount == snapshot.changeCount else { return }
        lastChangeCount = snapshot.changeCount
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
                source: source,
                pasteboardChangeCount: snapshot.changeCount
            )
        case .text(let content):
            captureText(
                content,
                source: source,
                pasteboardChangeCount: snapshot.changeCount
            )
        case .none:
            return
        }
    }

    func captureText(
        _ content: String,
        source: (name: String?, bundleIdentifier: String?),
        pasteboardChangeCount: Int? = nil
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
        let id = UUID()
        if content.utf8.count <= ClipboardTextStore.externalizationByteLimit {
            let processedContent = ClipboardTextWriteQueue.process(
                content,
                id: id,
                textStore: textStore
            )
            finishCapturingText(
                processedContent,
                originalContent: content,
                id: id,
                kind: analysis.kind,
                containsSensitiveData: analysis.containsSensitiveData,
                source: source,
                richTextRTFBase64: nil,
                richTextHTML: nil,
                pasteboardChangeCount: pasteboardChangeCount
            )
            return
        }

        textWriteQueue.processAndSave(
            content,
            id: id,
            textStore: textStore
        ) { [weak self] processedContent in
            Task { @MainActor in
                guard let self else { return }
                self.finishCapturingText(
                    processedContent,
                    originalContent: content,
                    id: id,
                    kind: analysis.kind,
                    containsSensitiveData: analysis.containsSensitiveData,
                    source: source,
                    richTextRTFBase64: nil,
                    richTextHTML: nil,
                    pasteboardChangeCount: pasteboardChangeCount
                )
            }
        }
    }

    func finishCapturingText(
        _ processedContent: ProcessedClipboardText,
        originalContent: String,
        id: UUID,
        kind: ContentKind,
        containsSensitiveData: Bool,
        source: (name: String?, bundleIdentifier: String?),
        richTextRTFBase64: String?,
        richTextHTML: String?,
        pasteboardChangeCount: Int?
    ) {
        guard pasteboardChangeCount.map({ pasteboard.changeCount == $0 }) ?? true else {
            if let fileName = processedContent.fileName {
                textStore.delete(fileName: fileName)
            }
            return
        }
        insertCaptured(
            duplicate: {
                self.content(
                    $0,
                    matches: originalContent,
                    digest: processedContent.digest
                )
                    && (kind != .richText || $0.kind == .richText)
            }
        ) { wasPinned in
            ClipboardItem(
                id: id,
                content: processedContent.content,
                kind: kind,
                isPinned: wasPinned,
                containsSensitiveData: containsSensitiveData,
                sourceAppName: source.name,
                sourceBundleIdentifier: source.bundleIdentifier,
                richTextRTFBase64: richTextRTFBase64,
                richTextHTML: richTextHTML,
                contentFileName: processedContent.fileName,
                contentDigest: processedContent.digest,
                contentCharacterCount: processedContent.characterCount,
                contentLineCount: processedContent.lineCount,
                contentByteCount: processedContent.byteCount
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
        source: (name: String?, bundleIdentifier: String?),
        pasteboardChangeCount: Int? = nil
    ) -> Bool {
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return true }
        let rtfBase64 = rtfData?.base64EncodedString()
        guard items.first?.content != plainText
                || items.first?.richTextRTFBase64 != rtfBase64
                || items.first?.richTextHTML != html else {
            return true
        }

        let id = UUID()
        if plainText.utf8.count <= ClipboardTextStore.externalizationByteLimit {
            let processedContent = ClipboardTextWriteQueue.process(
                plainText,
                id: id,
                textStore: textStore
            )
            finishCapturingText(
                processedContent,
                originalContent: plainText,
                id: id,
                kind: .richText,
                containsSensitiveData: ContentAnalyzer.containsSensitiveData(plainText),
                source: source,
                richTextRTFBase64: rtfBase64,
                richTextHTML: html,
                pasteboardChangeCount: pasteboardChangeCount
            )
            return true
        }

        textWriteQueue.processAndSave(
            plainText,
            id: id,
            textStore: textStore
        ) { [weak self] processedContent in
            Task { @MainActor in
                guard let self else { return }
                self.finishCapturingText(
                    processedContent,
                    originalContent: plainText,
                    id: id,
                    kind: .richText,
                    containsSensitiveData: ContentAnalyzer
                        .containsSensitiveData(plainText),
                    source: source,
                    richTextRTFBase64: rtfBase64,
                    richTextHTML: html,
                    pasteboardChangeCount: pasteboardChangeCount
                )
            }
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
        let duplicateItems = items.filter(duplicate)
        let wasPinned = duplicateItems.first?.isPinned ?? false
        duplicateItems.forEach(deleteStoredResources)
        items.removeAll(where: duplicate)
        items.insert(make(wasPinned), at: 0)
        trimHistory(limit: settings.historyLimit)
        save()
        return wasPinned
    }

    private func content(
        _ item: ClipboardItem,
        matches content: String,
        digest: String
    ) -> Bool {
        if item.contentDigest == digest {
            return true
        }
        if let fileName = item.contentFileName {
            return textStore.content(fileName: fileName) == content
        }
        return item.content == content
    }
}
