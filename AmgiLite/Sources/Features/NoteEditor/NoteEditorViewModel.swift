import AnkiKit
import Foundation

/// State machine for the note editor: loads the note plus its notetype, keeps
/// the draft aligned to the notetype's field count, and owns save/delete/
/// preview.
@MainActor
final class NoteEditorViewModel {
    enum State {
        case loading
        case content
        case error(String)
    }

    let noteID: NoteID

    private(set) var state: State = .loading {
        didSet { onStateChange?(state) }
    }

    private(set) var draft: NoteDraft?
    private(set) var notetype: Notetype?

    var onStateChange: ((State) -> Void)?

    private let services: LiteServices
    private let session: CollectionSession

    init(services: LiteServices, session: CollectionSession, noteID: NoteID) {
        self.services = services
        self.session = session
        self.noteID = noteID
    }

    var title: String {
        guard let draft else { return "Note" }
        return NoteSummary.plainText(draft.baseline.sfld)
    }

    var validationMessage: String? { draft?.validate() }

    var canSave: Bool {
        guard let draft else { return false }
        return draft.isDirty && draft.validate() == nil
    }

    func load() {
        state = .loading
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.ensureOpen()
                let note = try await self.services.browse.note(id: self.noteID)
                let notetype = try await self.services.notetypes.notetype(id: note.mid)
                self.notetype = notetype
                self.draft = NoteDraft(note: note, notetype: notetype)
                self.state = .content
            } catch {
                self.state = .error(ErrorMessages.text(for: error))
            }
        }
    }

    func updateField(at index: Int, text: String) {
        guard var draft, draft.fields.indices.contains(index) else { return }
        draft.fields[index] = text
        self.draft = draft
    }

    func updateTags(_ tags: String) {
        guard var draft else { return }
        draft.tags = tags
        self.draft = draft
    }

    // MARK: - Saving + deleting

    func save() async throws {
        guard let draft else { return }
        if let message = draft.validate() {
            throw LiteError.engine(message)
        }
        try await services.noteEditing.save(draft.apply())
    }

    /// Number of cards a delete would remove (shown in the confirmation).
    func cardCount() async throws -> Int {
        try await services.noteEditing.cardIDs(of: noteID).count
    }

    func delete() async throws {
        try await services.noteEditing.delete(id: noteID)
    }

    // MARK: - Preview

    func makePreview() async throws -> RenderedCard {
        guard let draft, let notetype, let template = notetype.templates.first else {
            throw LiteError.engine("This notetype has no template to preview.")
        }
        // The saved CSS is correct here: this screen does not edit CSS.
        return try await services.notetypes.preview(
            notetypeID: notetype.id,
            template: template,
            cardOrd: 0,
            sampleFields: draft.fields
        )
    }
}
