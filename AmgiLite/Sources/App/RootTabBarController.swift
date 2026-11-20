import UIKit

@MainActor
final class RootTabBarController: UITabBarController {
    init(screens: ScreenFactories, router: Router) {
        super.init(nibName: nil, bundle: nil)

        let decks = screens.makeDecks()
        let browse = screens.makeBrowse()
        let settings = screens.makeSettings()

        viewControllers = [
            wrap(decks, title: "Decks", systemImage: "rectangle.stack", router: router),
            wrap(browse, title: "Browse", systemImage: "list.bullet", router: router),
            wrap(settings, title: "Settings", systemImage: "gearshape", router: router),
        ]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func wrap(
        _ root: UIViewController,
        title: String,
        systemImage: String,
        router: Router
    ) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = true
        navigation.tabBarItem = UITabBarItem(
            title: title,
            image: UIImage(systemName: systemImage),
            selectedImage: nil
        )
        router.register(navigation)
        return navigation
    }
}
