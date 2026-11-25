import AnkiKit
import UIKit

/// Template editor for one notetype: template picker, name, front/back/CSS
/// panels, field insertion bar, validation banner, preview and save.
///
/// Structural edits (fields/templates added, removed or reordered) trigger a
/// full sync on the next collection sync, so saving one asks first (E2).
@MainActor
final class TemplateEditorViewController: UIViewController {
    private enum Panel: Int {
        case front = 0
        case back = 1
        case styles = 2
    }

    private let viewModel: TemplateEditorViewModel
    private let services: LiteServices
    private let session: CollectionSession

    private let contentStack = UIStackView()
    private let selectorContainer = UIStackView()
    private let templateSelector = UISegmentedControl(items: [])
    private let templateMenuButton = UIButton(type: .system)
    private let nameField = UITextField()
    private let panelControl = UISegmentedControl(items: ["Front", "Back", "Styles"])
    private let validationLabel = UILabel()
    private let structuralLabel = UILabel()
    private let editor = TemplateSourceEditor()
    private let previewButton = AmgiButton(style: .secondary, title: "Preview")
    private let loadingView = LoadingStateView(message: "Loading notetype…")
    private var errorView: ErrorStateView?
    private var progressView: BlockingProgressView?
    private var saveItem: UIBarButtonItem?
    private var bottomConstraint: NSLayoutConstraint?
    private var panel: Panel = .front
    private var templateIndex = 0

    init(
        services: LiteServices,
        session: CollectionSession,
        notetypeID: NotetypeID,
        initialTemplate: Int,
        previewNoteID: NoteID?
    ) {
        self.services = services
        self.session = session
        self.viewModel = TemplateEditorViewModel(
            services: services,
            session: session,
            notetypeID: notetypeID,
            initialTemplate: initialTemplate,
            previewNoteID: previewNoteID
        )
        super.init(nibName: nil, bundle: nil)
        title = "Template"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshStatus()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Restore the gesture for whatever is below us.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        setUpLayout()
        setUpNavigationItems()
        setUpStateViews()
        observeKeyboard()

        viewModel.onStateChange = { [weak self] state in
            self?.apply(state)
        }
        viewModel.load()
    }

    // MARK: - Layout

