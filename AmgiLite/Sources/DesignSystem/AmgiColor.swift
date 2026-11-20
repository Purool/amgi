import UIKit

/// Semantic colors, UIKit-only. Values mirror `AmgiUI/Sources/Theme` so Lite
/// reads as the same app, but nothing is imported from the SwiftUI modules.
enum AmgiColor {
    static let background = dynamic(light: 0xF7F5F0, dark: 0x121212)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let surfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let textPrimary = dynamic(light: 0x1A1A1A, dark: 0xF2F2F2)
    static let textSecondary = dynamic(light: 0x6B6B6B, dark: 0xA8A8A8)
    static let textTertiary = dynamic(light: 0x9A9A9A, dark: 0x7A7A7A)
    static let separator = dynamic(light: 0xE3E0D8, dark: 0x38383A)
    static let accent = dynamic(light: 0x2F6F5E, dark: 0x7FC4B0)
    static let positive = dynamic(light: 0x2E7D4F, dark: 0x6FD08C)
    static let warning = dynamic(light: 0xB5731A, dark: 0xE9B45C)
    static let danger = dynamic(light: 0xB03A3A, dark: 0xEF7A7A)

    private static func dynamic(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
