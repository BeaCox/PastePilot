import Foundation

struct MenuBarInteractionState {
    var previewTask: Task<Void, Never>?
    var closePreviewTask: Task<Void, Never>?
    var noticeTask: Task<Void, Never>?
    var fullTextSearchTask: Task<Void, Never>?
    var fullTextSearch = FullTextSearchState()

    mutating func reset() {
        previewTask?.cancel()
        closePreviewTask?.cancel()
        noticeTask?.cancel()
        fullTextSearchTask?.cancel()
        previewTask = nil
        closePreviewTask = nil
        noticeTask = nil
        fullTextSearchTask = nil
        fullTextSearch.clear()
    }
}
