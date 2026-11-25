import AnkiKit
import UIKit

/// Deck options for one deck: preset switching, daily limits, new/review
/// order, burying, advanced multipliers and the FSRS section. Saving is one
/// `updateDeckConfigs` call; the service re-reads the context so the deck's
/// per-day overrides are always passed back untouched (E7).
@MainActor
final class DeckOptionsViewController: UIViewController {
    private let viewModel: DeckOptionsViewModel
    private let session: CollectionSession
    private let services: LiteServices

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<DeckOptionsSection, DeckOptionsRow>!

    private let loadingView = LoadingStateView(message: "Loading deck options…")
    private var errorView: ErrorStateView?
    private var progressView: BlockingProgressView?
    private var saveItem: UIBarButtonItem?

    init(services: LiteServices, session: CollectionSession, deckID: DeckID, deckName: String) {
        self.services = services
        self.session = session
        self.viewModel = DeckOptionsViewModel(
            services: services,
            session: session,
            deckID: deckID,
            deckName: deckName
        )
        super.init(nibName: nil, bundle: nil)
        title = deckName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshSaveItem()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        setUpCollectionView()
        setUpStateViews()
        setUpNavigationItems()

        viewModel.onStateChange = { [weak self] state in
            self?.apply(state)
        }
        viewModel.onDraftChange = { [weak self] in
            self?.refreshSaveItem()
        }
        viewModel.load()
    }

    // MARK: - Setup