    private func setUpLayout() {
        selectorContainer.axis = .vertical
        selectorContainer.spacing = AmgiSpacing.xs

        templateSelector.selectedSegmentIndex = 0
        templateSelector.addTarget(self, action: #selector(templateSelectorChanged), for: .valueChanged)

        templateMenuButton.contentHorizontalAlignment = .left
        templateMenuButton.titleLabel?.font = AmgiTypography.body
        templateMenuButton.setTitleColor(AmgiColor.accent, for: .normal)
        templateMenuButton.showsMenuAsPrimaryAction = true
        templateMenuButton.isHidden = true

        selectorContainer.addArrangedSubview(templateSelector)

        let nameLabel = UILabel()
        nameLabel.text = "Template name"
        nameLabel.font = AmgiTypography.caption
        nameLabel.textColor = AmgiColor.textSecondary
        nameLabel.adjustsFontForContentSizeCategory = true

        nameField.font = AmgiTypography.body
        nameField.textColor = AmgiColor.textPrimary
        nameField.borderStyle = .roundedRect
        nameField.clearButtonMode = .whileEditing
        nameField.returnKeyType = .done
        nameField.autocapitalizationType = .words
        nameField.delegate = self
        nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
        nameField.accessibilityLabel = "Template name"

        panelControl.selectedSegmentIndex = 0
        panelControl.addTarget(self, action: #selector(panelChanged), for: .valueChanged)

        validationLabel.font = AmgiTypography.caption
        validationLabel.textColor = AmgiColor.danger
        validationLabel.adjustsFontForContentSizeCategory = true
        validationLabel.numberOfLines = 0
        validationLabel.isHidden = true

        structuralLabel.font = AmgiTypography.caption
        structuralLabel.textColor = AmgiColor.warning
        structuralLabel.adjustsFontForContentSizeCategory = true
        structuralLabel.numberOfLines = 0
        structuralLabel.text = """
        Changing the number or order of fields/templates makes the next sync a \
        full sync.
        """
        structuralLabel.isHidden = true

        editor.onTextChange = { [weak self] text in
            self?.editorChanged(text)
        }

        previewButton.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)

        for view in [selectorContainer, nameLabel, nameField, panelControl,
                     structuralLabel, validationLabel, editor, previewButton] {
            contentStack.addArrangedSubview(view)
        }
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = AmgiSpacing.sm
        contentStack.setCustomSpacing(AmgiSpacing.md, after: nameField)
        contentStack.setCustomSpacing(AmgiSpacing.md, after: panelControl)
        view.addSubview(contentStack)

        let bottom = contentStack.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor,
            constant: -AmgiSpacing.md
        )
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AmgiSpacing.md),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.md),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.md),
            bottom,
            editor.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        bottomConstraint = bottom
    }

    private func setUpNavigationItems() {
        let save = UIBarButtonItem(
            barButtonSystemItem: .save,
            target: self,
            action: #selector(saveTapped)
        )
        save.isEnabled = false
        navigationItem.rightBarButtonItem = save
        saveItem = save
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(cancelTapped)
        )
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

    private func observeKeyboard() {
        for name in [
            UIResponder.keyboardWillChangeFrameNotification,
            UIResponder.keyboardWillHideNotification,
        ] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillChangeFrame(_:)),
                name: name,
                object: nil
            )
        }
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard
            let frameEnd = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else { return }
        let frameInView = view.convert(frameEnd, from: nil)
        let overlap = max(0, view.bounds.maxY - frameInView.minY - view.safeAreaInsets.bottom)
        bottomConstraint?.constant = -(AmgiSpacing.md + overlap)
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - State

    private func apply(_ state: TemplateEditorViewModel.State) {
        switch state {
        case .loading:
            contentStack.isHidden = true
            loadingView.isHidden = false
            errorView?.removeFromSuperview()
            errorView = nil
        case .content:
            contentStack.isHidden = false
            loadingView.isHidden = true
            errorView?.removeFromSuperview()
            errorView = nil
            renderLoadedState()
        case .error(let message):
            loadingView.isHidden = true
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

    private func renderLoadedState() {
        guard let draft = viewModel.draft else { return }
        title = draft.notetype.name
        templateIndex = viewModel.clampedTemplateIndex

        rebuildTemplateSelector(names: draft.templates.map(\.name))
        nameField.text = draft.template(at: templateIndex)?.name ?? ""
        editor.setFieldTokens(viewModel.fieldTokens())
        loadPanelText()
        refreshStatus()
    }

    private func rebuildTemplateSelector(names: [String]) {
        selectorContainer.arrangedSubviews.forEach { $0.removeFromSuperview() }

        if names.count <= 4 {
            templateSelector.removeAllSegments()
            for (index, name) in names.enumerated() {
                templateSelector.insertSegment(withTitle: name, at: index, animated: false)
            }
            templateSelector.selectedSegmentIndex = min(templateIndex, max(0, names.count - 1))
            templateSelector.isHidden = names.count <= 1
            templateMenuButton.isHidden = true
            selectorContainer.addArrangedSubview(templateSelector)
        } else {
            templateSelector.isHidden = true
            templateMenuButton.isHidden = false
            configureTemplateMenu(names: names)
            selectorContainer.addArrangedSubview(templateMenuButton)
        }
    }

    private func configureTemplateMenu(names: [String]) {
        templateMenuButton.setTitle(names[safe: templateIndex] ?? "Template", for: .normal)
        let actions = names.enumerated().map { index, name in
            UIAction(
                title: name,
                state: index == templateIndex ? .on : .off
            ) { [weak self] _ in
                guard let self else { return }
                self.templateIndex = index
                self.loadSelectedTemplate()
                self.configureTemplateMenu(names: names)
            }
        }
        templateMenuButton.menu = UIMenu(children: actions)
    }

    // MARK: - Panel + template switching

    private func loadPanelText() {
        guard let template = viewModel.draft?.template(at: templateIndex) else {
            editor.text = ""
            return
        }
        switch panel {
        case .front:
            editor.text = template.config.qFormat
        case .back:
            editor.text = template.config.aFormat
        case .styles:
            editor.text = viewModel.draft?.notetype.config.css ?? ""
        }
    }

    private func commitEditorText() {
        let text = editor.text ?? ""
        switch panel {
        case .front:
            viewModel.setFront(text, at: templateIndex)
        case .back:
            viewModel.setBack(text, at: templateIndex)
        case .styles:
            viewModel.setCSS(text)
        }
    }

    private func editorChanged(_ text: String) {
        switch panel {
        case .front:
            viewModel.setFront(text, at: templateIndex)
        case .back:
            viewModel.setBack(text, at: templateIndex)
        case .styles:
            viewModel.setCSS(text)
        }
        refreshStatus()
    }

    private func loadSelectedTemplate() {
        commitEditorText()
        nameField.text = viewModel.draft?.template(at: templateIndex)?.name ?? ""
        editor.setFieldTokens(viewModel.fieldTokens())
        loadPanelText()
        refreshStatus()
    }

    private func refreshStatus() {
        let message = viewModel.validationMessage
        validationLabel.text = message
        validationLabel.isHidden = message == nil
        structuralLabel.isHidden = !viewModel.hasStructuralChange

        let dirty = viewModel.draft?.isDirty == true
        saveItem?.isEnabled = dirty && message == nil
        // A swipe-back would otherwise bypass the Discard confirmation.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = !dirty
    }

    // MARK: - Actions

    @objc private func templateSelectorChanged() {
        templateIndex = templateSelector.selectedSegmentIndex
        loadSelectedTemplate()
    }

    @objc private func panelChanged() {
        commitEditorText()
        panel = Panel(rawValue: panelControl.selectedSegmentIndex) ?? .front
        loadPanelText()
    }

    @objc private func nameChanged() {
        let name = nameField.text ?? ""
        viewModel.setTemplateName(name, at: templateIndex)
        if templateIndex < templateSelector.numberOfSegments, templateSelector.isHidden == false {
            templateSelector.setTitle(name, forSegmentAt: templateIndex)
        }
        refreshStatus()
    }

    @objc private func cancelTapped() {
        guard viewModel.draft?.isDirty == true else {
            navigationController?.popViewController(animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Discard changes?",
            message: "Your template edits will be lost.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func saveTapped() {
        commitEditorText()
        guard viewModel.draft?.isDirty == true else { return }

        if let message = viewModel.validationMessage {
            Alerts.present(message, title: "Fix the template first", on: self)
            return
        }

        guard viewModel.hasStructuralChange else {
            performSave()
            return
        }

        let alert = UIAlertController(
            title: "Full sync required",
            message: """
            Adding, removing or reordering fields or templates makes the next \
            collection sync a full sync. Save anyway?
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            self?.performSave()
        })
        present(alert, animated: true)
    }

    private func performSave() {
        guard progressView == nil else { return }
        editor.resignFirstResponder()
        let overlay = BlockingProgressView.install(in: view, title: "Saving template")
        overlay.setCancelTitle(nil)
        progressView = overlay

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.viewModel.save()
                self.dismissProgress()
                // E3: re-read happened in the view model; rebuild from it.
                self.renderLoadedState()
            } catch {
                self.dismissProgress()
                Alerts.present(error: error, title: "Couldn't save template", on: self)
            }
        }
    }

    @objc private func previewTapped() {
        commitEditorText()
        guard viewModel.draft != nil else { return }
        previewButton.isEnabled = false

        Task { [weak self] in
            guard let self else { return }
            defer { self.previewButton.isEnabled = true }
            do {
                let (rendered, note) = try await self.viewModel.makePreview(
                    templateIndex: self.templateIndex
                )
                let name = self.viewModel.draft?.template(at: self.templateIndex)?.name ?? "Preview"
                let preview = CardPreviewViewController(
                    rendered: rendered,
                    templateName: name,
                    note: note,
                    services: self.services
                )
                let navigation = UINavigationController(rootViewController: preview)
                self.present(navigation, animated: true)
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

extension TemplateEditorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
