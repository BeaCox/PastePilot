import Foundation
import Testing
@testable import PastePilot

struct FullTextSearchStateTests {
    @Test
    func matchingIDsOnlyApplyToCompletedQuery() {
        let firstID = UUID()
        var state = FullTextSearchState()

        state.start(query: "needle")
        state.finish(query: "needle", ids: [firstID])

        #expect(!state.isSearching)
        #expect(state.matchingIDs(for: "needle") == [firstID])
        #expect(state.matchingIDs(for: "other").isEmpty)
    }

    @Test
    func staleCompletionDoesNotReplaceNewerSearch() {
        let oldID = UUID()
        let newID = UUID()
        var state = FullTextSearchState()

        state.start(query: "old")
        state.start(query: "new")
        state.finish(query: "old", ids: [oldID])

        #expect(state.isSearching)
        #expect(state.matchingIDs(for: "old").isEmpty)

        state.finish(query: "new", ids: [newID])

        #expect(!state.isSearching)
        #expect(state.matchingIDs(for: "new") == [newID])
    }

    @Test
    func staleCancellationDoesNotStopNewerSearch() {
        var state = FullTextSearchState()

        state.start(query: "old")
        state.start(query: "new")
        state.cancel(query: "old")

        #expect(state.isSearching)

        state.cancel(query: "new")

        #expect(!state.isSearching)
    }

    @Test
    func clearDropsMatchesAndStopsSearching() {
        let id = UUID()
        var state = FullTextSearchState()

        state.start(query: "needle")
        state.finish(query: "needle", ids: [id])
        state.start(query: "needle")
        state.clear(completedQuery: "needle")

        #expect(!state.isSearching)
        #expect(state.matchingIDs(for: "needle").isEmpty)
    }
}
