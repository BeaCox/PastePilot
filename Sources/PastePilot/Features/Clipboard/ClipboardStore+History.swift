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
        removedItems.forEach(deleteStoredResources)
        items = items.filter { retainedIDs.contains($0.id) }
        sortItems()
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
            NSLog("PastePilot recovered clipboard history from backup")
            save()
            removeOrphanedImages()
            removeOrphanedText()
        case .unrecoverable:
            NSLog("PastePilot could not decode clipboard history or its backup")
        case .empty:
            break
        }
        sortItems()
        purgeExpired()
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
            do {
                try textStore.save(item.content, fileName: fileName)
                didExternalize = true
                return item.externalizedContent(fileName: fileName)
            } catch {
                NSLog("PastePilot failed to externalize loaded text content: \(error)")
                return item
            }
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
        thumbnailCache.removeObject(forKey: "\(fileName)-22" as NSString)
        imageStore.delete(fileName: fileName)
    }

    func deleteTextFile(for item: ClipboardItem) {
        guard let fileName = item.contentFileName else { return }
        textStore.delete(fileName: fileName)
    }

    func deleteStoredResources(for item: ClipboardItem) {
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
