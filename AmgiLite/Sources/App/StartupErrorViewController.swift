import UIKit

/// Shown when the Rust engine cannot be loaded. On an iOS 14 device this is the
/// first symptom of a framework that was built with a newer deployment target.
final class StartupErrorViewController: UIViewController {
    private let titleText: String
    private let message: String

    init(title: String, message: String) {
        self.titleText = title
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = AmgiColor.background

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = AmgiSpacing.sm

        let title = UILabel()
        title.text = titleText
        title.font = AmgiTypography.title
        title.textColor = AmgiColor.danger
        title.numberOfLines = 0

        let detail = UILabel()
        detail.text = message
        detail.font = AmgiTypography.callout
        detail.textColor = AmgiColor.textSecondary
        detail.numberOfLines = 0

        stack.addArrangedSubview(title)
        stack.addArrangedSubview(detail)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: AmgiSpacing.lg),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -AmgiSpacing.lg),
        ])
    }
}
