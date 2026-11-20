import Foundation

/// Tracks whether the collection is open. `AnkiBackend.currentMediaFolderPath`
/// stays set after `closeCollection()`, so it cannot answer this question; the
/// services need their own latch to fail with `LiteError.collectionNotOpen`
/// instead of surfacing a raw backend error after close.
final class CollectionState: @unchecked Sendable {
    private let lock = NSLock()
    private var storedMediaFolder: String?

    var isOpen: Bool {
        withLock { storedMediaFolder != nil }
    }

    var mediaFolderPath: String? {
        withLock { storedMediaFolder }
    }

    func markOpen(mediaFolder: String) {
        withLock { storedMediaFolder = mediaFolder }
    }

    func markClosed() {
        withLock { storedMediaFolder = nil }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
