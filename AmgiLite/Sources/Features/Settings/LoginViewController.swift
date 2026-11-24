import UIKit

/// The AnkiWeb sign-in form, presented modally by the Settings tab and by
/// onboarding. The owner supplies `onAttempt` (typically a view model call)
/// and must invoke the completion exactly once: `nil` dismisses the form,
/// a message is shown inline as an alert.
@MainActor
final class LoginViewController: UIViewController {
    var onAttempt: ((_ username: String, _ password: String, _ completion: @escaping (String?) -> Void) -> Void)?

    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let signInButton = AmgiButton(style: .primary, title: "Sign In")
    private var bottomConstraint: NSLayoutConstraint?

    init() {
        super.init(nibName: nil, bundle: nil)
        title = "Sign in to AnkiWeb"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )

        setUpForm()
        observeKeyboard()
    }

    // MARK: - Form

    private func setUpForm() {
        let hint = UILabel()
        hint.font = AmgiTypography.callout
        hint.adjustsFontForContentSizeCategory = true
        hint.textColor = AmgiColor.textSecondary
        hint.numberOfLines = 0
        hint.text = "Your AnkiWeb credentials are stored in this device's Keychain."

        usernameField.translatesAutoresizingMaskIntoConstraints = false
        usernameField.placeholder = "Email or username"
        usernameField.autocapitalizationType = .none
        usernameField.autocorrectionType = .no
        usernameField.keyboardType = .emailAddress
        usernameField.borderStyle = .roundedRect
        usernameField.font = AmgiTypography.body
        usernameField.returnKeyType = .next
        usernameField.delegate = self
        usernameField.accessibilityLabel = "AnkiWeb username"

        passwordField.translatesAutoresizingMaskIntoConstraints = false
        passwordField.placeholder = "Password"
        passwordField.isSecureTextEntry = true
        passwordField.borderStyle = .roundedRect
        passwordField.font = AmgiTypography.body
        passwordField.returnKeyType = .done
        passwordField.delegate = self
        passwordField.accessibilityLabel = "AnkiWeb password"

        signInButton.translatesAutoresizingMaskIntoConstraints = false
        signInButton.accessibilityLabel = "Sign in to AnkiWeb"
        signInButton.addTarget(self, action: #selector(submit), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [hint, usernameField, passwordField, signInButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AmgiSpacing.md
        view.addSubview(stack)

        let bottom = stack.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -AmgiSpacing.lg
        )
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AmgiSpacing.lg),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.lg),
            bottom,
        ])
        bottomConstraint = bottom
    }

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillChangeFrame),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil
        )
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func submit() {
        guard let onAttempt else { return }
        let username = usernameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = passwordField.text ?? ""
        guard !username.isEmpty, !password.isEmpty else {
            Alerts.present("Enter your AnkiWeb username and password.", title: "Missing details", on: self)
            return
        }

        setFormEnabled(false)
        onAttempt(username, password) { [weak self] failureMessage in
            guard let self else { return }
            if let failureMessage {
                self.setFormEnabled(true)
                Alerts.present(failureMessage, title: "Sign-in failed", on: self)
            } else {
                self.dismiss(animated: true)
            }
        }
    }

    private func setFormEnabled(_ enabled: Bool) {
        usernameField.isEnabled = enabled
        passwordField.isEnabled = enabled
        signInButton.isEnabled = enabled
        signInButton.setTitle(enabled ? "Sign In" : "Signing in…", for: .normal)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        let overlap = max(0, view.bounds.height - frameEnd.minY)
        bottomConstraint?.constant = -AmgiSpacing.lg - overlap
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
}

// MARK: - Text field delegate

extension LoginViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === usernameField {
            passwordField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
            submit()
        }
        return true
    }
}
