import AnkiBackend
import AnkiKit
import UIKit

/// Composition root. Owns the engine and the screen factories the Phase 1/2
/// shards replace; nothing else in the app constructs `AnkiBackend`.
@MainActor
final class AppContainer {
    var screens = ScreenFactories()

    private(set) var backend: AnkiBackend?
    private(set) var router: Router?

    /// Constructing the backend is the Phase 0 engine smoke test: it loads the
    /// Rust dylib through `AnkiRustLib` and fails loudly if the iOS 14 slice is
    /// missing or mislinked.
    func makeRootViewController() -> UIViewController {
        do {
            backend = try AnkiBackend(preferredLangs: ["en"])
        } catch {
            return StartupErrorViewController(
                title: "Engine failed to start",
                message: String(describing: error)
            )
        }

        let router = Router()
        self.router = router
        return RootTabBarController(screens: screens, router: router)
    }
}

/// Swapped by the Phase 1/2 integration shard (`Composition.swift`).
struct ScreenFactories {
    var makeDecks: () -> UIViewController = {
        PlaceholderViewController(title: "Decks", detail: "Deck list lands in Phase 2 (S6).")
    }

    var makeBrowse: () -> UIViewController = {
        PlaceholderViewController(title: "Browse", detail: "Browser lands in Phase 2 (S8).")
    }

    var makeSettings: () -> UIViewController = {
        PlaceholderViewController(title: "Settings", detail: "Settings land in Phase 3 (S11).")
    }
}
