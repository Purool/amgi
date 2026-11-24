import UIKit

/// One read-only note row: title on top, snippet (or nothing) underneath.
final class NoteCell: UICollectionViewListCell {
    func configure(with summary: NoteSummary) {
        var content = defaultContentConfiguration()
        content.text = summary.title
        content.secondaryText = summary.snippet.isEmpty ? nil : summary.snippet

        content.textProperties.font = AmgiTypography.body
        content.textProperties.color = AmgiColor.textPrimary
        content.textProperties.adjustsFontForContentSizeCategory = true

        content.secondaryTextProperties.font = AmgiTypography.callout
        content.secondaryTextProperties.color = AmgiColor.textSecondary
        content.secondaryTextProperties.adjustsFontForContentSizeCategory = true
        content.secondaryTextProperties.numberOfLines = 2

        contentConfiguration = content
    }
}
