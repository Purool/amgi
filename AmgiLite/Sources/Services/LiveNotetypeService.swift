import AnkiBackend
import AnkiKit
import AnkiProtoBridge

struct LiveNotetypeService: NotetypeServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    func names() async throws -> [NotetypeNameId] {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.notetypeNames)
        }
    }

    func notetype(id: NotetypeID) async throws -> Notetype {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.notetype(for: id))
        }
    }

    func save(_ notetype: Notetype) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            try backend.invoke(.updateNotetype(notetype))
        }
    }

    func remove(id: NotetypeID) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        try await backendOffload {
            try backend.invoke(.removeNotetype(id: id))
        }
    }

    func preview(
        notetypeID: NotetypeID,
        template: Notetype.Template,
        cardOrd: Int,
        sampleFields: [String]
    ) async throws -> RenderedCard {
        let backend = self.backend
        try requireCollectionOpen(state)
        let ord = UInt32(clamping: max(0, cardOrd))
        return try await backendOffload {
            try backend.invoke(.renderUncommittedCard(
                notetypeId: notetypeID,
                template: template,
                cardOrd: ord,
                sampleFields: sampleFields
            ))
        }
    }
}
