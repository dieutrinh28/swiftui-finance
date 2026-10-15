import SwiftUI
import UIKit

/// Semantic colours. Views use these names, never raw hex values, so light and
/// dark appearance stay consistent.
///
/// Brand direction: soft pastel blue (primary), green (positive) and pink
/// (accent) on white or near-white surfaces. Pastels are **fills only**: they
/// fail contrast as text (1.4–1.7:1). Text and icons that carry meaning use the
/// strong tokens below, all verified at WCAG AA (≥ 4.5:1) on `background`,
/// `surface` and their own soft fill, in light and dark mode
/// (see `docs/DESIGN_SYSTEM.md`).
enum AppColor {
    // MARK: Surfaces

    /// Screen background: near-white with a hint of blue.
    static let background = Color(light: 0xF8FAFD, dark: 0x0F141B)
    /// Cards, rows and sheets.
    static let surface = Color(light: 0xFFFFFF, dark: 0x19202A)
    /// Inset areas inside a surface (tracks, segmented areas).
    static let surfaceMuted = Color(light: 0xF1F5FA, dark: 0x222B37)
    /// Hairline borders and dividers.
    static let border = Color(light: 0xE8EDF4, dark: 0x2A3442)

    // MARK: Text

    static let textPrimary = Color(light: 0x243247, dark: 0xE7ECF3)
    /// Spec value #778397 was 3.7:1; darkened to reach 4.5:1 on every surface.
    static let textSecondary = Color(light: 0x5F6C82, dark: 0x9AA6B6)

    // MARK: Brand

    /// Pastel blue for primary buttons, selected states and highlights (fill only).
    static let brand = Color(light: 0xA9C9F5, dark: 0x8DB8F2)
    /// Text and icons placed on `brand`.
    static let onBrand = Color(light: 0x243247, dark: 0x10213A)
    /// Pastel green (fill only): savings, success.
    static let brandGreen = Color(light: 0xB9E4CE, dark: 0x5FCB92)
    /// Pastel pink (fill only), used sparingly for accents.
    static let brandPink = Color(light: 0xF4C6D7, dark: 0xE79BB8)
    /// Readable blue for links, tints, selected text and transfer amounts.
    static let accent = Color(light: 0x2C66B8, dark: 0x8DB8F2)

    // MARK: Soft fills (backgrounds behind icons, banners and tiles)

    static let softBlue = Color(light: 0xEAF2FD, dark: 0x1C2C42)
    static let softGreen = Color(light: 0xEAF6EF, dark: 0x173126)
    static let softPink = Color(light: 0xFCEEF3, dark: 0x382330)
    static let softAmber = Color(light: 0xFDF3DC, dark: 0x362C16)
    static let softCoral = Color(light: 0xFCEEEA, dark: 0x3A231F)

    // MARK: Financial and status meaning (always paired with a sign, icon or label)

    static let positive = Color(light: 0x1D7A4B, dark: 0x5FCB92)
    static let negative = Color(light: 0xC2412F, dark: 0xF28A75)
    static let warning = Color(light: 0x94600A, dark: 0xE9B24E)
    static let destructive = Color(light: 0xC62F3A, dark: 0xFF7272)
    /// Fill of a neutral swipe action (Skip): white text stays readable (5.3:1) in both modes.
    static let neutralAction = Color(light: 0x5F6C82, dark: 0x5F6C82)

    // MARK: Roles used across the app (kept for existing call sites)

    /// Money in.
    static let income = positive
    /// Money out.
    static let expense = negative
    /// Movement between the user's own wallets: neither income nor expense.
    static let transfer = accent
    /// Attention without error: paused items, near-limit budgets, overdue backups.
    static let liability = warning
}

/// Colours a user can pick for wallets and categories.
/// The raw value is persisted as `colorIdentifier`; only the rendering changed.
///
/// Mid-tone, slightly softened hues that sit well next to the pastel brand
/// colours. Shown as an icon on a 15–25 % tint, never as text.
enum PaletteColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    /// Unknown identifiers (e.g. from a newer backup) fall back to gray for display only.
    init(identifier: String) {
        self = PaletteColor(rawValue: identifier) ?? .gray
    }

    var color: Color {
        switch self {
        case .red: Color(light: 0xD9544D, dark: 0xF07A72)
        case .orange: Color(light: 0xD9762F, dark: 0xF09A5A)
        case .yellow: Color(light: 0xB98A0E, dark: 0xE6BC45)
        case .green: Color(light: 0x2F8F5E, dark: 0x5FCB92)
        case .mint: Color(light: 0x24917F, dark: 0x5CCDB8)
        case .teal: Color(light: 0x2A8798, dark: 0x5FBFD0)
        case .cyan: Color(light: 0x2A8CB8, dark: 0x6CC2E8)
        case .blue: Color(light: 0x3B7DD8, dark: 0x8DB8F2)
        case .indigo: Color(light: 0x5767CC, dark: 0x99A5F0)
        case .purple: Color(light: 0x8460C4, dark: 0xB89AEB)
        case .pink: Color(light: 0xC9558A, dark: 0xEC94BC)
        case .brown: Color(light: 0x8F6A4C, dark: 0xC8A283)
        case .gray: Color(light: 0x6E7A8C, dark: 0xA3AEBD)
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
