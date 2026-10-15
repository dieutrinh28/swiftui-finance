import SwiftUI

/// An SF Symbol on a softly tinted rounded square: the app's single icon
/// container style (categories, wallets, banners). Scales with Dynamic Type.
struct IconBadge: View {
    enum Size {
        /// Settings-style rows.
        case small
        case regular
        case large
    }

    let systemName: String
    let tint: Color
    var size: Size = .regular

    @ScaledMetric(relativeTo: .body) private var smallSide = ComponentSize.iconBadgeSmall
    @ScaledMetric(relativeTo: .body) private var regularSide = ComponentSize.iconBadge
    @ScaledMetric(relativeTo: .body) private var largeSide = ComponentSize.iconBadgeLarge
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let side: CGFloat = switch size {
        case .small: smallSide
        case .regular: regularSide
        case .large: largeSide
        }
        Image(systemName: systemName)
            .font(.system(size: side * 0.44, weight: .medium))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(
                tint.opacity(colorScheme == .dark ? 0.22 : 0.14),
                in: RoundedRectangle(cornerRadius: side * 0.32, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: Spacing.md) {
        IconBadge(systemName: "fork.knife", tint: PaletteColor.orange.color)
        IconBadge(systemName: "banknote", tint: PaletteColor.green.color)
        IconBadge(systemName: "creditcard", tint: PaletteColor.indigo.color)
        IconBadge(systemName: "house", tint: PaletteColor.brown.color, size: .large)
    }
    .padding()
}
