import AnkiKit
import UIKit

/// Modal note editor: one HTML text view per field, a tag field, save/delete,
/// and a preview that uses the unsaved values. Presented by the note detail
/// and by Browse's context menu — editing is a modal task, so it has no route.
@MainActor
final class NoteEditorViewController: UIViewController {
    private let viewModel: NoteEditorViewModel
    private let services: LiteServices

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let loadingView = LoadingStateView(message: "Loading note…")
    private var errorView: ErrorStateView?
    private var progressView: BlockingProgressView?
    private var saveItem: UIBarButtonItem?
    private var keyboardAvoider: KeyboardAvoider?

    private let hintLabel = UILabel()
    private let validationLabel = UILabel()
    private let tagsField = UITextField()
    private let previewButton = AmgiButton(style: .secondary, title: "Preview")
    private let deleteButton = AmgiButton(style: .destructive, title: "Delete Note")

    var onSaved: (() -> Void)?
    /// Called after a successful delete; the presenter decides where to go.
    var onDeleted: (() -> Void)?

    init(services: LiteServices, session: CollectionSession, noteID: NoteID) {
        self.services = services
        self.viewModel = NoteEditorViewModel(
            services: services,
            session: session,
            noteID: noteID
        )
        super.init(nibName: nil, bundle: nil)
        title = "Edit Note"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        setUpLayout()
        setUpNavigationItems()
        setUpStateViews()
        keyboardAvoider = KeyboardAvoider(rootView: view, scrollView: scrollView)

        viewModel.onStateChange = { [weak self] state in
            self?.apply(state)
        }
        viewModel.load()
    }

    // MARK: - Layout

    private func setUpLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        view.addSubview(scrollView)

        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AmgiSpacing.md
        scrollView.addSubview(stack)

        hintLabel.font = AmgiTypography.caption
        hintLabel.textColor = AmgiColor.textSecondary
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.numberOfLines = 0
        hintLabel.text = """
        Fields are saved as HTML source and rendered with Anki's rules. Use the \
        bar above the keyboard for common tags.
        """

        validationLabel.font = AmgiTypography.caption
        validationLabel.textColor = AmgiColor.danger
        validationLabel.adjustsFontForContentSizeCategory = true
        validationLabel.numberOfLines = 0
        validationLabel.isHidden = true

