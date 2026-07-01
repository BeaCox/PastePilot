import Foundation
import Testing
@testable import PastePilot

struct FullTextSearchStateTests {
    @Test
    func matchingIDsOnlyApplyToCompletedQuery() {
        let firstID = UUID()
        var state = FullTextSearchState()

        let token = state.start(query: "needle")
        state.finish(token: token, ids: [firstID])

        #expect(!state.isSearching)
        #expect(state.matchingIDs(for: "needle") == [firstID])
        #expect(state.matchingIDs(for: "other").isEmpty)
    }

    @Test
    func staleCompletionDoesNotReplaceNewerSearch() {
        let oldID = UUID()
        let newID = UUID()
        var state = FullTextSearchState()

        let oldToken = state.start(query: "old")
        let newToken = state.start(query: "new")
        state.finish(token: oldToken, ids: [oldID])

        #expect(state.isSearching)
        #expect(state.matchingIDs(for: "old").isEmpty)

        state.finish(token: newToken, ids: [newID])

        #expect(!state.isSearching)
        #expect(state.matchingIDs(for: "new") == [newID])
    }

    @Test
    func staleCancellationDoesNotStopNewerSearch() {
        var state = FullTextSearchState()

        let oldToken = state.start(query: "old")
        let newToken = state.start(query: "new")
        state.cancel(token: oldToken)

        #expect(state.isSearching)

        state.cancel(token: newToken)

        #expect(!state.isSearching)
    }

    @Test
    func staleSameQueryCancellationDoesNotStopNewerSearch() {
        var state = FullTextSearchState()

        let oldToken = state.start(query: "needle")
        let newToken = state.start(query: "needle")
        state.cancel(token: oldToken)

        #expect(state.isSearching)

        state.cancel(token: newToken)

        #expect(!state.isSearching)
    }

    @Test
    func staleSameQueryCompletionDoesNotReplaceNewerSearch() {
        let oldID = UUID()
        let newID = UUID()
        var state = FullTextSearchState()

        let oldToken = state.start(query: "needle")
        let newToken = state.start(query: "needle")
        state.finish(token: oldToken, ids: [oldID])

        #expect(state.isSearching)
        #expect(state.matchingIDs(for: "needle").isEmpty)

        state.finish(token: newToken, ids: [newID])

        #expect(!state.isSearching)
        #expect(state.matchingIDs(for: "needle") == [newID])
    }

    @Test
    func clearDropsMatchesAndStopsSearching() {
        let id = UUID()
        var state = FullTextSearchState()

        let firstToken = state.start(query: "needle")
        state.finish(token: firstToken, ids: [id])
        _ = state.start(query: "needle")
        state.clear(completedQuery: "needle")

        #expect(!state.isSearching)
        #expect(state.matchingIDs(for: "needle").isEmpty)
    }

    @Test
    func interactionStateResetClearsTasksAndSearch() {
        let id = UUID()
        var state = MenuBarInteractionState()
        let token = state.fullTextSearch.start(query: "needle")
        state.fullTextSearch.finish(token: token, ids: [id])
        state.previewTask = Task {}
        state.closePreviewTask = Task {}
        state.noticeTask = Task {}
        state.fullTextSearchTask = Task {}

        state.reset()

        #expect(state.previewTask == nil)
        #expect(state.closePreviewTask == nil)
        #expect(state.noticeTask == nil)
        #expect(state.fullTextSearchTask == nil)
        #expect(!state.fullTextSearch.isSearching)
        #expect(state.fullTextSearch.matchingIDs(for: "needle").isEmpty)
    }
}
