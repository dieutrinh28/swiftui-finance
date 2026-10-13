import SwiftUI
import UIKit

/// Semantic colours. Views use these names, never raw hex values, so light
/// and dark appearance stay consistent. The accent colour lives in the asset
/// catalogue (`AccentColor`) and is available as `Color.accentColor`.
enum AppColor {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)

    static let income = Color(light: 0x15803D, dark: 0x4ADE80)
    static let expense = Color(light: 0xB91C1C, dark: 0xF87171)
    static let transfer = Color(light: 0x1D4ED8, dark: 0x60A5FA)
    static let liability = Color(light: 0xC2410C, dark: 0xFB923C)
}

/// Colours a user can pick for wallets and categories.
/// The raw value is persisted as `colorIdentifier`.
enum PaletteColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    /// Unknown identifiers (e.g. from a newer backup) fall back to gray for display only.
    init(identifier: String) {
        self = PaletteColor(rawValue: identifier) ?? .gray
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

extension Color {
    /// A colour that adapts to light and dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
