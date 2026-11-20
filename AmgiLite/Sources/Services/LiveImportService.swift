import AnkiBackend
import AnkiKit
import AnkiProtoBridge
import Foundation

struct LiveImportService: ImportServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    /// `.apkg` import is a long blocking call (unzip + SQLite writes), so it
    /// must stay off the main actor for the whole duration.
    func importPackage(at url: URL) async throws {
        let backend = self.backend
        try requireCollectionOpen(state)
        let summary: ImportLogSummary = try await backendOffload {
            try backend.invoke(.importAnkiPackage(path: url.path))
        }
        _ = summary
    }
}

/// Phase 3 replaces this with the real AnkiWeb client. Until then the settings
/// screen can render honestly: sync exists in the UI, but is not wired.
struct UnavailableSyncService: SyncServicing {
    var isLoggedIn: Bool { false }

    func logIn(username: String, password: String) async throws {
        throw LiteError.notImplemented
    }

    func sync() async throws {
        throw LiteError.notImplemented
    }
}
