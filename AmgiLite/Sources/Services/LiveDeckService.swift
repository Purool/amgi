import AnkiBackend
import AnkiKit
import AnkiProtoBridge

struct LiveDeckService: DeckServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    func deckTree() async throws -> [DeckRow] {
        let backend = self.backend
        try requireCollectionOpen(state)
        let roots: [DeckTreeNode] = try await backendOffload {
            try backend.invoke(.deckTree())
        }
        return Self.flatten(roots, depth: 0)
    }

    func counts(for deckID: DeckID) async throws -> DeckCounts {
        let backend = self.backend
        try requireCollectionOpen(state)
        return try await backendOffload {
            try backend.invoke(.deckCounts(for: deckID)) ?? .zero
        }
    }

    /// Depth-first, parents before children — the order the deck list renders in.
    static func flatten(_ nodes: [DeckTreeNode], depth: Int) -> [DeckRow] {
        nodes.flatMap { node in
            [DeckRow(
                id: node.id,
                name: node.name,
                fullName: node.fullName,
                counts: node.counts,
                depth: depth
            )] + flatten(node.children, depth: depth + 1)
        }
    }
}
