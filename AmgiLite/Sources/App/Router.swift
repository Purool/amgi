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

    var makeReview: (DeckID) -> UIViewController = { _ in
        PlaceholderViewController(title: "Review", detail: "Review flow lands in Phase 2 (S7).")
    }

    var makeBrowseNote: (NoteID) -> UIViewController = { _ in
        PlaceholderViewController(title: "Note", detail: "Note detail lands in Phase 2 (S8).")
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
