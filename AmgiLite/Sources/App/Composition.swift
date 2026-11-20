import AnkiKit
import UIKit

/// Screens the tab bar hosts, in tab order. Phase 2 swaps the temporary deck
/// list and the browse placeholder for the real feature view controllers;
/// Phase 3 replaces the settings screen. Nothing else in the shell changes.
struct ScreenFactories {
    let makeDecks: () -> UIViewController
    let makeBrowse: () -> UIViewController
    let makeSettings: () -> UIViewController
}

/// The single wiring point. Integration tasks edit this file only.
///
/// Phase 1.5 (S5) status: S1 services, S2 design system and S3 card rendering
/// are reachable from the shell. `Features/` is still empty, so the Decks tab
/// drives `DeckServicing` through a temporary list and a temporary card preview
/// exercises the `CardWebView` seam. Both temporary controllers live here by
/// design and are deleted when S6/S7 take over the tabs.
@MainActor
enum Composition {
    static func makeScreens(
        services: LiteServices,
        session: CollectionSession,
        router: Router
    ) -> ScreenFactories {
        ScreenFactories(
            makeDecks: {
                TemporaryDeckListController(
                    services: services,
                    session: session,
                    router: router
                )
            },
            makeBrowse: {
                PlaceholderViewController(
                    title: "Browse",
                    detail: "Browser lands in Phase 2 (S8)."
                )
            },
            makeSettings: {
                EngineStatusViewController(services: services, session: session)
            }
        )
    }
}

// MARK: - Temporary deck list (replaced by Phase 2, S6)

/// Stand-in for `Features/Decks`. Drives `DeckServicing` end to end so the
/// shell exercises services + design system on device before the feature shard
/// lands: loading / empty / error states, diffable rows with count badges,
/// pull-to-refresh and a `Router` push on tap.
@MainActor
final class TemporaryDeckListController: UIViewController {
    private enum State {
        case loading
        case content([DeckRow])
        case empty
        case error(String)
    }

    private enum Section {
        case decks
    }

    private let services: LiteServices
    private let session: CollectionSession
    private let router: Router

    private var state: State = .loading {
        didSet { apply(state) }
    }
    /// Kept beside the diffable snapshot: the cell handler resolves indentation
    /// and badge counts from the `DeckRow` behind each item ID.
    private var rows: [DeckRow] = []

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DeckRow.ID>!

    private let loadingView = LoadingStateView(message: "Opening collection…")
    private let emptyView = EmptyStateView(
        symbol: "rectangle.stack",
        title: "No decks",
        message: "The collection is open but has nothing to study yet. Import a deck once the setup flow lands (Phase 3)."
    )
    private var errorView: ErrorStateView?
    private let refreshControl = UIRefreshControl()

    init(services: LiteServices, session: CollectionSession, router: Router) {
        self.services = services
        self.session = session
        self.router = router
        super.init(nibName: nil, bundle: nil)
        title = "Decks"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        setUpCollectionView()
        setUpStateViews()

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Preview",
            style: .plain,
            target: self,
            action: #selector(openPreview)
        )

