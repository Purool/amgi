import AnkiKit
import UIKit
import UniformTypeIdentifiers

/// The Settings tab: AnkiWeb account + sync, package import, and about info.
/// A diffable list of three sections; flows with blocking engine calls
/// (sync, import) show `BlockingProgressView` over the screen.
@MainActor
final class SettingsViewController: UIViewController {
    private enum Section: Hashable {
        case account
        case collection
        case about
    }

    private enum Item: Hashable {
        case accountStatus(text: String)
        case signIn
        case syncNow
        case importPackage
        case noteTypes
        case version(text: String)
        case about
    }

    private let viewModel: SettingsViewModel
    private let router: Router

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Item>!

    private var progressView: BlockingProgressView?
    /// Cancel on import means "stop waiting": the engine call continues, and
    /// the completion still reports the outcome when it returns.
    private var importCancelled = false

    init(viewModel: SettingsViewModel, router: Router) {
        self.viewModel = viewModel
        self.router = router
        super.init(nibName: nil, bundle: nil)
        title = "Settings"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        setUpCollectionView()

        viewModel.onAccountChange = { [weak self] in
            self?.applySnapshot()
        }
        viewModel.onSyncStateChange = { [weak self] state in
            self?.applySyncState(state)
        }
        viewModel.refresh()
    }

    // MARK: - List

