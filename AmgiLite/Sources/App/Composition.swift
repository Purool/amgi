import AnkiKit
import UIKit

/// Screens the tab bar hosts, in tab order. Phase 3 replaces the settings
/// screen. Nothing else in the shell changes.
struct ScreenFactories {
    let makeDecks: () -> UIViewController
    let makeBrowse: () -> UIViewController
    let makeSettings: () -> UIViewController
}

/// The single wiring point. Integration tasks edit this file only.
///
/// Phase 2 (S6/S7/S8) + 2.5 (S9) status: the Decks and Browse tabs drive the
/// real feature screens, and `Router.makeReview` / `Router.makeBrowseNote`
/// resolve to the review flow and the read-only note detail. The placeholder
/// page is gone — `PlaceholderViewController` was deleted with the Phase 1.5
/// temporary screens, and every route now ends at a feature screen. Settings
/// is still the Phase 1 engine status screen until Phase 3 (S11).
@MainActor
enum Composition {
    static func makeScreens(
        services: LiteServices,
        session: CollectionSession,
        router: Router
    ) -> ScreenFactories {
        router.makeReview = { deckID in
            ReviewViewController(services: services, session: session, deckID: deckID)
        }
        router.makeBrowseNote = { noteID in
            NoteDetailViewController(services: services, noteID: noteID)
        }

        return ScreenFactories(
            makeDecks: {
                DecksViewController(
                    viewModel: DecksViewModel(services: services, session: session),
                    router: router
                )
            },
            makeBrowse: {
                BrowseViewController(
                    viewModel: BrowseViewModel(services: services, session: session),
                    router: router
                )
            },
            makeSettings: {
                EngineStatusViewController(services: services, session: session)
            }
        )
    }
}
