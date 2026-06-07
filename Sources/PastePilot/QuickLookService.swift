import AppKit
@preconcurrency import QuickLookUI

final class QuickLookService: NSObject, QLPreviewPanelDataSource {
    static let shared = QuickLookService()

    private var urls: [URL] = []

    func preview(_ urls: [URL]) -> Bool {
        let existingURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingURLs.isEmpty, let panel = QLPreviewPanel.shared() else {
            return false
        }
        self.urls = existingURLs
        panel.dataSource = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
        return true
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(
        _ panel: QLPreviewPanel!,
        previewItemAt index: Int
    ) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
