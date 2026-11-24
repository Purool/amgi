import AnkiBackend
import AnkiKit
import AnkiProtoBridge

struct LiveReviewService: ReviewServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    func setCurrentDeck(_ deckID: DeckID) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            try backend.invoke(.setCurrentDeck(deckId: deckID))
        }
    }

    func queuedCards(limit: Int) async throws -> QueuedCardsResult {
        let fetchLimit = UInt32(clamping: max(0, limit))
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.getQueuedCards(fetchLimit: fetchLimit))
        }
    }

    func render(cardID: CardID) async throws -> RenderedCard {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.renderExistingCard(cardId: cardID))
        }
    }

    func answer(
        cardID: CardID,
        states: ReviewSchedulingStates,
        rating: Rating,
        timeSpent: UInt32
    ) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            try backend.invoke(.answerReviewCard(
                cardId: cardID,
                rating: rating,
                timeSpentMs: timeSpent,
                states: states
            ))
        }
    }

    /// No-op when the undo stack is empty: the backend reports `undoEmpty` and
    /// the review screen treats it as "nothing to undo", not as a failure.
    func undo() async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            _ = try? backend.invoke(.undoLastAction)
        }
    }
}
