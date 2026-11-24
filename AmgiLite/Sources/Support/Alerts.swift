import UIKit

/// Shared alert presentation. Errors are mapped once in `ErrorMessages`;
/// screens never hand-build an error alert per call site.
@MainActor
enum Alerts {
    /// Presents a generic failure alert with an OK action.
    static func present(
        _ message: String,
        title: String,
        on viewController: UIViewController
    ) {
        present(
            title: title,
            message: message,
            on: viewController,
            actions: [UIAlertAction(title: "OK", style: .default)]
        )
    }

    /// Convenience wrapper around `text(for:)` for call sites that hold the
    /// raw thrown error instead of a mapped message.
    static func present(
        error: Error,
        title: String,
        on viewController: UIViewController
    ) {
        present(ErrorMessages.text(for: error), title: title, on: viewController)
    }

    static func present(
        title: String,
        message: String,
        on viewController: UIViewController,
        actions: [UIAlertAction]
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        for action in actions {
            alert.addAction(action)
        }
        // Only a plain action is a sensible default; a leading destructive or
        // cancel-style action must not become the preferred one by accident.
        if let first = actions.first, first.style == .default {
            alert.preferredAction = first
        }
        viewController.present(alert, animated: true)
    }

    /// Presents a titled informational alert (flow outcomes, not errors).
    static func presentMessage(
        title: String,
        message: String,
        on viewController: UIViewController
    ) {
        present(
            message,
            title: title,
            on: viewController
        )
    }

    /// Presents a decision alert whose actions come from the call site
    /// (conflict prompts and similar). Distinct from the single-message
    /// helpers so call sites cannot omit `actions` by accident.
    static func presentDecision(
        title: String,
        message: String,
        on viewController: UIViewController,
        actions: [UIAlertAction]
    ) {
        present(title: title, message: message, on: viewController, actions: actions)
    }
}
