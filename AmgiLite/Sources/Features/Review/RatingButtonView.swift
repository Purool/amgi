import UIKit

/// One of the four grading keys under a card's back side. iOS 14 has no
/// `UIButton.Configuration`, so this is a hand-tracked `UIControl` subclass:
/// a two-line tile (rating name + scheduled interval) with a tinted wash that
/// fires `.touchUpInside` on a normal tap.
final class RatingButtonView: UIControl {
    enum Kind {
        case again
        case hard
        case good
        case easy

        var title: String {
            switch self {
            case .again: return "Again"
            case .hard: return "Hard"
            case .good: return "Good"
            case .easy: return "Easy"
            }
        }

        var tint: UIColor {
            switch self {
            case .again: return AmgiColor.danger
            case .hard: return AmgiColor.warning
            case .good: return AmgiColor.positive
            case .easy: return AmgiColor.accent
            }
        }
    }

    private let kind: Kind
    private let titleLabel = UILabel()
    private let intervalLabel = UILabel()

    /// The scheduled interval shown under the title ("4d", "2.5mo", …). An
    /// empty string hides the second line entirely.
    var intervalText: String = "" {
        didSet {
            intervalLabel.text = intervalText
            intervalLabel.isHidden = intervalText.isEmpty
            updateAccessibility()
        }
    }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)

        backgroundColor = kind.tint.withAlphaComponent(0.14)
        layer.cornerRadius = AmgiRadius.md
        layer.cornerCurve = .continuous

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = kind.title
        titleLabel.font = AmgiTypography.headline
        titleLabel.textColor = kind.tint
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true

        intervalLabel.translatesAutoresizingMaskIntoConstraints = false
        intervalLabel.font = AmgiTypography.caption
        intervalLabel.textColor = AmgiColor.textSecondary
        intervalLabel.textAlignment = .center
        intervalLabel.adjustsFontForContentSizeCategory = true
        intervalLabel.isHidden = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, intervalLabel])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = AmgiSpacing.xxs
        // The labels must not swallow touches meant for the control itself.
        stack.isUserInteractionEnabled = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: AmgiSpacing.sm + 2),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -(AmgiSpacing.sm + 2)),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: AmgiSpacing.xs),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -AmgiSpacing.xs),
        ])

        updateAccessibility()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isEnabled: Bool {
        didSet { updateAppearance() }
    }

    override var isHighlighted: Bool {
        didSet { updateAppearance() }
    }

    // MARK: - Touch tracking (hand-written; `UIButton.Configuration` is iOS 15)

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isHighlighted = true
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        isHighlighted = isTouchInside
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        isHighlighted = false
        guard let touch else { return }
        if bounds.contains(touch.location(in: self)) {
            sendActions(for: .touchUpInside)
        }
    }

    override func cancelTracking(with event: UIEvent?) {
        isHighlighted = false
    }

    // MARK: - Presentation state

    private func updateAppearance() {
        alpha = !isEnabled ? 0.4 : (isHighlighted ? 0.72 : 1)
    }

    private func updateAccessibility() {
        isAccessibilityElement = true
        var label = "Rating \(kind.title)"
        if !intervalText.isEmpty {
            label += ", \(intervalText)"
        }
        accessibilityLabel = label
    }
}
