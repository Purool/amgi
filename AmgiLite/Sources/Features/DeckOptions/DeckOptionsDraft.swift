import AnkiKit
import Foundation

// Pure model + parsing for the deck-options screen. No engine, no UIKit — the
// screen edits a draft and only `apply()` produces the `DeckConfig` that is
// written back. Every unexposed field is carried through untouched (Easy
// Days, timers, audio, `other`), which is why the draft starts from the
// original config instead of a fresh `DeckConfig()`.

// MARK: - Parsing

/// `"1m 10m 1h 1d"` ↔ minutes. Bare numbers are minutes (Anki's convention).
func parseDeckSteps(_ text: String) -> [Float] {
    text
        .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
        .compactMap { token -> Float? in
            let lowered = String(token).lowercased()
            if lowered.hasSuffix("s"), let value = Float(lowered.dropLast()) { return value / 60 }
            if lowered.hasSuffix("m"), let value = Float(lowered.dropLast()) { return value }
            if lowered.hasSuffix("h"), let value = Float(lowered.dropLast()) { return value * 60 }
            if lowered.hasSuffix("d"), let value = Float(lowered.dropLast()) { return value * 1440 }
            return Float(lowered)
        }
}

func formatDeckSteps(_ values: [Float]) -> String {
    values.map(formatDeckStep).joined(separator: " ")
}

private func formatDeckStep(_ step: Float) -> String {
    let fallback = "\(step)m".replacingOccurrences(of: ".0m", with: "m")
    let seconds = (Double(step) * 60).rounded()
    guard seconds > 0, seconds < 2_147_483_648 else { return fallback }
    let whole = Int(seconds)
    let (size, suffix) = [(86_400, "d"), (3600, "h"), (60, "m"), (1, "s")]
        .first { whole % $0.0 == 0 }!
    let text = "\(whole / size)\(suffix)"
    // Only use the abbreviation when it round-trips exactly: rslib recomputes
    // in-progress cards' remaining steps whenever the saved steps differ.
    return parseDeckSteps(text) == [step] ? text : fallback
}

func parseDeckFloats(_ text: String) -> [Float] {
    text
        .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
        .compactMap { Float($0) }
}

func formatDeckWeights(_ values: [Float]) -> String {
    values.map { String(format: "%.4f", $0) }.joined(separator: ", ")
}

/// Mirrors upstream Anki: only relearning steps that fit inside one day are
/// counted for the optimizer, so "10m 1d" contributes 1, not 2.
func relearningStepsInDay(_ steps: [Float]) -> UInt32 {
    var count: UInt32 = 0
    var accumulated: Float = 0
    for step in steps {
        accumulated += step
        if accumulated >= 1440 { break }
        count += 1
    }
    return count
}

/// Baseline weights prefer the 6-parameter set (E5: the context back-fills it
/// from 5/4 already), then fall back for collections that never optimized.
func currentDeckWeights(_ config: DeckConfig.Config) -> [Float] {
    if !config.fsrsParams6.isEmpty { return config.fsrsParams6 }
    if !config.fsrsParams5.isEmpty { return config.fsrsParams5 }
    return config.fsrsParams4
}

/// Engine value domains (E9). Controls clamp to these; values outside are
/// silently reset to defaults by the engine, so nothing may submit them.
enum DeckOptionLimits {
    static let perDay = 0.0...9999.0
    static let interval = 1.0...36500.0
    static let leech = 1.0...9999.0
    static let desiredRetention = 0.70...0.99
    static let historicalRetention = 0.70...0.97
    static let intervalMultiplier = 0.5...2.0
    static let hardMultiplier = 0.5...1.3
    static let easyMultiplier = 1.0...5.0
}

// MARK: - Draft

struct DeckOptionsDraft {
    /// The preset as it was loaded. `isDirty` compares against it, so it must
    /// never be mutated.
    let baseline: DeckConfig
    /// Working copy; unexposed fields come from `baseline` and stay put.
    var config: DeckConfig

