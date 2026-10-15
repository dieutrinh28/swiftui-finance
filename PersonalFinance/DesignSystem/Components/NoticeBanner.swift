import SwiftUI

/// A short, calm message on a soft tinted surface: something needs attention
/// (due items), or general information. The icon and the wording carry the
/// meaning; the tint only supports it.
struct NoticeBanner: View {
    enum Tone {
        case info
        case attention
        case success

        var fill: Color {
            switch self {
            case .info: AppColor.softBlue
            case .attention: AppColor.softAmber
            case .success: AppColor.softGreen
            }
        }

        var ink: Color {
            switch self {
            case .info: AppColor.accent
            case .attention: AppColor.warning
            case .success: AppColor.positive
            }
        }
    }

    let systemImage: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey? = nil
    var tone: Tone = .info
    /// Shows a chevron when the banner leads somewhere.
    var showsDisclosure = false

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Image(systemName: systemImage)
                .font(.title3.weight(.medium))
                .foregroundStyle(tone.ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(AppColor.textPrimary)
                if let message {
                    Text(message)
                        .font(.meta)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }
            Spacer(minLength: Spacing.sm)
            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppColor.textSecondary)
                    .accessibilityHidden(true)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.fill, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: Spacing.md) {
        NoticeBanner(systemImage: "bell.badge", title: "2 recurring transactions due",
                     message: "Review and record them.", tone: .attention, showsDisclosure: true)
        NoticeBanner(systemImage: "lock.shield", title: "Stored only on this iPhone")
    }
    .padding(Spacing.screen)
}
