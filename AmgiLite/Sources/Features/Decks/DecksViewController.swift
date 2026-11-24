import UIKit

/// The Decks tab: a diffable list of the collection's deck tree with count
/// badges, pull-to-refresh, and a `Router` push to review on tap. All layout
/// and state-view handling mirrors the temporary implementation this screen
/// replaces (`TemporaryDeckListController`).
@MainActor
final class DecksViewController: UIViewController {
    private enum Section {
        case decks
    }

    private let viewModel: DecksViewModel
    private let router: Router

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DeckRow.ID>!

    private let loadingView = LoadingStateView(message: "Opening collection…")
    private let emptyView = EmptyStateView(
        symbol: "rectangle.stack",
        title: "No decks",
        message: "This collection has nothing to study yet. Import an .apkg from Settings, or sync from AnkiWeb."
    )
    private var errorView: ErrorStateView?
    private let refreshControl = UIRefreshControl()

    init(viewModel: DecksViewModel, router: Router) {
        self.viewModel = viewModel
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

        viewModel.onStateChange = { [weak self] state in
            self?.apply(state)
        }
        viewModel.load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning from review changes the counts, so refresh quietly:
        // no loading overlay, the current surface stays on screen.
        viewModel.load(showLoadingOverlay: false)
    }

    // MARK: - Setup

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

        let registration = UICollectionView.CellRegistration<DeckCell, DeckRow.ID> {
            [weak self] cell, _, id in
            guard let row = self?.viewModel.row(for: id) else { return }

            cell.configure(with: row)
            cell.setIndentation(row.depth)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, DeckRow.ID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, id in
            guard self?.viewModel.row(for: id) != nil else { return nil }
            return collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: id
            )
        }
        // The diffable data source owns the data source role only; the
        // collection view's delegate stays with this controller for taps.
        collectionView.delegate = self
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

    // MARK: - State

    private func apply(_ state: DecksViewModel.State) {
        switch state {
        case .loading:
            loadingView.isHidden = false
            emptyView.isHidden = true
            errorView?.isHidden = true
            collectionView.isHidden = true
        case .content(let rows):
            loadingView.isHidden = true
            emptyView.isHidden = true
            errorView?.isHidden = true
            collectionView.isHidden = false

            var snapshot = NSDiffableDataSourceSnapshot<Section, DeckRow.ID>()
            snapshot.appendSections([.decks])
            snapshot.appendItems(rows.map(\.id))
            dataSource.apply(snapshot, animatingDifferences: false)
        case .empty:
            loadingView.isHidden = true
            emptyView.isHidden = false
            errorView?.isHidden = true
            collectionView.isHidden = false
            dataSource.apply(
                NSDiffableDataSourceSnapshot<Section, DeckRow.ID>(),
                animatingDifferences: false
            )
        case .error(let message):
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

    // MARK: - Actions

    @objc private func refreshPulled() {
        viewModel.load(showLoadingOverlay: false)
    }
}

// MARK: - Selection

extension DecksViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        guard let deckID = viewModel.selectDeck(id) else { return }
        router.push(.review(deckID: deckID), from: self)
    }
}
