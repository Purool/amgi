import AnkiKit
import UIKit

/// Modal card preview shared by the template and note editors. The caller
/// renders one `RenderedCard` before presenting (with draft CSS swapped in
/// when appropriate), so this screen only switches sides and reloads on a
/// dark-mode change.
@MainActor
final class CardPreviewViewController: UIViewController {
    private let rendered: RenderedCard
    private let note: String?
    private let services: LiteServices

    private let sideControl = UISegmentedControl(items: ["Front", "Back"])
    private let cardSurface: CardWebView
    private let noteLabel = UILabel()
    private var side: CardSide = .front

    init(rendered: RenderedCard, templateName: String, note: String?, services: LiteServices) {
        self.rendered = rendered
        self.note = note
        self.services = services

        let collection = services.collection
        self.cardSurface = CardWebView(mediaRootProvider: {
            collection.mediaFolderPath.map { URL(fileURLWithPath: $0) }
        })

        super.init(nibName: nil, bundle: nil)
        title = templateName
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(doneTapped)
        )

        sideControl.selectedSegmentIndex = 0
        sideControl.addTarget(self, action: #selector(sideChanged), for: .valueChanged)

        noteLabel.font = AmgiTypography.caption
        noteLabel.textColor = AmgiColor.warning
        noteLabel.adjustsFontForContentSizeCategory = true
        noteLabel.numberOfLines = 0
        noteLabel.text = note
        noteLabel.isHidden = note == nil

        cardSurface.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [sideControl, noteLabel, cardSurface])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AmgiSpacing.sm
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: AmgiSpacing.sm),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.md),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.md),
        ])

        render()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            render()
        }
    }

    private func render() {
        let page = CardPageBuilder.page(
            for: rendered,
            side: side,
            isDark: traitCollection.userInterfaceStyle == .dark
        )
        cardSurface.load(html: page, baseURL: nil)
    }

    @objc private func sideChanged() {
        side = sideControl.selectedSegmentIndex == 0 ? .front : .back
        render()
    }

    @objc private func doneTapped() {
        dismiss(animated: true)
    }
}
