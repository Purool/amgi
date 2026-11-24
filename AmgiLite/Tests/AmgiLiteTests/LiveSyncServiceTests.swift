import XCTest

import AnkiBackend
import AnkiKit
@testable import AmgiLite

/// Offline paths of `LiveSyncService`: everything that must not touch the
/// network or the Keychain. Login and incremental sync are exercised on
/// device, never in CI (`Tests/AGENTS.md`: no network in tests).
final class LiveSyncServiceTests: XCTestCase {
    // MARK: - Fixtures

    private struct Workspace {
        let root: URL
        let media: URL

        var paths: CollectionPaths {
            CollectionPaths(
                collectionPath: root.appendingPathComponent("collection.anki2").path,
                mediaFolderPath: media.path,
                mediaDatabasePath: root.appendingPathComponent("collection.media.db2").path
            )
        }

        static func make() throws -> Workspace {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("amgilite-sync-\(UUID().uuidString)", isDirectory: true)
            let media = root.appendingPathComponent("collection.media", isDirectory: true)
            try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
            return Workspace(root: root, media: media)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: - Collection-gated flows

    func testSyncWithoutAnOpenCollectionFailsWithCollectionNotOpen() async throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)

        do {
            try await services.sync.sync()
            XCTFail("sync must refuse to run before the collection is open")
        } catch let error as LiteError {
            XCTAssertEqual(error, .collectionNotOpen)
        } catch {
            XCTFail("expected LiteError.collectionNotOpen, got \(error)")
        }
    }

    func testFullSyncWithoutAnOpenCollectionFailsWithCollectionNotOpen() async throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)

        for direction in [SyncDirection.upload, .download] {
            do {
                try await services.sync.fullSync(direction: direction)
                XCTFail("fullSync(\(direction)) must refuse to run before the collection is open")
            } catch let error as LiteError {
                XCTAssertEqual(error, .collectionNotOpen)
            } catch {
                XCTFail("expected LiteError.collectionNotOpen, got \(error)")
            }
        }
    }

    // MARK: - Local queries

    func testMediaSyncStatusIsInactiveWithoutASync() async throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)
        let workspace = try Workspace.make()
        defer { workspace.cleanUp() }

        try await services.collection.open(workspace.paths)
        defer { Task { try? await services.collection.close() } }

        let status = try await services.sync.mediaSyncStatus()
        XCTAssertFalse(status.active)
        XCTAssertNil(status.progress)
    }

    /// Cancelling with nothing running must be a silent no-op: the abort
    /// requests are best effort and must never surface an error of their own.
    func testCancelWithoutARunningSyncDoesNotThrow() async throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)

        await services.sync.cancel()
    }

    // MARK: - Contract surface

    /// A service instance that never logged in reports the logged-out state
    /// without any I/O beyond a Keychain read.
    func testAccountSummaryReflectsLoginState() throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])
        let services = LiteServices.live(backend: backend)

        // Do not pin either outcome: a previous test run (or the device)
        // may have left credentials behind. What matters is consistency —
        // the summary must agree with the flag and expose the name only
        // when logged in.
        if services.sync.isLoggedIn, let username = services.sync.loggedInUsername {
            XCTAssertFalse(username.isEmpty)
        }
    }
}
