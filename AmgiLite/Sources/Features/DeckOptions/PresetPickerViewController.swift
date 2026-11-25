import AnkiKit
import UIKit

/// Preset list for one deck: switch, create, rename, delete. Every mutation
/// runs through `DeckOptionsViewModel`, which re-reads the engine context, so
/// the parent screen and this list both stay in sync.
@MainActor
final class PresetPickerViewController: UIViewController {
    private enum Section {
        case presets
    }

    private let viewModel: DeckOptionsViewModel
    private let onPresetsChanged: () -> Void

    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, DeckConfigID>!
    private var progressView: BlockingProgressView?

    init(
        viewModel: DeckOptionsViewModel,
        context: DeckConfigsForUpdate,
        onPresetsChanged: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onPresetsChanged = onPresetsChanged
        super.init(nibName: nil, bundle: nil)
        title = "Preset"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addTapped)
        )

        setUpCollectionView()
        applySnapshot()
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

        let registration = UICollectionView.CellRegistration<UICollectionViewListCell, DeckConfigID> {
            [weak self] cell, _, id in
            guard let self, let preset = self.preset(for: id) else { return }

            var content = cell.defaultContentConfiguration()
            content.text = preset.name
            content.textProperties.font = AmgiTypography.body
            content.textProperties.color = AmgiColor.textPrimary
            content.textProperties.adjustsFontForContentSizeCategory = true
            let uses = self.viewModel.presets.first(where: { $0.config.id == id })?.useCount ?? 0
            content.secondaryText = uses == 1 ? "Used by 1 deck" : "Used by \(uses) decks"
            content.secondaryTextProperties.font = AmgiTypography.caption
            content.secondaryTextProperties.color = AmgiColor.textSecondary
            cell.contentConfiguration = content
            cell.accessories = self.viewModel.currentPresetID == id ? [.checkmark()] : []
        }

        dataSource = UICollectionViewDiffableDataSource<Section, DeckConfigID>(
            collectionView: collectionView
        ) { collectionView, indexPath, id in
            collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
        }
    }

    private func preset(for id: DeckConfigID) -> DeckConfig? {
        viewModel.presets.first(where: { $0.config.id == id })?.config
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<Section, DeckConfigID>()
        snapshot.appendSections([.presets])
        snapshot.appendItems(viewModel.presets.map(\.config.id))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Actions

    @objc private func addTapped() {
        let currentName = viewModel.draft?.config.name ?? "Preset"
        let suggested = uniquePresetName(
            "\(currentName) copy",
            existing: viewModel.presets.map(\.config.name)
        )

        let alert = UIAlertController(
            title: "New preset",
            message: "Copies the current preset's settings.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = suggested
            field.placeholder = "Preset name"
            field.autocapitalizationType = .words
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text ?? suggested
            self?.createPreset(named: name)
        })
        present(alert, animated: true)
    }

    private func createPreset(named name: String) {
        run("Creating preset") { [weak self] in
            guard let self else { return }
            try await self.viewModel.createPreset(
                name: name,
                applyToChildren: self.viewModel.draft?.applyToChildren ?? false
            )
        }
    }

    private func switchPreset(_ preset: DeckConfig) {
        run("Switching preset") { [weak self] in
            guard let self else { return }
            try await self.viewModel.switchPreset(
                to: preset,
                applyToChildren: self.viewModel.draft?.applyToChildren ?? false
            )
        }
    }

    private func renamePreset(_ preset: DeckConfig) {
        let alert = UIAlertController(
            title: "Rename preset",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = preset.name
            field.placeholder = "Preset name"
            field.autocapitalizationType = .words
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Rename", style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text ?? preset.name
            self?.run("Renaming preset") { [weak self] in
                guard let self else { return }
                try await self.viewModel.renamePreset(
                    preset,
                    to: name,
                    applyToChildren: self.viewModel.draft?.applyToChildren ?? false
                )
            }
        })
        present(alert, animated: true)
    }

    private func deletePreset(_ preset: DeckConfig) {
        // E8: preset 1 is the engine's fallback and cannot be removed.
        guard preset.id.rawValue != 0, preset.id.rawValue != 1 else {
            Alerts.present(
                "The default preset can't be deleted.",
                title: "Can't delete preset",
                on: self
            )
            return
        }

        let alert = UIAlertController(
            title: "Delete “\(preset.name)”?",
            message: "Decks using this preset will fall back to the default preset.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.run("Deleting preset") { [weak self] in
                guard let self else { return }
                try await self.viewModel.deletePreset(
                    id: preset.id,
                    applyToChildren: self.viewModel.draft?.applyToChildren ?? false
                )
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Run + progress

    private func run(_ title: String, _ body: @escaping () async throws -> Void) {
        guard progressView == nil else { return }
        let overlay = BlockingProgressView.install(in: view, title: title)
        overlay.setCancelTitle(nil)
        progressView = overlay

        Task { [weak self] in
            guard let self else { return }
            do {
                try await body()
                self.finishProgress()
                self.applySnapshot()
                self.onPresetsChanged()
            } catch {
                self.finishProgress()
                Alerts.present(error: error, title: title, on: self)
            }
        }
    }

    private func finishProgress() {
        progressView?.removeFromSuperview()
        progressView = nil
    }
}

// MARK: - Selection + context menu

extension PresetPickerViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let preset = preset(for: id) else {
            return
        }
        guard id != viewModel.currentPresetID else { return }
        switchPreset(preset)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let id = dataSource.itemIdentifier(for: indexPath), let preset = preset(for: id) else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIAction] = [
                UIAction(title: "Rename", image: UIImage(systemName: "pencil")) { _ in
                    self.renamePreset(preset)
                },
            ]
            if preset.id.rawValue != 0, preset.id.rawValue != 1 {
                actions.append(UIAction(
                    title: "Delete",
                    image: UIImage(systemName: "trash"),
                    attributes: .destructive
                ) { _ in
                    self.deletePreset(preset)
                })
            }
            return UIMenu(children: actions)
        }
    }
}
