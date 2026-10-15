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

    /// Leading/trailing margin of scrolling screens.
    static let screen: CGFloat = 20
    /// Gap between sections of a screen.
    static let section: CGFloat = 28
}

/// Corner radii. Continuous corners everywhere (`style: .continuous`).
enum Radius {
    /// Cards and major surfaces.
    static let card: CGFloat = 20
    /// Buttons, banners and inputs.
    static let control: CGFloat = 14
    /// Chips and small tags.
    static let chip: CGFloat = 10
}

/// Very soft, diffused elevation for light mode. Dark mode uses a hairline
/// border instead, because shadows are invisible on dark surfaces.
enum Elevation {
    static let cardColor = Color(light: 0x243247, dark: 0x000000).opacity(0.06)
    static let cardRadius: CGFloat = 14
    static let cardY: CGFloat = 4
}

/// Fixed component sizes. Scaled with Dynamic Type where they hold text or icons.
enum ComponentSize {
    /// Minimum height of primary and secondary buttons (above the 44 pt touch target).
    static let buttonHeight: CGFloat = 50
    /// Icon badge (rounded square behind an SF Symbol).
    static let iconBadgeSmall: CGFloat = 30
    static let iconBadge: CGFloat = 38
    static let iconBadgeLarge: CGFloat = 46
    /// Thickness of progress meters.
    static let meterHeight: CGFloat = 8
}

/// Type scale. Everything is based on text styles, so it follows Dynamic Type.
/// Financial figures use rounded, monospaced digits so columns of numbers align.
extension Font {
    // Text
    /// Section headings on a screen ("Budgets", "Recent transactions").
    static let sectionTitle = Font.title3.weight(.semibold)
    /// Titles inside a card or banner.
    static let cardTitle = Font.headline
    /// Row titles.
    static let rowTitle = Font.body.weight(.medium)
    /// Secondary row text, metadata and timestamps.
    static let meta = Font.footnote
    /// Labels above values ("Income", "Assets"); with `.weight(.semibold)` a list group
    /// header, with `.weight(.medium)` small controls (filter chip, inline link).
    static let label = Font.subheadline
    /// Explanatory sentences inside a card: empty messages, descriptions, errors.
    static let supporting = Font.subheadline
    /// Notes under a card or chart, table labels, status badges (`.weight(.semibold)`).
    static let fine = Font.caption
    /// The title of a full-screen message (welcome, store error). Bold like a screen title.
    static let heroTitle = Font.largeTitle.weight(.bold)
    /// The sentence under a hero title.
    static let lead = Font.body
    /// The checkmark of the selected row in a single-choice list.
    static let checkmark = Font.body.weight(.semibold)
    /// The circle / filled circle of a multiple-choice row.
    static let selectionCircle = Font.title3
    /// Technical details (error descriptions to copy).
    static let code = Font.footnote.monospaced()

    // Amounts
    /// The one dominant figure of a screen (net worth, wallet balance).
    static let amountHero = Font.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit()
    /// Secondary summary figures (income and expense tiles).
    static let amountLarge = Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
    /// Amounts in rows.
    static let amountRow = Font.system(.body, design: .rounded, weight: .semibold).monospacedDigit()
    /// Small amounts beside a label.
    static let amountDetail = Font.system(.subheadline, design: .rounded, weight: .medium).monospacedDigit()
}
