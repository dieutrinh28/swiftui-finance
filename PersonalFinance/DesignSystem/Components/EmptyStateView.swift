import SwiftUI

/// A calm empty state: an icon in a soft circle, a short title, one sentence
/// on what to do next, and optional actions.
struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let actions: Actions

    @ScaledMetric(relativeTo: .title) private var circle: CGFloat = 72

    init(
        systemImage: String,
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        @ViewBuilder actions: () -> Actions
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: systemImage)
                .font(.system(size: circle * 0.4, weight: .medium))
                .foregroundStyle(AppColor.accent)
                .frame(width: circle, height: circle)
                .background(AppColor.softBlue, in: Circle())
                .accessibilityHidden(true)
            VStack(spacing: Spacing.xs) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.textSecondary)
            }
            .multilineTextAlignment(.center)
            actions
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: LocalizedStringKey, message: LocalizedStringKey) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

#Preview {
    EmptyStateView(
        systemImage: "list.bullet.rectangle",
        title: "No transactions yet",
        message: "Income, expenses and transfers you record will appear here."
    ) {
        Button("Add Transaction", systemImage: "plus") {}
            .buttonStyle(.appPrimary)
    }
    .frame(maxHeight: .infinity)
    .screenBackground()
}
