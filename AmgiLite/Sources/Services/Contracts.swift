import AnkiKit
import Foundation

// The only boundary between the UIKit app and the engine. Phase 1 (shard S1)
// implements these against `AnkiBackend`; feature shards depend on the
// protocols and never import `AnkiBackend` themselves.
//
// Keep this file append-only once shards start: it is the contract they code
// against, and it is owned by the scaffold, not by any feature shard.

public struct DeckRow: Sendable, Equatable, Identifiable {
    public let id: DeckID
    public let name: String
    public let fullName: String
    public let counts: DeckCounts
    public let depth: Int

    public init(id: DeckID, name: String, fullName: String, counts: DeckCounts, depth: Int) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.counts = counts
        self.depth = depth
    }
}

public struct NoteSummary: Sendable, Equatable, Identifiable {
    public let id: NoteID
    public let title: String
    public let snippet: String

    public init(id: NoteID, title: String, snippet: String) {
        self.id = id
        self.title = title
        self.snippet = snippet
    }
}

/// Where a collection lives on disk. All three paths are absolute.
public struct CollectionPaths: Sendable, Equatable {
    public let collectionPath: String
    public let mediaFolderPath: String
    public let mediaDatabasePath: String

    public init(collectionPath: String, mediaFolderPath: String, mediaDatabasePath: String) {
        self.collectionPath = collectionPath
        self.mediaFolderPath = mediaFolderPath
        self.mediaDatabasePath = mediaDatabasePath
    }
}

public protocol CollectionServicing: Sendable {
    func open(_ paths: CollectionPaths) async throws
    func close() async throws
    var mediaFolderPath: String? { get }
}

public protocol DeckServicing: Sendable {
    /// Flattened deck tree, depth-first, parents before children.
    func deckTree() async throws -> [DeckRow]
    func counts(for deckID: DeckID) async throws -> DeckCounts
}

public protocol ReviewServicing: Sendable {
    func queuedCards(limit: Int) async throws -> QueuedCardsResult
    func render(cardID: CardID) async throws -> RenderedCard
    func answer(cardID: CardID, rating: Rating, timeSpent: UInt32) async throws
    func undo() async throws
}

public protocol BrowseServicing: Sendable {
    func searchNotes(query: String, limit: Int) async throws -> [NoteSummary]
    func note(id: NoteID) async throws -> NoteRecord
}

public protocol ImportServicing: Sendable {
    /// `.apkg` / `.colpkg` import. The Rust importer owns the zip parsing.
    func importPackage(at url: URL) async throws
}

public protocol SyncServicing: Sendable {
    var isLoggedIn: Bool { get }
    func logIn(username: String, password: String) async throws
    func sync() async throws
}

public enum LiteError: Error, Sendable, Equatable {
    case collectionNotOpen
    case unsupportedPackage
    case notLoggedIn
    case engine(String)
}
