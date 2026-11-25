import UIKit

/// Insets a scroll view so the keyboard cannot cover the focused row.
/// `UIKeyboardLayoutGuide` is iOS 15; this is the notification-based path the
/// rest of the app uses (`LoginViewController` predates this helper).
@MainActor
final class KeyboardAvoider: NSObject {
    private weak var scrollView: UIScrollView?
    private weak var rootView: UIView?

    init(rootView: UIView, scrollView: UIScrollView) {
        self.rootView = rootView
        self.scrollView = scrollView
        super.init()

        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let rootView,
            let scrollView,
            let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }

        let frameInRoot = rootView.convert(frameEnd, from: nil)
        let overlap = max(0, rootView.bounds.maxY - frameInRoot.minY)
        // Safe-area bottom is already part of the scroll view's adjusted
        // insets; only add the part the keyboard sticks out beyond it.
        let safeBottom = rootView.safeAreaInsets.bottom
        let inset = max(0, overlap - safeBottom)

        scrollView.contentInset.bottom = inset
        scrollView.verticalScrollIndicatorInsets.bottom = inset
    }
}
