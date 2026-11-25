import Foundation

extension ClipboardStore {
    func historyItemExportSource(for item: ClipboardItem) -> HistoryItemExportSource {
        HistoryItemExportSource(
            item: item,
            textDirectoryURL: textStore.directoryURL,
            imageDirectoryURL: imageStore.directoryURL
        )
    }

    func sortItems() {
        items = ClipboardHistoryOrdering.pinnedFirst(items)
    }

    @discardableResult
    func normalizePinnedOrder() -> Bool {
        let pinnedIDs = ClipboardHistoryOrdering.pinnedItems(items).map(\.id)
        var didChange = false
        let orderByID = Dictionary(
            uniqueKeysWithValues: pinnedIDs.enumerated().map { ($0.element, $0.offset) }
        )
        for index in items.indices {
            let expectedOrder = items[index].isPinned ? orderByID[items[index].id] : nil
            if items[index].pinnedOrder != expectedOrder {
                items[index].pinnedOrder = expectedOrder
                didChange = true
            }
        }
        sortItems()
        return didChange
    }

    func movePinnedItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        var pinnedIDs = ClipboardHistoryOrdering.pinnedItems(items).map(\.id)
        let validSource = source.filter { pinnedIDs.indices.contains($0) }
        guard !validSource.isEmpty else { return }

        let movedIDs = validSource.sorted().map { pinnedIDs[$0] }
        for index in validSource.sorted(by: >) {
            pinnedIDs.remove(at: index)
        }
        let removedBeforeDestination = validSource.filter { $0 < destination }.count
        let insertionIndex = min(
            max(0, destination - removedBeforeDestination),
            pinnedIDs.count
        )
        pinnedIDs.insert(contentsOf: movedIDs, at: insertionIndex)
        applyPinnedOrder(pinnedIDs)
        sortItems()
        save()
    }

    func applyPinnedOrder(_ orderedIDs: [UUID]) {
        let orderByID = Dictionary(
            uniqueKeysWithValues: orderedIDs.enumerated().map { ($0.element, $0.offset) }
        )
        for index in items.indices {
            items[index].pinnedOrder = items[index].isPinned
                ? orderByID[items[index].id]
                : nil
        }
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

        let imageByteCounts = imageByteCounts(for: items)
        let textByteCounts = textByteCounts(for: items)
        var imageRefCounts: [String: Int] = [:]
        var textRefCounts: [String: Int] = [:]
        for item in items {
            if let fileName = item.imageFileName {
                imageRefCounts[fileName, default: 0] += 1
            }
            if let fileName = item.contentFileName {
                textRefCounts[fileName, default: 0] += 1
            }
        }

        var retainedByteCount = estimatedStorageByteCount(
            for: items,
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
            retainedByteCount -= HistoryRepository.estimatedItemByteCount(for: item)
            if let fileName = item.imageFileName, let count = imageRefCounts[fileName] {
                if count <= 1 {
                    imageRefCounts.removeValue(forKey: fileName)
                    retainedByteCount -= imageByteCounts[fileName] ?? 0
                } else {
                    imageRefCounts[fileName] = count - 1
                }
            }
            if let fileName = item.contentFileName, let count = textRefCounts[fileName] {
                if count <= 1 {
                    textRefCounts.removeValue(forKey: fileName)
                    retainedByteCount -= textByteCounts[fileName] ?? 0
                } else {
                    textRefCounts[fileName] = count - 1
                }
            }
        }

        guard !removedIDs.isEmpty else { return false }
        let removedItems = items.filter { removedIDs.contains($0.id) }
        cancelOCR(for: removedItems)
        removedItems.forEach(deleteStoredResources)
        items.removeAll { removedIDs.contains($0.id) }
        sortItems()
        return true
    }

    func applyStorageLimit() {
        guard settings.storageLimitMB > 0 else { return }
        removeOrphanedImages()
        removeOrphanedText()
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
        if normalizePinnedOrder() {
            save()
        }
        purgeExpired()
        applyStorageLimit()
    }

    func externalizeLoadedLargeTextContent() -> Bool {
        var didExternalize = false
        items = items.map { item in
            guard item.contentFileName == nil,
                  !item.isProtected,
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
        let retained = Set(
            items.compactMap(\.imageFileName)
                + pendingDeletions.values.compactMap(\.item.imageFileName)
        )
        imageStore.removeOrphans(retaining: retained)
    }

    func removeOrphanedText() {
        let retained = Set(
            items.compactMap(\.contentFileName)
                + pendingDeletions.values.compactMap(\.item.contentFileName)
        )
        textStore.removeOrphans(retaining: retained)
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
        batchOCRTask?.cancel()
        batchOCRTask = nil
        ocrTasksByItemID.values.forEach { $0.cancel() }
        ocrTasksByItemID.removeAll()
        ocrTaskTokensByItemID.removeAll()
    }
}
