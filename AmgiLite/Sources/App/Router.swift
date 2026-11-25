import AnkiKit
import UIKit

enum Route: Equatable {
    case review(deckID: DeckID)
    case browseNote(noteID: NoteID)
    case deckOptions(deckID: DeckID, deckName: String)
    case notetypeList
    case templateEditor(notetypeID: NotetypeID, initialTemplate: Int, previewNoteID: NoteID?)
}

/// Phase 0 navigation seam. Feature shards provide the screen factories in
/// `Composition.swift`; they never reach into the tab bar directly.
///
/// Note editing is deliberately not a route: it is presented modally, matching
/// how `LoginViewController` is shown.
@MainActor
final class Router {
    private var navigations: [ObjectIdentifier: UINavigationController] = [:]

    /// Factory seams, wired once by `Composition.makeMainScreens` before any
    /// screen is presented; tripping a default means the wiring was skipped.
    var makeReview: (DeckID) -> UIViewController = { _ in
        preconditionFailure("Router.makeReview must be wired in Composition.makeMainScreens")
    }

    var makeBrowseNote: (NoteID) -> UIViewController = { _ in
        preconditionFailure("Router.makeBrowseNote must be wired in Composition.makeMainScreens")
    }

    var makeDeckOptions: (DeckID, String) -> UIViewController = { _, _ in
        preconditionFailure("Router.makeDeckOptions must be wired in Composition.makeMainScreens")
    }

    var makeNotetypeList: () -> UIViewController = {
        preconditionFailure("Router.makeNotetypeList must be wired in Composition.makeMainScreens")
    }

    var makeTemplateEditor: (NotetypeID, Int, NoteID?) -> UIViewController = { _, _, _ in
        preconditionFailure("Router.makeTemplateEditor must be wired in Composition.makeMainScreens")
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
        case .deckOptions(let deckID, let deckName):
            return makeDeckOptions(deckID, deckName)
        case .notetypeList:
            return makeNotetypeList()
        case .templateEditor(let notetypeID, let initialTemplate, let previewNoteID):
            return makeTemplateEditor(notetypeID, initialTemplate, previewNoteID)
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
