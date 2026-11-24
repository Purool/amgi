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
