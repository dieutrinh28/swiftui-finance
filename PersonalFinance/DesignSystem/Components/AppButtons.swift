import SwiftUI

/// The main action of a screen or card: pastel blue fill with dark text
/// (7.6:1 in light mode). Full width, at least 50 pt high.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppColor.onBrand.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity, minHeight: ComponentSize.buttonHeight)
            .padding(.horizontal, Spacing.lg)
            .background(
                AppColor.brand.opacity(isEnabled ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

/// A supporting action: soft blue fill with the readable accent colour.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AppColor.accent.opacity(isEnabled ? 1 : 0.5))
            .frame(maxWidth: .infinity, minHeight: ComponentSize.buttonHeight)
            .padding(.horizontal, Spacing.lg)
            .background(AppColor.softBlue, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// The primary action pinned to the bottom of a form (`.safeAreaInset(edge: .bottom)`).
/// Sits above the keyboard when it is shown, so Save is always reachable.
struct PrimaryActionBar: View {
    let title: LocalizedStringKey
    var systemImage: String = "checkmark"
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.appPrimary)
        .disabled(!isEnabled)
        .padding(.horizontal, Spacing.screen)
        .padding(.top, Spacing.md)
        .padding(.bottom, Spacing.sm)
        .background {
            AppColor.background
                .overlay(alignment: .top) {
                    Rectangle().fill(AppColor.border).frame(height: 1)
                }
                .ignoresSafeArea()
        }
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var appPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var appSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

#Preview {
    VStack(spacing: Spacing.md) {
        Button("Add Transaction", systemImage: "plus") {}
            .buttonStyle(.appPrimary)
        Button("See All") {}
            .buttonStyle(.appSecondary)
        Button("Disabled") {}
            .buttonStyle(.appPrimary)
            .disabled(true)
    }
    .padding(Spacing.screen)
}
