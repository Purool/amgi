import AnkiKit
import Foundation

/// Onboarding view model: the three setup flows (create / import / sign in)
/// in service-call form, without any UIKit. The view controller wraps each
/// one in its progress card and completion handling.
@MainActor
final class OnboardingViewModel {
    private let services: LiteServices
    private let session: CollectionSession

    init(services: LiteServices, session: CollectionSession) {
        self.services = services
        self.session = session
    }

    /// Opening the standard collection path creates a fresh collection when
    /// the file does not exist yet.
    func createCollection() async throws {
        try await session.ensureOpen()
    }

    func importPackage(at url: URL) async throws {
        // The import needs an open collection; creating it is part of the
        // flow, not a separate user step.
        try await session.ensureOpen()
        try await services.importExport.importPackage(at: url)
    }

    /// `completion` receives `nil` on success or the mapped failure message,
    /// and is always called exactly once on the main actor.
    func logIn(
        username: String,
        password: String,
        completion: @escaping (String?) -> Void
    ) {
        Task { [services] in
            do {
                try await services.sync.logIn(username: username, password: password)
                completion(nil)
            } catch {
                completion(ErrorMessages.text(for: error))
            }
        }
    }
}