        previewButton.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            stack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: AmgiSpacing.md
            ),
            stack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: -AmgiSpacing.lg
            ),
            stack.leadingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: AmgiSpacing.md
            ),
            stack.trailingAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -AmgiSpacing.md
            ),
            stack.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor,
                constant: -2 * AmgiSpacing.md
            ),
        ])
    }

    private func setUpNavigationItems() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
        let save = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
        save.isEnabled = false
        navigationItem.rightBarButtonItem = save
        saveItem = save
    }

    private func setUpStateViews() {
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(loadingView)
        NSLayoutConstraint.activate([
            loadingView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            loadingView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            loadingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: - State

    private func apply(_ state: NoteEditorViewModel.State) {
        switch state {
        case .loading:
            loadingView.isHidden = false
            scrollView.isHidden = true
            errorView?.removeFromSuperview()
            errorView = nil
        case .content:
            loadingView.isHidden = true
            scrollView.isHidden = false
            errorView?.removeFromSuperview()
            errorView = nil
            renderDraft()
        case .error(let message):
            loadingView.isHidden = true
            scrollView.isHidden = true
            showError(message)
        }
    }

    private func showError(_ message: String) {
        errorView?.removeFromSuperview()
        let replacement = ErrorStateView(message: message, retry: { [weak self] in
            self?.viewModel.load()
        })
        replacement.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(replacement)
        NSLayoutConstraint.activate([
            replacement.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            replacement.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            replacement.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            replacement.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        errorView = replacement
    }

    private func renderDraft() {
        guard let draft = viewModel.draft else { return }
        stack.arrangedSubviews.forEach {
            stack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        stack.addArrangedSubview(hintLabel)

        for (index, name) in draft.fieldNames.enumerated() {
            let field = NoteFieldView(
                index: index,
                name: name,
                text: draft.fields[safe: index] ?? ""
            )
            field.onTextChange = { [weak self] text in
                self?.viewModel.updateField(at: index, text: text)
                self?.refreshStatus()
            }
            stack.addArrangedSubview(field)
        }

        let tagsLabel = UILabel()
        tagsLabel.text = "Tags"
        tagsLabel.font = AmgiTypography.caption
        tagsLabel.textColor = AmgiColor.textSecondary
        tagsLabel.adjustsFontForContentSizeCategory = true

        let tagsHint = UILabel()
        tagsHint.text = "Separate tags with spaces."
        tagsHint.font = AmgiTypography.caption
        tagsHint.textColor = AmgiColor.textTertiary
        tagsHint.adjustsFontForContentSizeCategory = true

        tagsField.text = draft.tags
        tagsField.placeholder = "tag1 tag2"
        tagsField.font = AmgiTypography.body
        tagsField.textColor = AmgiColor.textPrimary
        tagsField.borderStyle = .roundedRect
        tagsField.autocapitalizationType = .none
        tagsField.autocorrectionType = .no
        tagsField.returnKeyType = .done
        tagsField.clearButtonMode = .whileEditing
        tagsField.delegate = self
        tagsField.addTarget(self, action: #selector(tagsChanged), for: .editingChanged)
        tagsField.accessibilityLabel = "Tags"

        stack.addArrangedSubview(tagsLabel)
        stack.addArrangedSubview(tagsField)
        stack.addArrangedSubview(tagsHint)
        stack.addArrangedSubview(validationLabel)
        stack.addArrangedSubview(previewButton)
        stack.addArrangedSubview(deleteButton)

        refreshStatus()
    }

    private func refreshStatus() {
        let message = viewModel.validationMessage
        validationLabel.text = message
        validationLabel.isHidden = message == nil
        saveItem?.isEnabled = viewModel.canSave
        // The editor is a page sheet: without this, a swipe-down at the top of
        // the scroll view would dismiss it and silently drop the edits.
        navigationController?.isModalInPresentation = viewModel.draft?.isDirty == true
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        guard viewModel.draft?.isDirty == true else {
            dismiss(animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Discard changes?",
            message: "Your edits to this note will be lost.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func saveTapped() {
        guard viewModel.canSave else { return }
        view.endEditing(true)
        guard progressView == nil else { return }
        let overlay = BlockingProgressView.install(in: view, title: "Saving note")
        overlay.setCancelTitle(nil)
        progressView = overlay

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.viewModel.save()
                self.dismissProgress()
                let onSaved = self.onSaved
                self.dismiss(animated: true) {
                    onSaved?()
                }
            } catch {
                self.dismissProgress()
                Alerts.present(error: error, title: "Couldn't save note", on: self)
            }
        }
    }

    @objc private func deleteTapped() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let count = try await self.viewModel.cardCount()
                self.confirmDelete(cardCount: count)
            } catch {
                Alerts.present(error: error, title: "Couldn't check cards", on: self)
            }
        }
    }

    private func confirmDelete(cardCount: Int) {
        let message = cardCount == 1
            ? "This deletes the note and its 1 card. It can't be undone."
            : "This deletes the note and its \(cardCount) cards. It can't be undone."
        let alert = UIAlertController(
            title: "Delete note?",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.performDelete()
        })
        present(alert, animated: true)
    }

    private func performDelete() {
        guard progressView == nil else { return }
        let overlay = BlockingProgressView.install(in: view, title: "Deleting note")
        overlay.setCancelTitle(nil)
        progressView = overlay

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.viewModel.delete()
                self.dismissProgress()
                let onDeleted = self.onDeleted
                self.dismiss(animated: true) {
                    onDeleted?()
                }
            } catch {
                self.dismissProgress()
                Alerts.present(error: error, title: "Couldn't delete note", on: self)
            }
        }
    }

    @objc private func tagsChanged() {
        viewModel.updateTags(tagsField.text ?? "")
        refreshStatus()
    }

    @objc private func previewTapped() {
        view.endEditing(true)
        previewButton.isEnabled = false
        Task { [weak self] in
            guard let self else { return }
            defer { self.previewButton.isEnabled = true }
            do {
                let rendered = try await self.viewModel.makePreview()
                let preview = CardPreviewViewController(
                    rendered: rendered,
                    templateName: "Preview",
                    note: "Showing the unsaved field values.",
                    services: self.services
                )
                self.present(UINavigationController(rootViewController: preview), animated: true)
            } catch {
                Alerts.present(error: error, title: "Couldn't render preview", on: self)
            }
        }
    }

    private func dismissProgress() {
        progressView?.removeFromSuperview()
        progressView = nil
    }
}

// MARK: - Text field

extension NoteEditorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
