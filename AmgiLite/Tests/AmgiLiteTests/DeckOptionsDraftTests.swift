import XCTest

import AnkiKit
@testable import AmgiLite

final class DeckOptionsDraftTests: XCTestCase {
    // MARK: - Fixtures

    private func makeConfig() -> DeckConfig {
        var config = DeckConfig(id: DeckConfigID(2), name: "Test Preset")
        config.mtimeSecs = 123
        config.usn = 4
        config.config = DeckConfig.Config(
            learnSteps: [1, 10],
            relearnSteps: [10],
            fsrsParams4: [1, 2, 3],
            fsrsParams5: [4, 5, 6],
            fsrsParams6: [7, 8, 9],
            newPerDay: 20,
            reviewsPerDay: 200,
            newPerDayMinimum: 3,
            initialEase: 2.5,
            easyMultiplier: 1.3,
            hardMultiplier: 1.2,
            lapseMultiplier: 0.5,
            intervalMultiplier: 1.0,
            maximumReviewInterval: 36500,
            minimumLapseInterval: 1,
            graduatingIntervalGood: 1,
            graduatingIntervalEasy: 4,
            leechThreshold: 8,
            desiredRetention: 0.9,
            ignoreRevlogsBeforeDate: "2020-01-01",
            easyDaysPercentages: [1, 0.9, 1, 1, 1, 1, 1],
            historicalRetention: 0.9,
            paramSearch: "",
            other: Data([1, 2, 3])
        )
        return config
    }

    private func makeContext(
        config: DeckConfig,
        fsrs: Bool = false,
        desiredRetentionOverride: Float? = nil
    ) -> DeckConfigsForUpdate {
        var limits = DeckConfigsForUpdate.CurrentDeck.Limits()
        limits.desiredRetention = desiredRetentionOverride
        return DeckConfigsForUpdate(
            allConfig: [.init(config: config, useCount: 1)],
            currentDeck: .init(
                name: "Default",
                configID: config.id,
                parentConfigIds: [],
                limits: limits
            ),
            defaults: config,
            fsrs: fsrs,
            fsrsHealthCheck: true,
            applyAllParentLimits: false,
            daysSinceLastFsrsOptimize: 0
        )
    }

    // MARK: - Parsing

    func testStepParsingAndFormatting() {
        XCTAssertEqual(parseDeckSteps("1m 10m 1h 1d"), [1, 10, 60, 1440])
        XCTAssertEqual(parseDeckSteps("1m,10m\n1h"), [1, 10, 60])
        XCTAssertEqual(formatDeckSteps([1, 10, 60, 1440]), "1m 10m 1h 1d")

        // Only exact round-trips use an abbreviation.
        XCTAssertEqual(formatDeckSteps([0.001]), "0.001m")
        // 1.5m is exactly 90s; the formatter prefers the exact unit.
        XCTAssertEqual(formatDeckSteps([1.5]), "90s")
    }

    func testWeightFormattingAndParsing() {
        let values: [Float] = [0.4, 0.9, 2.3, 5.8]
        let text = formatDeckWeights(values)
        let parsed = parseDeckFloats(text)
        XCTAssertEqual(parsed.count, values.count)
        for (lhs, rhs) in zip(parsed, values) {
            XCTAssertEqual(lhs, rhs, accuracy: 5e-5)
        }
        XCTAssertEqual(formatDeckWeights(parsed), text, "formatting is idempotent")
        XCTAssertEqual(parseDeckFloats("0.4 0.9\n2.3,5.8"), values)
    }

    func testRelearningStepsCountOnlyStepsWithinADay() {
        XCTAssertEqual(relearningStepsInDay([10, 1440]), 1)
        XCTAssertEqual(relearningStepsInDay([10, 20]), 2)
        XCTAssertEqual(relearningStepsInDay([1440]), 0)
    }

    // MARK: - apply()

