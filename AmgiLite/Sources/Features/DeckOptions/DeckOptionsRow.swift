import AnkiKit

/// Section order and titles for the deck-options list.
enum DeckOptionsSection: Int, CaseIterable, Hashable {
    case preset
    case dailyLimits
    case newCards
    case lapses
    case burying
    case order
    case advanced
    case fsrs

    var title: String {
        switch self {
        case .preset: return "Preset"
        case .dailyLimits: return "Daily Limits"
        case .newCards: return "New Cards"
        case .lapses: return "Lapses"
        case .burying: return "Burying"
        case .order: return "Order"
        case .advanced: return "Advanced"
        case .fsrs: return "FSRS"
        }
    }

    var rows: [DeckOptionsRow] {
        switch self {
        case .preset:
            return [.preset, .applyToChildren]
        case .dailyLimits:
            return [.newPerDay, .reviewsPerDay, .ignoreReviewLimit]
        case .newCards:
            return [
                .learnSteps, .graduatingInterval, .easyInterval,
                .insertOrder, .gatherOrder, .sortOrder,
            ]
        case .lapses:
            return [.relearnSteps, .leechThreshold, .leechAction]
        case .burying:
            return [.buryNew, .buryReviews, .buryInterdayLearning]
        case .order:
            return [.reviewOrder, .newMix, .interdayMix]
        case .advanced:
            return [.maximumInterval, .intervalMultiplier, .hardMultiplier, .easyMultiplier]
        case .fsrs:
            return [
                .fsrsEnabled, .desiredRetention, .historicalRetention, .fsrsWeights,
                .paramSearch, .healthCheck, .optimizeAll, .lastOptimized,
            ]
        }
    }
}

enum DeckOptionsRow: Hashable {
    // Preset
    case preset
    case applyToChildren
    // Daily limits
    case newPerDay
    case reviewsPerDay
    case ignoreReviewLimit
    // New cards
    case learnSteps
    case graduatingInterval
    case easyInterval
    case insertOrder
    case gatherOrder
    case sortOrder
    // Lapses
    case relearnSteps
    case leechThreshold
    case leechAction
    // Burying
    case buryNew
    case buryReviews
    case buryInterdayLearning
    // Order
    case reviewOrder
    case newMix
    case interdayMix
    // Advanced
    case maximumInterval
    case intervalMultiplier
    case hardMultiplier
    case easyMultiplier
    // FSRS
    case fsrsEnabled
    case desiredRetention
    case historicalRetention
    case fsrsWeights
    case paramSearch
    case healthCheck
    case optimizeAll
    case lastOptimized

    var section: DeckOptionsSection {
        for section in DeckOptionsSection.allCases where section.rows.contains(self) {
            return section
        }
        return .preset
    }
}

// MARK: - Enum labels

extension NewCardInsertOrder {
    var label: String {
        switch self {
        case .due: return "Due"
        case .random: return "Random"
        }
    }
}

extension NewCardGatherPriority {
    var label: String {
        switch self {
        case .deck: return "Deck"
        case .lowestPosition: return "Lowest position"
        case .highestPosition: return "Highest position"
        case .randomNotes: return "Random notes"
        case .randomCards: return "Random cards"
        case .deckThenRandomNotes: return "Deck, then random notes"
        }
    }
}

extension NewCardSortOrder {
    var label: String {
        switch self {
        case .template: return "Template"
        case .noSort: return "No sort"
        case .templateThenRandom: return "Template, then random"
        case .randomNoteThenTemplate: return "Random note, then template"
        case .randomCard: return "Random card"
        }
    }
}

extension ReviewCardOrder {
    var label: String {
        switch self {
        case .day: return "Due date"
        case .dayThenDeck: return "Due date, then deck"
        case .deckThenDay: return "Deck, then due date"
        case .intervalsAscending: return "Ascending interval"
        case .intervalsDescending: return "Descending interval"
        case .easeAscending: return "Ascending ease"
        case .easeDescending: return "Descending ease"
        case .retrievabilityAscending: return "Ascending retrievability"
        case .retrievabilityDescending: return "Descending retrievability"
        case .random: return "Random"
        case .added: return "Oldest first"
        case .reverseAdded: return "Newest first"
        case .relativeOverdueness: return "Relative overdueness"
        }
    }
}

extension ReviewMix {
    var label: String {
        switch self {
        case .mixWithReviews: return "Mix with reviews"
        case .afterReviews: return "After reviews"
        case .beforeReviews: return "Before reviews"
        }
    }
}

extension LeechAction {
    var label: String {
        switch self {
        case .suspend: return "Suspend"
        case .tagOnly: return "Tag only"
        }
    }
}
