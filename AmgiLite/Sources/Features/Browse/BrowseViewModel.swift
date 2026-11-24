import AnkiKit
import Foundation

/// Browse tab view model: a read-only, paged list of notes.
///
/// Pagination note: `BrowseServicing.searchNotes(query:limit:)` has no offset
/// parameter — the engine returns the first `limit` matches for a query. "Load
/// more" therefore re-runs the same query with a bigger limit
/// (`notes.count + pageSize`) and replaces the list wholesale. Scrolling down
/// re-fetches notes the user has already seen; acceptable for v1 (the engine
/// call is cheap and the diffable snapshot keeps row identities stable).
@MainActor
final class BrowseViewModel {
    static let pageSize = 50

    enum State {
        case idle
        case loading
        case content([NoteSummary], query: String)
        case empty
        case error(String)
    }

    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle
    private(set) var notes: [NoteSummary] = []
    private(set) var query: String = ""
    private(set) var canLoadMore = false

    private let services: LiteServices
    private let session: CollectionSession

    /// The actually running fetch (initial search, refresh or load-more).
    private var searchTask: Task<Void, Never>?
    /// The 300 ms debounce task spawned by `updateQuery`.
    private var debounceTask: Task<Void, Never>?
    private var debounceGeneration = 0
    /// True while `searchTask` may still deliver a result.
    private var isSearchInFlight = false
    /// Guards `loadMore` against concurrent triggers.
    private var isLoadingMore = false

    init(services: LiteServices, session: CollectionSession) {
        self.services = services
        self.session = session
    }

    /// Search-bar text changed. Debounced by 300 ms; any in-flight search is
    /// cancelled first so only the latest query wins.
    func updateQuery(_ text: String) {
        guard text != query else { return }
        query = text

        searchTask?.cancel()
        isSearchInFlight = false
        debounceGeneration += 1
        let generation = debounceGeneration

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            guard generation == self.debounceGeneration else { return }
            self.search(query: text, showLoadingOverlay: false)
            // No await between the search and this write, so a newer
            // `updateQuery` cannot have taken over `debounceTask` meanwhile.
            self.debounceTask = nil
        }
    }

    func search(query: String, showLoadingOverlay: Bool) {
        searchTask?.cancel()
        // Cancels a pending debounce (search-bar cleared / pull-to-refresh
        // while the user had just typed). When called from the debounce task
        // itself this only sets the current task's cancelled flag, which the
        // task body no longer consults afterwards.
        debounceTask?.cancel()
        debounceTask = nil

        self.query = query
        isSearchInFlight = true
        searchTask = Task { [weak self] in
            await self?.runSearch(query: query, limit: Self.pageSize, showLoadingOverlay: showLoadingOverlay)
        }
    }

    /// Loads the next page. The engine has no offset, so this re-runs the
    /// current query with `notes.count + pageSize` and replaces `notes`.
    func loadMore() {
        guard canLoadMore, !isLoadingMore, !isSearchInFlight, debounceTask == nil else { return }
        guard case .content = state else { return }

        isLoadingMore = true
        isSearchInFlight = true
        let limit = notes.count + Self.pageSize
        let currentQuery = query
        searchTask = Task { [weak self] in
            await self?.runSearch(query: currentQuery, limit: limit, showLoadingOverlay: false)
        }
    }

    func summary(for id: NoteID) -> NoteSummary? {
        notes.first { $0.id == id }
    }

    private func runSearch(query: String, limit: Int, showLoadingOverlay: Bool) async {
        if showLoadingOverlay {
            state = .loading
            emit()
        }

        do {
            try await session.ensureOpen()
            let results = try await services.browse.searchNotes(query: query, limit: limit)
            // The query may have changed (and this task been cancelled) while
            // the engine call was running; only fresh results are applied.
            // A cancelled run must not touch the in-flight flags: they belong
            // to whichever run replaced it.
            guard !Task.isCancelled else { return }

            isSearchInFlight = false
            isLoadingMore = false
            notes = results
            canLoadMore = results.count == limit
            state = results.isEmpty ? .empty : .content(results, query: query)
            emit()
        } catch {
            guard !Task.isCancelled else { return }
            isSearchInFlight = false
            isLoadingMore = false
            state = .error("Engine error: \(error)")
            emit()
        }
    }

    private func emit() {
        onStateChange?(state)
    }
}
