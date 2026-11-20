import AnkiKit
import UIKit

/// Temporary Phase 1 screen: opens the collection, reads the deck tree and the
/// due counts, and shows the result. It is the runtime proof that services work
/// on device, and it is replaced by the real settings screen in Phase 3.
final class EngineStatusViewController: UIViewController {
    private let services: LiteServices
    private let session: CollectionSession

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let reloadButton = AmgiButton(style: .secondary, title: "Reload")

    init(services: LiteServices, session: CollectionSession) {
        self.services = services
        self.session = session
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

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = AmgiTypography.callout
        statusLabel.textColor = AmgiColor.textSecondary
        statusLabel.numberOfLines = 0
        statusLabel.text = "Opening collection…"

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = false
        spinner.startAnimating()

        reloadButton.translatesAutoresizingMaskIntoConstraints = false
        reloadButton.addTarget(self, action: #selector(reload), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [spinner, statusLabel, reloadButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = AmgiSpacing.md
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AmgiSpacing.lg),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.lg),
        ])

        reload()
    }

    @objc private func reload() {
        spinner.startAnimating()
        statusLabel.text = "Opening collection…"

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.ensureOpen()
                let rows = try await self.services.decks.deckTree()
                let due = rows.reduce(0) { $0 + $1.counts.reviewCount }
                let learning = rows.reduce(0) { $0 + $1.counts.learnCount }
                let new = rows.reduce(0) { $0 + $1.counts.newCount }
                let media = self.services.collection.mediaFolderPath ?? "—"
                self.spinner.stopAnimating()
                self.statusLabel.text = """
                Collection open
                Decks: \(rows.count)
                Due \(due) · Learning \(learning) · New \(new)
                Media: \(media)
                """
            } catch {
                self.spinner.stopAnimating()
                self.statusLabel.text = "Engine error: \(error)"
            }
        }
    }
}
