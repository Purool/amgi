//
//  CardClient.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 27.03.2026.
//

public import AnkiKit
public import Dependencies
import DependenciesMacros
import AnkiBackend
import AnkiProtoBridge
import AnkiServices
import Logging

@DependencyClient
public struct CardClient: Sendable {
    public var fetchDue: @Sendable (_ deckId: DeckID) async throws -> [CardRecord]
    public var fetchByNote: @Sendable (_ noteId: NoteID) async throws -> [CardRecord]
    public var suspend: @Sendable (_ cardId: CardID) async throws -> Void
    public var bury: @Sendable (_ cardId: CardID) async throws -> Void
    public var flag: @Sendable (_ cardId: CardID, _ value: UInt32) async throws -> Void
    public var resetToNew: @Sendable (_ cardId: CardID) async throws -> Void
    public var setDueDate: @Sendable (_ cardId: CardID, _ days: String) async throws -> Void
    public var undoLast: @Sendable () async throws -> Void
    public var getCardFlags: @Sendable (_ cardId: CardID) async throws -> UInt32
    public var hasUndoableAction: @Sendable () async throws -> Bool
    public var removeCards: @Sendable (_ cardIds: [CardID]) async throws -> Void
}

extension CardClient: TestDependencyKey {
    public static let testValue = CardClient()
}

extension DependencyValues {
    public var cardClient: CardClient {
        get { self[CardClient.self] }
        set { self[CardClient.self] = newValue }
    }
}

private let logger = Logger(label: "com.ankiapp.card.client")

extension CardClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        @Dependency(\.schedulerService) var scheduler
        @Dependency(\.decksService) var decks

        return Self(
            fetchDue: { deckId in
                try await backendOffload {
                    do {
                        try decks.setCurrentDeck(deckId)
                        logger.info("Set current deck to \(deckId)")
                    } catch {
                        logger.error("setCurrentDeck failed for deckId=\(deckId): \(error)")
                        throw error
                    }

                    do {
                        let currentDeck = try decks.getCurrentDeck()
                        logger.info("Verified current deck: id=\(currentDeck.id), name=\(currentDeck.name)")
                    } catch {
                        logger.warning("Could not verify current deck (non-fatal): \(error)")
                    }

                    do {
                        let result = try scheduler.getQueuedCards(200)
                        logger.info("QueuedCards for deckId=\(deckId): \(result.cards.count) cards")
                        return result.cards.map(\.card)
                    } catch {
                        logger.error("fetchDue failed for deckId=\(deckId): \(error)")
                        throw error
                    }
                }
            },
            fetchByNote: { noteId in
                let ids = try await backend.invoke(.cardIDsOfNote(id: noteId))
                var cards: [CardRecord] = []
                cards.reserveCapacity(ids.count)
                for id in ids {
                    cards.append(try await backend.invoke(.getCard(id: id)))
                }
                return cards
            },
            suspend: { cardId in
                try await backend.invoke(.suspendCards(cardIds: [cardId]))
            },
            bury: { cardId in
                try await backend.invoke(.buryCards(cardIds: [cardId]))
            },
            flag: { cardId, value in
                try await backend.invoke(.setFlag(cardIds: [cardId], flag: value))
            },
            resetToNew: { cardId in
                try await backend.invoke(.scheduleCardsAsNew(cardIds: [cardId], log: true))
            },
            setDueDate: { cardId, days in
                try await backend.invoke(.setDueDate(cardIds: [cardId], days: days))
            },
            undoLast: {
                try await backend.invoke(.undoLastAction)
            },
            getCardFlags: { cardId in
                let card = try await backend.invoke(.getCard(id: cardId))
                return UInt32(card.flags) & 0b111
            },
            hasUndoableAction: {
                try await backend.invoke(.hasUndoableAction)
            },
            removeCards: { cardIds in
                try await backend.invoke(.removeCards(cardIds: cardIds))
                logger.info("Removed \(cardIds.count) cards")
            }
        )
    }()
}
