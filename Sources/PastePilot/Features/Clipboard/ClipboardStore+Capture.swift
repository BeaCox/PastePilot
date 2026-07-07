import AppKit
import Foundation

struct RetainedRichTextPayload {
    let rtfBase64: String?
    let html: String?
    let didDiscardRepresentation: Bool

    var hasFormatting: Bool {
        rtfBase64 != nil || html != nil
    }
}

struct SensitiveContentStorageResult {
    let content: String
    let kind: ContentKind
    let containsSensitiveData: Bool
    let richTextRTFBase64: String?
    let richTextHTML: String?
}

enum RichTextPayloadPolicy {
    static let historyByteLimit = 256 * 1_024

    static func retainedPayload(
        rtfBase64: String?,
        html: String?
    ) -> RetainedRichTextPayload {
        var remainingBytes = historyByteLimit
        var retainedRTFBase64: String?
        var retainedHTML: String?
        var didDiscardRepresentation = false

        if let rtfBase64 {
            let byteCount = rtfBase64.utf8.count
            if byteCount <= remainingBytes {
                retainedRTFBase64 = rtfBase64
                remainingBytes -= byteCount
            } else {
                didDiscardRepresentation = true
            }
        }

        if let html {
            let byteCount = html.utf8.count
            if byteCount <= remainingBytes {
                retainedHTML = html
            } else {
                didDiscardRepresentation = true
            }
        }

        return RetainedRichTextPayload(
            rtfBase64: retainedRTFBase64,
            html: retainedHTML,
            didDiscardRepresentation: didDiscardRepresentation
        )
    }
}

