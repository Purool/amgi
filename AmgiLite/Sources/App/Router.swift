import AnkiKit
import UIKit

enum Route: Equatable {
    case review(deckID: DeckID)
    case browseNote(noteID: NoteID)
}

/// Phase 0 navigation seam. Feature shards provide the screen factories in
/// `Composition.swift`; they never reach into the tab bar directly.
@MainActor
final class Router {
    private var navigations: [ObjectIdentifier: UINavigationController] = [:]

    /// Factory seams, wired once by `Composition.makeScreens` before any
    /// screen is presented; tripping a default means the wiring was skipped.
    var makeReview: (DeckID) -> UIViewController = { _ in
        preconditionFailure("Router.makeReview must be wired in Composition.makeScreens")
    }

    var makeBrowseNote: (NoteID) -> UIViewController = { _ in
        preconditionFailure("Router.makeBrowseNote must be wired in Composition.makeScreens")
    }

    func register(_ navigation: UINavigationController) {
        guard let root = navigation.viewControllers.first else { return }
        navigations[ObjectIdentifier(root)] = navigation
    }

    func push(_ route: Route, from source: UIViewController) {
        guard let navigation = navigationContaining(source) else { return }
        navigation.pushViewController(viewController(for: route), animated: true)
    }

    private func viewController(for route: Route) -> UIViewController {
        switch route {
        case .review(let deckID):
            return makeReview(deckID)
        case .browseNote(let noteID):
            return makeBrowseNote(noteID)
        }
    }

    private func navigationContaining(_ viewController: UIViewController) -> UINavigationController? {
        var current: UIViewController? = viewController
        while let candidate = current {
            if let navigation = candidate as? UINavigationController {
                return navigation
            }
            current = candidate.parent
        }
        return nil
    }
}
