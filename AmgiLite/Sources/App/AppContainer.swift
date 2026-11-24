import AnkiBackend
import AnkiKit
import UIKit

/// Composition root. The only place that constructs `AnkiBackend`; everything
/// else receives `LiteServices`.
@MainActor
final class AppContainer {
    private(set) var backend: AnkiBackend?
    private(set) var services: LiteServices?
    private(set) var session: CollectionSession?

    /// Set by `SceneDelegate` so an onboarding completion can reinstall the
    /// tab bar without the container knowing about the window.
    var onRootFinished: (() -> Void)?

    func makeRootViewController() -> UIViewController {
        guard backend == nil else {
            return rootViewController()
        }

        let backend: AnkiBackend
        do {
            backend = try AnkiBackend(preferredLangs: ["en"])
        } catch {
            return StartupErrorViewController(
                title: "Engine failed to start",
                message: String(describing: error)
            )
        }

        let services = LiteServices.live(backend: backend)
        let session = CollectionSession(collection: services.collection)

        self.backend = backend
        self.services = services
        self.session = session

        return rootViewController()
    }

    // MARK: - Roots

    private func rootViewController() -> UIViewController {
        guard let services, let session else {
            preconditionFailure("makeRootViewController must run before any root is built")
        }

        if OnboardingGate.needsOnboarding {
            return OnboardingViewController(
                viewModel: OnboardingViewModel(services: services, session: session),
                onFinish: { [weak self] in
                    OnboardingGate.markComplete()
                    self?.installMainRoot()
                }
            )
        }
        return mainRootViewController()
    }

    /// The tab bar root, rebuilt whenever onboarding completes.
    private func mainRootViewController() -> UIViewController {
        guard let services, let session else {
            preconditionFailure("makeRootViewController must run before any root is built")
        }

        let router = Router()
        let screens = Composition.makeMainScreens(
            services: services,
            session: session,
            router: router
        )
        return RootTabBarController(screens: screens, router: router)
    }

    private func installMainRoot() {
        onRootFinished?()
    }
}
