import UIKit

/// Dynamic-Type-aware fonts. `UIFontMetrics` (iOS 11) is the iOS 14-safe
/// replacement for SwiftUI's `.font(.body)` / `.dynamicTypeSize`.
enum AmgiTypography {
    static var largeTitle: UIFont { scaled(.largeTitle, size: 34, weight: .bold, max: 44) }
    static var title: UIFont { scaled(.title1, size: 28, weight: .semibold, max: 38) }
    static var headline: UIFont { scaled(.headline, size: 17, weight: .semibold) }
    static var body: UIFont { scaled(.body, size: 17) }
    static var callout: UIFont { scaled(.callout, size: 16) }
    static var caption: UIFont { scaled(.caption1, size: 12) }

    private static func scaled(
        _ style: UIFont.TextStyle,
        size: CGFloat,
        weight: UIFont.Weight = .regular,
        max: CGFloat? = nil
    ) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let metrics = UIFontMetrics(forTextStyle: style)
        guard let max else {
            return metrics.scaledFont(for: base)
        }
        return metrics.scaledFont(for: base, maximumPointSize: max)
    }
}

enum AmgiSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum AmgiRadius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 18
}
