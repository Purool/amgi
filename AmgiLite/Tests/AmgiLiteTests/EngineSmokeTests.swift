import XCTest

import AnkiBackend
import AnkiKit

/// Phase 0 gate: proves the copied engine sources compile against iOS 14, the
/// Rust dylib loads, and SQLite can create a collection. Everything else in
/// Phase 0 is build configuration.
final class EngineSmokeTests: XCTestCase {
    func testBackendLoadsAndCreatesCollection() throws {
        let backend = try AnkiBackend(preferredLangs: ["en"])

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("amgilite-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaFolder = root.appendingPathComponent("collection.media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaFolder, withIntermediateDirectories: true)

        try backend.openCollection(
            collectionPath: root.appendingPathComponent("collection.anki2").path,
            mediaFolderPath: mediaFolder.path,
            mediaDbPath: root.appendingPathComponent("collection.media.db2").path
        )

        XCTAssertEqual(backend.currentMediaFolderPath, mediaFolder.path)

        try backend.closeCollection()
    }
}
