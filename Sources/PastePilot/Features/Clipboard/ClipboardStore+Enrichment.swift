import CoreGraphics
import Foundation

extension ClipboardStore {
    func fetchLinkMetadataIfNeeded(for itemID: UUID, urlString: String) {
        guard settings.linkMetadataFetchingEnabled,
              let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              URLSessionLinkMetadataService.isEligible(url) else {
            return
        }

        cancelLinkMetadata(for: itemID)
        let service = linkMetadataService
        let taskToken = UUID()
        linkMetadataTaskTokensByItemID[itemID] = taskToken
        linkMetadataTasksByItemID[itemID] = Task { [weak self] in
            let metadata = await service.metadata(for: url)
            guard let self else { return }
            defer {
                if self.linkMetadataTaskTokensByItemID[itemID] == taskToken {
                    self.linkMetadataTasksByItemID[itemID] = nil
                    self.linkMetadataTaskTokensByItemID[itemID] = nil
                }
            }
            guard !Task.isCancelled,
                  let metadata,
                  let index = self.items.firstIndex(where: { $0.id == itemID }),
                  self.items[index].kind == .url else {
                return
            }
            guard self.items[index].linkMetadata != metadata else { return }
            self.items[index].linkMetadata = metadata
            self.save()
        }
    }

    func performBarcodeDetection(on image: CGImage, itemID: UUID) {
        cancelBarcodeDetection(for: itemID)
        let service = barcodeDetectionService
        let taskToken = UUID()
        barcodeTaskTokensByItemID[itemID] = taskToken
        barcodeTasksByItemID[itemID] = Task { [weak self] in
            let detectedBarcodes = await service.detectBarcodes(in: image)
            guard let self else { return }
            defer {
                if self.barcodeTaskTokensByItemID[itemID] == taskToken {
                    self.barcodeTasksByItemID[itemID] = nil
                    self.barcodeTaskTokensByItemID[itemID] = nil
                }
            }
            guard !Task.isCancelled,
                  let index = self.items.firstIndex(where: { $0.id == itemID }) else {
                return
            }
            let retainedBarcodes = DetectedBarcodePolicy.retained(detectedBarcodes)
            let storageResult = self.barcodeStorageResult(retainedBarcodes)
            let storedBarcodes = storageResult.barcodes.isEmpty
                ? nil
                : storageResult.barcodes
            let becomesSensitive = storageResult.containsSensitiveData
                && !self.items[index].containsSensitiveData
            guard self.items[index].detectedBarcodes != storedBarcodes
                    || becomesSensitive else {
                return
            }
            self.items[index].detectedBarcodes = storedBarcodes
            if storageResult.containsSensitiveData {
                self.items[index].containsSensitiveData = true
            }
            self.save()
        }
    }

    func rerunBarcodeDetectionForImages() {
        cancelAllBarcodeDetectionTasks()
        let targets: [(id: UUID, url: URL)] = items.compactMap { item in
            guard item.isImage, let fileName = item.imageFileName else { return nil }
            return (item.id, imageStore.fileURL(fileName: fileName))
        }
        guard !targets.isEmpty else { return }

        let service = barcodeDetectionService
        batchBarcodeTask = Task { [weak self] in
            let maxConcurrent = 3
            await withTaskGroup(of: (UUID, [DetectedBarcode]).self) { group in
                var iterator = targets.makeIterator()
                for _ in 0..<maxConcurrent {
                    guard let target = iterator.next() else { break }
                    group.addTask {
                        let barcodes = await Self.detectBarcodes(at: target.url, service: service)
                        return (target.id, barcodes)
                    }
                }
                while let (itemID, detectedBarcodes) = await group.next() {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    self?.applyDetectedBarcodes(detectedBarcodes, to: itemID)
                    if let nextTarget = iterator.next() {
                        group.addTask {
                            let barcodes = await Self.detectBarcodes(at: nextTarget.url, service: service)
                            return (nextTarget.id, barcodes)
                        }
                    }
                }
            }
            if let self {
                self.batchBarcodeTask = nil
            }
        }
    }

    nonisolated private static func detectBarcodes(
        at url: URL,
        service: any BarcodeDetectionService
    ) async -> [DetectedBarcode] {
        guard !Task.isCancelled,
              let cgImage = ClipboardImageStore.cgImage(at: url) else {
            return []
        }
        return await service.detectBarcodes(in: cgImage)
    }

    private func applyDetectedBarcodes(
        _ detectedBarcodes: [DetectedBarcode],
        to itemID: UUID
    ) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else {
            return
        }
        let retainedBarcodes = DetectedBarcodePolicy.retained(detectedBarcodes)
        let storageResult = barcodeStorageResult(retainedBarcodes)
        let storedBarcodes = storageResult.barcodes.isEmpty
            ? nil
            : storageResult.barcodes
        let becomesSensitive = storageResult.containsSensitiveData
            && !items[index].containsSensitiveData
        guard items[index].detectedBarcodes != storedBarcodes
                || becomesSensitive else {
            return
        }
        items[index].detectedBarcodes = storedBarcodes
        if storageResult.containsSensitiveData {
            items[index].containsSensitiveData = true
        }
        save()
    }

    func cancelLinkMetadata(for itemID: UUID) {
        linkMetadataTasksByItemID[itemID]?.cancel()
        linkMetadataTasksByItemID[itemID] = nil
        linkMetadataTaskTokensByItemID[itemID] = nil
    }

    func cancelBarcodeDetection(for itemID: UUID) {
        barcodeTasksByItemID[itemID]?.cancel()
        barcodeTasksByItemID[itemID] = nil
        barcodeTaskTokensByItemID[itemID] = nil
    }

    func cancelEnrichment(for itemID: UUID) {
        cancelLinkMetadata(for: itemID)
        cancelBarcodeDetection(for: itemID)
    }

    func cancelAllEnrichmentTasks() {
        linkMetadataTasksByItemID.values.forEach { $0.cancel() }
        linkMetadataTasksByItemID.removeAll()
        linkMetadataTaskTokensByItemID.removeAll()
        cancelAllBarcodeDetectionTasks()
    }

    private func cancelAllBarcodeDetectionTasks() {
        batchBarcodeTask?.cancel()
        batchBarcodeTask = nil
        barcodeTasksByItemID.values.forEach { $0.cancel() }
        barcodeTasksByItemID.removeAll()
        barcodeTaskTokensByItemID.removeAll()
    }

    private func barcodeStorageResult(
        _ barcodes: [DetectedBarcode]
    ) -> (barcodes: [DetectedBarcode], containsSensitiveData: Bool) {
        let userPatterns = settings.userSensitivePatterns
        let policy = SensitiveContentStoragePolicy(
            rawValue: settings.sensitiveContentStoragePolicy
        ) ?? .storeOriginal
        var containsSensitiveData = false
        let stored = barcodes.compactMap { barcode -> DetectedBarcode? in
            guard ContentAnalyzer.containsSensitiveData(
                barcode.payload,
                userPatterns: userPatterns
            ) else {
                return barcode
            }
            switch policy {
            case .storeOriginal:
                containsSensitiveData = true
                return barcode
            case .storeRedacted:
                return DetectedBarcode(
                    payload: ContentAnalyzer.redacted(
                        barcode.payload,
                        userPatterns: userPatterns
                    ),
                    symbology: barcode.symbology
                )
            case .skip:
                return nil
            }
        }
        return (stored, containsSensitiveData)
    }
}
