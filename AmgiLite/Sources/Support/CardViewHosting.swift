import UIKit

/// Phase 0 seam for the card surface. Phase 1 (shard S3) replaces
/// `CardPlaceholderView` with a `WKWebView` + `WKURLSchemeHandler` pair and
/// keeps this protocol unchanged so the review screen can be built in parallel.
protocol CardViewHosting: AnyObject {
    func load(html: String, baseURL: URL?)
    var isLoading: Bool { get }
}

final class CardPlaceholderView: UIView, CardViewHosting {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = AmgiColor.surface

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AmgiTypography.body
        label.textColor = AmgiColor.textTertiary
        label.numberOfLines = 0
        label.textAlignment = .center
        label.text = "Card surface lands in Phase 1 (S3)."
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: AmgiSpacing.md),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -AmgiSpacing.md),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var isLoading: Bool { false }

    func load(html: String, baseURL: URL?) {
        label.text = html.isEmpty ? "(empty card)" : html
    }
}