    // Request-level switches. `updateDeckConfigs` carries these beside the
    // preset, and their initial values must mirror the context.
    var applyToChildren: Bool = false
    var fsrsEnabled: Bool
    var ignoreReviewLimit: Bool
    var applyAllParentLimits: Bool
    var runHealthCheck: Bool

    // Text-backed fields, kept verbatim while editing so a half-typed value
    // never lands in the draft. `apply()` parses them.
    var learnStepsText: String
    var relearnStepsText: String
    var weightsText: String
    var weightsEdited: Bool = false
    var paramSearch: String

    /// Deck-level desired-retention override, shown instead of the preset's
    /// value when present. `nil` when the deck inherits.
    let desiredRetentionOverride: Float?

    private let initialToggles: Toggles

    struct Toggles: Equatable {
        var applyToChildren: Bool
        var fsrsEnabled: Bool
        var ignoreReviewLimit: Bool
        var applyAllParentLimits: Bool
        var runHealthCheck: Bool
    }

    init(config: DeckConfig, context: DeckConfigsForUpdate) {
        self.baseline = config
        self.config = config
        self.fsrsEnabled = context.fsrs
        self.ignoreReviewLimit = context.newCardsIgnoreReviewLimit
        self.applyAllParentLimits = context.applyAllParentLimits
        self.runHealthCheck = context.fsrsHealthCheck
        self.learnStepsText = formatDeckSteps(config.config.learnSteps)
        self.relearnStepsText = formatDeckSteps(config.config.relearnSteps)
        self.weightsText = formatDeckWeights(currentDeckWeights(config.config))
        self.paramSearch = config.config.paramSearch
        self.desiredRetentionOverride = context.currentDeck?.limits?.desiredRetention
        self.initialToggles = Toggles(
            applyToChildren: false,
            fsrsEnabled: context.fsrs,
            ignoreReviewLimit: context.newCardsIgnoreReviewLimit,
            applyAllParentLimits: context.applyAllParentLimits,
            runHealthCheck: context.fsrsHealthCheck
        )
    }

    // MARK: Presentation values

    /// Effective desired retention (0…1). The deck-level override wins when
    /// set, matching what the scheduler will actually use.
    var desiredRetention: Float {
        get { desiredRetentionOverride ?? normalized(config.config.desiredRetention, fallback: 0.90) }
        set { config.config.desiredRetention = newValue }
    }

    var historicalRetention: Float {
        get { normalized(config.config.historicalRetention, fallback: 0.90) }
        set { config.config.historicalRetention = newValue }
    }

    var intervalMultiplier: Float {
        get { normalized(config.config.intervalMultiplier, fallback: 1.0) }
        set { config.config.intervalMultiplier = newValue }
    }

    var hardMultiplier: Float {
        get { normalized(config.config.hardMultiplier, fallback: 1.2) }
        set { config.config.hardMultiplier = newValue }
    }

    var easyMultiplier: Float {
        get { normalized(config.config.easyMultiplier, fallback: 1.3) }
        set { config.config.easyMultiplier = newValue }
    }

    var hasWeights: Bool { !currentDeckWeights(config.config).isEmpty }

    // MARK: Mutation

    mutating func setLearnStepsText(_ text: String) {
        learnStepsText = text
    }

    mutating func setRelearnStepsText(_ text: String) {
        relearnStepsText = text
    }

    mutating func setWeightsText(_ text: String) {
        weightsText = text
        weightsEdited = true
    }

    /// Applies an optimizer result. The user still has to press Save.
    mutating func applyOptimizedWeights(_ weights: [Float]) {
        weightsText = formatDeckWeights(weights)
        weightsEdited = true
    }

    // MARK: Output

