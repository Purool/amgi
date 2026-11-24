import UIKit

@MainActor
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var container: AppContainer?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let container = AppContainer()
        self.container = container

        // Onboarding finishes by asking for a root reinstall, so the container
        // must outlive the first root it built.
        container.onRootFinished = { [weak self] in
            self?.installRoot()
        }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        installRoot()
    }

    private func installRoot() {
        guard let container, let window else { return }
        window.rootViewController = container.makeRootViewController()
        window.makeKeyAndVisible()
    }
}
