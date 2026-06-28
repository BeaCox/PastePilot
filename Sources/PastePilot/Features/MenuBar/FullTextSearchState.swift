import Foundation

struct FullTextSearchState: Equatable {
    private var activeQuery: String?
    private var completedQuery = ""
    private var completedIDs: Set<UUID> = []

    var isSearching: Bool {
        activeQuery != nil
    }

    mutating func clear(completedQuery: String = "") {
        activeQuery = nil
        self.completedQuery = completedQuery
        completedIDs = []
    }

    mutating func start(query: String) {
        activeQuery = query
    }

    mutating func cancel(query: String) {
        guard activeQuery == query else { return }
        activeQuery = nil
    }

    mutating func finish(query: String, ids: Set<UUID>) {
        guard activeQuery == query else { return }
        activeQuery = nil
        completedQuery = query
        completedIDs = ids
    }

    func matchingIDs(for query: String) -> Set<UUID> {
        completedQuery == query ? completedIDs : []
    }
}
