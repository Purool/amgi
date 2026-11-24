import AnkiKit
import UIKit

/// Browse tab (S8): every note in the collection, optionally filtered by the
/// search bar. Read-only list — rows push the note detail through the Router.
@MainActor
final class BrowseViewController: UIViewController {
    private enum Section {
        case notes
    }

    private let viewModel: BrowseViewModel
    private let router: Router

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, NoteID>!

    private let loadingView = LoadingStateView(message: "Opening collection…")
    /// Recreated per empty state: the "no matches" copy embeds the query.
    private var emptyView: EmptyStateView?
    private var errorView: ErrorStateView?
    private let refreshControl = UIRefreshControl()

    init(viewModel: BrowseViewModel, router: Router) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
        title = "Browse"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        setUpSearchController()
        setUpCollectionView()
        setUpStateViews()

        viewModel.onStateChange = { [weak self] state in
            self?.apply(state)
        }
        // First screen: the first page of all notes.
        viewModel.search(query: "", showLoadingOverlay: true)
    }

    // MARK: Setup

    private func setUpSearchController() {
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search notes"

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
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
        collectionView.accessibilityLabel = "Note list"
        collectionView.delegate = self
        refreshControl.addTarget(self, action: #selector(refreshPulled), for: .valueChanged)
        collectionView.refreshControl = refreshControl
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let registration = UICollectionView.CellRegistration<NoteCell, NoteID> {
            [weak self] cell, _, id in
            guard let summary = self?.viewModel.summary(for: id) else { return }
            cell.configure(with: summary)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, NoteID>(
            collectionView: collectionView
        ) { [weak self] collectionView, indexPath, id in
            guard self?.viewModel.summary(for: id) != nil else { return nil }
            return collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: id
            )
        }
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
        loadingView.isHidden = true
    }

    private func pinStateView(_ stateView: UIView) {
        stateView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stateView)
        NSLayoutConstraint.activate([
            stateView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    // MARK: State

    private func clearStateViews() {
        emptyView?.removeFromSuperview()
        emptyView = nil
        errorView?.removeFromSuperview()
        errorView = nil
        loadingView.isHidden = true
    }

    private func emptySnapshot() -> NSDiffableDataSourceSnapshot<Section, NoteID> {
        NSDiffableDataSourceSnapshot<Section, NoteID>()
    }

    private func apply(_ state: BrowseViewModel.State) {
        switch state {
        case .idle, .loading:
            emptyView?.removeFromSuperview()
            emptyView = nil
            errorView?.removeFromSuperview()
            errorView = nil
            loadingView.isHidden = false
            collectionView.isHidden = true
            dataSource.apply(emptySnapshot(), animatingDifferences: false)

        case .content(let notes, _):
            clearStateViews()
            collectionView.isHidden = false

            var snapshot = NSDiffableDataSourceSnapshot<Section, NoteID>()
            snapshot.appendSections([.notes])
            snapshot.appendItems(notes.map(\.id))
            dataSource.apply(snapshot, animatingDifferences: false)

        case .empty:
            emptyView?.removeFromSuperview()
            errorView?.removeFromSuperview()
            errorView = nil
            loadingView.isHidden = true
            collectionView.isHidden = true
            dataSource.apply(emptySnapshot(), animatingDifferences: false)

            let empty = viewModel.query.isEmpty
                ? EmptyStateView(
                    symbol: "tray",
                    title: "No notes",
                    message: "The collection has no notes yet."
                )
                : EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "No matches",
                    message: "Nothing matches “\(viewModel.query)”."
                )
            pinStateView(empty)
            emptyView = empty

        case .error(let message):
            emptyView?.removeFromSuperview()
            emptyView = nil
            loadingView.isHidden = true
            collectionView.isHidden = true
            dataSource.apply(emptySnapshot(), animatingDifferences: false)

            let replacement = ErrorStateView(message: message, retry: { [weak self] in
                self?.viewModel.search(
                    query: self?.viewModel.query ?? "",
                    showLoadingOverlay: true
                )
            })
            pinStateView(replacement)
            errorView = replacement
        }

        refreshControl.endRefreshing()
    }

    // MARK: Actions

    @objc private func refreshPulled() {
        viewModel.search(query: viewModel.query, showLoadingOverlay: false)
    }
}

extension BrowseViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let noteID = dataSource.itemIdentifier(for: indexPath) else { return }
        router.push(.browseNote(noteID: noteID), from: self)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        // Prefetch the next page shortly before the end of the list.
        if indexPath.item >= viewModel.notes.count - 10, viewModel.canLoadMore {
            viewModel.loadMore()
        }
    }
}

extension BrowseViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.updateQuery(searchController.searchBar.text ?? "")
    }
}
