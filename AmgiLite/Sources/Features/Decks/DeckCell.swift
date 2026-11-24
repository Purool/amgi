import UIKit

/// Count pills for one deck row (new / learning / due), trailing in the cell.
/// Badges with a zero count hide themselves (`AmgiBadgeView`), and the whole
/// view exposes one merged accessibility label instead of three separate
/// elements.
final class DeckBadgesView: UIView {
    private let newBadge = AmgiBadgeView(kind: .new)
    private let learningBadge = AmgiBadgeView(kind: .learning)
    private let dueBadge = AmgiBadgeView(kind: .due)

    init() {
        super.init(frame: .zero)

        let stack = UIStackView(arrangedSubviews: [newBadge, learningBadge, dueBadge])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = AmgiSpacing.xs
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        isAccessibilityElement = true
        update(new: 0, learning: 0, due: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(new: Int, learning: Int, due: Int) {
        newBadge.count = new
        learningBadge.count = learning
        dueBadge.count = due
        accessibilityLabel = "\(new) new, \(learning) learning, \(due) due"
    }
}

/// One deck row in the inset-grouped list: deck name on the left, count
/// badges trailing. Indentation is applied by the registration closure via
/// `setIndentation(_:)`, mirroring the deck tree's depth.
final class DeckCell: UICollectionViewListCell {
    private let badges = DeckBadgesView()

    func configure(with row: DeckRow) {
        var content = defaultContentConfiguration()
        content.text = row.name
        content.textProperties.font = AmgiTypography.body
        content.textProperties.color = AmgiColor.textPrimary
        content.textProperties.adjustsFontForContentSizeCategory = true
        contentConfiguration = content

        badges.update(
            new: row.counts.newCount,
            learning: row.counts.learnCount,
            due: row.counts.reviewCount
        )
        accessories = [.customView(
            configuration: UICellAccessory.CustomViewConfiguration(
                customView: badges,
                placement: .trailing()
            )
        )]
    }

    func setIndentation(_ depth: Int) {
        indentationLevel = depth
        indentationWidth = 14
    }
}
