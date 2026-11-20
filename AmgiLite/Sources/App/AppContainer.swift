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

    func makeRootViewController() -> UIViewController {
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
        let router = Router()

        self.backend = backend
        self.services = services
        self.session = session

        let screens = Composition.makeScreens(
            services: services,
            session: session,
            router: router
        )
        return RootTabBarController(screens: screens, router: router)
    }
}