    func testApplyChangesOnlyExposedFields() {
        let config = makeConfig()
        var draft = DeckOptionsDraft(config: config, context: makeContext(config: config))

        draft.config.config.newPerDay = 55
        let result = draft.apply()

        XCTAssertEqual(result.config.newPerDay, 55)
        // Unexposed fields must survive untouched.
        XCTAssertEqual(result.config.easyDaysPercentages, config.config.easyDaysPercentages)
        XCTAssertEqual(result.config.other, config.config.other)
        XCTAssertEqual(result.config.initialEase, config.config.initialEase)
        XCTAssertEqual(result.config.lapseMultiplier, config.config.lapseMultiplier)
        XCTAssertEqual(result.config.newPerDayMinimum, config.config.newPerDayMinimum)
        XCTAssertEqual(result.config.ignoreRevlogsBeforeDate, config.config.ignoreRevlogsBeforeDate)
        XCTAssertEqual(result.mtimeSecs, config.mtimeSecs)
        XCTAssertEqual(result.usn, config.usn)
    }

    func testDraftIsCleanOnLoad() {
        let config = makeConfig()
        let draft = DeckOptionsDraft(config: config, context: makeContext(config: config))
        XCTAssertFalse(draft.isDirty)
        XCTAssertNil(draft.weightsValidationMessage)
    }

    func testWeightWriteRules() {
        let config = makeConfig()

        // 1. Untouched weights: every parameter set is preserved.
        var untouched = DeckOptionsDraft(config: config, context: makeContext(config: config))
        untouched.config.config.newPerDay = 1
        var result = untouched.apply()
        XCTAssertEqual(result.config.fsrsParams4, config.config.fsrsParams4)
        XCTAssertEqual(result.config.fsrsParams5, config.config.fsrsParams5)
        XCTAssertEqual(result.config.fsrsParams6, config.config.fsrsParams6)

        // 2. Edited weights: only fsrsParams6 is rewritten.
        var edited = DeckOptionsDraft(config: config, context: makeContext(config: config))
        edited.setWeightsText("1, 2, 3, 4")
        result = edited.apply()
        XCTAssertEqual(result.config.fsrsParams6, [1, 2, 3, 4])
        XCTAssertEqual(result.config.fsrsParams4, config.config.fsrsParams4)
        XCTAssertEqual(result.config.fsrsParams5, config.config.fsrsParams5)

        // 3. FSRS off must not clear stored weights.
        var off = DeckOptionsDraft(config: config, context: makeContext(config: config, fsrs: false))
        off.fsrsEnabled = false
        result = off.apply()
        XCTAssertEqual(result.config.fsrsParams6, config.config.fsrsParams6)
    }

    func testWeightsValidationRejectsNonNumbers() {
        let config = makeConfig()
        var draft = DeckOptionsDraft(config: config, context: makeContext(config: config))
        draft.setWeightsText("0.4 nope 1.2")
        XCTAssertNotNil(draft.weightsValidationMessage)

        draft.setWeightsText("0.4, 0.9, 1.2")
        XCTAssertNil(draft.weightsValidationMessage)

        draft.setWeightsText("  ")
        XCTAssertNotNil(draft.weightsValidationMessage)
    }

    func testDesiredRetentionOverrideWins() {
        let config = makeConfig()
        var context = makeContext(config: config, desiredRetentionOverride: 0.85)
        context.fsrs = true
        let draft = DeckOptionsDraft(config: config, context: context)
        XCTAssertEqual(draft.desiredRetention, 0.85, accuracy: 0.0001)
    }

    func testSaveOptionsMirrorContextFlags() {
        let config = makeConfig()
        var context = makeContext(config: config)
        context.newCardsIgnoreReviewLimit = true
        context.fsrsHealthCheck = true
        context.applyAllParentLimits = true

        let draft = DeckOptionsDraft(config: config, context: context)
        let options = draft.saveOptions
        XCTAssertTrue(options.ignoreReviewLimit)
        XCTAssertTrue(options.runHealthCheck)
        XCTAssertTrue(options.applyAllParentLimits)
        XCTAssertFalse(options.applyToChildren)
    }

    // MARK: - Preset names

    func testUniquePresetName() {
        XCTAssertEqual(uniquePresetName("Custom", existing: ["Default"]), "Custom")
        XCTAssertEqual(uniquePresetName("Default", existing: ["Default"]), "Default 2")
        XCTAssertEqual(
            uniquePresetName("Default", existing: ["Default", "Default 2"]),
            "Default 3"
        )
        XCTAssertEqual(uniquePresetName("   ", existing: []), "Preset")
    }
}
