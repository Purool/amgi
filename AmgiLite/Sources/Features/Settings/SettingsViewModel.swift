import AnkiKit
import Foundation

/// Settings tab view model. Owns the account state and the sync/import flows;
/// the view controller observes `onAccountChange` / `onSyncStateChange` and
/// drives the UIKit surfaces (rows, progress overlay, conflict alert).
@MainActor
final class SettingsViewModel {
    enum SyncState: Equatable {
        case idle
        /// Indeterminate progress with phase / media-progress text.
        case running(String)
        /// The server requires a full sync; the user must pick a direction.
        case conflict
        case finished
        case failed(String)
    }

    private(set) var syncState: SyncState = .idle {
        didSet { onSyncStateChange?(syncState) }
    }

    var onSyncStateChange: ((SyncState) -> Void)?
    var onAccountChange: (() -> Void)?

    private let services: LiteServices
    private let session: CollectionSession
    /// Polls media-sync progress while a sync runs; cancelled with the flow.
    private var pollingTask: Task<Void, Never>?

    init(services: LiteServices, session: CollectionSession) {
        self.services = services
        self.session = session
    }

    // MARK: - Account

    var isLoggedIn: Bool { services.sync.isLoggedIn }

    var loggedInUsername: String? { services.sync.loggedInUsername }

    /// Subtitle for the account row.
    var accountSummary: String {
        guard isLoggedIn else { return "Not signed in to AnkiWeb" }
        return loggedInUsername.map { "Signed in as \($0)" } ?? "Signed in"
    }

    var canSync: Bool { isLoggedIn && syncState == .idle }

    func refresh() {
        onAccountChange?()
    }

    /// Runs a login. `completion` receives `nil` on success or the mapped
    /// failure message, and is always called exactly once on the main actor.
    func logIn(
        username: String,
        password: String,
        completion: @escaping (String?) -> Void
    ) {
        Task { [services] in
            do {
                try await services.sync.logIn(username: username, password: password)
                self.refresh()
                completion(nil)
            } catch {
                completion(ErrorMessages.text(for: error))
            }
        }
    }

    // MARK: - Sync

    func sync() {
        guard case .idle = syncState else { return }
        syncState = .running("Connecting to AnkiWeb…")
        startPolling()
        Task { [services] in
            do {
                try await services.sync.sync()
                self.finishSync()
            } catch let error as SyncError {
                self.handleSyncError(error)
            } catch {
                self.failSync(error)
            }
        }
    }

    /// The user-chosen direction after a conflict prompt.
    func fullSync(direction: SyncDirection) {
        guard isLoggedIn else { return }
        syncState = .running(direction == .upload ? "Uploading collection…" : "Downloading collection…")
        startPolling()
        Task { [services] in
            do {
                try await services.sync.fullSync(direction: direction)
                self.finishSync()
            } catch let error as SyncError {
                self.handleSyncError(error)
            } catch {
                self.failSync(error)
            }
        }
    }

    func cancelSync() {
        Task { [services] in
            await services.sync.cancel()
        }
    }

    // MARK: - Import

    /// Import runs with the collection open; `.apkg` parsing is one blocking
    /// engine call, so callers show the blocking progress card around it.
    func importPackage(at url: URL) async throws {
        try await session.ensureOpen()
        try await services.importExport.importPackage(at: url)
    }

    // MARK: - Private

    private func finishSync() {
        stopPolling()
        syncState = .finished
    }

    private func failSync(_ error: Error) {
        stopPolling()
        syncState = .failed(ErrorMessages.text(for: error))
    }

    private func handleSyncError(_ error: SyncError) {
        // The struct exposes these as static values, so match by equality.
        if error == SyncError.fullSyncRequired || error == SyncError.fullUploadRequired {
            stopPolling()
            syncState = .conflict
        } else {
            failSync(error)
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        let services = self.services
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    let status = try await services.sync.mediaSyncStatus()
                    if status.active, let progress = status.progress {
                        self?.syncState = .running(
                            "Media: checked \(progress.checked), added \(progress.added), removed \(progress.removed)"
                        )
                    }
                } catch {
                    // Polling failures must not break the sync flow.
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}
