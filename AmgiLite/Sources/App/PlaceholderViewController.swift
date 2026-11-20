import UIKit

/// Stand-in for screens the feature shards have not landed yet. Kept in the
/// scaffold so every Phase can build and launch before its UI exists.
final class PlaceholderViewController: UIViewController {
    private let detail: String

    init(title: String, detail: String) {
        self.detail = detail
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = detail
        label.font = AmgiTypography.body
        label.textColor = AmgiColor.textSecondary
        label.numberOfLines = 0
        label.textAlignment = .center

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.lg),
            label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.lg),
        ])
    }
}
