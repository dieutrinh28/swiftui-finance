import SwiftUI

/// Spacing scale (4-point grid).
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum Radius {
    static let card: CGFloat = 16
}

/// Type styles for financial figures. All are based on text styles, so they
/// follow Dynamic Type, and use monospaced digits so columns of numbers align.
extension Font {
    static let amountHero = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    static let amountRow = Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit()
    static let amountDetail = Font.system(.subheadline, design: .rounded).monospacedDigit()
}
