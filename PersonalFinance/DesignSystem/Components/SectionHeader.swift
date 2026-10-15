import SwiftUI

/// A section title above a card, with an optional trailing control
/// ("See All", a period picker, a count). Marked as a heading for VoiceOver.
struct SectionHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing

    init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(AppColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.sm)
            trailing
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.accent)
        }
        .padding(.horizontal, Spacing.xs)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}

#Preview {
    VStack(spacing: Spacing.lg) {
        SectionHeader("Budgets")
        SectionHeader("Recent transactions") {
            Button("See All") {}
        }
    }
    .padding(Spacing.screen)
}