extension ClipboardStore {
    func captureIfNeeded() {
        if Date().timeIntervalSince(lastPurgeCheck) > 60 {
            lastPurgeCheck = Date()
            purgeExpired()
        }
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        guard pendingCaptureChangeCount != changeCount else { return }

        if let baseline = ignoreNextCopyBaselineChangeCount,
           changeCount != baseline {
            ignoreNextCopyBaselineChangeCount = nil
            pendingCaptureChangeCount = nil
            lastChangeCount = changeCount
            noticePoster.post(
                PastePilotNotice(
                    "Ignored copied item".localized,
                    style: .success
                )
            )
            return
        }

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
        let source = (
            name: snapshot.sourceAppName,
            bundleIdentifier: snapshot.sourceBundleIdentifier
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

        let userPatterns = settings.userSensitivePatterns
        let analysis = ContentAnalyzer.analyze(
            trimmedContent,
            userPatterns: userPatterns
        )
        guard !isIgnored(bundleIdentifier: source.bundleIdentifier) else { return }
        guard let storageResult = sensitiveContentStorageResult(
            content: content,
            kind: analysis.kind,
            containsSensitiveData: analysis.containsSensitiveData,
            richTextRTFBase64: nil,
            richTextHTML: nil,
            userPatterns: userPatterns
        ) else {
            return
        }
        saveCapturedText(
            storageResult,
            source: source,
            pasteboardChangeCount: pasteboardChangeCount
        )
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
        if processedContent.externalizationFailed {
            noticePoster.post(
                PastePilotNotice(
                    "Large text could not be saved separately".localized,
                    style: .warning
                )
            )
        }
        insertCaptured(
            duplicate: {
                self.content(
                    $0,
                    matches: originalContent,
                    digest: processedContent.digest
                )
                    && (kind == .richText) == ($0.kind == .richText)
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
        let payload = RichTextPayloadPolicy.retainedPayload(
            rtfBase64: rtfBase64,
            html: html
        )
        let userPatterns = settings.userSensitivePatterns
        let trimmedPlainText = plainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = payload.hasFormatting
            ? ContentKind.richText
            : ContentAnalyzer.analyze(
                trimmedPlainText,
                userPatterns: userPatterns
            ).kind
        let containsSensitiveData = ContentAnalyzer.containsSensitiveData(
            plainText,
            userPatterns: userPatterns
        )
        guard items.first?.content != plainText
                || items.first?.richTextRTFBase64 != payload.rtfBase64
                || items.first?.richTextHTML != payload.html else {
            return true
        }
        guard let storageResult = sensitiveContentStorageResult(
            content: plainText,
            kind: kind,
            containsSensitiveData: containsSensitiveData,
            richTextRTFBase64: payload.rtfBase64,
            richTextHTML: payload.html,
            userPatterns: userPatterns
        ) else {
            return true
        }
        if payload.didDiscardRepresentation {
            noticePoster.post(
                PastePilotNotice(
                    "Rich text formatting was too large to preserve".localized,
                    style: .warning
                )
            )
        }

        saveCapturedText(
            storageResult,
            source: source,
            pasteboardChangeCount: pasteboardChangeCount
        )
        return true
    }

    func saveCapturedText(
        _ storageResult: SensitiveContentStorageResult,
        source: (name: String?, bundleIdentifier: String?),
        pasteboardChangeCount: Int?
    ) {
        let id = UUID()
        if storageResult.content.utf8.count <= ClipboardTextStore.externalizationByteLimit {
            let processedContent = ClipboardTextWriteQueue.process(
                storageResult.content,
                id: id,
                textStore: textStore,
                logger: logger
            )
            finishCapturingText(
                processedContent,
                originalContent: storageResult.content,
                id: id,
                kind: storageResult.kind,
                containsSensitiveData: storageResult.containsSensitiveData,
                source: source,
                richTextRTFBase64: storageResult.richTextRTFBase64,
                richTextHTML: storageResult.richTextHTML,
                pasteboardChangeCount: pasteboardChangeCount
            )
            return
        }

        textWriteQueue.processAndSave(
            storageResult.content,
            id: id,
            textStore: textStore,
            logger: logger
        ) { [weak self] processedContent in
            Task { @MainActor in
                guard let self else { return }
                self.finishCapturingText(
                    processedContent,
                    originalContent: storageResult.content,
                    id: id,
                    kind: storageResult.kind,
                    containsSensitiveData: storageResult.containsSensitiveData,
                    source: source,
                    richTextRTFBase64: storageResult.richTextRTFBase64,
                    richTextHTML: storageResult.richTextHTML,
                    pasteboardChangeCount: pasteboardChangeCount
                )
            }
        }
    }

    func isIgnored(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return settings.ignoredBundleIdentifierSet.contains(bundleIdentifier)
    }

    func sensitiveContentStorageResult(
        content: String,
        kind: ContentKind,
        containsSensitiveData: Bool,
        richTextRTFBase64: String?,
        richTextHTML: String?,
        userPatterns: [UserSensitivePattern] = []
    ) -> SensitiveContentStorageResult? {
        guard containsSensitiveData else {
            return SensitiveContentStorageResult(
                content: content,
                kind: kind,
                containsSensitiveData: false,
                richTextRTFBase64: richTextRTFBase64,
                richTextHTML: richTextHTML
            )
        }

        let policy = SensitiveContentStoragePolicy(
            rawValue: settings.sensitiveContentStoragePolicy
        ) ?? .storeOriginal

        switch policy {
        case .storeOriginal:
            return SensitiveContentStorageResult(
                content: content,
                kind: kind,
                containsSensitiveData: true,
                richTextRTFBase64: richTextRTFBase64,
                richTextHTML: richTextHTML
            )
        case .storeRedacted:
            let redactedContent = ContentAnalyzer.redacted(
                content,
                userPatterns: userPatterns
            )
            let redactedKind = kind == .richText
                ? ContentAnalyzer.analyze(
                    redactedContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    userPatterns: userPatterns
                ).kind
                : kind
            return SensitiveContentStorageResult(
                content: redactedContent,
                kind: redactedKind,
                containsSensitiveData: false,
                richTextRTFBase64: nil,
                richTextHTML: nil
            )
        case .skip:
            return nil
        }
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
        enforceStorageLimit()
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
