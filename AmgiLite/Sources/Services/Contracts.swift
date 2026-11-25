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
    /// Filtered decks have no preset: `getDeckConfigsForUpdate` rejects them,
    /// so every "Deck Options" entry point checks this before routing.
    public let isFiltered: Bool

    public init(
        id: DeckID,
        name: String,
        fullName: String,
        counts: DeckCounts,
        depth: Int,
        isFiltered: Bool = false
    ) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.counts = counts
        self.depth = depth
        self.isFiltered = isFiltered
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

// MARK: - Phase 4 contracts

/// Request-level switches for one deck-options save. `DeckConfig` carries the
/// preset itself; these travel beside it in `updateDeckConfigs`.
public struct DeckOptionsSaveOptions: Sendable, Equatable {
    public var applyToChildren: Bool
    /// Collection-level FSRS toggle.
    public var fsrsEnabled: Bool
    public var ignoreReviewLimit: Bool
    public var applyAllParentLimits: Bool
    public var runHealthCheck: Bool

    public init(
        applyToChildren: Bool = false,
        fsrsEnabled: Bool = false,
        ignoreReviewLimit: Bool = false,
        applyAllParentLimits: Bool = false,
        runHealthCheck: Bool = false
    ) {
        self.applyToChildren = applyToChildren
        self.fsrsEnabled = fsrsEnabled
        self.ignoreReviewLimit = ignoreReviewLimit
        self.applyAllParentLimits = applyAllParentLimits
        self.runHealthCheck = runHealthCheck
    }
}

public protocol DeckOptionsServicing: Sendable {
    /// Presets + the current deck + collection-level FSRS flags; one load
    /// fills the whole screen.
    func context(deckID: DeckID) async throws -> DeckConfigsForUpdate
    /// The preset the current deck uses, with `deckConfig(for:)` and the
    /// engine defaults as fallbacks.
    func config(for deckID: DeckID) async throws -> DeckConfig
    func save(deckID: DeckID, config: DeckConfig, options: DeckOptionsSaveOptions) async throws
    /// Switches to an existing preset, preserving its id so the engine
    /// updates that row instead of creating a new one.
    func switchPreset(deckID: DeckID, to preset: DeckConfig, applyToChildren: Bool) async throws
    func renamePreset(
        deckID: DeckID,
        preset: DeckConfig,
        to name: String,
        applyToChildren: Bool
    ) async throws
    /// `base.id` is reset to 0 so the engine allocates a new preset. Callers
    /// are responsible for a unique name.
    func createPreset(
        deckID: DeckID,
        from base: DeckConfig,
        name: String,
        applyToChildren: Bool
    ) async throws
    /// Deletes `id` and points the deck at `fallback`. Preset ids 0 and 1 are
    /// rejected.
    func deletePreset(
        deckID: DeckID,
        id: DeckConfigID,
        fallback: DeckConfig,
        applyToChildren: Bool
    ) async throws
    func optimizeWeights(_ request: FsrsOptimizeRequest) async throws -> FsrsOptimizeResult
    /// `updateDeckConfigs` + `.computeAllParams` + `fsrs: true`.
    func optimizeAllPresets(deckID: DeckID, current: DeckConfig) async throws
}

public protocol NotetypeServicing: Sendable {
    func names() async throws -> [NotetypeNameId]
    func notetype(id: NotetypeID) async throws -> Notetype
    func save(_ notetype: Notetype) async throws
    func remove(id: NotetypeID) async throws
    /// Renders an unsaved template against the saved notetype's fields/CSS.
    /// `cardOrd` decides which template ordinal the engine sees.
    func preview(
        notetypeID: NotetypeID,
        template: Notetype.Template,
        cardOrd: Int,
        sampleFields: [String]
    ) async throws -> RenderedCard
}

public protocol NoteEditingServicing: Sendable {
    /// Blank note template with the right field count and a generated guid.
    /// `NewNoteTemplate`'s initializer is package-scoped, so only services
    /// create one; screens may only edit `fields` / `tags`.
    func newNoteTemplate(notetypeID: NotetypeID) async throws -> NewNoteTemplate
    func addNote(_ template: NewNoteTemplate, to deckID: DeckID) async throws
    /// Writes fields + tags only; `sfld` / `csum` are the engine's job.
    func save(_ note: NoteRecord) async throws
    func delete(id: NoteID) async throws
    /// Cards generated by the note — used to state the impact of a deletion.
    func cardIDs(of noteID: NoteID) async throws -> [CardID]
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
