import UIKit

/// Count pill used by the deck list (new / learning / due).
final class AmgiBadgeView: UIView {
    enum Kind {
        case new
        case learning
        case due

        var tint: UIColor {
            switch self {
            case .new: return AmgiColor.accent
            case .learning: return AmgiColor.warning
            case .due: return AmgiColor.positive
            }
        }
    }

    private let label = UILabel()

    var count: Int = 0 {
        didSet { refresh() }
    }

    init(kind: Kind, count: Int = 0) {
        self.kind = kind
        self.count = count
        super.init(frame: .zero)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = AmgiTypography.caption
        label.textColor = kind.tint
        label.textAlignment = .center
        addSubview(label)

        layer.cornerRadius = 9
        layer.cornerCurve = .continuous
        backgroundColor = kind.tint.withAlphaComponent(0.14)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 18),
        ])

        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private let kind: Kind

    private func refresh() {
        label.text = "\(count)"
        isHidden = count == 0
        accessibilityLabel = "\(count) \(kind)"
    }
}
