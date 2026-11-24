//
//  MediaClient.swift
//  AnkiClients
//
//  Created by Vladimir Gusev on 27.03.2026.
//

public import AnkiKit
public import Foundation
public import Dependencies
import DependenciesMacros
import AnkiBackend
import AnkiProtoBridge
import Logging

public enum MediaClientError: Error { case noMediaFolder }

@DependencyClient
public struct MediaClient: Sendable {
    public var localURL: @Sendable (_ filename: String) -> URL? = { _ in nil }

    /// Root of Anki's media folder, or nil before a collection is open.
    /// Prefer `localURL` when you want one file — this is for callers that
    /// resolve paths themselves, like the card WebView's asset scheme handler.
    public var folderURL: @Sendable () -> URL? = { nil }
    public var save: @Sendable (_ data: Data, _ filename: String) async throws -> Void
    public var delete: @Sendable (_ filename: String) async throws -> Void

    /// Runs Anki's media-check pass and returns a snapshot of orphan vs. missing media files.
    public var checkMedia: @Sendable () async throws -> MediaCheckResult

    /// Moves named media files into Anki's trash directory (recoverable until emptied).
    public var trashMediaFiles: @Sendable (_ filenames: [String]) async throws -> Void

    /// Permanently deletes everything currently in the media trash.
    public var emptyTrash: @Sendable () async throws -> Void

    /// Restores files in the media trash back into the active media folder.
    public var restoreTrash: @Sendable () async throws -> Void
}

extension MediaClient: TestDependencyKey {
    public static let testValue = MediaClient()
}

extension DependencyValues {
    public var mediaClient: MediaClient {
        get { self[MediaClient.self] }
        set { self[MediaClient.self] = newValue }
    }
}

private let logger = Logger(label: "com.amgiapp.media.client")

extension MediaClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend

        return Self(
            localURL: { filename in
                guard let folder = backend.currentMediaFolderPath else { return nil }
                let url = URL(fileURLWithPath: folder).appendingPathComponent(filename)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            },
            folderURL: {
                backend.currentMediaFolderPath.map { URL(fileURLWithPath: $0) }
            },
            save: { data, filename in
                try await backendOffload {
                    guard let folder = backend.currentMediaFolderPath else { throw MediaClientError.noMediaFolder }
                    let url = URL(fileURLWithPath: folder).appendingPathComponent(filename)
                    try data.write(to: url)
                }
            },
            delete: { filename in
                try await backendOffload {
                    guard let folder = backend.currentMediaFolderPath else { return }
                    let url = URL(fileURLWithPath: folder).appendingPathComponent(filename)
                    try FileManager.default.removeItem(at: url)
                }
            },
            checkMedia: {
                try await backend.invoke(.checkMedia)
            },
            trashMediaFiles: { filenames in
                try await backend.invoke(.trashMediaFiles(filenames: filenames))
                logger.info("Moved \(filenames.count) media files to trash")
            },
            emptyTrash: {
                try await backend.invoke(.emptyMediaTrash)
                logger.info("Media trash emptied")
            },
            restoreTrash: {
                try await backend.invoke(.restoreMediaTrash)
                logger.info("Media trash restored")
            }
        )
    }()
}