    private func setUpCollectionView() {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.backgroundColor = AmgiColor.background
        listConfiguration.headerMode = .supplementary

        let layout = UICollectionViewCompositionalLayout { _, environment in
            NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: environment)
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.accessibilityLabel = "Deck options"
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let switchCell = UICollectionView.CellRegistration<AmgiSwitchRowCell, DeckOptionsRow> {
            [weak self] cell, _, row in
            self?.configureSwitch(cell: cell, row: row)
        }
        let stepperCell = UICollectionView.CellRegistration<AmgiStepperRowCell, DeckOptionsRow> {
            [weak self] cell, _, row in
            self?.configureStepper(cell: cell, row: row)
        }
        let textCell = UICollectionView.CellRegistration<AmgiTextRowCell, DeckOptionsRow> {
            [weak self] cell, _, row in
            self?.configureText(cell: cell, row: row)
        }
        let menuCell = UICollectionView.CellRegistration<AmgiMenuRowCell, DeckOptionsRow> {
            [weak self] cell, _, row in
            self?.configureMenu(cell: cell, row: row)
        }
        let disclosureCell = UICollectionView.CellRegistration<AmgiDisclosureRowCell, DeckOptionsRow> {
            [weak self] cell, _, row in
            self?.configureDisclosure(cell: cell, row: row)
        }
        let sliderCell = UICollectionView.CellRegistration<AmgiSliderRowCell, DeckOptionsRow> {
            [weak self] cell, _, row in
            self?.configureSlider(cell: cell, row: row)
        }
        let actionCell = UICollectionView.CellRegistration<AmgiActionRowCell, DeckOptionsRow> {
            [weak self] cell, _, row in
            self?.configureAction(cell: cell, row: row)
        }
        let infoCell = UICollectionView.CellRegistration<AmgiInfoRowCell, DeckOptionsRow> {
            [weak self] cell, _, row in
            self?.configureInfo(cell: cell, row: row)
        }

        dataSource = UICollectionViewDiffableDataSource<DeckOptionsSection, DeckOptionsRow>(
            collectionView: collectionView
        ) { collectionView, indexPath, row in
            switch row {
            case .applyToChildren, .ignoreReviewLimit, .buryNew, .buryReviews,
                 .buryInterdayLearning, .fsrsEnabled, .healthCheck:
                return collectionView.dequeueConfiguredReusableCell(
                    using: switchCell, for: indexPath, item: row
                )
            case .newPerDay, .reviewsPerDay, .graduatingInterval, .easyInterval,
                 .leechThreshold, .maximumInterval, .hardMultiplier, .easyMultiplier:
                return collectionView.dequeueConfiguredReusableCell(
                    using: stepperCell, for: indexPath, item: row
                )
            case .learnSteps, .relearnSteps, .paramSearch:
                return collectionView.dequeueConfiguredReusableCell(
                    using: textCell, for: indexPath, item: row
                )
            case .insertOrder, .gatherOrder, .sortOrder, .leechAction,
                 .reviewOrder, .newMix, .interdayMix:
                return collectionView.dequeueConfiguredReusableCell(
                    using: menuCell, for: indexPath, item: row
                )
            case .preset, .fsrsWeights:
                return collectionView.dequeueConfiguredReusableCell(
                    using: disclosureCell, for: indexPath, item: row
                )
            case .intervalMultiplier, .desiredRetention, .historicalRetention:
                return collectionView.dequeueConfiguredReusableCell(
                    using: sliderCell, for: indexPath, item: row
                )
            case .optimizeAll:
                return collectionView.dequeueConfiguredReusableCell(
                    using: actionCell, for: indexPath, item: row
                )
            case .lastOptimized:
                return collectionView.dequeueConfiguredReusableCell(
                    using: infoCell, for: indexPath, item: row
                )
            }
        }

        let header = UICollectionView.SupplementaryRegistration<AmgiSectionHeaderView>(
            elementKind: UICollectionView.elementKindSectionHeader
        ) { header, _, indexPath in
            let sections = DeckOptionsSection.allCases
            guard indexPath.section < sections.count else { return }
            header.configure(text: sections[indexPath.section].title)
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(using: header, for: indexPath)
        }

        // Dismiss the keyboard when the list is dragged.
        collectionView.keyboardDismissMode = .interactive
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

    // MARK: - State

    private func apply(_ state: DeckOptionsViewModel.State) {
        switch state {
        case .loading:
            loadingView.isHidden = false
            errorView?.removeFromSuperview()
            errorView = nil
            collectionView.isHidden = true
        case .content:
            loadingView.isHidden = true
            errorView?.removeFromSuperview()
            errorView = nil
            collectionView.isHidden = false
            renderContent()
            refreshSaveItem()
        case .error(let message):
            loadingView.isHidden = true
            collectionView.isHidden = true
            showError(message)
        }
    }

    private func renderContent() {
        var snapshot = NSDiffableDataSourceSnapshot<DeckOptionsSection, DeckOptionsRow>()
        for section in DeckOptionsSection.allCases {
            snapshot.appendSections([section])
            snapshot.appendItems(section.rows, toSection: section)
        }
        dataSource.apply(snapshot, animatingDifferences: false)
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

    private func refreshSaveItem() {
        saveItem?.isEnabled = viewModel.canSave
        // A swipe-back would otherwise bypass the Discard confirmation.
        navigationController?.interactivePopGestureRecognizer?.isEnabled = !viewModel.canSave
    }

    private func reloadRow(_ row: DeckOptionsRow) {
        var snapshot = dataSource.snapshot()
        guard snapshot.itemIdentifiers.contains(row) else { return }
        snapshot.reloadItems([row])
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Cell configuration

    private func configureSwitch(cell: AmgiSwitchRowCell, row: DeckOptionsRow) {
        guard let draft = viewModel.draft else { return }
        switch row {
        case .applyToChildren:
            cell.configure(
                title: "Apply to subdecks",
                secondary: "Also use this preset for child decks.",
                isOn: draft.applyToChildren
            ) { [weak self] isOn in
                self?.viewModel.mutate { $0.applyToChildren = isOn }
            }
        case .ignoreReviewLimit:
            cell.configure(
                title: "New cards ignore review limit",
                secondary: "Keep showing new cards after the review limit is reached.",
                isOn: draft.ignoreReviewLimit
            ) { [weak self] isOn in
                self?.viewModel.mutate { $0.ignoreReviewLimit = isOn }
            }
        case .buryNew:
            cell.configure(title: "Bury new siblings", isOn: draft.config.config.buryNew) {
                [weak self] isOn in
                self?.viewModel.mutate { $0.config.config.buryNew = isOn }
            }
        case .buryReviews:
            cell.configure(title: "Bury review siblings", isOn: draft.config.config.buryReviews) {
                [weak self] isOn in
                self?.viewModel.mutate { $0.config.config.buryReviews = isOn }
            }
        case .buryInterdayLearning:
            cell.configure(
                title: "Bury interday learning siblings",
                isOn: draft.config.config.buryInterdayLearning
            ) { [weak self] isOn in
                self?.viewModel.mutate { $0.config.config.buryInterdayLearning = isOn }
            }
        case .fsrsEnabled:
            cell.configure(
                title: "Enable FSRS",
                secondary: "Collection-wide. Existing cards keep their intervals until rescheduled.",
                isOn: draft.fsrsEnabled
            ) { [weak self] isOn in
                self?.setFSRSEnabled(isOn)
            }
        case .healthCheck:
            cell.configure(
                title: "Health check",
                secondary: "Ask the optimizer to verify the review history.",
                isOn: draft.runHealthCheck
            ) { [weak self] isOn in
                self?.viewModel.mutate { $0.runHealthCheck = isOn }
            }
        default:
            break
        }
    }

    private func configureStepper(cell: AmgiStepperRowCell, row: DeckOptionsRow) {
        guard let draft = viewModel.draft else { return }
        let config = draft.config.config

        switch row {
        case .newPerDay:
            cell.configure(
                title: "New cards/day",
                value: Double(config.newPerDay),
                range: DeckOptionLimits.perDay,
                display: { "\(Int($0))" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.config.config.newPerDay = Int(value) }
            }
        case .reviewsPerDay:
            cell.configure(
                title: "Maximum reviews/day",
                value: Double(config.reviewsPerDay),
                range: DeckOptionLimits.perDay,
                display: { "\(Int($0))" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.config.config.reviewsPerDay = Int(value) }
            }
        case .graduatingInterval:
            cell.configure(
                title: "Graduating interval",
                secondary: "Days.",
                value: Double(config.graduatingIntervalGood),
                range: DeckOptionLimits.interval,
                display: { "\(Int($0)) days" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.config.config.graduatingIntervalGood = Int(value) }
            }
        case .easyInterval:
            cell.configure(
                title: "Easy interval",
                secondary: "Days.",
                value: Double(config.graduatingIntervalEasy),
                range: DeckOptionLimits.interval,
                display: { "\(Int($0)) days" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.config.config.graduatingIntervalEasy = Int(value) }
            }
        case .leechThreshold:
            cell.configure(
                title: "Leech threshold",
                secondary: "Lapses before the leech action runs.",
                value: Double(config.leechThreshold),
                range: DeckOptionLimits.leech,
                display: { "\(Int($0))" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.config.config.leechThreshold = Int(value) }
            }
        case .maximumInterval:
            cell.configure(
                title: "Maximum interval",
                secondary: "Days.",
                value: Double(config.maximumReviewInterval),
                range: DeckOptionLimits.interval,
                display: { "\(Int($0)) days" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.config.config.maximumReviewInterval = Int(value) }
            }
        case .hardMultiplier:
            cell.configure(
                title: "Hard interval",
                value: Double(draft.hardMultiplier * 100),
                range: (DeckOptionLimits.hardMultiplier.lowerBound * 100) ... (DeckOptionLimits.hardMultiplier.upperBound * 100),
                display: { "\(Int($0.rounded()))%" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.hardMultiplier = Float(value / 100) }
            }
        case .easyMultiplier:
            cell.configure(
                title: "Easy bonus",
                value: Double(draft.easyMultiplier * 100),
                range: (DeckOptionLimits.easyMultiplier.lowerBound * 100) ... (DeckOptionLimits.easyMultiplier.upperBound * 100),
                display: { "\(Int($0.rounded()))%" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.easyMultiplier = Float(value / 100) }
            }
        default:
            break
        }
    }

    private func configureText(cell: AmgiTextRowCell, row: DeckOptionsRow) {
        guard let draft = viewModel.draft else { return }
        switch row {
        case .learnSteps:
            cell.configure(
                title: "Learning steps",
                secondary: "Minutes; suffix with s/m/h/d.",
                text: draft.learnStepsText,
                placeholder: "1m 10m",
                onChange: { [weak self] text in
                    self?.viewModel.mutate { $0.setLearnStepsText(text) }
                },
                onCommit: { [weak self] text in
                    self?.viewModel.mutate { $0.setLearnStepsText(text) }
                }
            )
        case .relearnSteps:
            cell.configure(
                title: "Relearning steps",
                secondary: "Minutes; suffix with s/m/h/d.",
                text: draft.relearnStepsText,
                placeholder: "10m",
                onChange: { [weak self] text in
                    self?.viewModel.mutate { $0.setRelearnStepsText(text) }
                },
                onCommit: { [weak self] text in
                    self?.viewModel.mutate { $0.setRelearnStepsText(text) }
                }
            )
        case .paramSearch:
            cell.configure(
                title: "Parameter search",
                secondary: "Reviews used to train FSRS.",
                text: draft.paramSearch,
                placeholder: viewModel.defaultParamSearch,
                onChange: { [weak self] text in
                    self?.viewModel.mutate { $0.paramSearch = text }
                },
                onCommit: { [weak self] text in
                    self?.viewModel.mutate { $0.paramSearch = text }
                }
            )
        default:
            break
        }
    }

    private func configureMenu(cell: AmgiMenuRowCell, row: DeckOptionsRow) {
        guard let draft = viewModel.draft else { return }
        let config = draft.config.config

        switch row {
        case .insertOrder:
            let values = NewCardInsertOrder.allCases
            cell.configure(
                title: "Insertion order",
                options: values.map { .init(title: $0.label, isSelected: $0 == config.newCardInsertOrder) }
            ) { [weak self] index in
                guard values.indices.contains(index) else { return }
                let value = values[index]
                self?.viewModel.mutate { $0.config.config.newCardInsertOrder = value }
                self?.reloadRow(.insertOrder)
            }
        case .gatherOrder:
            let values = NewCardGatherPriority.allCases
            cell.configure(
                title: "Gather order",
                options: values.map { .init(title: $0.label, isSelected: $0 == config.newCardGatherPriority) }
            ) { [weak self] index in
                guard values.indices.contains(index) else { return }
                let value = values[index]
                self?.viewModel.mutate { $0.config.config.newCardGatherPriority = value }
                self?.reloadRow(.gatherOrder)
            }
        case .sortOrder:
            let values = NewCardSortOrder.allCases
            cell.configure(
                title: "Sort order",
                options: values.map { .init(title: $0.label, isSelected: $0 == config.newCardSortOrder) }
            ) { [weak self] index in
                guard values.indices.contains(index) else { return }
                let value = values[index]
                self?.viewModel.mutate { $0.config.config.newCardSortOrder = value }
                self?.reloadRow(.sortOrder)
            }
        case .leechAction:
            let values = LeechAction.allCases
            cell.configure(
                title: "Leech action",
                options: values.map { .init(title: $0.label, isSelected: $0 == config.leechAction) }
            ) { [weak self] index in
                guard values.indices.contains(index) else { return }
                let value = values[index]
                self?.viewModel.mutate { $0.config.config.leechAction = value }
                self?.reloadRow(.leechAction)
            }
        case .reviewOrder:
            let values = ReviewCardOrder.allCases
            cell.configure(
                title: "Review order",
                options: values.map { .init(title: $0.label, isSelected: $0 == config.reviewOrder) }
            ) { [weak self] index in
                guard values.indices.contains(index) else { return }
                let value = values[index]
                self?.viewModel.mutate { $0.config.config.reviewOrder = value }
                self?.reloadRow(.reviewOrder)
            }
        case .newMix:
            let values = ReviewMix.allCases
            cell.configure(
                title: "New/review mix",
                options: values.map { .init(title: $0.label, isSelected: $0 == config.newMix) }
            ) { [weak self] index in
                guard values.indices.contains(index) else { return }
                let value = values[index]
                self?.viewModel.mutate { $0.config.config.newMix = value }
                self?.reloadRow(.newMix)
            }
        case .interdayMix:
            let values = ReviewMix.allCases
            cell.configure(
                title: "Interday learning mix",
                options: values.map { .init(title: $0.label, isSelected: $0 == config.interdayLearningMix) }
            ) { [weak self] index in
                guard values.indices.contains(index) else { return }
                let value = values[index]
                self?.viewModel.mutate { $0.config.config.interdayLearningMix = value }
                self?.reloadRow(.interdayMix)
            }
        default:
            break
        }
    }

    private func configureDisclosure(cell: AmgiDisclosureRowCell, row: DeckOptionsRow) {
        guard let draft = viewModel.draft else { return }
        switch row {
        case .preset:
            cell.configure(title: "Preset", secondary: draft.config.name)
        case .fsrsWeights:
            let count = currentDeckWeights(draft.config.config).count
            cell.configure(
                title: "FSRS weights",
                secondary: count == 0 ? "Not set" : "\(count) parameters"
            )
        default:
            break
        }
    }

    private func configureSlider(cell: AmgiSliderRowCell, row: DeckOptionsRow) {
        guard let draft = viewModel.draft else { return }
        switch row {
        case .intervalMultiplier:
            cell.configure(
                title: "Interval multiplier",
                value: draft.intervalMultiplier * 100,
                range: Float(DeckOptionLimits.intervalMultiplier.lowerBound * 100) ... Float(DeckOptionLimits.intervalMultiplier.upperBound * 100),
                display: { "\(Int($0.rounded()))%" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.intervalMultiplier = value / 100 }
            }
        case .desiredRetention:
            let hasOverride = draft.desiredRetentionOverride != nil
            cell.configure(
                title: "Desired retention",
                value: draft.desiredRetention * 100,
                range: Float(DeckOptionLimits.desiredRetention.lowerBound * 100) ... Float(DeckOptionLimits.desiredRetention.upperBound * 100),
                display: { "\(Int($0.rounded()))%" },
                enabled: !hasOverride
            ) { [weak self] value in
                self?.viewModel.mutate { $0.desiredRetention = value / 100 }
            }
        case .historicalRetention:
            cell.configure(
                title: "Historical retention",
                value: draft.historicalRetention * 100,
                range: Float(DeckOptionLimits.historicalRetention.lowerBound * 100) ... Float(DeckOptionLimits.historicalRetention.upperBound * 100),
                display: { "\(Int($0.rounded()))%" }
            ) { [weak self] value in
                self?.viewModel.mutate { $0.historicalRetention = value / 100 }
            }
        default:
            break
        }
    }

    private func configureAction(cell: AmgiActionRowCell, row: DeckOptionsRow) {
        guard row == .optimizeAll else { return }
        let enabled = viewModel.draft?.fsrsEnabled == true
        cell.configure(title: "Optimize all presets", enabled: enabled)
    }

    private func configureInfo(cell: AmgiInfoRowCell, row: DeckOptionsRow) {
        guard row == .lastOptimized else { return }
        let days = viewModel.context?.daysSinceLastFsrsOptimize ?? 0
        if days <= 0 {
            cell.configure(message: "FSRS parameters have never been optimized.")
        } else {
            cell.configure(
                message: "Last optimized \(days) day\(days == 1 ? "" : "s") ago."
            )
        }
    }

    // MARK: - FSRS confirmation

    private func setFSRSEnabled(_ enabled: Bool) {
        guard let draft = viewModel.draft else { return }
        guard enabled != draft.fsrsEnabled else { return }

        guard enabled else {
            viewModel.mutate { $0.fsrsEnabled = false }
            reloadRow(.fsrsEnabled)
            reloadRow(.optimizeAll)
            reloadRow(.fsrsWeights)
            return
        }

        let alert = UIAlertController(
            title: "Enable FSRS?",
            message: """
            FSRS is a collection-wide setting. Existing cards keep their current \
            intervals until they are rescheduled, and automatic rescheduling is not \
            available in this build.
            """,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.reloadRow(.fsrsEnabled)
        })
        alert.addAction(UIAlertAction(title: "Enable", style: .default) { [weak self] _ in
            self?.viewModel.mutate { $0.fsrsEnabled = true }
            self?.reloadRow(.fsrsEnabled)
            self?.reloadRow(.optimizeAll)
            self?.reloadRow(.fsrsWeights)
        })
        present(alert, animated: true)
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        guard let draft = viewModel.draft, draft.isDirty else {
            navigationController?.popViewController(animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Discard changes?",
            message: "Your edits to this preset will be lost.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
            self?.navigationController?.popViewController(animated: true)
        })
        present(alert, animated: true)
    }

    @objc private func saveTapped() {
        guard viewModel.canSave else { return }
        presentProgress(title: "Saving options")

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.viewModel.save()
                self.dismissProgress()
                self.navigationController?.popViewController(animated: true)
            } catch {
                self.dismissProgress()
                Alerts.present(error: error, title: "Couldn't save options", on: self)
            }
        }
    }

