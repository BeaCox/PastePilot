import Foundation

extension ClipboardStore {
    func sortItems() {
        items.sort { $0.createdAt > $1.createdAt }
    }

    func trimHistory(limit: Int) {
        let pinned = items.filter(\.isPinned)
        let recent = items.filter { !$0.isPinned }.prefix(max(1, limit))
        let retainedIDs = Set((pinned + recent).map(\.id))
        let removedItems = items.filter { !retainedIDs.contains($0.id) }
        cancelOCR(for: removedItems)
        removedItems.forEach(deleteImageFile)
        items = items.filter { retainedIDs.contains($0.id) }
        sortItems()
    }

    func load() {
        let result = historyRepository.load()
        items = result.items
        switch result.source {
        case .primary:
            removeOrphanedImages()
        case .backup:
            NSLog("PastePilot recovered clipboard history from backup")
            save()
            removeOrphanedImages()
        case .unrecoverable:
            NSLog("PastePilot could not decode clipboard history or its backup")
        case .empty:
            break
        }
        sortItems()
        purgeExpired()
    }

    func removeOrphanedImages() {
        imageStore.removeOrphans(
            retaining: Set(items.compactMap(\.imageFileName))
        )
    }

    func save() {
        historyWriteQueue.save(items) { error in
            if let error {
                NSLog("PastePilot failed to save history: \(error)")
                NotificationCenter.default.postPastePilotNotice(
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
        imageStore.delete(fileName: fileName)
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
