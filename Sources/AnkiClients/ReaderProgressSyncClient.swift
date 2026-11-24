//
//  ReaderProgressSyncClient.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 05.05.2026.
//

public import Reader
public import Dependencies
import DependenciesMacros
import AnkiBackend
import Foundation

/// Cross-device sync adapter for `ReaderProgressStore`. The store persists
/// per-book progress locally to UserDefaults; this client mirrors writes
/// into the Anki collection config so the same progress reaches other
/// devices via Anki sync.
///
/// Lives in `AnkiClients` rather than `Reader` because the bridge
/// to Anki's `setConfigJSONValue` is an Anki concern. `Reader` itself
/// stays Anki-free.
@DependencyClient
public struct ReaderProgressSyncClient: Sendable {
    /// Returns the merged manifest of book → progress entries that the
    /// Anki collection currently holds, or nil if nothing has been
    /// synced yet from any device.
    public var loadManifest: @Sendable () async throws -> ReaderProgressManifest?
    /// Pushes a single book's progress into the collection config and
    /// returns the resulting manifest. Idempotent on identical writes.
    public var pushBookProgress: @Sendable (
        _ bookID: String,
        _ payload: ReaderSavedProgress
    ) async throws -> ReaderProgressManifest
}

extension ReaderProgressSyncClient: TestDependencyKey {
    public static let testValue = ReaderProgressSyncClient()
}

extension DependencyValues {
    public var readerProgressSyncClient: ReaderProgressSyncClient {
        get { self[ReaderProgressSyncClient.self] }
        set { self[ReaderProgressSyncClient.self] = newValue }
    }
}

/// JSON-encoded shape stored in the Anki collection config under the
/// `amgi.reader.progress` key. Mirrors DreamAfar's manifest schema so a
/// collection synced between forks can interoperate.
public struct ReaderProgressManifest: Codable, Sendable, Equatable {
    public var version: Int
    public var entries: [String: ReaderSavedProgress]

    public init(version: Int = 1, entries: [String: ReaderSavedProgress] = [:]) {
        self.version = version
        self.entries = entries
    }
}

extension ReaderProgressSyncClient: DependencyKey {
    /// Anki collection-config key matching DreamAfar's. Keep stable so a
    /// collection that has been read from either fork sees the same
    /// progress data.
    private static let collectionConfigKey = "amgi.reader.progress"

    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            loadManifest: {
                try await backendOffload {
                    try backend.getConfigJSONValue(for: collectionConfigKey)
                }
            },
            pushBookProgress: { bookID, payload in
                try await backendOffload {
                    var manifest: ReaderProgressManifest = (try backend.getConfigJSONValue(for: collectionConfigKey))
                        ?? ReaderProgressManifest()

                    // Last-write-wins per book. The caller stamps `updatedAt`
                    // so this routine doesn't need its own clock.
                    if let existing = manifest.entries[bookID],
                       existing.updatedAt > payload.updatedAt {
                        return manifest
                    }

                    manifest.entries[bookID] = payload
                    try backend.setConfigJSONValue(manifest, for: collectionConfigKey)
                    return manifest
                }
            }
        )
    }()
}