    private func pushPresetPicker() {
        guard let context = viewModel.context else { return }
        let picker = PresetPickerViewController(
            viewModel: viewModel,
            context: context,
            onPresetsChanged: { [weak self] in
                self?.renderContent()
                self?.refreshSaveItem()
            }
        )
        navigationController?.pushViewController(picker, animated: true)
    }

    private func pushWeightsEditor() {
        guard let draft = viewModel.draft else { return }
        let editor = FsrsWeightsViewController(
            initialText: draft.weightsText,
            paramSearch: viewModel.effectiveParamSearch,
            relearningSteps: relearningStepsInDay(parseDeckSteps(draft.relearnStepsText)),
            runHealthCheck: draft.runHealthCheck,
            services: services
        )
        editor.onApply = { [weak self] text in
            guard let self, self.viewModel.draft?.weightsText != text else { return }
            self.viewModel.mutate { $0.setWeightsText(text) }
            self.reloadRow(.fsrsWeights)
        }
        navigationController?.pushViewController(editor, animated: true)
    }

    private func optimizeAll() {
        guard viewModel.draft?.fsrsEnabled == true else { return }
        presentProgress(title: "Optimizing all presets")
        progressView?.setStatus("This can take a while on a large collection. It can't be interrupted.")
        progressView?.onCancel = { [weak self] in
            // No interrupt RPC: "cancel" can only stop waiting.
            self?.progressView?.stopAnimating()
            self?.progressView?.setStatus("Stopped waiting — optimization continues in the engine.")
            self?.progressView?.setCancelTitle(nil)
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.viewModel.optimizeAllPresets()
                self.dismissProgress()
                Alerts.presentMessage(
                    title: "Optimization finished",
                    message: "FSRS parameters were recomputed for every preset.",
                    on: self
                )
            } catch {
                self.dismissProgress()
                Alerts.present(error: error, title: "Couldn't optimize presets", on: self)
            }
        }
    }

    private func presentProgress(title: String) {
        guard progressView == nil else { return }
        let overlay = BlockingProgressView.install(in: view, title: title)
        overlay.setStatus("Working…")
        overlay.setCancelTitle(nil)
        overlay.onCancel = { [weak self] in
            self?.dismissProgress()
        }
        progressView = overlay
    }

    private func dismissProgress() {
        progressView?.removeFromSuperview()
        progressView = nil
    }
}

// MARK: - Selection

extension DeckOptionsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let row = dataSource.itemIdentifier(for: indexPath) else { return }
        switch row {
        case .preset:
            pushPresetPicker()
        case .fsrsWeights:
            pushWeightsEditor()
        case .optimizeAll:
            optimizeAll()
        default:
            break
        }
    }
}
