import UIKit

/// Screens the tab bar hosts, in tab order. Phase 2 swaps the placeholders for
/// the real feature view controllers; nothing else in the shell changes.
struct ScreenFactories {
    let makeDecks: () -> UIViewController
    let makeBrowse: () -> UIViewController
    let makeSettings: () -> UIViewController
}

/// The single wiring point. Integration tasks edit this file only.
@MainActor
enum Composition {
    static func makeScreens(
        services: LiteServices,
        session: CollectionSession,
        router: Router
    ) -> ScreenFactories {
        // Phase 2 replaces the first two closures with DecksViewController and
        // BrowseViewController; Phase 3 replaces the settings placeholder.
        ScreenFactories(
            makeDecks: {
                PlaceholderViewController(
                    title: "Decks",
                    detail: "Deck list lands in Phase 2 (S6)."
                )
            },
            makeBrowse: {
                PlaceholderViewController(
                    title: "Browse",
                    detail: "Browser lands in Phase 2 (S8)."
                )
            },
            makeSettings: {
                EngineStatusViewController(services: services, session: session)
            }
        )
    }
}
