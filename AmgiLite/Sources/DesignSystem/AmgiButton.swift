import UIKit

enum AmgiButtonStyle {
    case primary
    case secondary
    case destructive
}

/// iOS 14 has no `UIButton.Configuration` (15), so styling is done the old way:
/// background color + insets + a tint that follows the palette.
final class AmgiButton: UIButton {
    private let style: AmgiButtonStyle

    init(style: AmgiButtonStyle, title: String) {
        self.style = style
        super.init(frame: .zero)
        setTitle(title, for: .normal)
        titleLabel?.font = AmgiTypography.headline
        titleLabel?.adjustsFontForContentSizeCategory = true
        layer.cornerRadius = AmgiRadius.md
        layer.cornerCurve = .continuous
        contentEdgeInsets = UIEdgeInsets(
            top: AmgiSpacing.sm + 2,
            left: AmgiSpacing.md,
            bottom: AmgiSpacing.sm + 2,
            right: AmgiSpacing.md
        )
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.72 : (isEnabled ? 1 : 0.4) }
    }

    override var isEnabled: Bool {
        didSet { alpha = isEnabled ? 1 : 0.4 }
    }

    private func applyStyle() {
        switch style {
        case .primary:
            backgroundColor = AmgiColor.accent
            setTitleColor(.white, for: .normal)
        case .secondary:
            backgroundColor = AmgiColor.surfaceElevated
            setTitleColor(AmgiColor.textPrimary, for: .normal)
            layer.borderWidth = 1
            layer.borderColor = AmgiColor.separator.cgColor
        case .destructive:
            backgroundColor = AmgiColor.danger.withAlphaComponent(0.12)
            setTitleColor(AmgiColor.danger, for: .normal)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // `cgColor` is resolved once; dynamic colors need a re-resolve.
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = AmgiColor.separator.cgColor
        }
    }
}
