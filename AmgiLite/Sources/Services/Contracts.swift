import AnkiKit
import Foundation

// The only boundary between the UIKit app and the engine. `LiteServices`
// implements these against `AnkiBackend`; feature code depends on the protocols
// and never imports the engine itself.
//
// Implementation note: protocol methods are `async` because every call hops off
// the caller's actor via `backendOffload` — `AnkiBackend.invoke` is a blocking
// FFI call and must never run on the main thread.

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

extension CollectionPaths {
    /// `<Documents>/collection.anki2` + its media folder and media DB. The media
    /// directory is created eagerly: the Rust engine treats it as already
    /// existing and fails the open if it is missing.
    public static func standard() throws -> CollectionPaths {
        let fileManager = FileManager.default
        let documents = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let media = documents.appendingPathComponent("collection.media", isDirectory: true)
        try fileManager.createDirectory(at: media, withIntermediateDirectories: true)

        return CollectionPaths(
            collectionPath: documents.appendingPathComponent("collection.anki2").path,
            mediaFolderPath: media.path,
            mediaDatabasePath: documents.appendingPathComponent("collection.media.db2").path
        )
    }
}

public protocol CollectionServicing: Sendable {
    func open(_ paths: CollectionPaths) async throws
    func close() async throws
    /// Absolute path of the open collection's media folder, or nil when closed.
    var mediaFolderPath: String? { get }
}

public protocol DeckServicing: Sendable {
    /// Flattened deck tree, depth-first, parents before children.
    func deckTree() async throws -> [DeckRow]
    func counts(for deckID: DeckID) async throws -> DeckCounts
}

public protocol ReviewServicing: Sendable {
    /// Point the engine's study queue at this deck. `queuedCards` builds the
    /// queue for the *current* deck (plus its subdecks), not globally, so this
    /// must run before every `queuedCards` fetch.
    func setCurrentDeck(_ deckID: DeckID) async throws
    func queuedCards(limit: Int) async throws -> QueuedCardsResult
    func render(cardID: CardID) async throws -> RenderedCard
    /// `states` must be the scheduling states returned with this card by
    /// `queuedCards(limit:)`; reusing them for a different card mis-schedules.
    func answer(
        cardID: CardID,
        states: ReviewSchedulingStates,
        rating: Rating,
        timeSpent: UInt32
    ) async throws
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
    /// AnkiWeb account name when logged in, `nil` otherwise.
    var loggedInUsername: String? { get }
    func logIn(username: String, password: String) async throws
    func sync() async throws
    /// Forced full upload/download. Shown after the conflict prompt when the
    /// server requires a full sync and neither direction can be chosen by
    /// the engine alone (`fullSyncRequired` / `fullUploadRequired`).
    func fullSync(direction: SyncDirection) async throws
    /// Media-sync progress. `active` is false when nothing is running.
    func mediaSyncStatus() async throws -> MediaSyncStatus
    /// Best-effort cancel of a running sync (collection + media). Safe to
    /// call when nothing runs.
    func cancel() async
}

public enum LiteError: Error, Sendable, Equatable {
    case collectionNotOpen
    case unsupportedPackage
    case notLoggedIn
    /// A feature the engine cannot serve in this build (kept for the review
    /// screen's error mapping).
    case notImplemented
    case engine(String)
}
