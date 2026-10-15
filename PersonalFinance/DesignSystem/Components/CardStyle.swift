import SwiftUI

/// The one surface style of the app: a rounded card with a hairline border and,
/// in light mode, a very soft shadow.
///
/// - `fill`: `AppColor.surface` for ordinary cards; a soft tint
///   (`AppColor.softBlue`, …) for the single highlighted surface of a screen.
/// - `elevated: false` drops the shadow (tinted or nested surfaces).
///
/// Group related rows inside **one** card rather than giving every row its own.
struct CardStyle: ViewModifier {
    var fill: Color = AppColor.surface
    var padding: CGFloat = Spacing.lg
    var elevated = true

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: shape)
            .overlay {
                shape.strokeBorder(AppColor.border, lineWidth: 1)
            }
            .shadow(
                color: elevated && colorScheme == .light ? Elevation.cardColor : .clear,
                radius: Elevation.cardRadius, y: Elevation.cardY
            )
    }
}

extension View {
    func cardStyle(fill: Color = AppColor.surface, padding: CGFloat = Spacing.lg, elevated: Bool = true) -> some View {
        modifier(CardStyle(fill: fill, padding: padding, elevated: elevated))
    }

    /// Screen background for scrolling screens and lists.
    func screenBackground() -> some View {
        background(AppColor.background.ignoresSafeArea())
    }

    /// Native grouped `List` / `Form` on the app background: hairline
    /// separators and sentence-case section headers. Combine with
    /// `surfaceRows()` / `highlightedRows()` on sections.
    func appGroupedStyle() -> some View {
        scrollContentBackground(.hidden)
            .screenBackground()
            .listRowSeparatorTint(AppColor.border)
            .textCase(nil)
    }

    /// Rows of a list section on the standard surface.
    func surfaceRows() -> some View {
        listRowBackground(AppColor.surface)
    }

    /// The single highlighted row of a screen (its main figure), on a soft tint.
    func highlightedRows() -> some View {
        listRowBackground(AppColor.softBlue)
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        Text("Surface card").cardStyle()
        Text("Highlighted card").cardStyle(fill: AppColor.softBlue, elevated: false)
    }
    .padding(Spacing.screen)
    .frame(maxHeight: .infinity)
    .screenBackground()
}
