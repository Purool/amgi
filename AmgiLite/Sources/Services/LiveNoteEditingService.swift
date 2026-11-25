import AnkiBackend
import AnkiKit
import AnkiProtoBridge

struct LiveNoteEditingService: NoteEditingServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    func newNoteTemplate(notetypeID: NotetypeID) async throws -> NewNoteTemplate {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.newNote(notetypeId: notetypeID))
        }
    }

    func addNote(_ template: NewNoteTemplate, to deckID: DeckID) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            try backend.invoke(.addNote(template: template, deckId: deckID))
        }
    }

    func save(_ note: NoteRecord) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            try backend.invoke(.updateNote(note))
        }
    }

    func delete(id: NoteID) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            try backend.invoke(.removeNote(id: id))
        }
    }

    func cardIDs(of noteID: NoteID) async throws -> [CardID] {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.cardIDsOfNote(id: noteID))
        }
    }
}
