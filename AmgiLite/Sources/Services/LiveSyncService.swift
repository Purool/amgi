import AnkiBackend
import AnkiKit
import AnkiProtoBridge
import AnkiSync
import Foundation

/// AnkiWeb sync over the engine's sync service. The flow mirrors the main
/// app's `AnkiServices/SyncService` (written without `Dependencies`): login
/// exchanges username/password for a host key, `sync` runs an incremental
/// round and escalates to full upload/download when the server requires it.
///
/// Credentials live in the Keychain (`AnkiSync.KeychainHelper`, default
/// profile — Lite has no profile registry), so a login survives relaunches.
struct LiveSyncService: SyncServicing {
    private let backend: AnkiBackend
    private let state: CollectionState

    /// v1 talks to AnkiWeb only; the server may still redirect the backend to
    /// a shard mid-sync, which is tracked separately from this default.
    static let defaultEndpoint = "https://sync.ankiweb.net"

    init(backend: AnkiBackend, state: CollectionState) {
        self.backend = backend
        self.state = state
    }

    var isLoggedIn: Bool { KeychainHelper.loadHostKey() != nil }

    var loggedInUsername: String? { KeychainHelper.loadUsername() }

    func logIn(username: String, password: String) async throws {
        let backend = self.backend
        let hkey: String
        do {
            hkey = try await backendOffload {
                try backend.invoke(.syncLogin(
                    endpoint: Self.defaultEndpoint,
                    username: username,
                    password: password
                ))
            }
        } catch let error as BackendError where error.isSyncAuthError {
            throw SyncError.authFailed
        }

        // Only persist after the server accepted the credentials, so a failed
        // login never leaves a stale host key behind. Resetting the shard
        // endpoint too: a fresh login must not inherit the previous session's
        // redirect target.
        do {
            try KeychainHelper.saveHostKey(hkey)
            try KeychainHelper.saveUsername(username)
            KeychainHelper.deleteCurrentEndpoint()
        } catch {
            throw LiteError.engine("Saving the login failed: \(error)")
        }
    }

    /// Incremental sync. On `fullDownload` the local collection is empty, so
    /// the server's copy replaces it outright; `fullSync` / `fullUpload` need
    /// a user decision and surface as `SyncError` for the conflict prompt.
    func sync() async throws {
        try requireCollectionOpen(state)
        var auth = SyncAuth(hkey: try currentHostKey(), endpoint: currentEndpoint())

        let result: SyncCollectionResult = try await backendOffload {
            try backend.invoke(.syncCollection(auth: auth, syncMedia: true))
        }

        if let rawEndpoint = result.newEndpoint {
            guard let normalized = try? SyncEndpoint.normalized(rawEndpoint) else {
                throw SyncError(
                    message: "The server redirected sync to an unencrypted public address. Sync stopped."
                )
            }
            auth = SyncAuth(hkey: auth.hkey, endpoint: normalized)
            // AnkiWeb pins upload/download to a shard and only emits the
            // redirect here — persist it so later full syncs hit the shard.
            try? KeychainHelper.saveCurrentEndpoint(normalized)
        }

        switch result.required {
        case .noChanges, .normalSync:
            break
        case .fullSync:
            throw SyncError.fullSyncRequired
        case .fullDownload:
            try await fullUploadOrDownload(auth: auth, upload: false, serverUsn: result.serverMediaUsn)
            // A full download replaces the local database wholesale; ask the
            // engine to verify it before reporting success.
            _ = try await backendOffload { try backend.invoke(.checkDatabase) }
        case .fullUpload:
            throw SyncError.fullUploadRequired
        case .unrecognized(let value):
            throw SyncError(
                message: "The server reported an unrecognized sync state (\(value)). Nothing was transferred."
            )
        }
    }

    /// The user-chosen half of a forced full sync. Media sync is started
    /// explicitly: `serverUsn` 0 would claim a known media version, so
    /// `syncMedia` fetches the real one.
    func fullSync(direction: SyncDirection) async throws {
        try requireCollectionOpen(state)
        let auth = SyncAuth(hkey: try currentHostKey(), endpoint: currentEndpoint())
        try await backendOffload {
            try backend.invoke(.fullUploadOrDownload(
                auth: auth,
                upload: direction == .upload,
                serverUsn: nil
            ))
        }
        try await backendOffload { try backend.invoke(.syncMedia(auth: auth)) }
    }

    func mediaSyncStatus() async throws -> MediaSyncStatus {
        try await backendOffload { try backend.invoke(.mediaSyncStatus) }
    }

    /// Best effort: ask the engine to abort both sync directions. `abortSync`
    /// is declared `bypassesLock` because the interrupted sync holds the
    /// engine's global lock; a rejected or no-op abort must never surface as
    /// an error of its own.
    func cancel() async {
        let backend = self.backend
        _ = try? await backendOffload { try backend.invoke(.abortSync) }
        _ = try? await backendOffload { try backend.invoke(.abortMediaSync) }
    }

    // MARK: - Private

    /// The interrupted-sync helper, kept off the public surface so callers
    /// cannot skip the conflict prompt.
    private func fullUploadOrDownload(
        auth: SyncAuth, upload: Bool, serverUsn: Int32?
    ) async throws {
        try await backendOffload {
            try backend.invoke(.fullUploadOrDownload(
                auth: auth, upload: upload, serverUsn: serverUsn
            ))
        }
    }

    /// No stored host key means `isLoggedIn` lied, which cannot happen
    /// through the UI (Sync is gated on it) — fail with the auth error rather
    /// than letting the backend reject an empty key opaque-ly.
    private func currentHostKey() throws -> String {
        guard let hkey = KeychainHelper.loadHostKey() else {
            throw SyncError.authFailed
        }
        return hkey
    }

    /// The last server redirect wins; fall back to the AnkiWeb default.
    private func currentEndpoint() -> String {
        KeychainHelper.loadCurrentEndpoint() ?? Self.defaultEndpoint
    }
}
