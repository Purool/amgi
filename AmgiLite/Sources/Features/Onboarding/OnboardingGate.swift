import Foundation

/// Decides whether a launch needs the onboarding screen. Two signals, in
/// order: the persisted flag wins once set; a collection that already exists
/// on disk also counts as done, so a reinstall or cleared defaults never
/// gates a user with data behind the intro screen again.
enum OnboardingGate {
    private static let key = "amgiLite.hasCompletedOnboarding"

    static var needsOnboarding: Bool {
        if UserDefaults.standard.bool(forKey: key) {
            return false
        }
        guard let paths = try? CollectionPaths.standard() else {
            return true
        }
        if FileManager.default.fileExists(atPath: paths.collectionPath) {
            markComplete()
            return false
        }
        return true
    }

    static func markComplete() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
