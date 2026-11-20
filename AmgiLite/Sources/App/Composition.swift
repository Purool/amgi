import UIKit

/// The single wiring point feature shards append to. Each integration task owns
/// this file; shards never edit it directly, which is what keeps their file
/// ownership disjoint.
@MainActor
enum Composition {
    static func makeContainer() -> AppContainer {
        AppContainer()
    }

    /// Phase 1: replace the placeholder factories with real screens.
    static func installScreens(into container: AppContainer) {
        _ = container
    }
}
