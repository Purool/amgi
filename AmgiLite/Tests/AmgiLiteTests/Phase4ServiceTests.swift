import XCTest

import AnkiKit
@testable import AmgiLite

/// Engine-level tests for the Phase 4 services: notetypes, deck options and
/// note editing against a real collection.
final class Phase4ServiceTests: XCTestCase {
    private var collection: TestCollection!

    override func setUp() async throws {
        try await super.setUp()
        collection = try TestCollection.make()
        try await collection.open()
    }

    override func tearDown() async throws {
        await collection?.cleanUp()
        collection = nil
        try await super.tearDown()
    }

    // MARK: - Notetypes

    func testNotetypeNamesOnFreshCollection() async throws {
        let names = try await collection.services.notetypes.names()
        XCTAssertFalse(names.isEmpty)
        XCTAssertTrue(names.contains { $0.name == "Basic" }, "stock Basic notetype is expected")

        let id = try await collection.basicNotetypeID()
        let notetype = try await collection.services.notetypes.notetype(id: id)
        XCTAssertFalse(notetype.fields.isEmpty)
        XCTAssertFalse(notetype.templates.isEmpty)
    }

    func testUpdateTemplateRoundTrip() async throws {
        let id = try await collection.basicNotetypeID()
        var notetype = try await collection.services.notetypes.notetype(id: id)
        notetype.templates[0].name += " Edited"
        notetype.templates[0].config.qFormat += "<!-- phase4 -->"
        notetype.templates[0].config.aFormat += "<!-- phase4 back -->"
        notetype.config.css += " /* phase4 */"

        try await collection.services.notetypes.save(notetype)

        let reread = try await collection.services.notetypes.notetype(id: id)
        XCTAssertEqual(reread.templates[0].name, notetype.templates[0].name)
        XCTAssertEqual(reread.templates[0].config.qFormat, notetype.templates[0].config.qFormat)
        XCTAssertEqual(reread.templates[0].config.aFormat, notetype.templates[0].config.aFormat)
        XCTAssertEqual(reread.config.css, notetype.config.css)
    }

    func testInvalidTemplateRejectedByEngine() async throws {
        let id = try await collection.basicNotetypeID()
        var notetype = try await collection.services.notetypes.notetype(id: id)
        notetype.templates[0].config.qFormat = "{{NoSuchField}}"

        do {
            try await collection.services.notetypes.save(notetype)
            XCTFail("engine should reject a template referencing a missing field")
        } catch {
            // The engine's message is authoritative; the client pre-check is a
            // subset and this proves the fallback path is exercised.
        }
    }

    func testAddFieldAppendsOrdinal() async throws {
        let id = try await collection.basicNotetypeID()
        var notetype = try await collection.services.notetypes.notetype(id: id)
        let expectedCount = notetype.fields.count + 1
        notetype.fields.append(.init(name: "Extra"))

        try await collection.services.notetypes.save(notetype)

        let reread = try await collection.services.notetypes.notetype(id: id)
        XCTAssertEqual(reread.fields.count, expectedCount)
        XCTAssertEqual(reread.fields.last?.name, "Extra")
        XCTAssertEqual(reread.fields.last?.ord, expectedCount - 1, "engine assigns the final ordinal (E1)")
    }

    func testTemplatePreviewReturnsRenderedHTML() async throws {
        let id = try await collection.basicNotetypeID()
        let notetype = try await collection.services.notetypes.notetype(id: id)
        let fields = Array(repeating: "sample", count: notetype.fields.count)

        let rendered = try await collection.services.notetypes.preview(
            notetypeID: id,
            template: notetype.templates[0],
            cardOrd: 0,
            sampleFields: fields
        )
        XCTAssertFalse(rendered.frontHTML.isEmpty)
    }

    // MARK: - Deck options

    func testDeckOptionsContextShape() async throws {
        let deckID = try await collection.defaultDeckID()
        let context = try await collection.services.deckOptions.context(deckID: deckID)

        XCTAssertFalse(context.allConfig.isEmpty)
        XCTAssertNotNil(context.currentDeck)
        XCTAssertNotNil(context.defaults)
        XCTAssertFalse(context.fsrs, "FSRS is off by default")
        XCTAssertNotNil(context.currentDeck?.configID)
    }

    func testSaveDailyLimitsAndSteps() async throws {
        let deckID = try await collection.defaultDeckID()
        let context = try await collection.services.deckOptions.context(deckID: deckID)
        var config = try await collection.services.deckOptions.config(for: deckID)
        config.config.newPerDay = 42
        config.config.reviewsPerDay = 123
        config.config.learnSteps = [1, 10, 60]

        let options = DeckOptionsSaveOptions(
            fsrsEnabled: context.fsrs,
            ignoreReviewLimit: context.newCardsIgnoreReviewLimit,
            applyAllParentLimits: context.applyAllParentLimits,
            runHealthCheck: context.fsrsHealthCheck
        )
        try await collection.services.deckOptions.save(
            deckID: deckID,
            config: config,
            options: options
        )

        let reread = try await collection.services.deckOptions.config(for: deckID)
        XCTAssertEqual(reread.config.newPerDay, 42)
        XCTAssertEqual(reread.config.reviewsPerDay, 123)
        XCTAssertEqual(reread.config.learnSteps, [1, 10, 60])
    }

