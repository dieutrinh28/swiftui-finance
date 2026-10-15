import SwiftUI
import UIKit

/// Shown when the database cannot be opened. Explains that nothing was
/// deleted, lets the user retry, and exposes details for support.
struct StoreErrorView: View {
    let failure: StoreFailure
    let retry: () -> Void

    @State private var copiedDetails = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        IconBadge(systemName: "externaldrive.badge.exclamationmark", tint: AppColor.negative, size: .large)
                            .accessibilityHidden(true)
                        Text("Your data couldn't be opened")
                            .font(.heroTitle)
                            .foregroundStyle(AppColor.textPrimary)
                        Text("Nothing was deleted or reset. Your records stay on this iPhone until the problem is resolved.")
                            .font(.lead)
                            .foregroundStyle(AppColor.textSecondary)
                    }

                    Text(failure.message)
                        .font(.supporting)
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardStyle()

                    VStack(spacing: Spacing.md) {
                        Button("Try Again", action: retry)
                            .buttonStyle(.appPrimary)
                        Button {
                            UIPasteboard.general.string = failure.technicalDetails
                            copiedDetails = true
                        } label: {
                            Label(copiedDetails ? "Details Copied" : "Copy Technical Details",
                                  systemImage: copiedDetails ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.appSecondary)
                    }

                    DisclosureGroup("Technical details") {
                        Text(failure.technicalDetails)
                            .font(.code)
                            .foregroundStyle(AppColor.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.label)
                    .tint(AppColor.accent)
                }
                .padding(.horizontal, Spacing.screen)
                .padding(.vertical, Spacing.xl)
            }
            .screenBackground()
            .navigationTitle("Database Error")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    StoreErrorView(
        failure: StoreFailure(
            error: CocoaError(.fileReadCorruptFile),
            storeURL: URL(filePath: "/Application Support/PersonalFinance.store")
        ),
        retry: {}
    )
}
