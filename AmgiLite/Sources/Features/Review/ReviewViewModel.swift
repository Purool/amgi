import AnkiKit
import Foundation

/// State machine for the review screen.
///
/// Engine note: `getQueuedCards` has no deck filter parameter — the queue the
/// engine returns is global across the whole collection, so a card shown here
/// may not belong to the deck the user navigated from. `deckID` is kept only
/// as the hook where a future filter would attach once the engine grows one.
///
/// Scheduling contract (from `ReviewServicing`): a card's `states` are only
/// valid for that card. Therefore every answer is immediately followed by a
/// fresh `queuedCards(limit: 1)` fetch — the answered card has left the queue,
/// so the next result's first entry carries its own states.
@MainActor
final class ReviewViewModel {
    enum State {
        case loading
        case front(ReadyCard)
        case back(ReadyCard, [RatingButtonSpec])
        case done(Int)
        case error(String)
    }

    struct ReadyCard {
        let card: QueuedReviewCard
        let rendered: RenderedCard
    }

    /// One rating key as the engine's `nextIntervals` describes it. A missing
    /// interval string renders as an empty subtitle rather than a placeholder.
    struct RatingButtonSpec {
        let rating: Rating
        let interval: String
    }

    var onStateChange: ((State) -> Void)?
    /// Errors that must not replace the screen: a failed `answer` keeps the
    /// card on its back side, a failed `undo` keeps the current card. The
    /// view controller surfaces these as an alert.
    var onTransientError: ((String) -> Void)?

    private(set) var answeredCount: Int = 0
    /// new + learning + review from the most recent `queuedCards` fetch.
    private(set) var remainingCount: Int = 0

    private let services: LiteServices
    private let session: CollectionSession
    private let deckID: DeckID

    private var current: ReadyCard?
    /// Timing starts when the front side appears — Anki counts the whole card,
    /// not just the answer phase.
    private var cardShownAt: Date?

    init(services: LiteServices, session: CollectionSession, deckID: DeckID) {
        self.services = services
        self.session = session
        self.deckID = deckID
    }

    // MARK: - Intents

    func start() {
        Task { [weak self] in
            await self?.loadAndPresent()
        }
    }

    /// Re-run the last failed load.
    func retry() {
        Task { [weak self] in
            await self?.loadAndPresent()
        }
    }

    func showAnswer() {
        guard let current else { return }
        emit(.back(current, ratingSpecs(for: current)))
    }

    func rate(_ rating: Rating) {
        guard let card = current else { return }
        // Measure before clearing the clock, and clear synchronously so a
        // double tap cannot answer the same card twice.
        let timeSpent = timeSpentSoFar()
        let queued = card.card
        current = nil
        cardShownAt = nil

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.services.review.answer(
                    cardID: queued.card.id,
                    states: queued.states,
                    rating: rating,
                    timeSpent: timeSpent
                )
            } catch {
                // Restore the card: the answer did not land, so the rating
                // buttons stay usable for another try.
                self.current = card
                self.onTransientError?(Self.describe(error))
                return
            }
            self.answeredCount += 1
            await self.loadAndPresent()
        }
    }

    func undo() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.services.review.undo()
            } catch {
                // Undo did not land; keep the current card exactly as shown.
                self.onTransientError?(Self.describe(error))
                return
            }
            self.answeredCount = max(0, self.answeredCount - 1)
            // The undone card is back at the front of the queue; reloading
            // fetches, renders and shows it as the next front.
            await self.loadAndPresent()
        }
    }

    // MARK: - Queue loading

    private func loadAndPresent() async {
        emit(.loading)
        do {
            try await session.ensureOpen()
            let queued = try await services.review.queuedCards(limit: 1)
            remainingCount = queued.newCount + queued.learningCount + queued.reviewCount

            guard let queuedCard = queued.cards.first else {
                current = nil
                emit(.done(answeredCount))
                return
            }

            let rendered = try await services.review.render(cardID: queuedCard.card.id)
            let ready = ReadyCard(card: queuedCard, rendered: rendered)
            current = ready
            cardShownAt = Date()
            emit(.front(ready))
        } catch {
            emit(.error(Self.describe(error)))
        }
    }

    // MARK: - Helpers

    private func emit(_ state: State) {
        onStateChange?(state)
    }

    private func ratingSpecs(for card: ReadyCard) -> [RatingButtonSpec] {
        // Fixed Anki order; `nextIntervals` maps each rating to its display text.
        [.again, .hard, .good, .easy].map { rating in
            RatingButtonSpec(rating: rating, interval: card.card.nextIntervals[rating] ?? "")
        }
    }

    private func timeSpentSoFar() -> UInt32 {
        guard let cardShownAt else { return 0 }
        let elapsedSeconds = Date().timeIntervalSince(cardShownAt)
        // `TimeInterval` is a Double; `UInt32(clamping:)` only takes integers.
        return UInt32(clamping: Int((elapsedSeconds * 1000).rounded()))
    }

    private static func describe(_ error: Error) -> String {
        switch error as? LiteError {
        case .collectionNotOpen:
            return "The collection is not open."
        case .engine(let message):
            return "Engine error: \(message)"
        case .notImplemented:
            return "Not supported yet."
        default:
            return "Engine error: \(error)"
        }
    }
}
