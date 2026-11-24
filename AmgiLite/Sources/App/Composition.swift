import AnkiKit
import UIKit

/// Screens the tab bar hosts, in tab order.
struct ScreenFactories {
    let makeDecks: () -> UIViewController
    let makeBrowse: () -> UIViewController
    let makeSettings: () -> UIViewController
}

/// The single wiring point. Integration tasks edit this file only.
///
/// Phase 3 (S10/S11) status: Settings is now the real screen — AnkiWeb
/// account, sync with progress and the full-sync conflict prompt, `.apkg`
/// import, and about info. Onboarding is not a tab: `AppContainer` shows it
/// instead of the tab bar on first launch and swaps in `makeMainScreens()`
/// when it completes.
@MainActor
enum Composition {
    /// The tab bar screens. Called once per root install.
    static func makeMainScreens(
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
                SettingsViewController(
                    viewModel: SettingsViewModel(services: services, session: session)
                )
            }
        )
    }
}
