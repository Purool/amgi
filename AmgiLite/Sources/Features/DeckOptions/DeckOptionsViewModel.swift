import AnkiKit
import Foundation

/// State machine for the deck-options screen. It owns the draft and every
/// service call; the view controller only renders and forwards intents.
@MainActor
final class DeckOptionsViewModel {
    enum State {
        case loading
        case content
        case error(String)
    }

    let deckID: DeckID
    let deckName: String

    private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    private(set) var draft: DeckOptionsDraft?
    private(set) var context: DeckConfigsForUpdate?

    var onStateChange: ((State) -> Void)?
    /// Fired after every draft mutation so the screen can refresh Save.
    var onDraftChange: (() -> Void)?

    private let services: LiteServices
    private let session: CollectionSession

    init(services: LiteServices, session: CollectionSession, deckID: DeckID, deckName: String) {
        self.services = services
        self.session = session
        self.deckID = deckID
        self.deckName = deckName
    }

    var canSave: Bool {
        guard let draft else { return false }
        return draft.isDirty && draft.weightsValidationMessage == nil
    }

    var presetName: String { draft?.config.name ?? "—" }

    var presets: [DeckConfigsForUpdate.ConfigWithExtra] {
        context?.allConfig ?? []
    }

    var currentPresetID: DeckConfigID? {
        context?.currentDeck?.configID
    }

    var defaultPreset: DeckConfig? {
        context?.allConfig.first(where: { $0.config.id == DeckConfigID(1) })?.config
            ?? context?.defaults
    }

    // MARK: - Loading

    func load(showLoadingOverlay: Bool = true) {
        if showLoadingOverlay {
            state = .loading
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.ensureOpen()
                let context = try await self.services.deckOptions.context(deckID: self.deckID)
                let config = try await self.services.deckOptions.config(for: self.deckID)
                self.apply(context: context, config: config)
            } catch {
                self.state = .error(ErrorMessages.text(for: error))
            }
        }
    }

    private func apply(context: DeckConfigsForUpdate, config: DeckConfig) {
        self.context = context
        self.draft = DeckOptionsDraft(config: config, context: context)
        self.state = .content
        self.onDraftChange?()
    }

    /// Re-reads the context after a preset mutation and rebuilds the draft.
    private func reload() async throws {
        let context = try await services.deckOptions.context(deckID: deckID)
        let config = try await services.deckOptions.config(for: deckID)
        apply(context: context, config: config)
    }

    // MARK: - Editing

    func mutate(_ body: (inout DeckOptionsDraft) -> Void) {
        guard var draft else { return }
        body(&draft)
        self.draft = draft
        onDraftChange?()
    }

    // MARK: - Saving

    func save() async throws {
        guard let draft else { return }
        if let message = draft.weightsValidationMessage {
            throw LiteError.engine(message)
        }
        try await services.deckOptions.save(
            deckID: deckID,
            config: draft.apply(),
            options: draft.saveOptions
        )
    }

    // MARK: - Preset operations

    func switchPreset(to preset: DeckConfig, applyToChildren: Bool) async throws {
        try await services.deckOptions.switchPreset(
            deckID: deckID,
            to: preset,
            applyToChildren: applyToChildren
        )
        try await reload()
    }

    func renamePreset(_ preset: DeckConfig, to name: String, applyToChildren: Bool) async throws {
        try await services.deckOptions.renamePreset(
            deckID: deckID,
            preset: preset,
            to: name,
            applyToChildren: applyToChildren
        )
        try await reload()
    }

    func createPreset(name: String, applyToChildren: Bool) async throws {
        guard let base = draft?.apply() ?? context?.defaults else {
            throw LiteError.engine("No preset to copy.")
        }
        let existing = presets.map { $0.config.name }
        let unique = uniquePresetName(name, existing: existing)
        try await services.deckOptions.createPreset(
            deckID: deckID,
            from: base,
            name: unique,
            applyToChildren: applyToChildren
        )
        try await reload()
    }

    func deletePreset(id: DeckConfigID, applyToChildren: Bool) async throws {
        guard let fallback = defaultPreset else {
            throw LiteError.engine("No fallback preset available.")
        }
        try await services.deckOptions.deletePreset(
            deckID: deckID,
            id: id,
            fallback: fallback,
            applyToChildren: applyToChildren
        )
        try await reload()
    }

    // MARK: - FSRS

    func optimizeWeights() async throws -> FsrsOptimizeResult {
        guard let draft else {
            throw LiteError.engine("Deck options are not loaded.")
        }
        let request = FsrsOptimizeRequest(
            search: effectiveParamSearch,
            currentWeights: FsrsWeights(parseDeckFloats(draft.weightsText)),
            relearningStepsPerDay: Int(
                relearningStepsInDay(parseDeckSteps(draft.relearnStepsText))
            ),
            runHealthCheck: draft.runHealthCheck
        )
        return try await services.deckOptions.optimizeWeights(request)
    }

    func optimizeAllPresets() async throws {
        guard let draft else {
            throw LiteError.engine("Deck options are not loaded.")
        }
        try await services.deckOptions.optimizeAllPresets(
            deckID: deckID,
            current: draft.apply()
        )
        try await reload()
    }

    var effectiveParamSearch: String {
        let trimmed = draft?.paramSearch.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultParamSearch : trimmed
    }

    var defaultParamSearch: String {
        "preset:\"\(presetName)\" -is:suspended"
    }
}
