import XCTest

import AnkiBackend
import AnkiKit
@testable import AmgiLite

final class LiteServicesTests: XCTestCase {
    // MARK: - Fixtures

    /// One isolated collection per test; deleted afterwards.
    private struct Workspace {
        let root: URL
        let media: URL

        var paths: CollectionPaths {
            CollectionPaths(
                collectionPath: root.appendingPathComponent("collection.anki2").path,
                mediaFolderPath: media.path,
                mediaDatabasePath: root.appendingPathComponent("collection.media.db2").path
            )
        }

        static func make() throws -> Workspace {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("amgilite-services-\(UUID().uuidString)", isDirectory: true)
            let media = root.appendingPathComponent("collection.media", isDirectory: true)
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
            return Workspace(root: root, media: media)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Live services

    func testLiveServicesQueryAnEmptyCollection() async throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)
        let workspace = try Workspace.make()
        defer { workspace.cleanUp() }

        try await services.collection.open(workspace.paths)
        XCTAssertEqual(services.collection.mediaFolderPath, workspace.media.path)

        let decks = try await services.decks.deckTree()
        XCTAssertFalse(decks.isEmpty, "a fresh collection always has a default deck")
        XCTAssertEqual(decks.first?.depth, 0)

        let counts = try await services.decks.counts(for: decks[0].id)
        XCTAssertEqual(counts.total, 0)

        let queued = try await services.review.queuedCards(limit: 5)
        XCTAssertTrue(queued.cards.isEmpty)
        XCTAssertEqual(queued.newCount, 0)

        let notes = try await services.browse.searchNotes(query: "", limit: 10)
        XCTAssertTrue(notes.isEmpty)

        try await services.collection.close()
        XCTAssertNil(services.collection.mediaFolderPath)
    }

    func testQueriesBeforeOpenFailWithCollectionNotOpen() async throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)

        await assertCollectionNotOpen {
            _ = try await services.decks.deckTree()
        }
        await assertCollectionNotOpen {
            _ = try await services.review.queuedCards(limit: 1)
        }
        await assertCollectionNotOpen {
            _ = try await services.browse.searchNotes(query: "", limit: 1)
        }
        await assertCollectionNotOpen {
            try await services.review.undo()
        }
    }

    func testImportingAMissingPackageThrows() async throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)
        let workspace = try Workspace.make()
        defer { workspace.cleanUp() }

        try await services.collection.open(workspace.paths)
        defer { Task { try? await services.collection.close() } }

        let missing = workspace.root.appendingPathComponent("missing-\(UUID().uuidString).apkg")
        do {
            try await services.importExport.importPackage(at: missing)
            XCTFail("importing a missing .apkg must throw")
        } catch {
            // Any thrown error is acceptable here; the engine owns the message.
        }
    }

    // MARK: - Session

    func testCollectionSessionOpensOnlyOnce() async throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)
        let workspace = try Workspace.make()
        defer { workspace.cleanUp() }

        let session = CollectionSession(collection: services.collection, paths: { workspace.paths })
        try await session.ensureOpen()
        // The second call must be a no-op: reopening a live collection would
        // reset the backend's in-memory state mid-session.
        try await session.ensureOpen()

        let isOpen = await session.isOpen
        XCTAssertTrue(isOpen)

        let decks = try await services.decks.deckTree()
        XCTAssertFalse(decks.isEmpty)

        try await session.close()
        let isOpenAfterClose = await session.isOpen
        XCTAssertFalse(isOpenAfterClose)
    }

    // MARK: - Pure helpers

    func testDeckTreeFlattensDepthFirst() {
        let tree = [
            DeckTreeNode(
                id: DeckID(1),
                name: "Default",
                fullName: "Default",
                counts: DeckCounts(newCount: 0, learnCount: 0, reviewCount: 0),
                children: [
                    DeckTreeNode(id: DeckID(2), name: "Child", fullName: "Default::Child"),
                ]
            ),
            DeckTreeNode(id: DeckID(3), name: "Other", fullName: "Other"),
        ]

        let rows = LiveDeckService.flatten(tree, depth: 0)
        XCTAssertEqual(rows.map(\.id), [DeckID(1), DeckID(2), DeckID(3)])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 0])
    }

    func testCardPageCarriesCSSTemplateAndBaseURL() {
        let card = RenderedCard(
            frontHTML: "<p>Question</p>",
            backHTML: "<p>Answer</p>",
            cardCSS: ".card { color: red; }"
        )

        let page = CardPageBuilder.page(for: card, side: .back, isDark: true)

        XCTAssertTrue(page.contains("<p>Answer</p>"))
        XCTAssertFalse(page.contains("<p>Question</p>"))
        XCTAssertTrue(page.contains(".card { color: red; }"))
        XCTAssertTrue(page.contains("amgi-asset://media/"))
        XCTAssertTrue(page.contains("nightMode"))
    }

    func testNoteSummaryStripsHTMLAndUsesSortField() {
        let note = NoteRecord(
            id: NoteID(7),
            guid: "g",
            mid: NotetypeID(1),
            mod: 0,
            flds: "<b>Front</b>\u{1F}Back&amp;more",
            sfld: "<b>Front</b>",
            csum: 0
        )

        let summary = NoteSummary(note: note)
        XCTAssertEqual(summary.title, "Front")
        XCTAssertEqual(summary.snippet, "Back&more")
    }

    // MARK: - Helpers

    private func assertCollectionNotOpen(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
            XCTFail("expected LiteError.collectionNotOpen", file: file, line: line)
        } catch let error as LiteError {
            XCTAssertEqual(error, .collectionNotOpen, file: file, line: line)
        } catch {
            XCTFail("expected LiteError.collectionNotOpen, got \(error)", file: file, line: line)
        }
    }
}
