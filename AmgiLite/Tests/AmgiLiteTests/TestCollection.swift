import Foundation

import AnkiBackend
import AnkiKit
@testable import AmgiLite

/// One real engine collection per test, in its own temp directory. The engine
/// is the object under test, so nothing is mocked (see `Tests/AGENTS.md`).
final class TestCollection {
    let backend: AnkiBackend
    let services: LiteServices
    let session: CollectionSession
    let root: URL
    let media: URL

    private init(backend: AnkiBackend, root: URL, media: URL) {
        self.backend = backend
        self.root = root
        self.media = media
        self.services = LiteServices.live(backend: backend)
        self.session = CollectionSession(
            collection: services.collection,
            paths: {
                CollectionPaths(
                    collectionPath: root.appendingPathComponent("collection.anki2").path,
                    mediaFolderPath: media.path,
                    mediaDatabasePath: root.appendingPathComponent("collection.media.db2").path
                )
            }
        )
    }

    static func make() throws -> TestCollection {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("amgilite-phase4-\(UUID().uuidString)", isDirectory: true)
        let media = root.appendingPathComponent("collection.media", isDirectory: true)
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        let backend = try AnkiBackend(preferredLangs: ["en"])
        return TestCollection(backend: backend, root: root, media: media)
    }

    func open() async throws {
        try await session.ensureOpen()
    }

    func cleanUp() async {
        try? await session.close()
        try? FileManager.default.removeItem(at: root)
    }

    /// The stock `Default` deck of a fresh collection.
    func defaultDeckID() async throws -> DeckID {
        let rows = try await services.decks.deckTree()
        guard let first = rows.first else {
            throw LiteError.engine("fresh collection has no deck")
        }
        return first.id
    }

    func basicNotetypeID() async throws -> NotetypeID {
        let names = try await services.notetypes.names()
        if let basic = names.first(where: { $0.name == "Basic" }) {
            return basic.id
        }
        guard let first = names.first else {
            throw LiteError.engine("fresh collection has no notetype")
        }
        return first.id
    }
}
