//
//  SyncClient.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 27.03.2026.
//

public import AnkiKit
public import Dependencies
import DependenciesMacros
import Foundation
import AnkiBackend
import AnkiServices
import AnkiSync
import Logging

@DependencyClient
public struct SyncClient: Sendable {
    public var sync: @Sendable () async throws -> SyncSummary
    public var fullSync: @Sendable (_ direction: SyncDirection) async throws -> Void
    public var mediaSyncStatus: @Sendable () async throws -> MediaSyncStatus
    public var abortMediaSync: @Sendable () async throws -> Void
    public var abortSync: @Sendable () async throws -> Void

    /// Merge local + server collections by:
    /// 1. exporting local as a temporary .apkg
    /// 2. full-downloading the server's collection (replacing local on disk)
    /// 3. importing the .apkg into the just-downloaded collection
    /// 4. full-uploading the merged result back to the server
    /// 5. deleting the temporary .apkg on success
    ///
    /// Reports progress via the optional callback (e.g. "Backing up local...",
    /// "Downloading from server...", "Merging...", "Uploading merged
    /// collection..."). On partial failure, the temporary .apkg is left on disk
    /// and its path is surfaced in `SyncError.recoveryBackupPath`.
    public var merge: @Sendable (_ progress: (@Sendable (String) -> Void)?) async throws -> Void
}

extension SyncClient: TestDependencyKey {
    public static let testValue = SyncClient()
}

extension DependencyValues {
    public var syncClient: SyncClient {
        get { self[SyncClient.self] }
        set { self[SyncClient.self] = newValue }
    }
}

private let logger = Logger(label: "com.ankiapp.sync.client")

/// How long a merge-flow backup is kept before it's considered stale. A failed
/// merge deliberately leaves its backup on disk for recovery; this window is
/// generous enough to cover that while preventing indefinite accumulation.
private let mergeBackupRetention: TimeInterval = 7 * 24 * 60 * 60

/// Path for a merge-flow backup .apkg. Lives in Documents/MergeBackups/ so
/// it survives across app launches if the merge fails partway.
private func makeMergeBackupURL() throws -> URL {
    let documents = try FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    let folder = documents.appendingPathComponent("MergeBackups", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

    sweepStaleMergeBackups(in: folder)

    let stamp = Int(Date().timeIntervalSince1970)
    return folder.appendingPathComponent("merge-backup-\(stamp).apkg")
}

/// Removes merge-backup-*.apkg files older than `mergeBackupRetention` so failed
/// merges don't pile up tens-of-MB files in the user's Documents. Best-effort:
/// any error sweeping a single file is logged and skipped.
private func sweepStaleMergeBackups(in folder: URL) {
    let fileManager = FileManager.default
    guard let entries = try? fileManager.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
    ) else { return }

    let cutoff = Date().addingTimeInterval(-mergeBackupRetention)
    for entry in entries where entry.lastPathComponent.hasPrefix("merge-backup-")
        && entry.pathExtension == "apkg" {
        let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        guard let modified, modified < cutoff else { continue }
        do {
            try fileManager.removeItem(at: entry)
            logger.info("Swept stale merge backup \(entry.lastPathComponent)")
        } catch {
            logger.warning("Failed to sweep stale merge backup \(entry.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

extension SyncClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.syncService) var syncService
        @Dependency(\.importExportService) var importExportService

        return Self(
            sync: {
                let hostKey = KeychainHelper.loadHostKey() ?? ""
                guard !hostKey.isEmpty else { throw SyncError.authFailed }
                let endpoint = KeychainHelper.loadCurrentEndpoint() ?? KeychainHelper.loadEndpoint() ?? ""
                logger.info("Starting sync")
                return try await syncService.sync(endpoint, hostKey)
            },
            fullSync: { direction in
                let hostKey = KeychainHelper.loadHostKey() ?? ""
                guard !hostKey.isEmpty else { throw SyncError.authFailed }
                let endpoint = KeychainHelper.loadCurrentEndpoint() ?? KeychainHelper.loadEndpoint() ?? ""
                try await syncService.fullSync(endpoint, hostKey, direction, true)
            },
            mediaSyncStatus: { try await syncService.mediaSyncStatus() },
            abortMediaSync: { try await syncService.abortMediaSync() },
            abortSync: { try await syncService.abortSync() },
            merge: { progress in
                let hostKey = KeychainHelper.loadHostKey() ?? ""
                guard !hostKey.isEmpty else { throw SyncError.authFailed }
                let endpoint = KeychainHelper.loadCurrentEndpoint() ?? KeychainHelper.loadEndpoint() ?? ""

                let backupURL = try makeMergeBackupURL()
                let backupPath = backupURL.path

                // Step 1: export local as .apkg backup (no destruction yet, so
                // failure here is safely retryable).
                progress?("Backing up local collection...")
                logger.info("Merge: exporting local backup to \(backupPath)")
                do {
                    try await backendOffload { try importExportService.exportApkgForMerge(backupPath) }
                } catch {
                    try? FileManager.default.removeItem(at: backupURL)
                    throw SyncError(message: "Merge failed during backup: \(error.localizedDescription)")
                }

                // From here on, partial failures leave the backup in place so
                // the user can recover.
                func wrap(_ stage: String, _ work: () async throws -> Void) async throws {
                    do {
                        try await work()
                    } catch {
                        logger.error("Merge failed at \(stage): \(error.localizedDescription)")
                        throw SyncError(
                            message: "Merge failed during \(stage): \(error.localizedDescription). Local backup saved at \(backupPath).",
                            recoveryBackupPath: backupPath
                        )
                    }
                }

                progress?("Downloading from server...")
                try await wrap("download") {
                    try await syncService.fullSync(endpoint, hostKey, .download, false)
                }

                progress?("Merging in local data...")
                try await wrap("merge import") {
                    _ = try await backendOffload { try importExportService.importApkgForMerge(backupPath) }
                }

                progress?("Uploading merged collection...")
                try await wrap("upload") {
                    try await syncService.fullSync(endpoint, hostKey, .upload, true)
                }

                // Success — clean up.
                try? FileManager.default.removeItem(at: backupURL)
                logger.info("Merge complete")
            }
        )
    }()

    public static func login(
        username: String,
        password: String
    ) async throws -> String {
        @Dependency(\.syncService) var syncService

        logger.info("Logging in as \(username)")
        let endpoint = KeychainHelper.loadEndpoint() ?? ""
        let hostKey = try await syncService.login(endpoint, username, password)
        try KeychainHelper.saveHostKey(hostKey)
        try KeychainHelper.saveUsername(username)
        return hostKey
    }
}
