import AnkiBackend
import AnkiKit

/// Thin, injection-based wrappers over `AnkiBackend`. Every call hops off the
/// caller's actor: `invoke` blocks on the engine lock and on SQLite.
///
/// These types live in the app target on purpose — `Sources/AGENTS.md` allows
/// engine imports only in `Sources/Services/`. The `Request` factories in
/// `AnkiProtoBridge` are `public`, so no package-level access is needed here.

struct LiveCollectionService: CollectionServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    var mediaFolderPath: String? {
        state.mediaFolderPath
    }

    func open(_ paths: CollectionPaths) async throws {
        let backend = self.backend
        try await backendOffload {
            try backend.openCollection(
                collectionPath: paths.collectionPath,
                mediaFolderPath: paths.mediaFolderPath,
                mediaDbPath: paths.mediaDatabasePath
            )
        }
        state.markOpen(mediaFolder: paths.mediaFolderPath)
    }

    func close() async throws {
        let backend = self.backend
        try await backendOffload {
            try backend.closeCollection()
        }
        state.markClosed()
    }
}