    private func setUpCollectionView() {
        var listConfiguration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        listConfiguration.backgroundColor = AmgiColor.background
        let layout = UICollectionViewCompositionalLayout { _, environment in
            NSCollectionLayoutSection.list(using: listConfiguration, layoutEnvironment: environment)
        }

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColor = .clear
        collectionView.accessibilityLabel = "Settings list"
        collectionView.delegate = self
        view.addSubview(collectionView)

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, Item> {
            [weak self] cell, _, item in
            self?.configure(cell: cell, item: item)
        }

        dataSource = UICollectionViewDiffableDataSource<Section, Item>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(
                using: registration,
                for: indexPath,
                item: item
            )
        }
        applySnapshot()
    }

    private func configure(cell: UICollectionViewListCell, item: Item) {
        var content = cell.defaultContentConfiguration()

        switch item {
        case .accountStatus(let text):
            content.image = UIImage(systemName: "person.crop.circle")
            content.text = "AnkiWeb"
            content.secondaryText = text
        case .signIn:
            content.image = UIImage(systemName: "arrow.right.circle")
            content.text = "Sign in to AnkiWeb"
        case .syncNow:
            content.image = UIImage(systemName: "arrow.triangle.2.circlepath")
            content.text = "Sync now"
        case .importPackage:
            content.image = UIImage(systemName: "square.and.arrow.down")
            content.text = "Import .apkg file"
        case .noteTypes:
            content.image = UIImage(systemName: "square.stack.3d.up")
            content.text = "Note Types"
            content.secondaryText = "Edit cards and templates"
        case .version(let text):
            content.image = UIImage(systemName: "info.circle")
            content.text = "Version"
            content.secondaryText = text
        case .about:
            content.text = "About"
            content.secondaryText = """
            Offline-first flashcards, compatible with Anki. Built on the \
            upstream Rust engine (AGPL-3.0).
            """
            content.secondaryTextProperties.color = AmgiColor.textSecondary
            content.secondaryTextProperties.numberOfLines = 0
        }

        content.textProperties.font = AmgiTypography.body
        content.textProperties.color = AmgiColor.textPrimary
        content.secondaryTextProperties.font = AmgiTypography.caption
        content.secondaryTextProperties.color = AmgiColor.textSecondary
        content.secondaryTextProperties.numberOfLines = 0
        content.imageProperties.tintColor = AmgiColor.accent
        content.imageProperties.maximumSize = CGSize(width: 26, height: 26)
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: AmgiSpacing.sm, leading: 0, bottom: AmgiSpacing.sm, trailing: 0
        )
        // "Sync now" reads as disabled while it cannot run: grey text, and a
        // tap is a no-op (list cells have no `isEnabled` on iOS 14).
        if case .syncNow = item {
            content.textProperties.color = viewModel.canSync
                ? AmgiColor.textPrimary
                : AmgiColor.textTertiary
            content.imageProperties.tintColor = viewModel.canSync
                ? AmgiColor.accent
                : AmgiColor.textTertiary
        }
        cell.contentConfiguration = content
        cell.backgroundConfiguration = UIBackgroundConfiguration.clear()
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Item>()
        snapshot.appendSections([.account, .collection, .about])
        snapshot.appendItems(
            [
                .accountStatus(text: viewModel.accountSummary),
                .signIn,
                .syncNow,
            ],
            toSection: .account
        )
        snapshot.appendItems([.importPackage, .noteTypes], toSection: .collection)
        snapshot.appendItems(
            [
                .version(text: versionText()),
                .about,
            ],
            toSection: .about
        )
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func versionText() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        default: return "—"
        }
    }

    // MARK: - Sync state

    private func applySyncState(_ state: SettingsViewModel.SyncState) {
        switch state {
        case .idle:
            dismissProgress()
        case .running(let text):
            showSyncProgress(status: text)
        case .conflict:
            dismissProgress()
            presentConflictPrompt()
        case .finished:
            dismissProgress()
            Alerts.presentMessage(
                title: "Sync finished",
                message: "Your decks are up to date.",
                on: self
            )
        case .failed(let message):
            dismissProgress()
            Alerts.present(message, title: "Sync failed", on: self)
        }
    }

    private func showSyncProgress(status: String) {
        if let progressView {
            progressView.setStatus(status)
        } else {
            let overlay = BlockingProgressView.install(in: view, title: "Syncing")
            overlay.setStatus(status)
            overlay.onCancel = { [weak self] in
                // "Stop waiting": the engine keeps running, the screen comes
                // back when the call returns either way.
                self?.viewModel.cancelSync()
            }
            progressView = overlay
        }
    }

    private func dismissProgress() {
        progressView?.removeFromSuperview()
        progressView = nil
    }

    /// The engine's conflict states need a human decision; neither direction
    /// is safe to choose for the user.
    private func presentConflictPrompt() {
        let alert = UIAlertController(
            title: "Full sync required",
            message: "The server and this device have diverged. Upload replaces the server's copy with this device's data; download replaces this device's data with the server's copy.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Upload to AnkiWeb", style: .default) { [weak self] _ in
            self?.viewModel.fullSync(direction: .upload)
        })
        alert.addAction(UIAlertAction(title: "Download from AnkiWeb", style: .default) { [weak self] _ in
            self?.viewModel.fullSync(direction: .download)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.viewModel.refresh()
        })
        present(alert, animated: true)
    }

    // MARK: - Import

    private func pickPackage() {
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

    private func importPackage(at url: URL) {
        guard progressView == nil else { return }
        importCancelled = false

        let overlay = BlockingProgressView.install(in: view, title: "Importing")
        overlay.setStatus("Reading the package… large decks can take a while.")
        overlay.onCancel = { [weak self] in
            guard let self else { return }
            self.importCancelled = true
            overlay.stopAnimating()
            overlay.setStatus("Stopped waiting — the import keeps running in the background.")
            overlay.setCancelTitle(nil)
        }
        progressView = overlay

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.viewModel.importPackage(at: url)
                self.finishImport(success: true)
            } catch {
                self.finishImport(success: false, error: error)
            }
        }
    }

    private func finishImport(success: Bool, error: Error? = nil) {
        dismissProgress()
        if success {
            Alerts.presentMessage(
                title: importCancelled ? "Import finished" : "Import complete",
                message: "The deck is in your collection now.",
                on: self
            )
        } else if let error {
            Alerts.present(error: error, title: "Import failed", on: self)
        }
    }
}

// MARK: - Selection

extension SettingsViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let item = dataSource.itemIdentifier(for: indexPath) else { return }
        switch item {
        case .signIn:
            presentLogin()
        case .syncNow:
            guard viewModel.canSync else { return }
            viewModel.sync()
        case .importPackage:
            pickPackage()
        case .noteTypes:
            router.push(.notetypeList, from: self)
        case .accountStatus, .version, .about:
            break
        }
    }
}

// MARK: - Login sheet

extension SettingsViewController {
    private func presentLogin() {
        let login = LoginViewController()
        login.onAttempt = { [weak self] username, password, completion in
            guard let self else {
                completion("The settings screen is gone.")
                return
            }
            self.viewModel.logIn(username: username, password: password, completion: completion)
        }
        present(UINavigationController(rootViewController: login), animated: true)
    }
}

// MARK: - Document picker

extension SettingsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importPackage(at: url)
    }
}
