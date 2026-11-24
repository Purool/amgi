import UIKit
import UniformTypeIdentifiers

/// First-launch screen, shown instead of the tab bar until the user has a
/// collection: create one, import an `.apkg`, or sign in to AnkiWeb. All
/// three complete onboarding; "Skip" defers everything to Settings.
///
/// The screen deliberately lives outside the tab bar: `AppContainer` decides
/// gate-or-tabs at launch and swaps the root when `onFinish` fires.
@MainActor
final class OnboardingViewController: UIViewController {
    private let viewModel: OnboardingViewModel
    private let onFinish: () -> Void

    private var progressView: BlockingProgressView?
    private var isBusy = false

    init(viewModel: OnboardingViewModel, onFinish: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
        title = "Welcome"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background
        setUpContent()
    }

    // MARK: - Content

    private func setUpContent() {
        let icon = UIImageView(image: UIImage(systemName: "rectangle.stack"))
        icon.tintColor = AmgiColor.accent
        icon.contentMode = .scaleAspectFit
        icon.isAccessibilityElement = false

        let headline = UILabel()
        headline.font = AmgiTypography.largeTitle
        headline.adjustsFontForContentSizeCategory = true
        headline.textColor = AmgiColor.textPrimary
        headline.textAlignment = .center
        headline.numberOfLines = 0
        headline.text = "AmgiLite"
        headline.accessibilityTraits = .header

        let subtitle = UILabel()
        subtitle.font = AmgiTypography.body
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = AmgiColor.textSecondary
        subtitle.textAlignment = .center
        subtitle.numberOfLines = 0
        subtitle.text = "Offline-first flashcards, compatible with Anki."

        let createButton = AmgiButton(style: .primary, title: "Create a collection")
        createButton.accessibilityLabel = "Create a new collection"
        createButton.addTarget(self, action: #selector(createCollection), for: .touchUpInside)

        let importButton = AmgiButton(style: .secondary, title: "Import an .apkg file")
        importButton.accessibilityLabel = "Import an Anki package file"
        importButton.addTarget(self, action: #selector(pickPackage), for: .touchUpInside)

        let signInButton = AmgiButton(style: .secondary, title: "Sign in to AnkiWeb")
        signInButton.accessibilityLabel = "Sign in to AnkiWeb"
        signInButton.addTarget(self, action: #selector(presentLogin), for: .touchUpInside)

        let skipButton = UIButton(type: .system)
        skipButton.setTitle("Skip for now", for: .normal)
        skipButton.setTitleColor(AmgiColor.textSecondary, for: .normal)
        skipButton.titleLabel?.font = AmgiTypography.callout
        skipButton.titleLabel?.adjustsFontForContentSizeCategory = true
        skipButton.accessibilityLabel = "Skip setup for now"
        skipButton.addTarget(self, action: #selector(skip), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            icon, headline, subtitle, createButton, importButton, signInButton, skipButton,
        ])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AmgiSpacing.md
        stack.setCustomSpacing(AmgiSpacing.xl, after: icon)
        stack.setCustomSpacing(AmgiSpacing.lg, after: subtitle)
        view.addSubview(stack)

        // The three action buttons span the screen; the stack itself keeps a
        // centered, content-driven width so the labels stay readable.
        for button in [createButton, importButton, signInButton] {
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor, constant: AmgiSpacing.xl
                ),
                button.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor, constant: -AmgiSpacing.xl
                ),
            ])
        }

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),

            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: AmgiSpacing.xl
            ),
            stack.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -AmgiSpacing.xl
            ),
        ])
    }

    // MARK: - Actions

    @objc private func createCollection() {
        guard beginWork(
            title: "Creating collection",
            status: "Setting up your collection…",
            cancellable: false
        ) else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.viewModel.createCollection()
                self.complete()
            } catch {
                self.fail(error)
            }
        }
    }

    @objc private func pickPackage() {
        var types: [UTType] = []
        for fileExtension in ["apkg", "colpkg"] {
            if let type = UTType(filenameExtension: fileExtension) {
                types.append(type)
            }
        }
        if types.isEmpty {
            types = [.data]
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    @objc private func presentLogin() {
        let login = LoginViewController()
        login.onAttempt = { [weak self] username, password, completion in
            guard let self else {
                completion("The setup screen is gone.")
                return
            }
            self.viewModel.logIn(username: username, password: password) { failureMessage in
                completion(failureMessage)
                if failureMessage == nil {
                    self.complete()
                }
            }
        }
        present(UINavigationController(rootViewController: login), animated: true)
    }

    @objc private func skip() {
        complete()
    }

    // MARK: - Flow helpers

    private func complete() {
        onFinish()
    }

    private func fail(_ error: Error) {
        dismissProgress()
        isBusy = false
        Alerts.present(error: error, title: "Setup failed", on: self)
    }

    /// Installs the blocking card and marks the screen busy. Returns false
    /// (and does nothing) when a flow is already running.
    private func beginWork(title: String, status: String, cancellable: Bool) -> Bool {
        guard !isBusy, progressView == nil else { return false }
        isBusy = true

        let overlay = BlockingProgressView.install(in: view, title: title)
        overlay.setStatus(status)
        if cancellable {
            // Cancel means "stop waiting": the engine call cannot be
            // interrupted safely, so the card stays up and the flow reports
            // its outcome when the call returns.
            overlay.onCancel = { [weak self, weak overlay] in
                guard let self, let overlay, overlay === self.progressView else { return }
                overlay.stopAnimating()
                overlay.setStatus("Stopped waiting — the import keeps running in the background.")
                overlay.setCancelTitle(nil)
            }
        }
        overlay.setCancelTitle(cancellable ? "Cancel" : nil)
        progressView = overlay
        return true
    }

    private func dismissProgress() {
        progressView?.removeFromSuperview()
        progressView = nil
    }
}

// MARK: - Document picker

extension OnboardingViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        guard beginWork(
            title: "Importing package",
            status: "Reading the package… large decks can take a while.",
            cancellable: true
        ) else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.viewModel.importPackage(at: url)
                self.complete()
            } catch {
                self.fail(error)
            }
        }
    }
}
