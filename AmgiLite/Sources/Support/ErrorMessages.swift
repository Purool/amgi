import AnkiKit
import Foundation

/// Error → user-facing text. View models call `text(for:)` so no UIKit type
/// leaks into them; `Alerts` (Support) turns the result into an alert.
enum ErrorMessages {
    static func text(for error: Error) -> String {
        switch error {
        case let liteError as LiteError:
            switch liteError {
            case .collectionNotOpen:
                return "The collection is not open."
            case .unsupportedPackage:
                return "That file is not an Anki package (.apkg / .colpkg)."
            case .notImplemented:
                return "Not available in this build."
            case .notLoggedIn:
                return "Sign in to AnkiWeb first."
            case .engine(let message):
                return message.isEmpty ? "The engine reported an error." : message
            }
        case let syncError as SyncError:
            return syncError.message.isEmpty ? "Sync failed." : syncError.message
        case let localized as LocalizedError where localized.errorDescription != nil:
            return localized.errorDescription ?? "\(error)"
        default:
            return "\(error)"
        }
    }
}
