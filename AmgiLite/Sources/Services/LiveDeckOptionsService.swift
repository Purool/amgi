import AnkiBackend
import AnkiKit
import AnkiProtoBridge
import Foundation

/// Deck-options reads/writes. Every mutation goes through
/// `updateDeckConfigs`; the request-level switches (`limits`, ignore-review,
/// parent limits, FSRS) come from a fresh context read inside the service so
/// a screen cannot accidentally clear a deck-level override (E7).
struct LiveDeckOptionsService: DeckOptionsServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    func context(deckID: DeckID) async throws -> DeckConfigsForUpdate {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.deckConfigsForUpdate(deckId: deckID))
        }
    }

    func config(for deckID: DeckID) async throws -> DeckConfig {
        let context = try await context(deckID: deckID)
        let currentID = context.currentDeck?.configID ?? DeckConfigID(0)

        if currentID.rawValue != 0 {
            if let matched = context.allConfig.first(where: { $0.config.id == currentID })?.config {
                return matched
            }
            let backend = self.backend
            return try await backendOffload {
                try backend.invoke(.deckConfig(for: currentID))
            }
        }

        if let defaults = context.defaults {
            return defaults
        }

        throw BackendError(
            kind: .invalidInput,
            message: "Deck \(deckID.rawValue) has no preset and the engine supplied no defaults"
        )
    }

    func save(deckID: DeckID, config: DeckConfig, options: DeckOptionsSaveOptions) async throws {
        let context = try await context(deckID: deckID)
        // A filtered deck (or a vanished one) has no preset to update, and
        // sending `limits: nil` would wipe the deck-level overrides.
        guard context.currentDeck != nil else {
            throw BackendError(
                kind: .filteredDeckError,
                message: "Filtered decks have no deck options."
            )
        }

        let request = makeUpdateRequest(
            deckID: deckID,
            context: context,
            configs: [config],
            removed: [],
            mode: options.applyToChildren ? .applyToChildren : .normal,
            fsrs: options.fsrsEnabled,
            ignoreReviewLimit: options.ignoreReviewLimit,
            applyAllParentLimits: options.applyAllParentLimits,
            healthCheck: options.runHealthCheck
        )
        try await invokeUpdate(request)
    }

    func switchPreset(deckID: DeckID, to preset: DeckConfig, applyToChildren: Bool) async throws {
        let context = try await context(deckID: deckID)
        let request = makeUpdateRequest(
            deckID: deckID,
            context: context,
            configs: [preset],
            removed: [],
            mode: applyToChildren ? .applyToChildren : .normal,
            fsrs: context.fsrs
        )
        try await invokeUpdate(request)
    }

    func renamePreset(
        deckID: DeckID,
        preset: DeckConfig,
        to name: String,
        applyToChildren: Bool
    ) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackendError(kind: .invalidInput, message: "Preset name can't be empty")
        }

        var renamed = preset
        renamed.name = trimmed
        let context = try await context(deckID: deckID)
        let request = makeUpdateRequest(
            deckID: deckID,
            context: context,
            configs: [renamed],
            removed: [],
            mode: applyToChildren ? .applyToChildren : .normal,
            fsrs: context.fsrs
        )
        try await invokeUpdate(request)
    }

    func createPreset(
        deckID: DeckID,
        from base: DeckConfig,
        name: String,
        applyToChildren: Bool
    ) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackendError(kind: .invalidInput, message: "Preset name can't be empty")
        }

        var created = base
        created.id = DeckConfigID(0)
        created.name = trimmed
        let context = try await context(deckID: deckID)
        let request = makeUpdateRequest(
            deckID: deckID,
            context: context,
            configs: [created],
            removed: [],
            mode: applyToChildren ? .applyToChildren : .normal,
            fsrs: context.fsrs
        )
        try await invokeUpdate(request)
    }

    func deletePreset(
        deckID: DeckID,
        id: DeckConfigID,
        fallback: DeckConfig,
        applyToChildren: Bool
    ) async throws {
        guard id.rawValue != 0, id.rawValue != 1 else {
            throw BackendError(
                kind: .invalidInput,
                message: "The default preset can't be deleted."
            )
        }
        guard id != fallback.id else {
            throw BackendError(
                kind: .invalidInput,
                message: "The fallback preset must differ from the deleted preset."
            )
        }

        let context = try await context(deckID: deckID)
        let request = makeUpdateRequest(
            deckID: deckID,
            context: context,
            configs: [fallback],
            removed: [id],
            mode: applyToChildren ? .applyToChildren : .normal,
            fsrs: context.fsrs
        )
        try await invokeUpdate(request)
    }

    func optimizeWeights(_ request: FsrsOptimizeRequest) async throws -> FsrsOptimizeResult {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.computeFsrsParams(request))
        }
    }

    func optimizeAllPresets(deckID: DeckID, current: DeckConfig) async throws {
        let context = try await context(deckID: deckID)
        let request = makeUpdateRequest(
            deckID: deckID,
            context: context,
            configs: [current],
            removed: [],
            mode: .computeAllParams,
            // E6: computeAllParams requires fsrs == true.
            fsrs: true
        )
        try await invokeUpdate(request)
    }

    // MARK: - Private

    private func invokeUpdate(_ request: UpdateDeckConfigsRequest) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            try backend.invoke(.updateDeckConfigs(request))
        }
    }

    private func makeUpdateRequest(
        deckID: DeckID,
        context: DeckConfigsForUpdate,
        configs: [DeckConfig],
        removed: [DeckConfigID],
        mode: UpdateDeckConfigsMode,
        fsrs: Bool,
        ignoreReviewLimit: Bool? = nil,
        applyAllParentLimits: Bool? = nil,
        healthCheck: Bool? = nil
    ) -> UpdateDeckConfigsRequest {
        UpdateDeckConfigsRequest(
            targetDeckID: deckID,
            configs: configs,
            removedConfigIds: removed,
            mode: mode,
            cardStateCustomizer: context.cardStateCustomizer,
            // E7: pass the deck's overrides back untouched.
            limits: context.currentDeck?.limits,
            newCardsIgnoreReviewLimit: ignoreReviewLimit ?? context.newCardsIgnoreReviewLimit,
            fsrs: fsrs,
            applyAllParentLimits: applyAllParentLimits ?? context.applyAllParentLimits,
            fsrsHealthCheck: healthCheck ?? context.fsrsHealthCheck
        )
    }
}
