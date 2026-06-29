import Foundation

struct FullTextSearchState: Equatable {
    struct SearchToken: Equatable, Sendable {
        fileprivate let id = UUID()
    }

    private struct ActiveSearch: Equatable, Sendable {
        let token: SearchToken
        let query: String
    }

    private var activeSearch: ActiveSearch?
    private var completedQuery = ""
    private var completedIDs: Set<UUID> = []

    var isSearching: Bool {
        activeSearch != nil
    }

    mutating func clear(completedQuery: String = "") {
        activeSearch = nil
        self.completedQuery = completedQuery
        completedIDs = []
    }

    mutating func start(query: String) -> SearchToken {
        let token = SearchToken()
        activeSearch = ActiveSearch(token: token, query: query)
        return token
    }

    mutating func cancel(token: SearchToken) {
        guard activeSearch?.token == token else { return }
        activeSearch = nil
    }

    mutating func finish(token: SearchToken, ids: Set<UUID>) {
        guard let search = activeSearch, search.token == token else { return }
        activeSearch = nil
        completedQuery = search.query
        completedIDs = ids
    }

    func matchingIDs(for query: String) -> Set<UUID> {
        completedQuery == query ? completedIDs : []
    }
}
