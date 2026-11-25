import AnkiKit
import Foundation

/// State machine for the template editor: loads the notetype + preview sample
/// fields, owns the draft, saves, and re-reads the notetype after a save (E3:
/// the engine does not hand back new ordinals).
@MainActor
final class TemplateEditorViewModel {
    enum State {
        case loading
        case content
        case error(String)
    }

    let notetypeID: NotetypeID
    let previewNoteID: NoteID?
    private(set) var initialTemplateIndex: Int

    private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    private(set) var draft: NotetypeDraft?
    private(set) var sampleFields: [String] = []

    var onStateChange: ((State) -> Void)?

    private let services: LiteServices
    private let session: CollectionSession

    init(
        services: LiteServices,
        session: CollectionSession,
        notetypeID: NotetypeID,
        initialTemplate: Int,
        previewNoteID: NoteID?
    ) {
        self.services = services
        self.session = session
        self.notetypeID = notetypeID
        self.initialTemplateIndex = max(0, initialTemplate)
        self.previewNoteID = previewNoteID
    }

    var notetypeName: String { draft?.notetype.name ?? "Notetype" }

    var templateCount: Int { draft?.templates.count ?? 0 }

    var clampedTemplateIndex: Int {
        let count = templateCount
        guard count > 0 else { return 0 }
        return min(max(initialTemplateIndex, 0), count - 1)
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
                let notetype = try await self.services.notetypes.notetype(id: self.notetypeID)
                self.draft = NotetypeDraft(notetype)
                self.initialTemplateIndex = self.clampedTemplateIndex
                self.sampleFields = await self.loadSampleFields(fieldCount: notetype.fields.count)
                self.state = .content
            } catch {
                self.state = .error(ErrorMessages.text(for: error))
            }
        }
    }

    /// Preview fields: the note the editor was opened from, else the first
    /// note of this notetype, else blanks. Always padded/truncated to the
    /// notetype's field count.
    private func loadSampleFields(fieldCount: Int) async -> [String] {
        if let previewNoteID, let note = try? await services.browse.note(id: previewNoteID) {
            return aligned(buildSampleFields(from: note), to: fieldCount)
        }

        let query = "mid:\(notetypeID.rawValue)"
        let summaries = (try? await services.browse.searchNotes(query: query, limit: 1)) ?? []
        if let first = summaries.first,
           let note = try? await services.browse.note(id: first.id) {
            return aligned(buildSampleFields(from: note), to: fieldCount)
        }

        return makeEmptySampleFields(fieldCount: fieldCount)
    }

    private func aligned(_ fields: [String], to count: Int) -> [String] {
        if fields.count == count { return fields }
        if fields.count > count { return Array(fields.prefix(count)) }
        return fields + Array(repeating: "", count: count - fields.count)
    }

    // MARK: - Editing

    func updateTemplate(at index: Int, _ body: (inout Notetype.Template) -> Void) {
        draft?.updateTemplate(at: index, body)
    }

    func setTemplateName(_ name: String, at index: Int) {
        updateTemplate(at: index) { $0.name = name }
    }

    func setFront(_ text: String, at index: Int) {
        updateTemplate(at: index) { $0.config.qFormat = text }
    }

    func setBack(_ text: String, at index: Int) {
        updateTemplate(at: index) { $0.config.aFormat = text }
    }

    func setCSS(_ text: String) {
        draft?.notetype.config.css = text
    }

    func fieldTokens() -> [String] {
        draft?.fieldTokens ?? ["{{FrontSide}}"]
    }

    var validationMessage: String? {
        draft?.validationMessage
    }

    var hasStructuralChange: Bool {
        draft?.hasStructuralChange ?? false
    }

    // MARK: - Preview

    func makePreview(templateIndex: Int) async throws -> (rendered: RenderedCard, note: String?) {
        guard let draft, let template = draft.template(at: templateIndex) else {
            throw LiteError.engine("This notetype has no template to preview.")
        }

        let rendered = try await services.notetypes.preview(
            notetypeID: notetypeID,
            template: template,
            cardOrd: templateIndex,
            sampleFields: sampleFields
        )

        // E4: the engine renders the saved CSS; swap in the draft CSS so the
        // preview matches what Save would produce.
        let withDraftCSS = RenderedCard(
            frontHTML: rendered.frontHTML,
            backHTML: rendered.backHTML,
            cardCSS: draft.notetype.config.css
        )
        let note = draft.hasUnsavedNewFields
            ? "New fields only appear in the preview after saving."
            : nil
        return (withDraftCSS, note)
    }

    // MARK: - Saving

    func save() async throws {
        guard let draft else { return }
        if let message = draft.validationMessage {
            throw LiteError.engine(message)
        }

        let selected = clampedTemplateIndex
        try await services.notetypes.save(draft.apply())

        // Re-read: the engine assigns ordinals but never returns them.
        let refreshed = try await services.notetypes.notetype(id: notetypeID)
        self.draft = NotetypeDraft(refreshed)
        self.initialTemplateIndex = min(selected, max(0, refreshed.templates.count - 1))
        self.state = .content
    }
}
