import AnkiKit
import UIKit

/// The note-type list: every notetype sorted by name, pushing the template
/// editor. Entry point is the Settings screen's Collection section.
@MainActor
final class NotetypeListViewController: UIViewController {
    private enum Section {
        case notetypes
    }

    private let services: LiteServices
    private let session: CollectionSession
    private let router: Router

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, NotetypeID>!
    private var entries: [NotetypeNameId] = []

    private let loadingView = LoadingStateView(message: "Loading note types…")
    private var errorView: ErrorStateView?
    private var emptyView: EmptyStateView?

    init(services: LiteServices, session: CollectionSession, router: Router) {
        self.services = services
        self.session = session
        self.router = router
        super.init(nibName: nil, bundle: nil)
        title = "Note Types"
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
        load()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Template edits change names; a quiet refresh keeps the list honest.
        if !entries.isEmpty {
            load(showLoadingOverlay: false)
        }
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
        collectionView.delegate = self
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, NotetypeID> {
            [weak self] cell, _, id in
            guard let entry = self?.entries.first(where: { $0.id == id }) else { return }
            var content = cell.defaultContentConfiguration()
            content.text = entry.name
            content.textProperties.font = AmgiTypography.body
            content.textProperties.color = AmgiColor.textPrimary
            content.textProperties.adjustsFontForContentSizeCategory = true
            cell.contentConfiguration = content
            cell.accessories = [.disclosureIndicator()]
        }

        dataSource = UICollectionViewDiffableDataSource<Section, NotetypeID>(
            collectionView: collectionView
        ) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
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

    // MARK: - Loading

    private func load(showLoadingOverlay: Bool = true) {
        if showLoadingOverlay {
            loadingView.isHidden = false
            collectionView.isHidden = true
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.ensureOpen()
                let names = try await self.services.notetypes.names()
                self.entries = sortedNotetypeNames(names)
                self.loadingView.isHidden = true
                self.clearStateOverlays()
                self.collectionView.isHidden = false

                var snapshot = NSDiffableDataSourceSnapshot<Section, NotetypeID>()
                snapshot.appendSections([.notetypes])
                snapshot.appendItems(self.entries.map(\.id))
                self.dataSource.apply(snapshot, animatingDifferences: false)

                if self.entries.isEmpty {
                    self.showEmpty()
                }
            } catch {
                self.loadingView.isHidden = true
                self.showError(ErrorMessages.text(for: error))
            }
        }
    }

    private func clearStateOverlays() {
        emptyView?.removeFromSuperview()
        emptyView = nil
        errorView?.removeFromSuperview()
        errorView = nil
    }

    private func showEmpty() {
        collectionView.isHidden = true
        let view = EmptyStateView(
            symbol: "square.stack.3d.up",
            title: "No note types",
            message: "This collection has no note types to edit."
        )
        pin(view)
        emptyView = view
    }

    private func showError(_ message: String) {
        clearStateOverlays()
        let replacement = ErrorStateView(message: message, retry: { [weak self] in
            self?.load()
        })
        pin(replacement)
        errorView = replacement
    }

    private func pin(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor),
            view.bottomAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
        ])
    }
}

// MARK: - Selection

extension NotetypeListViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath) else { return }
        router.push(
            .templateEditor(notetypeID: id, initialTemplate: 0, previewNoteID: nil),
            from: self
        )
    }
}
