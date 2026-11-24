import AnkiBackend
import AnkiKit
import AnkiProtoBridge
import Foundation

/// The composition of engine facades the app is given. Feature code takes this
/// whole struct (or a single protocol) and never sees `AnkiBackend`.
public struct LiteServices: Sendable {
    public let collection: any CollectionServicing
    public let decks: any DeckServicing
    public let review: any ReviewServicing
    public let browse: any BrowseServicing
    public let importExport: any ImportServicing
    public let sync: any SyncServicing

    public init(
        collection: any CollectionServicing,
        decks: any DeckServicing,
        review: any ReviewServicing,
        browse: any BrowseServicing,
        importExport: any ImportServicing,
        sync: any SyncServicing
    ) {
        self.collection = collection
        self.decks = decks
        self.review = review
        self.browse = browse
        self.importExport = importExport
        self.sync = sync
    }

    /// Live services over one open backend. Created exactly once, by
    /// `AppContainer`.
    public static func live(backend: AnkiBackend) -> LiteServices {
        let state = CollectionState()
        return LiteServices(
            collection: LiveCollectionService(backend: backend, state: state),
            decks: LiveDeckService(backend: backend, state: state),
            review: LiveReviewService(backend: backend, state: state),
            browse: LiveBrowseService(backend: backend, state: state),
            importExport: LiveImportService(backend: backend, state: state),
            sync: LiveSyncService(backend: backend, state: state)
        )
    }
}

/// Opens the collection at most once and remembers the outcome, so every screen
/// can call `ensureOpen()` without racing the first caller.
public actor CollectionSession {
    private let collection: any CollectionServicing
    /// Injectable so tests (and a future "open a picked file" flow) do not have
    /// to go through `Documents/`.
    private let paths: @Sendable () throws -> CollectionPaths
    private var opened = false

    public init(
        collection: any CollectionServicing,
        paths: @escaping @Sendable () throws -> CollectionPaths = { try CollectionPaths.standard() }
    ) {
        self.collection = collection
        self.paths = paths
    }

    public var isOpen: Bool { opened }

    public func ensureOpen() async throws {
        guard !opened else { return }
        try await collection.open(try paths())
        opened = true
    }

    public func close() async throws {
        guard opened else { return }
        try await collection.close()
        opened = false
    }
}
