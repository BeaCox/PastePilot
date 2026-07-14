import Foundation

extension ClipboardStore {
    func sortItems() {
        items = ClipboardHistoryOrdering.pinnedFirst(items)
    }

    func trimHistory(limit: Int) {
        let chronological = ClipboardHistoryOrdering.newestFirst(items)
        let pinned = chronological.filter(\.isPinned)
        let recent = chronological.filter { !$0.isPinned }.prefix(max(1, limit))
        let retainedIDs = Set((pinned + recent).map(\.id))
        let removedItems = items.filter { !retainedIDs.contains($0.id) }
        cancelOCR(for: removedItems)
        removedItems.forEach(deleteStoredResources)
        items = items.filter { retainedIDs.contains($0.id) }
        sortItems()
    }

    func localStorageByteCount() -> Int64 {
        historyRepository.dataDirectoryByteCount()
    }

    @discardableResult
    func exportBackup(to archiveURL: URL) throws -> HistoryBackupResult {
        historyWriteQueue.flush()
        try historyRepository.save(items)
        let result = try historyRepository.exportBackup(to: archiveURL)
        noticePoster.post(
            PastePilotNotice(
                "Backup exported".localized,
                style: .success
            )
        )
        return result
    }

    @discardableResult
    func restoreBackup(from archiveURL: URL) throws -> HistoryRestoreResult {
        historyWriteQueue.flush()
        cancelAllOCRTasks()
        cancelAllEnrichmentTasks()
        discardPendingImageSaves()
        let result = try historyRepository.restoreBackup(from: archiveURL)
        thumbnailCache.removeAllObjects()
        load()
        noticePoster.post(
            PastePilotNotice(
                "Backup restored".localized,
                style: .success
            )
        )
        return result
    }

    func estimatedRetainedStorageByteCount() -> Int64 {
        estimatedStorageByteCount(for: items)
    }

    func estimatedStorageByteCount(for items: [ClipboardItem]) -> Int64 {
        estimatedStorageByteCount(
            for: items,
            imageByteCounts: imageByteCounts(for: items),
            textByteCounts: textByteCounts(for: items)
        )
    }

    private func estimatedStorageByteCount(
        for items: [ClipboardItem],
        imageByteCounts: [String: Int64],
        textByteCounts: [String: Int64]
    ) -> Int64 {
        var total = historyRepository.estimatedHistoryByteCount(for: items)
        total += Set(items.compactMap(\.imageFileName)).reduce(Int64(0)) {
            $0 + (imageByteCounts[$1] ?? 0)
        }
        total += Set(items.compactMap(\.contentFileName)).reduce(Int64(0)) {
            $0 + (textByteCounts[$1] ?? 0)
        }
        return total
    }

    private func imageByteCounts(for items: [ClipboardItem]) -> [String: Int64] {
        byteCounts(
            for: Set(items.compactMap(\.imageFileName)),
            byteCount: imageStore.byteCount
        )
    }

    private func textByteCounts(for items: [ClipboardItem]) -> [String: Int64] {
        byteCounts(
            for: Set(items.compactMap(\.contentFileName)),
            byteCount: textStore.byteCount
        )
    }

    private func byteCounts(
        for fileNames: Set<String>,
        byteCount: (String) -> Int64
    ) -> [String: Int64] {
        Dictionary(uniqueKeysWithValues: fileNames.map { ($0, byteCount($0)) })
    }

    @discardableResult
    func enforceStorageLimit() -> Bool {
        let limit = Int64(settings.storageLimitMB) * 1_024 * 1_024
        guard limit > 0 else { return false }

        removeOrphanedImages()
        removeOrphanedText()

        let imageByteCounts = imageByteCounts(for: items)
        let textByteCounts = textByteCounts(for: items)
        var retainedItems = items
        var retainedByteCount = estimatedStorageByteCount(
            for: retainedItems,
            imageByteCounts: imageByteCounts,
            textByteCounts: textByteCounts
        )
        var removedIDs = Set<UUID>()

        let removableItems = items
            .filter { !$0.isPinned }
            .sorted { $0.createdAt < $1.createdAt }
        for item in removableItems {
            guard retainedByteCount > limit else { break }
            removedIDs.insert(item.id)
            retainedItems.removeAll { $0.id == item.id }
            retainedByteCount = estimatedStorageByteCount(
                for: retainedItems,
                imageByteCounts: imageByteCounts,
                textByteCounts: textByteCounts
            )
        }

        guard !removedIDs.isEmpty else { return false }
        let removedItems = items.filter { removedIDs.contains($0.id) }
        cancelOCR(for: removedItems)
        removedItems.forEach(deleteStoredResources)
        items = retainedItems
        sortItems()
        return true
    }