        reload()
    }

    private func setUpCollectionView() {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.backgroundColor = AmgiColor.background
        let layout = UICollectionViewCompositionalLayout { _, environment in
            NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: environment)
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.accessibilityLabel = "Deck list"
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let registration = UICollectionView.CellRegistration<TemporaryDeckCell, DeckRow.ID> {
            [weak self] cell, _, id in
            guard let row = self?.rows.first(where: { $0.id == id }) else { return }

            cell.configure(with: row)
            cell.indentationLevel = row.depth
            cell.indentationWidth = 14
        }

        dataSource = UICollectionViewDiffableDataSource<Section, DeckRow.ID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, id in
            guard self?.rows.contains(where: { $0.id == id }) == true else { return nil }
            return collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: id
            )
        }
    }

    private func setUpStateViews() {
        for stateView in [loadingView, emptyView] as [UIView] {
            stateView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(stateView)
            NSLayoutConstraint.activate([
                stateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                stateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
                stateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                stateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            ])
        }
        loadingView.isHidden = false
        emptyView.isHidden = true
    }

    private func showError(_ message: String) {
        errorView?.removeFromSuperview()
        let replacement = ErrorStateView(message: message, retry: { [weak self] in
            self?.reload()
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

    private func apply(_ state: State) {
        switch state {
        case .loading:
            loadingView.isHidden = false
            emptyView.isHidden = true
            errorView?.isHidden = true
            collectionView.isHidden = true
        case .content(let newRows):
            rows = newRows
            loadingView.isHidden = true
            emptyView.isHidden = true
            errorView?.isHidden = true
            collectionView.isHidden = false

            var snapshot = NSDiffableDataSourceSnapshot<Section, DeckRow.ID>()
            snapshot.appendSections([.decks])
            snapshot.appendItems(newRows.map(\.id))
            dataSource.apply(snapshot, animatingDifferences: false)
        case .empty:
            rows = []
            loadingView.isHidden = true
            emptyView.isHidden = true
            errorView?.isHidden = true
            collectionView.isHidden = false
            dataSource.apply(
                NSDiffableDataSourceSnapshot<Section, DeckRow.ID>(),
                animatingDifferences: false
            )
        case .error(let message):
            rows = []
            loadingView.isHidden = true
            emptyView.isHidden = true
            collectionView.isHidden = false
            dataSource.apply(
                NSDiffableDataSourceSnapshot<Section, DeckRow.ID>(),
                animatingDifferences: false
            )
            showError(message)
        }
        refreshControl.endRefreshing()
    }

    private func reload(showLoadingOverlay: Bool = true) {
        if showLoadingOverlay {
            state = .loading
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.ensureOpen()
                let tree = try await self.services.decks.deckTree()
                self.state = tree.isEmpty ? .empty : .content(tree)
            } catch {
                self.state = .error("Engine error: \(error)")
            }
        }
    }

    @objc private func refreshPulled() {
        reload(showLoadingOverlay: false)
    }

    @objc private func openPreview() {
        navigationController?.pushViewController(
            TemporaryCardPreviewController(services: services, session: session),
            animated: true
        )
    }
}

// MARK: - Temporary deck row (replaced by Phase 2, S6)

private final class TemporaryDeckBadges: UIView {
    private let newBadge = AmgiBadgeView(kind: .new)
    private let learningBadge = AmgiBadgeView(kind: .learning)
    private let dueBadge = AmgiBadgeView(kind: .due)

    init() {
        super.init(frame: .zero)

        let stack = UIStackView(arrangedSubviews: [newBadge, learningBadge, dueBadge])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = AmgiSpacing.xs
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(new: Int, learning: Int, due: Int) {
        newBadge.count = new
        learningBadge.count = learning
        dueBadge.count = due
    }
}

private final class TemporaryDeckCell: UICollectionViewListCell {
    private let badges = TemporaryDeckBadges()

    func configure(with row: DeckRow) {
        var content = defaultContentConfiguration()
        content.text = row.name
        content.textProperties.font = AmgiTypography.body
        content.textProperties.color = AmgiColor.textPrimary
        content.textProperties.adjustsFontForContentSizeCategory = true
        contentConfiguration = content

        badges.update(
            new: row.counts.newCount,
            learning: row.counts.learnCount,
            due: row.counts.reviewCount
        )
        accessories = [.customView(
            configuration: UICellAccessory.CustomViewConfiguration(
                customView: badges,
                placement: .trailing()
            )
        )]
    }
}

// MARK: - Temporary card preview (replaced by Phase 2, S7)

/// Temporary stand-in proving the S3 seam end to end on device: the first
/// queued card is rendered through `ReviewServicing` into `CardWebView`, with
/// the front/back sides switched by `CardPageBuilder`. Strictly read-only — it
/// never answers a card, so no scheduling state is touched; the real review
/// flow lands in Phase 2 (S7) and replaces this screen.
@MainActor
final class TemporaryCardPreviewController: UIViewController {
    private enum Phase {
        case loading
        case ready
        case notice(String)
    }

    private let services: LiteServices
    private let session: CollectionSession
    private let cardSurface: CardWebView

    private let noticeLabel = UILabel()
    private let captionLabel = UILabel()
    private let sideButton = AmgiButton(style: .secondary, title: "Show Answer")

    private var renderedCard: RenderedCard?
    private var showingBack = false

    init(services: LiteServices, session: CollectionSession) {
        self.services = services
        self.session = session

        let collection = services.collection
        self.cardSurface = CardWebView(mediaRootProvider: {
            collection.mediaFolderPath.map { URL(fileURLWithPath: $0) }
        })

        super.init(nibName: nil, bundle: nil)
        title = "Card preview"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        cardSurface.translatesAutoresizingMaskIntoConstraints = false

        noticeLabel.translatesAutoresizingMaskIntoConstraints = false
        noticeLabel.font = AmgiTypography.body
        noticeLabel.textColor = AmgiColor.textSecondary
        noticeLabel.textAlignment = .center
        noticeLabel.numberOfLines = 0
        noticeLabel.isHidden = true

        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.font = AmgiTypography.caption
        captionLabel.textColor = AmgiColor.textTertiary
        captionLabel.textAlignment = .center
        captionLabel.numberOfLines = 0
        captionLabel.text = "Preview only — no answers are recorded. Review controls land in Phase 2 (S7)."
        captionLabel.adjustsFontForContentSizeCategory = true

        sideButton.translatesAutoresizingMaskIntoConstraints = false
        sideButton.isEnabled = false
        sideButton.addTarget(self, action: #selector(toggleSide), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [cardSurface, noticeLabel, captionLabel, sideButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = AmgiSpacing.md
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        loadFirstCard()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // The page bakes its colors in; dark-mode switches need a fresh render.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            renderCurrentSide()
        }
    }

    private func loadFirstCard() {
        setPhase(.loading)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.ensureOpen()
                let queued = try await self.services.review.queuedCards(limit: 1)
                guard let queuedCard = queued.cards.first else {
                    self.setPhase(.notice("No queued cards to preview."))
                    return
                }
                let rendered = try await self.services.review.render(cardID: queuedCard.card.id)
                self.renderedCard = rendered
                self.showingBack = false
                self.setPhase(.ready)
                self.renderCurrentSide()
            } catch {
                self.setPhase(.notice("Render failed: \(error)"))
            }
        }
    }

    private func renderCurrentSide() {
        guard let renderedCard else { return }
        let page = CardPageBuilder.page(
            for: renderedCard,
            side: showingBack ? .back : .front,
            isDark: traitCollection.userInterfaceStyle == .dark
        )
        cardSurface.load(html: page, baseURL: nil)
        sideButton.setTitle(showingBack ? "Show Question" : "Show Answer", for: .normal)
    }

    @objc private func toggleSide() {
        showingBack.toggle()
        renderCurrentSide()
    }

    private func setPhase(_ phase: Phase) {
        switch phase {
        case .loading:
            noticeLabel.text = "Rendering…"
            noticeLabel.isHidden = false
            cardSurface.isHidden = true
            sideButton.isEnabled = false
        case .ready:
            noticeLabel.isHidden = true
            cardSurface.isHidden = false
            sideButton.isEnabled = true
        case .notice(let message):
            noticeLabel.text = message
            noticeLabel.isHidden = false
            cardSurface.isHidden = true
            sideButton.isEnabled = false
        }
    }
}
