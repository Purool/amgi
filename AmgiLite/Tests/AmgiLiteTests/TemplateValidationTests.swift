import XCTest

import AnkiKit
@testable import AmgiLite

final class TemplateValidationTests: XCTestCase {
    private func makeNotetype(
        kind: Notetype.Kind = .normal,
        fields: [String] = ["Front", "Back"],
        qFormat: String = "{{Front}}",
        aFormat: String = "{{FrontSide}}<hr>{{Back}}"
    ) -> Notetype {
        Notetype(
            id: NotetypeID(1),
            name: "Basic",
            config: .init(kind: kind),
            fields: fields.map { Notetype.Field(ord: nil, name: $0) },
            templates: [
                .init(
                    ord: 0,
                    name: "Card 1",
                    config: .init(qFormat: qFormat, aFormat: aFormat)
                ),
            ]
        )
    }

    // MARK: - Validation

    func testValidTemplateHasNoMessage() {
        XCTAssertNil(templateValidationMessage(for: makeNotetype()))
    }

    func testEmptyFrontTemplateIsRejected() {
        let message = templateValidationMessage(for: makeNotetype(qFormat: ""))
        XCTAssertNotNil(message)
    }

    func testUnknownFieldIsRejected() {
        let message = templateValidationMessage(for: makeNotetype(qFormat: "{{NoSuchField}}"))
        XCTAssertNotNil(message)
        XCTAssertTrue(message?.contains("NoSuchField") == true)
    }

    func testSpecialFieldsNeedNoNotetypeField() {
        let notetype = makeNotetype(
            qFormat: "{{Front}} {{Deck}} {{Tags}} {{Card}}",
            aFormat: "{{FrontSide}}"
        )
        XCTAssertNil(templateValidationMessage(for: notetype))
    }

    func testConditionalFieldReferencesAreRecognized() {
        let notetype = makeNotetype(
            qFormat: "{{#Front}}{{Front}}{{/Front}}",
            aFormat: "{{FrontSide}}"
        )
        XCTAssertNil(templateValidationMessage(for: notetype))
    }

    func testClozeRequiresClozeReference() {
        let noCloze = makeNotetype(kind: .cloze, qFormat: "{{Front}}", aFormat: "{{Back}}")
        XCTAssertNotNil(templateValidationMessage(for: noCloze))

        let cloze = makeNotetype(
            kind: .cloze,
            qFormat: "{{cloze:Front}}",
            aFormat: "{{cloze:Front}}"
        )
        XCTAssertNil(templateValidationMessage(for: cloze))
    }

    // MARK: - Sample fields

    func testSampleFieldsSplitAndAlign() {
        let note = NoteRecord(
            id: NoteID(1),
            guid: "g",
            mid: NotetypeID(1),
            mod: 0,
            flds: "front\u{1F}back",
            sfld: "front",
            csum: 0
        )
        XCTAssertEqual(buildSampleFields(from: note), ["front", "back"])
        XCTAssertEqual(makeEmptySampleFields(fieldCount: 3), ["", "", ""])
        XCTAssertEqual(makeEmptySampleFields(fieldCount: -1), [])
    }

    // MARK: - Draft structural changes

    func testTextOnlyChangeIsNotStructural() {
        var draft = NotetypeDraft(makeNotetype())
        draft.updateTemplate(at: 0) { $0.config.qFormat += " extra" }

        XCTAssertTrue(draft.isDirty)
        XCTAssertFalse(draft.hasStructuralChange)
    }

    func testAddingFieldIsStructural() {
        var draft = NotetypeDraft(makeNotetype())
        draft.appendField(named: "Extra")

        XCTAssertTrue(draft.isDirty)
        XCTAssertTrue(draft.hasStructuralChange)
        XCTAssertTrue(draft.hasUnsavedNewFields)
        XCTAssertEqual(draft.notetype.fields.last?.ord, nil, "new fields carry ord == nil (E1)")
    }

    func testRemovingTemplateIsStructural() {
        var draft = NotetypeDraft(makeNotetype())
        draft.removeTemplate(at: 0)

        XCTAssertTrue(draft.hasStructuralChange)
    }

    func testMovingFieldsIsStructural() {
        var draft = NotetypeDraft(makeNotetype(fields: ["A", "B", "C"]))
        draft.moveField(from: 0, to: 2)

        XCTAssertEqual(draft.fieldNames, ["B", "C", "A"])
        XCTAssertTrue(draft.hasStructuralChange)
    }

    func testFieldTokensIncludeAllFieldsAndFrontSide() {
        let draft = NotetypeDraft(makeNotetype(fields: ["Front", "Back"]))
        XCTAssertEqual(draft.fieldTokens, ["{{Front}}", "{{Back}}", "{{FrontSide}}"])
    }
}