    func applyStorageLimit() {
        guard enforceStorageLimit() else { return }
        save()
    }

    func load() {
        let result = historyRepository.load()
        items = result.items
        let externalizedLoadedText = externalizeLoadedLargeTextContent()
        switch result.source {
        case .primary:
            if externalizedLoadedText {
                save()
            }
            removeOrphanedImages()
            removeOrphanedText()
        case .backup:
            logger.log("PastePilot recovered clipboard history from backup")
            save()
            removeOrphanedImages()
            removeOrphanedText()
        case .unrecoverable:
            logger.log("PastePilot could not decode clipboard history or its backup")
        case .empty:
            break
        }
        sortItems()
        purgeExpired()
        applyStorageLimit()
    }

    func externalizeLoadedLargeTextContent() -> Bool {
        var didExternalize = false
        items = items.map { item in
            guard item.contentFileName == nil,
                  item.kind != .file,
                  item.kind != .image,
                  item.content.utf8.count > ClipboardTextStore.externalizationByteLimit else {
                return item
            }

            let fileName = "\(item.id.uuidString).txt"
            let processedContent = ClipboardTextWriteQueue.process(
                item.content,
                id: item.id,
                textStore: textStore,
                logger: logger
            )
            if processedContent.fileName != nil {
                didExternalize = true
                return item.externalizedContent(
                    fileName: fileName,
                    digest: processedContent.digest
                )
            }
            return item
        }
        return didExternalize
    }

    func removeOrphanedImages() {
        imageStore.removeOrphans(
            retaining: Set(items.compactMap(\.imageFileName))
        )
    }

    func removeOrphanedText() {
        textStore.removeOrphans(
            retaining: Set(items.compactMap(\.contentFileName))
        )
    }

    func save() {
        let noticePoster = noticePoster
        let logger = logger
        historyWriteQueue.save(items) { error in
            if let error {
                logger.log("PastePilot failed to save history: \(error)")
                noticePoster.post(
                    PastePilotNotice(
                        "History could not be saved".localized,
                        style: .error
                    )
                )
            }
        }
    }

    func deleteImageFile(for item: ClipboardItem) {
        markDeletedImageDigest(for: item)
        guard let fileName = item.imageFileName else { return }
        thumbnailCache.removeObject(forKey: "\(fileName)-22" as NSString)
        imageStore.delete(fileName: fileName)
    }

    func deleteTextFile(for item: ClipboardItem) {
        guard let fileName = item.contentFileName else { return }
        textStore.delete(fileName: fileName)
    }

    func deleteStoredResources(for item: ClipboardItem) {
        cancelEnrichment(for: item.id)
        deleteImageFile(for: item)
        deleteTextFile(for: item)
    }

    func discardPendingImageSaves() {
        imageSaveGeneration += 1
        discardAllImageSavesBeforeGeneration = imageSaveGeneration
    }

    func markDeletedImageDigest(for item: ClipboardItem) {
        guard let digest = item.imageDigest else { return }
        imageSaveGeneration += 1
        deletedImageDigestGenerations[digest] = imageSaveGeneration
    }

    func cancelOCR(for itemID: UUID) {
        ocrTasksByItemID[itemID]?.cancel()
        ocrTasksByItemID[itemID] = nil
        ocrTaskTokensByItemID[itemID] = nil
    }

    func cancelOCR(for items: [ClipboardItem]) {
        items.forEach { cancelOCR(for: $0.id) }
    }

    func cancelAllOCRTasks() {
        ocrTasksByItemID.values.forEach { $0.cancel() }
        ocrTasksByItemID.removeAll()
        ocrTaskTokensByItemID.removeAll()
    }
}