    func testDeckLimitsPreservedAcrossSave() async throws {
        let deckID = try await collection.defaultDeckID()
        let before = try await collection.services.deckOptions.context(deckID: deckID)
        let limitsBefore = before.currentDeck?.limits

        var config = try await collection.services.deckOptions.config(for: deckID)
        config.config.newPerDay = 7
        try await collection.services.deckOptions.save(
            deckID: deckID,
            config: config,
            options: DeckOptionsSaveOptions(fsrsEnabled: before.fsrs)
        )

        let after = try await collection.services.deckOptions.context(deckID: deckID)
        XCTAssertEqual(after.currentDeck?.limits, limitsBefore, "deck-level limits must round-trip (E7)")
    }

    func testCreateAndDeletePreset() async throws {
        let deckID = try await collection.defaultDeckID()
        let before = try await collection.services.deckOptions.context(deckID: deckID)
        let base = try await collection.services.deckOptions.config(for: deckID)
        let originalCount = before.allConfig.count

        try await collection.services.deckOptions.createPreset(
            deckID: deckID,
            from: base,
            name: "Phase 4",
            applyToChildren: false
        )

        let created = try await collection.services.deckOptions.context(deckID: deckID)
        XCTAssertEqual(created.allConfig.count, originalCount + 1)
        guard let newPreset = created.allConfig.first(where: { $0.config.name == "Phase 4" })?.config else {
            return XCTFail("new preset not found")
        }
        XCTAssertNotEqual(newPreset.id.rawValue, 0)

        guard let fallback = created.allConfig.first(where: { $0.config.id == DeckConfigID(1) })?.config
            ?? created.defaults
        else {
            return XCTFail("expected a default preset")
        }
        try await collection.services.deckOptions.deletePreset(
            deckID: deckID,
            id: newPreset.id,
            fallback: fallback,
            applyToChildren: false
        )

        let deleted = try await collection.services.deckOptions.context(deckID: deckID)
        XCTAssertEqual(deleted.allConfig.count, originalCount)
    }

    func testDeleteDefaultPresetThrows() async throws {
        let deckID = try await collection.defaultDeckID()
        let context = try await collection.services.deckOptions.context(deckID: deckID)
        guard let fallback = context.defaults else {
            return XCTFail("expected defaults")
        }

        do {
            try await collection.services.deckOptions.deletePreset(
                deckID: deckID,
                id: DeckConfigID(1),
                fallback: fallback,
                applyToChildren: false
            )
            XCTFail("preset 1 must not be deletable (E8)")
        } catch {
            // expected
        }
    }

    func testOptimizeWithoutHistoryReturnsZeroItems() async throws {
        let deckID = try await collection.defaultDeckID()
        let config = try await collection.services.deckOptions.config(for: deckID)
        let result = try await collection.services.deckOptions.optimizeWeights(
            FsrsOptimizeRequest(
                search: "",
                currentWeights: FsrsWeights(config.config.fsrsParams6),
                relearningStepsPerDay: 1,
                runHealthCheck: false
            )
        )
        XCTAssertEqual(result.trainingItemCount, 0, "an empty collection has no training items (E11)")
    }

    // MARK: - Notes

    func testAddAndEditNoteRoundTrip() async throws {
        let deckID = try await collection.defaultDeckID()
        let notetypeID = try await collection.basicNotetypeID()

        var template = try await collection.services.noteEditing.newNoteTemplate(
            notetypeID: notetypeID
        )
        template.fields[0] = "phase4 hello"
        try await collection.services.noteEditing.addNote(template, to: deckID)

        let summaries = try await collection.services.browse.searchNotes(
            query: "phase4 hello",
            limit: 10
        )
        guard let summary = summaries.first else {
            return XCTFail("added note was not searchable")
        }

        var note = try await collection.services.browse.note(id: summary.id)
        note.flds = note.flds.replacingOccurrences(of: "phase4 hello", with: "phase4 hello 2")
        try await collection.services.noteEditing.save(note)

        let reread = try await collection.services.browse.note(id: summary.id)
        XCTAssertTrue(reread.flds.contains("phase4 hello 2"))
    }

    func testNoteWithWrongFieldCountThrows() async throws {
        let deckID = try await collection.defaultDeckID()
        let notetypeID = try await collection.basicNotetypeID()

        var template = try await collection.services.noteEditing.newNoteTemplate(
            notetypeID: notetypeID
        )
        template.fields[0] = "field count guard"
        try await collection.services.noteEditing.addNote(template, to: deckID)

        let summaries = try await collection.services.browse.searchNotes(
            query: "field count guard",
            limit: 1
        )
        guard let summary = summaries.first else {
            return XCTFail("note missing")
        }

        var note = try await collection.services.browse.note(id: summary.id)
        note.flds = "only one field"
        do {
            try await collection.services.noteEditing.save(note)
            XCTFail("a short field list must be rejected (E13)")
        } catch {
            // expected
        }
    }

    func testDeleteNoteRemovesCards() async throws {
        let deckID = try await collection.defaultDeckID()
        let notetypeID = try await collection.basicNotetypeID()

        var template = try await collection.services.noteEditing.newNoteTemplate(
            notetypeID: notetypeID
        )
        template.fields[0] = "delete me"
        try await collection.services.noteEditing.addNote(template, to: deckID)

        let summaries = try await collection.services.browse.searchNotes(query: "delete me", limit: 1)
        guard let summary = summaries.first else {
            return XCTFail("note missing")
        }

        let cardIDs = try await collection.services.noteEditing.cardIDs(of: summary.id)
        XCTAssertFalse(cardIDs.isEmpty)

        try await collection.services.noteEditing.delete(id: summary.id)

        let after = try await collection.services.browse.searchNotes(query: "delete me", limit: 1)
        XCTAssertTrue(after.isEmpty)
    }
}