    /// The preset to save. Only exposed fields change; `fsrsParams4/5/6` are
    /// written per the plan's rules:
    /// - weights untouched → all three stay exactly as loaded;
    /// - weights edited/optimized → only `fsrsParams6` is rewritten;
    /// - FSRS off never clears the stored weights.
    func apply() -> DeckConfig {
        var result = config
        result.config.learnSteps = parseDeckSteps(learnStepsText)
        result.config.relearnSteps = parseDeckSteps(relearnStepsText)
        result.config.paramSearch = paramSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        result.config.newPerDay = clamp(result.config.newPerDay, DeckOptionLimits.perDay)
        result.config.reviewsPerDay = clamp(result.config.reviewsPerDay, DeckOptionLimits.perDay)
        result.config.maximumReviewInterval = clamp(
            result.config.maximumReviewInterval, DeckOptionLimits.interval
        )
        result.config.graduatingIntervalGood = clamp(
            result.config.graduatingIntervalGood, DeckOptionLimits.interval
        )
        result.config.graduatingIntervalEasy = clamp(
            result.config.graduatingIntervalEasy, DeckOptionLimits.interval
        )
        result.config.leechThreshold = clamp(result.config.leechThreshold, DeckOptionLimits.leech)
        // A zero means "never set" in old collections; leave it for the
        // engine's own defaulting rather than snapping it to the range start.
        result.config.desiredRetention = clampNonZero(
            result.config.desiredRetention, DeckOptionLimits.desiredRetention
        )
        result.config.historicalRetention = clampNonZero(
            result.config.historicalRetention, DeckOptionLimits.historicalRetention
        )
        result.config.intervalMultiplier = clampNonZero(
            result.config.intervalMultiplier, DeckOptionLimits.intervalMultiplier
        )
        result.config.hardMultiplier = clampNonZero(
            result.config.hardMultiplier, DeckOptionLimits.hardMultiplier
        )
        result.config.easyMultiplier = clampNonZero(
            result.config.easyMultiplier, DeckOptionLimits.easyMultiplier
        )
        if weightsEdited {
            result.config.fsrsParams6 = parseDeckFloats(weightsText)
        }
        return result
    }

    var saveOptions: DeckOptionsSaveOptions {
        DeckOptionsSaveOptions(
            applyToChildren: applyToChildren,
            fsrsEnabled: fsrsEnabled,
            ignoreReviewLimit: ignoreReviewLimit,
            applyAllParentLimits: applyAllParentLimits,
            runHealthCheck: runHealthCheck
        )
    }

    var toggles: Toggles {
        Toggles(
            applyToChildren: applyToChildren,
            fsrsEnabled: fsrsEnabled,
            ignoreReviewLimit: ignoreReviewLimit,
            applyAllParentLimits: applyAllParentLimits,
            runHealthCheck: runHealthCheck
        )
    }

    var isDirty: Bool {
        apply() != baseline || toggles != initialToggles
    }

    /// Validation that only concerns text this screen owns. The engine remains
    /// authoritative for values that drift out of range.
    var weightsValidationMessage: String? {
        guard weightsEdited else { return nil }
        let trimmed = weightsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Enter FSRS weights, or leave them unchanged."
        }
        let values = parseDeckFloats(trimmed)
        let tokenCount = trimmed
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" })
            .count
        guard values.count == tokenCount else {
            return "Weights must be numbers separated by spaces or commas."
        }
        return nil
    }

    // MARK: Helpers

    private func normalized(_ value: Float, fallback: Float) -> Float {
        value > 0 ? value : fallback
    }

    private func clamp(_ value: Int, _ range: ClosedRange<Double>) -> Int {
        Int(min(max(Double(value), range.lowerBound), range.upperBound))
    }

    private func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private func clampNonZero(_ value: Float, _ range: ClosedRange<Double>) -> Float {
        guard value > 0 else { return value }
        return Float(clamp(Double(value), range))
    }
}

/// `Name`, `Name 2`, `Name 3`… — the engine accepts duplicates (E12), so the
/// client must not create them.
func uniquePresetName(_ base: String, existing: [String]) -> String {
    let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
    let candidate = trimmed.isEmpty ? "Preset" : trimmed
    let taken = Set(existing.map { $0.lowercased() })
    guard taken.contains(candidate.lowercased()) else { return candidate }

    var index = 2
    while taken.contains("\(candidate) \(index)".lowercased()) {
        index += 1
    }
    return "\(candidate) \(index)"
}
