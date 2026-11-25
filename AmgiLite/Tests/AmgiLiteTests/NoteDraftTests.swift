import XCTest

import AnkiKit
@testable import AmgiLite

final class NoteDraftTests: XCTestCase {
    private func makeNotetype(fieldCount: Int = 2) -> Notetype {
        Notetype(
            id: NotetypeID(1),
            name: "Basic",
            fields: (1...fieldCount).map {
                Notetype.Field(ord: $0 - 1, name: "Field \($0)")
            },
            templates: [
                .init(ord: 0, name: "Card 1", config: .init(qFormat: "{{Field 1}}")),
            ]
        )
    }

    private func makeNote(flds: String, tags: String = " tag1  tag2 ") -> NoteRecord {
        NoteRecord(
            id: NoteID(9),
            guid: "guid",
            mid: NotetypeID(1),
            mod: 77,
            tags: tags,
            flds: flds,
            sfld: "sort",
            csum: 42,
            flags: 3,
            data: "payload"
        )
    }

    func testFieldsPadToNotetypeCount() {
        let draft = NoteDraft(note: makeNote(flds: "front"), notetype: makeNotetype(fieldCount: 3))
        XCTAssertEqual(draft.fields, ["front", "", ""])
    }

    func testFieldsTruncateToNotetypeCount() {
        let draft = NoteDraft(
            note: makeNote(flds: "one\u{1F}two\u{1F}three"),
            notetype: makeNotetype(fieldCount: 2)
        )
        XCTAssertEqual(draft.fields, ["one", "two"])
    }

    func testValidationRejectsEmptyFirstField() {
        let draft = NoteDraft(note: makeNote(flds: "\u{1F}back"), notetype: makeNotetype())
        XCTAssertNotNil(draft.validate())
    }

    func testValidationAcceptsPresentFirstField() {
        var draft = NoteDraft(note: makeNote(flds: "front\u{1F}back"), notetype: makeNotetype())
        draft.fields = ["front", "back"]
        XCTAssertNil(draft.validate())
    }

    func testApplyKeepsEngineOwnedFields() {
        var draft = NoteDraft(note: makeNote(flds: "front\u{1F}back"), notetype: makeNotetype())
        draft.fields[0] = "changed"
        draft.tags = " new   tag new "

        let applied = draft.apply()
        XCTAssertEqual(applied.flds, "changed\u{1F}back")
        XCTAssertEqual(applied.tags, "new tag")
        // E14: the engine recomputes these.
        XCTAssertEqual(applied.sfld, "sort")
        XCTAssertEqual(applied.csum, 42)
        XCTAssertEqual(applied.flags, 3)
        XCTAssertEqual(applied.data, "payload")
        XCTAssertEqual(applied.id, NoteID(9))
    }

    func testTagsAreTrimmedAndDeduplicated() {
        XCTAssertEqual(NoteDraft.normalizedTags("  a   b a  c "), "a b c")
        XCTAssertEqual(NoteDraft.normalizedTags(""), "")
        XCTAssertEqual(NoteDraft.normalizedTags("one\ntwo"), "one two")
    }

    func testDirtyTracking() {
        var draft = NoteDraft(note: makeNote(flds: "front\u{1F}back"), notetype: makeNotetype())
        XCTAssertFalse(draft.isDirty, "loading normalizes the stored tag spacing without marking dirty")

        draft.fields[1] = "changed"
        XCTAssertTrue(draft.isDirty)

        draft.fields[1] = "back"
        XCTAssertFalse(draft.isDirty)

        draft.tags = "other"
        XCTAssertTrue(draft.isDirty)
    }
}
