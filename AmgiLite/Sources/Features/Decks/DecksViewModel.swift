import AnkiKit
import Foundation

/// State machine for the deck list screen: owns nothing but state and the
/// `DeckServicing` / `CollectionSession` calls that drive it. The view
/// controller observes `onStateChange` and re-renders; it never calls the
/// services directly.
@MainActor
final class DecksViewModel {
    enum State {
        case loading
        case content([DeckRow])
        case empty
        case error(String)
    }

    private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    /// Called on every state transition, on the main actor.
    var onStateChange: ((State) -> Void)?

    /// Kept beside the state so the cell handler can resolve the `DeckRow`
    /// behind each diffable item ID without another service round trip.
    private var rows: [DeckRow] = []

    private let services: LiteServices
    private let session: CollectionSession

    init(services: LiteServices, session: CollectionSession) {
        self.services = services
        self.session = session
    }

    /// Refresh the deck tree. `showLoadingOverlay: true` moves through the
    /// `.loading` state (first entry, retry); `false` keeps the current
    /// surface on screen (pull-to-refresh, returning from review) and only
    /// swaps the result in.
    func load(showLoadingOverlay: Bool = true) {
        if showLoadingOverlay {
            state = .loading
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.ensureOpen()
                let tree = try await self.services.decks.deckTree()
                self.setRows(tree.isEmpty ? .empty : .content(tree), rows: tree)
            } catch {
                self.setRows(.error("Engine error: \(error)"), rows: [])
            }
        }
    }

    /// The `DeckRow` behind a diffable item ID, for cell configuration.
    func row(for id: DeckRow.ID) -> DeckRow? {
        rows.first(where: { $0.id == id })
    }

    /// Resolves a tapped row into the `DeckID` the review screen needs.
    /// Semantically this is just `row(for:)??.id`.
    func selectDeck(_ id: DeckRow.ID) -> DeckID? {
        row(for: id)?.id
    }

    private func setRows(_ newState: State, rows: [DeckRow]) {
        self.rows = rows
        state = newState
    }
}
